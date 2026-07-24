/**
 * Product-image resolution chain for Sage.
 *
 *   curated → cache (R2 + KV) → Kroger pack shot → OFF front image → null
 *
 * On a hit we download bytes once into R2 (`product-images/{barcode}`) and
 * point the iOS app at the stable Worker URL `GET /images/{barcode}`.
 */

import type { Env } from "./types.ts";
import type { OFFProduct } from "./off.ts";
import { resolveOFFFrontImage } from "./offImage.ts";
import { fetchKrogerImage, type KrogerDeps, DEFAULT_KROGER_BASE_URL } from "./kroger.ts";
import { shouldAttemptKroger } from "./barcode.ts";
import { adoptCuratedIfPresent } from "./curatedImages.ts";

export type ImageSourceName = "curated" | "kroger" | "off";

/** Public shape returned on /lookup (and mirrored into Product for the app). */
export interface ProductImagePayload {
  url: string;
  thumbUrl: string;
  source: ImageSourceName;
  isFrontImage: boolean;
  isLowQuality: boolean;
}

export interface ImageCacheMeta {
  source: ImageSourceName;
  isFrontImage: boolean;
  isLowQuality: boolean;
  width: number | null;
  height: number | null;
  fetchedAt: number;
  contentType: string;
  etag?: string;
  upstreamUrl?: string;
  /**
   * Schema version for this KV entry. Missing / older than
   * {@link IMAGE_CACHE_VERSION} → treat as stale and re-resolve (SWR).
   */
  cacheVersion?: number;
}

/**
 * Bump when the resolve chain changes (new upstream, barcode normalization,
 * curated tier, etc.) so existing KV rows re-resolve without a manual flush.
 */
export const IMAGE_CACHE_VERSION = 3;

const IMAGE_KV_PREFIX = "image:v1:";
const MISS_KV_PREFIX = "image:miss:v1:";
const KROGER_BACKOFF_PREFIX = "image:kroger-backoff:v1:";
const R2_KEY_PREFIX = "product-images/";

const FRESH_MS = 30 * 24 * 60 * 60 * 1000;       // 30 days
const KV_TTL_SECONDS = 40 * 24 * 60 * 60;         // keep past freshness for SWR
const MISS_TTL_SECONDS = 7 * 24 * 60 * 60;        // 7 days
const KROGER_BACKOFF_TTL_SECONDS = 6 * 60 * 60;   // 6 hours

function isCacheVersionCurrent(meta: ImageCacheMeta): boolean {
  return meta.cacheVersion === IMAGE_CACHE_VERSION;
}

export interface ResolveImageOptions {
  origin: string;                 // e.g. https://sage-backend.example.workers.dev
  preferredLanguages?: string[];
  /** Injected for tests. */
  krogerDeps?: Partial<KrogerDeps> & { fetchFn?: typeof fetch };
  fetchFn?: typeof fetch;
  now?: () => number;
  /** Skip waitUntil scheduling in unit tests. */
  waitUntil?: (p: Promise<unknown>) => void;
}

/**
 * Resolve the best available image for a barcode. Always returns the Worker
 * `/images/{barcode}` URL when bytes are (or become) cached in R2.
 */
export async function resolveProductImage(
  env: Env,
  barcode: string,
  offProduct: OFFProduct | null,
  opts: ResolveImageOptions,
): Promise<ProductImagePayload | null> {
  const now = opts.now ?? Date.now;
  const waitUntil = opts.waitUntil ?? (() => {});
  const trimmed = barcode.trim();
  if (!trimmed) return null;

  // Negative cache: nothing anywhere.
  if (await env.CACHE.get(missKey(trimmed))) {
    return null;
  }

  // Fresh / stale cache hit.
  const cached = await env.CACHE.get<ImageCacheMeta>(metaKey(trimmed), "json");
  if (cached) {
    const ageStale = now() - cached.fetchedAt > FRESH_MS;
    const versionStale = !isCacheVersionCurrent(cached);
    if (ageStale || versionStale) {
      console.log(JSON.stringify({
        event: "image_cache_stale",
        barcode: trimmed,
        reason: versionStale ? "cache_version" : "age",
        cacheVersion: cached.cacheVersion ?? null,
        expectedVersion: IMAGE_CACHE_VERSION,
      }));
      waitUntil(
        revalidate(env, trimmed, offProduct, opts).catch((err) => {
          console.log(JSON.stringify({
            event: "image_revalidate_error",
            barcode: trimmed,
            error: String(err),
          }));
        }),
      );
    }
    // Confirm object still exists in R2 before advertising the URL.
    const obj = await env.IMAGES.head(r2Key(trimmed));
    if (obj) {
      // Serve stale meanwhile; URL includes current IMAGE_CACHE_VERSION so
      // clients bypass immutable URLCache when the chain was bumped.
      return toPayload(opts.origin, trimmed, cached);
    }
    // R2 missing despite KV — fall through to full resolve.
  }

  return resolveAndStore(env, trimmed, offProduct, opts);
}

/** Background refresh used for stale-while-revalidate. */
async function revalidate(
  env: Env,
  barcode: string,
  offProduct: OFFProduct | null,
  opts: ResolveImageOptions,
): Promise<void> {
  await resolveAndStore(env, barcode, offProduct, opts);
}

async function resolveAndStore(
  env: Env,
  barcode: string,
  offProduct: OFFProduct | null,
  opts: ResolveImageOptions,
): Promise<ProductImagePayload | null> {
  const now = opts.now ?? Date.now;
  // Never pass unbound `fetch` — CF Workers throw Illegal invocation.
  const fetchFn: typeof fetch = opts.fetchFn
    ?? ((input, init) => fetch(input, init));

  // --- (a) Curated override -----------------------------------------------
  const curated = await adoptCuratedIfPresent(env, barcode, IMAGE_CACHE_VERSION, now);
  if (curated) {
    return toPayload(opts.origin, barcode, curated);
  }

  // --- (b) Kroger ----------------------------------------------------------
  const backoff = await env.CACHE.get(krogerBackoffKey(barcode));
  if (!shouldAttemptKroger(barcode)) {
    console.log(JSON.stringify({
      event: "image_kroger_skip",
      barcode,
      reason: "non_upc_a_range",
    }));
  } else if (!backoff) {
    const kroger = await fetchKrogerImage(barcode, {
      kv: env.CACHE,
      credentials: krogerCredentials(env),
      baseUrl: env.KROGER_BASE_URL || DEFAULT_KROGER_BASE_URL,
      fetchFn: opts.krogerDeps?.fetchFn ?? fetchFn,
      now,
      ...opts.krogerDeps,
    });

    if (kroger.kind === "hit") {
      const stored = await ingestUpstream(env, barcode, {
        upstreamUrl: kroger.image.url,
        source: "kroger",
        isFrontImage: kroger.image.isFrontImage,
        isLowQuality: false,
        width: kroger.image.estimatedWidth,
        height: null,
        fetchFn,
        now,
      });
      if (stored) {
        logWin(barcode, "kroger");
        return toPayload(opts.origin, barcode, stored);
      }
      // Download failed — fall through.
    } else if (kroger.kind === "rate_limited") {
      await env.CACHE.put(krogerBackoffKey(barcode), "1", {
        expirationTtl: KROGER_BACKOFF_TTL_SECONDS,
      });
      console.log(JSON.stringify({
        event: "image_kroger_backoff",
        barcode,
        ttlHours: 6,
      }));
    } else if (kroger.kind === "miss") {
      console.log(JSON.stringify({ event: "image_kroger_miss", barcode }));
    }
    // unavailable → continue
  }

  // --- (c) OFF -------------------------------------------------------------
  const off = resolveOFFFrontImage(
    offProduct,
    barcode,
    opts.preferredLanguages,
  );
  if (off && !off.isLowQuality) {
    const stored = await ingestUpstream(env, barcode, {
      upstreamUrl: off.displayURL,
      source: "off",
      isFrontImage: off.isFrontImage,
      isLowQuality: off.isLowQuality,
      width: off.width,
      height: off.height,
      fetchFn,
      now,
    });
    if (stored) {
      logWin(barcode, "off");
      return toPayload(opts.origin, barcode, stored);
    }
  } else if (off?.isLowQuality) {
    // Treat low-quality OFF as a miss for caching purposes — UI prefers
    // placeholder / user photo. Still log so we can measure.
    console.log(JSON.stringify({
      event: "image_off_low_quality",
      barcode,
      width: off.width,
      height: off.height,
    }));
  }

  // --- (d) total miss ------------------------------------------------------
  await env.CACHE.put(missKey(barcode), "1", { expirationTtl: MISS_TTL_SECONDS });
  console.log(JSON.stringify({ event: "image_miss", barcode }));
  return null;
}

interface IngestArgs {
  upstreamUrl: string;
  source: ImageSourceName;
  isFrontImage: boolean;
  isLowQuality: boolean;
  width: number | null;
  height: number | null;
  fetchFn: typeof fetch;
  now: () => number;
}

async function ingestUpstream(
  env: Env,
  barcode: string,
  args: IngestArgs,
): Promise<ImageCacheMeta | null> {
  const res = await args.fetchFn(args.upstreamUrl, {
    headers: { "User-Agent": "Sage/1.0 (image cache; contact@sage.app)" },
  });
  if (!res.ok) return null;
  const bytes = await res.arrayBuffer();
  if (!bytes.byteLength) return null;

  const contentType = res.headers.get("content-type") || "image/jpeg";
  // Prefer a stable Worker-owned ETag over upstream (Kroger etags are unstable).
  const etag = `"${barcode}-${bytes.byteLength}-${args.now()}"`;
  const meta: ImageCacheMeta = {
    source: args.source,
    isFrontImage: args.isFrontImage,
    isLowQuality: args.isLowQuality,
    width: args.width,
    height: args.height,
    fetchedAt: args.now(),
    contentType,
    etag,
    upstreamUrl: args.upstreamUrl,
    cacheVersion: IMAGE_CACHE_VERSION,
  };

  await env.IMAGES.put(r2Key(barcode), bytes, {
    httpMetadata: { contentType },
    customMetadata: {
      source: meta.source,
      isFrontImage: String(meta.isFrontImage),
      width: meta.width != null ? String(meta.width) : "",
      height: meta.height != null ? String(meta.height) : "",
      fetchedAt: String(meta.fetchedAt),
    },
  });
  console.log(JSON.stringify({
    event: "image_r2_put",
    barcode,
    source: meta.source,
    bytes: bytes.byteLength,
  }));
  await env.CACHE.put(metaKey(barcode), JSON.stringify(meta), {
    expirationTtl: KV_TTL_SECONDS,
  });
  // Clear any prior miss / backoff for this barcode.
  await env.CACHE.delete(missKey(barcode));

  return meta;
}

/** Serve pack-shot bytes from R2 for GET /images/{barcode}. */
export async function serveCachedImage(
  env: Env,
  barcode: string,
  ifNoneMatch: string | null,
  opts?: {
    origin?: string;
    waitUntil?: (p: Promise<unknown>) => void;
    /** When R2+KV miss, run the full resolve chain once (Top Rated / deep links). */
    lazyResolve?: boolean;
  },
): Promise<Response> {
  const trimmed = barcode.trim();
  const key = r2Key(trimmed);
  let obj = await env.IMAGES.get(key);
  let meta = await env.CACHE.get<ImageCacheMeta>(metaKey(trimmed), "json");

  // Lazy hydrate: KV knows the upstream URL but R2 was empty (e.g. pre-R2 era).
  if (!obj && meta?.upstreamUrl) {
    const fetched = await fetch(meta.upstreamUrl, {
      headers: { "User-Agent": "Sage/1.0 (image cache; contact@sage.app)" },
    });
    if (fetched.ok) {
      const bytes = await fetched.arrayBuffer();
      if (bytes.byteLength) {
        const contentType = fetched.headers.get("content-type") || meta.contentType || "image/jpeg";
        const etag = `"${trimmed}-${bytes.byteLength}-${Date.now()}"`;
        meta = { ...meta, contentType, etag, fetchedAt: Date.now() };
        await env.IMAGES.put(key, bytes, {
          httpMetadata: { contentType },
          customMetadata: {
            source: meta.source,
            isFrontImage: String(meta.isFrontImage),
            fetchedAt: String(meta.fetchedAt),
          },
        });
        await env.CACHE.put(metaKey(trimmed), JSON.stringify(meta), {
          expirationTtl: KV_TTL_SECONDS,
        });
        console.log(JSON.stringify({
          event: "image_r2_hydrate",
          barcode: trimmed,
          bytes: bytes.byteLength,
        }));
        obj = await env.IMAGES.get(key);
      }
    }
  }

  // Top Rated / alternatives hit /images/{barcode} without a prior /lookup —
  // resolve once so Kroger/curated/OFF land in R2.
  if (!obj && opts?.lazyResolve) {
    const origin = opts.origin
      ?? "https://sage-backend.sage-app1710.workers.dev";
    await resolveAndStore(env, trimmed, null, {
      origin,
      waitUntil: opts.waitUntil ?? (() => {}),
    }).catch((err) => {
      console.log(JSON.stringify({
        event: "image_lazy_resolve_error",
        barcode: trimmed,
        error: String(err),
      }));
    });
    obj = await env.IMAGES.get(key);
    meta = await env.CACHE.get<ImageCacheMeta>(metaKey(trimmed), "json");
  }

  if (!obj) {
    return new Response("Not found", { status: 404 });
  }

  const etag = meta?.etag ?? obj.httpEtag ?? `"${trimmed}"`;
  if (ifNoneMatch && ifNoneMatch === etag) {
    console.log(JSON.stringify({ event: "image_r2_hit", barcode: trimmed, status: 304 }));
    return new Response(null, {
      status: 304,
      headers: {
        ETag: etag,
        "Cache-Control": "public, max-age=31536000, immutable",
      },
    });
  }

  console.log(JSON.stringify({
    event: "image_r2_hit",
    barcode: trimmed,
    status: 200,
    bytes: obj.size,
  }));

  const headers = new Headers();
  headers.set("Content-Type", obj.httpMetadata?.contentType || meta?.contentType || "image/jpeg");
  headers.set("Cache-Control", "public, max-age=31536000, immutable");
  headers.set("ETag", etag);
  if (obj.size) headers.set("Content-Length", String(obj.size));
  return new Response(obj.body, { status: 200, headers });
}

export function publicImageURL(origin: string, barcode: string): string {
  // `v` busts client URLCache when IMAGE_CACHE_VERSION bumps (R2 key stays
  // stable; Cache-Control is immutable for a given versioned URL).
  const base = `${origin.replace(/\/$/, "")}/images/${encodeURIComponent(barcode)}`;
  return `${base}?v=${IMAGE_CACHE_VERSION}`;
}

function toPayload(
  origin: string,
  barcode: string,
  meta: ImageCacheMeta,
): ProductImagePayload {
  const url = publicImageURL(origin, barcode);
  return {
    url,
    thumbUrl: url,
    source: meta.source,
    isFrontImage: meta.isFrontImage,
    isLowQuality: meta.isLowQuality,
  };
}

function krogerCredentials(env: Env): { clientId: string; clientSecret: string } | null {
  if (!env.KROGER_CLIENT_ID || !env.KROGER_CLIENT_SECRET) return null;
  return { clientId: env.KROGER_CLIENT_ID, clientSecret: env.KROGER_CLIENT_SECRET };
}

function logWin(barcode: string, source: ImageSourceName): void {
  console.log(JSON.stringify({ event: "image_resolved", barcode, source }));
}

export function metaKey(barcode: string): string {
  return `${IMAGE_KV_PREFIX}${barcode}`;
}
export function missKey(barcode: string): string {
  return `${MISS_KV_PREFIX}${barcode}`;
}
export function krogerBackoffKey(barcode: string): string {
  return `${KROGER_BACKOFF_PREFIX}${barcode}`;
}
export function r2Key(barcode: string): string {
  return `${R2_KEY_PREFIX}${barcode}`;
}

// --- Alternatives / Top Rated enrichment -----------------------------------

interface AlternativesCandidate {
  barcode?: string;
  image_url?: string | null;
  [key: string]: unknown;
}

interface AlternativesFile {
  shelves?: Record<string, AlternativesCandidate[]>;
  [key: string]: unknown;
}

/**
 * Rewrite `image_url` to the Worker `/images/{barcode}` URL when R2 already
 * has bytes; otherwise keep the OFF URL and schedule background resolution.
 * Used by GET /alternatives so Top Rated picks up Kroger/curated shots.
 */
export async function enrichAlternativesImages(
  env: Env,
  file: AlternativesFile,
  opts: ResolveImageOptions,
): Promise<AlternativesFile> {
  const shelves = file.shelves ?? {};
  const pending: { barcode: string; offURL: string | null }[] = [];
  const outShelves: Record<string, AlternativesCandidate[]> = {};

  for (const [shelf, list] of Object.entries(shelves)) {
    outShelves[shelf] = [];
    for (const cand of list) {
      const barcode = String(cand.barcode ?? "").trim();
      const clone: AlternativesCandidate = { ...cand };
      if (!barcode) {
        outShelves[shelf]!.push(clone);
        continue;
      }
      const meta = await env.CACHE.get<ImageCacheMeta>(metaKey(barcode), "json");
      const hasR2 = meta ? !!(await env.IMAGES.head(r2Key(barcode))) : false;
      if (hasR2 && meta) {
        if (!isCacheVersionCurrent(meta)) {
          pending.push({ barcode, offURL: (cand.image_url as string) ?? null });
        }
        clone.image_url = publicImageURL(opts.origin, barcode);
      } else {
        pending.push({ barcode, offURL: (cand.image_url as string) ?? null });
      }
      outShelves[shelf]!.push(clone);
    }
  }

  const waitUntil = opts.waitUntil ?? (() => {});
  if (pending.length) {
    waitUntil(
      resolveAlternativesBatch(env, pending, opts).catch((err) => {
        console.log(JSON.stringify({
          event: "image_alternatives_enrich_error",
          error: String(err),
          count: pending.length,
        }));
      }),
    );
  }

  return { ...file, shelves: outShelves };
}

async function resolveAlternativesBatch(
  env: Env,
  pending: { barcode: string; offURL: string | null }[],
  opts: ResolveImageOptions,
): Promise<void> {
  // Limit concurrency so a full Top Rated refresh doesn't stampede Kroger.
  const concurrency = 3;
  let i = 0;
  async function worker() {
    while (i < pending.length) {
      const idx = i++;
      const item = pending[idx]!;
      const offProduct = item.offURL
        ? ({ image_front_url: item.offURL, image_url: item.offURL } as OFFProduct)
        : null;
      await resolveAndStore(env, item.barcode, offProduct, {
        ...opts,
        waitUntil: () => {},
      }).catch(() => {});
    }
  }
  await Promise.all(Array.from({ length: concurrency }, () => worker()));
}
