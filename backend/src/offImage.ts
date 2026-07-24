/**
 * OFF front-image selection — mirrors Sage/OFFImageResolver.swift so the
 * Worker reuses the same priority order without duplicating ad-hoc URL picks.
 *
 * Order: selected_images.front.display[preferred langs] → product lang →
 * any remaining display → image_front_url → image_url (non-front).
 */

import type { OFFProduct } from "./off.ts";

export interface OFFResolvedImage {
  displayURL: string;
  thumbURL: string | null;
  isFrontImage: boolean;
  width: number | null;
  height: number | null;
  isLowQuality: boolean;
}

const LOW_QUALITY_LONGEST = 300;
const DEFAULT_LANGS = ["pt", "en", "es"];

type ImageEntry = {
  rev?: string | number;
  sizes?: Record<string, { w?: number; h?: number }>;
};

export function resolveOFFFrontImage(
  product: OFFProduct | null | undefined,
  barcode: string,
  preferredLanguages: string[] = DEFAULT_LANGS,
): OFFResolvedImage | null {
  if (!product) return null;

  const langs = preferredLanguages.map(normalizeLang).filter(Boolean);
  const productLang = normalizeLang(String(product["lang"] ?? ""));
  const display = selectedFrontDisplay(product);
  const images = (product["images"] as Record<string, ImageEntry> | undefined) ?? undefined;
  const claimed = new Set<string>();

  for (const code of langs) {
    claimed.add(code);
    const hit = resolveSelected(code, barcode, display, images);
    if (hit) return hit;
  }

  if (productLang && !claimed.has(productLang)) {
    claimed.add(productLang);
    const hit = resolveSelected(productLang, barcode, display, images);
    if (hit) return hit;
  }

  if (display) {
    for (const rawKey of Object.keys(display).sort()) {
      const code = normalizeLang(rawKey);
      if (claimed.has(code)) continue;
      claimed.add(code);
      const hit = resolveSelected(code, barcode, display, images, display[rawKey]);
      if (hit) return hit;
    }
  }

  const front = fromReadyURL(
    asString(product["image_front_url"]),
    barcode,
    true,
    images,
  );
  if (front) return front;

  return fromReadyURL(asString(product["image_url"]), barcode, false, images);
}

/** Upgrade `.100.jpg` / `.200.jpg` → `.400.jpg` without changing lang/rev. */
export function upgradeOFFThumbURL(raw: string | null | undefined): string | null {
  const s = sanitize(raw);
  if (!s) return null;
  return s.replace(/\.(100|200)\.jpg$/i, ".400.jpg");
}

// --- internals -------------------------------------------------------------

function selectedFrontDisplay(product: OFFProduct): Record<string, string> | null {
  const selected = product["selected_images"] as
    | { front?: { display?: Record<string, string> } }
    | undefined;
  const d = selected?.front?.display;
  return d && typeof d === "object" ? d : null;
}

function resolveSelected(
  lang: string,
  barcode: string,
  display: Record<string, string> | null,
  images: Record<string, ImageEntry> | undefined,
  readyURL?: string,
): OFFResolvedImage | null {
  const raw =
    readyURL ??
    display?.[lang] ??
    (display
      ? Object.entries(display).find(([k]) => normalizeLang(k) === lang)?.[1]
      : undefined);
  if (!raw) return null;

  const key = `front_${lang}`;
  const entry = images?.[key];
  const rev = entry?.rev != null ? String(entry.rev) : null;
  if (rev) {
    const built = buildOFFURL(barcode, key, rev, entry);
    if (built) return built;
  }
  return fromReadyURL(raw, barcode, true, images, lang);
}

function fromReadyURL(
  raw: string | null,
  barcode: string,
  isFront: boolean,
  images: Record<string, ImageEntry> | undefined,
  lang?: string,
): OFFResolvedImage | null {
  let s = sanitize(raw);
  if (!s) return null;

  const parts = parseOFFImageURL(s);
  if (parts) {
    const entry = images?.[parts.imageKey];
    const rev = entry?.rev != null ? String(entry.rev) : parts.rev;
    const code = barcode || parts.barcodeHint || "";
    if (rev && code) {
      const built = buildOFFURL(code, parts.imageKey, rev, entry);
      if (built) {
        return {
          ...built,
          isFrontImage: isFront || parts.imageKey.startsWith("front_"),
        };
      }
    }
  }

  s = upgradeOFFThumbURL(s) ?? s;
  const size = estimatedSize(lang ? `front_${lang}` : parts?.imageKey, images);
  return {
    displayURL: s,
    thumbURL: upgradeOFFThumbURL(s) ?? s,
    isFrontImage: isFront,
    width: size?.w ?? null,
    height: size?.h ?? null,
    isLowQuality: isLowQuality(size),
  };
}

function buildOFFURL(
  barcode: string,
  imageKey: string,
  rev: string,
  entry: ImageEntry | undefined,
): OFFResolvedImage | null {
  const folder = splitBarcodeFolder(barcode);
  if (!folder) return null;
  const base = `https://images.openfoodfacts.org/images/products/${folder}/${imageKey}.${rev}`;
  const size = estimatedSizeFromEntry(entry);
  return {
    displayURL: `${base}.full.jpg`,
    thumbURL: `${base}.400.jpg`,
    isFrontImage: imageKey.startsWith("front_"),
    width: size?.w ?? null,
    height: size?.h ?? null,
    isLowQuality: isLowQuality(size),
  };
}

export function splitBarcodeFolder(barcode: string): string {
  const digits = barcode.replace(/\D/g, "");
  if (!digits) return barcode;
  if (digits.length >= 9) {
    return `${digits.slice(0, 3)}/${digits.slice(3, 6)}/${digits.slice(6, 9)}/${digits.slice(9)}`;
  }
  return digits;
}

function parseOFFImageURL(url: string): {
  imageKey: string;
  rev: string;
  barcodeHint: string | null;
} | null {
  const m = url.match(
    /images\/products\/(?:((?:\d{3}\/){3}\d+|\d+)\/)?([a-z]+_[a-z]{2})\.(\d+)\.(100|200|400|full)\.jpg$/i,
  );
  if (!m) return null;
  return {
    barcodeHint: m[1] ? m[1].replace(/\//g, "") : null,
    imageKey: m[2],
    rev: m[3],
  };
}

function estimatedSize(
  imageKey: string | undefined,
  images: Record<string, ImageEntry> | undefined,
): { w: number; h: number } | null {
  if (!imageKey || !images) return null;
  return estimatedSizeFromEntry(images[imageKey]);
}

function estimatedSizeFromEntry(entry: ImageEntry | undefined): { w: number; h: number } | null {
  const full = entry?.sizes?.["full"];
  const w = full?.w;
  const h = full?.h;
  if (typeof w === "number" && typeof h === "number" && w > 0 && h > 0) {
    return { w, h };
  }
  return null;
}

function isLowQuality(size: { w: number; h: number } | null): boolean {
  if (!size) return false;
  return Math.max(size.w, size.h) < LOW_QUALITY_LONGEST;
}

function normalizeLang(raw: string): string {
  const t = raw.trim().toLowerCase();
  if (!t) return "";
  const i = t.search(/[-_]/);
  return i === -1 ? t : t.slice(0, i);
}

function asString(v: unknown): string | null {
  return typeof v === "string" && v.trim() ? v.trim() : null;
}

function sanitize(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const s = raw.trim();
  if (!s) return null;
  try {
    const u = new URL(s);
    if (u.protocol !== "https:") return null;
    return s;
  } catch {
    return null;
  }
}
