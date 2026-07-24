/**
 * Curated pack-shot overrides — first tier of the image chain.
 * R2 key: `curated-images/{barcode}`
 */

import type { Env } from "./types.ts";

export const CURATED_R2_PREFIX = "curated-images/";
export const PRODUCT_R2_PREFIX = "product-images/";
export const IMAGE_KV_PREFIX = "image:v1:";
export const MISS_KV_PREFIX = "image:miss:v1:";

/** Max longest side for curated uploads (pixels). */
export const CURATED_MAX_SIDE = 1000;
/** Reject bodies larger than this before parsing. */
export const CURATED_MAX_BYTES = 2_500_000;

export function curatedKey(barcode: string): string {
  return `${CURATED_R2_PREFIX}${barcode.trim()}`;
}

export function productR2Key(barcode: string): string {
  return `${PRODUCT_R2_PREFIX}${barcode.trim()}`;
}

export function imageMetaKey(barcode: string): string {
  return `${IMAGE_KV_PREFIX}${barcode.trim()}`;
}

export function imageMissKey(barcode: string): string {
  return `${MISS_KV_PREFIX}${barcode.trim()}`;
}

export interface CuratedPutResult {
  barcode: string;
  bytes: number;
  contentType: string;
  width: number | null;
  height: number | null;
}

export interface CuratedMetaWrite {
  source: "curated";
  isFrontImage: true;
  isLowQuality: false;
  width: number | null;
  height: number | null;
  fetchedAt: number;
  contentType: string;
  etag: string;
  cacheVersion: number;
}

/**
 * Store a curated pack shot, copy into the public product-images slot, write
 * KV meta, and clear miss so the next hit serves it immediately.
 */
export async function putCuratedImage(
  env: Env,
  barcode: string,
  bytes: ArrayBuffer,
  contentType: string,
  cacheVersion: number,
): Promise<CuratedPutResult> {
  const trimmed = barcode.trim();
  if (!trimmed) throw new Error("missing_barcode");
  if (bytes.byteLength === 0) throw new Error("empty_body");
  if (bytes.byteLength > CURATED_MAX_BYTES) throw new Error("too_large");

  const ct = normalizeContentType(contentType);
  if (!ct) throw new Error("unsupported_type");

  const dims = sniffDimensions(new Uint8Array(bytes), ct);
  if (dims && Math.max(dims.width, dims.height) > CURATED_MAX_SIDE) {
    throw new Error("too_large_dimensions");
  }

  const now = Date.now();
  const etag = `"curated-${trimmed}-${bytes.byteLength}-${now}"`;
  const meta: CuratedMetaWrite = {
    source: "curated",
    isFrontImage: true,
    isLowQuality: false,
    width: dims?.width ?? null,
    height: dims?.height ?? null,
    fetchedAt: now,
    contentType: ct,
    etag,
    cacheVersion,
  };

  await env.IMAGES.put(curatedKey(trimmed), bytes, {
    httpMetadata: { contentType: ct },
    customMetadata: { source: "curated", fetchedAt: String(now) },
  });
  await env.IMAGES.put(productR2Key(trimmed), bytes, {
    httpMetadata: { contentType: ct },
    customMetadata: {
      source: "curated",
      isFrontImage: "true",
      fetchedAt: String(now),
    },
  });
  await env.CACHE.put(imageMetaKey(trimmed), JSON.stringify(meta), {
    expirationTtl: 40 * 24 * 60 * 60,
  });
  await env.CACHE.delete(imageMissKey(trimmed));

  console.log(JSON.stringify({
    event: "image_resolved",
    barcode: trimmed,
    source: "curated",
    bytes: bytes.byteLength,
  }));
  console.log(JSON.stringify({
    event: "image_r2_put",
    barcode: trimmed,
    source: "curated",
    bytes: bytes.byteLength,
  }));

  return {
    barcode: trimmed,
    bytes: bytes.byteLength,
    contentType: ct,
    width: dims?.width ?? null,
    height: dims?.height ?? null,
  };
}

/** If a curated object exists, copy it into product-images + KV and return meta. */
export async function adoptCuratedIfPresent(
  env: Env,
  barcode: string,
  cacheVersion: number,
  now: () => number = Date.now,
): Promise<CuratedMetaWrite | null> {
  const trimmed = barcode.trim();
  const obj = await env.IMAGES.get(curatedKey(trimmed));
  if (!obj) return null;
  const bytes = await obj.arrayBuffer();
  if (!bytes.byteLength) return null;
  const contentType = obj.httpMetadata?.contentType || "image/jpeg";
  const ts = now();
  const etag = `"curated-${trimmed}-${bytes.byteLength}-${ts}"`;
  const meta: CuratedMetaWrite = {
    source: "curated",
    isFrontImage: true,
    isLowQuality: false,
    width: null,
    height: null,
    fetchedAt: ts,
    contentType,
    etag,
    cacheVersion,
  };
  await env.IMAGES.put(productR2Key(trimmed), bytes, {
    httpMetadata: { contentType },
    customMetadata: { source: "curated", isFrontImage: "true" },
  });
  await env.CACHE.put(imageMetaKey(trimmed), JSON.stringify(meta), {
    expirationTtl: 40 * 24 * 60 * 60,
  });
  await env.CACHE.delete(imageMissKey(trimmed));
  console.log(JSON.stringify({
    event: "image_resolved",
    barcode: trimmed,
    source: "curated",
  }));
  return meta;
}

function normalizeContentType(raw: string): "image/jpeg" | "image/png" | null {
  const t = raw.toLowerCase().split(";")[0]!.trim();
  if (t === "image/jpeg" || t === "image/jpg") return "image/jpeg";
  if (t === "image/png") return "image/png";
  return null;
}

/** Minimal JPEG/PNG dimension sniff (no full decode). */
export function sniffDimensions(
  bytes: Uint8Array,
  contentType: string,
): { width: number; height: number } | null {
  if (contentType === "image/png" && bytes.length >= 24) {
    if (bytes[0] === 0x89 && bytes[1] === 0x50) {
      const width = readU32(bytes, 16);
      const height = readU32(bytes, 20);
      if (width > 0 && height > 0) return { width, height };
    }
  }
  if (contentType === "image/jpeg") {
    return jpegSize(bytes);
  }
  return null;
}

function readU32(b: Uint8Array, i: number): number {
  return ((b[i]! << 24) | (b[i + 1]! << 16) | (b[i + 2]! << 8) | b[i + 3]!) >>> 0;
}

function jpegSize(bytes: Uint8Array): { width: number; height: number } | null {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  let i = 2;
  while (i + 9 < bytes.length) {
    if (bytes[i] !== 0xff) { i++; continue; }
    const marker = bytes[i + 1]!;
    if (marker === 0xd9 || marker === 0xda) break;
    const len = (bytes[i + 2]! << 8) | bytes[i + 3]!;
    if (
      (marker >= 0xc0 && marker <= 0xc3) ||
      (marker >= 0xc5 && marker <= 0xc7) ||
      (marker >= 0xc9 && marker <= 0xcb) ||
      (marker >= 0xcd && marker <= 0xcf)
    ) {
      const height = (bytes[i + 5]! << 8) | bytes[i + 6]!;
      const width = (bytes[i + 7]! << 8) | bytes[i + 8]!;
      if (width > 0 && height > 0) return { width, height };
      return null;
    }
    i += 2 + len;
  }
  return null;
}
