/**
 * Kroger Products API client (OAuth2 client_credentials + product lookup).
 *
 * Live host (validated 2026-07-24): https://api.kroger.com
 * Override with env `KROGER_BASE_URL` (no trailing slash).
 *
 * Auth:
 *   POST {base}/v1/connect/oauth2/token
 *     grant_type=client_credentials&scope=product.compact
 *     → { access_token, expires_in, token_type }
 *
 * Products:
 *   GET {base}/v1/products/{productId}          → { data: Product } | 404 empty body
 *   GET {base}/v1/products?filter.term=…        → { data: Product[], meta }
 *   GET {base}/v1/products?filter.productId=…   → { data: Product[], meta }
 *   filter.upc is NOT supported (PRODUCT-2016).
 *
 * Images: `images[].perspective` ("front", "left", …) + `sizes[].{size,url}`
 * with size ∈ thumbnail|small|medium|large|xlarge.
 */

import { krogerProductIdCandidates, normalizeBarcodeForKroger } from "./barcode.ts";


/** Default production API host — override via Env.KROGER_BASE_URL. */
export const DEFAULT_KROGER_BASE_URL = "https://api.kroger.com";

const TOKEN_KV_KEY = "kroger:oauth:product.compact";
/** Refresh a minute before the token actually expires. */
const TOKEN_SKEW_MS = 60_000;

/** Approximate CDN widths for Kroger size names — pick largest ≤ ~1000px. */
const SIZE_WIDTH: Record<string, number> = {
  xlarge: 1000,
  large: 500,
  medium: 350,
  small: 200,
  thumbnail: 100,
};
const MAX_PICK_WIDTH = 1000;

export interface KrogerCredentials {
  clientId: string;
  clientSecret: string;
}

export interface KrogerImageHit {
  url: string;
  perspective: string;
  sizeName: string;
  estimatedWidth: number;
  isFrontImage: boolean;
}

export type KrogerFetchResult =
  | { kind: "hit"; image: KrogerImageHit }
  | { kind: "miss" }           // product absent or no usable image
  | { kind: "rate_limited" }   // 429 / 5xx — caller should negative-cache briefly
  | { kind: "unavailable" };   // no credentials configured

export interface KrogerDeps {
  kv: KVNamespace;
  credentials: KrogerCredentials | null;
  /** e.g. https://api.kroger.com — no trailing slash. */
  baseUrl?: string;
  fetchFn?: typeof fetch;
  now?: () => number;
}

interface TokenRecord {
  access_token: string;
  expires_at: number; // epoch ms
}

interface KrogerImageSize {
  size?: string;
  url?: string;
}

interface KrogerImage {
  perspective?: string;
  featured?: boolean;
  sizes?: KrogerImageSize[];
}

interface KrogerProduct {
  productId?: string;
  upc?: string;
  images?: KrogerImage[];
}

function rootUrl(deps: KrogerDeps): string {
  const raw = (deps.baseUrl || DEFAULT_KROGER_BASE_URL).trim();
  return raw.replace(/\/$/, "") || DEFAULT_KROGER_BASE_URL;
}

/**
 * Look up a barcode on Kroger and return the best front pack shot URL.
 * Soft-fails on rate limits / server errors so the image chain can continue.
 *
 * Tries {@link krogerProductIdCandidates} in order — standard GTIN-13 first,
 * then UPC-A without check digit (common Kroger `productId` form).
 */
export async function fetchKrogerImage(
  barcode: string,
  deps: KrogerDeps,
): Promise<KrogerFetchResult> {
  if (!deps.credentials?.clientId || !deps.credentials?.clientSecret) {
    return { kind: "unavailable" };
  }
  const candidates = krogerProductIdCandidates(barcode);
  if (!candidates.length) return { kind: "miss" };

  const fetchFn: typeof fetch = deps.fetchFn
    ?? ((input, init) => fetch(input, init));
  const now = deps.now ?? Date.now;
  const base = rootUrl(deps);

  console.log(JSON.stringify({
    event: "image_kroger_lookup",
    barcode,
    normalized: normalizeBarcodeForKroger(barcode),
    candidates,
  }));

  try {
    let token = await getAccessToken(deps, fetchFn, now, base);
    let sawRateLimit = false;

    for (const upc of candidates) {
      let res = await productById(base, upc, token, fetchFn);

      if (res.status === 401) {
        // Token revoked / expired early — drop cache and retry once.
        await deps.kv.delete(TOKEN_KV_KEY);
        token = await getAccessToken(deps, fetchFn, now, base, /* force */ true);
        res = await productById(base, upc, token, fetchFn);
      }

      if (res.status === 429 || res.status >= 500) {
        sawRateLimit = true;
        continue;
      }

      // Live API returns 404 with an empty body for unknown productIds.
      if (res.status === 404) {
        const search = await searchByTerm(base, upc, token, fetchFn);
        if (search.status === 429 || search.status >= 500) {
          sawRateLimit = true;
          continue;
        }
        if (!search.ok) continue;
        const searched = (await search.json()) as { data?: KrogerProduct[] };
        const product = Array.isArray(searched.data) ? searched.data[0] : undefined;
        const image = product ? pickBestImage(product.images ?? []) : null;
        if (image) {
          console.log(JSON.stringify({
            event: "image_kroger_hit",
            barcode,
            productId: upc,
            via: "filter.term",
          }));
          return { kind: "hit", image };
        }
        continue;
      }
      if (!res.ok) continue;

      // GET /products/{id} → `{ data: { ...product } }` (object, not array).
      const body = (await res.json()) as { data?: KrogerProduct | KrogerProduct[] };
      const product = Array.isArray(body.data) ? body.data[0] : body.data;
      if (!product) continue;
      const image = pickBestImage(product.images ?? []);
      if (image) {
        console.log(JSON.stringify({
          event: "image_kroger_hit",
          barcode,
          productId: upc,
          via: "products.id",
        }));
        return { kind: "hit", image };
      }
    }

    return sawRateLimit ? { kind: "rate_limited" } : { kind: "miss" };
  } catch {
    return { kind: "rate_limited" };
  }
}

/** Prefer perspective "front", then largest size with estimated width ≤ 1000. */
export function pickBestImage(images: KrogerImage[]): KrogerImageHit | null {
  if (!images.length) return null;

  const ordered = [...images].sort((a, b) => {
    const aFront = a.perspective?.toLowerCase() === "front" ? 0 : 1;
    const bFront = b.perspective?.toLowerCase() === "front" ? 0 : 1;
    if (aFront !== bFront) return aFront - bFront;
    if (a.featured && !b.featured) return -1;
    if (!a.featured && b.featured) return 1;
    return 0;
  });

  for (const img of ordered) {
    const sizes = img.sizes ?? [];
    let best: { url: string; sizeName: string; width: number } | null = null;
    for (const s of sizes) {
      if (!s.url || !s.size) continue;
      const width = SIZE_WIDTH[s.size.toLowerCase()] ?? 0;
      if (width <= 0 || width > MAX_PICK_WIDTH) continue;
      if (!best || width > best.width) {
        best = { url: s.url, sizeName: s.size.toLowerCase(), width };
      }
    }
    if (best) {
      const perspective = (img.perspective ?? "unknown").toLowerCase();
      return {
        url: best.url,
        perspective,
        sizeName: best.sizeName,
        estimatedWidth: best.width,
        isFrontImage: perspective === "front",
      };
    }
  }
  return null;
}

// --- OAuth -----------------------------------------------------------------

async function getAccessToken(
  deps: KrogerDeps,
  fetchFn: typeof fetch,
  now: () => number,
  base: string,
  force = false,
): Promise<string> {
  if (!force) {
    const cached = await deps.kv.get<TokenRecord>(TOKEN_KV_KEY, "json");
    if (cached?.access_token && cached.expires_at - TOKEN_SKEW_MS > now()) {
      return cached.access_token;
    }
  }

  const { clientId, clientSecret } = deps.credentials!;
  const basic = btoa(`${clientId}:${clientSecret}`);
  const res = await fetchFn(`${base}/v1/connect/oauth2/token`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${basic}`,
      Accept: "application/json",
    },
    body: "grant_type=client_credentials&scope=product.compact",
  });
  if (!res.ok) {
    throw new Error(`Kroger token ${res.status}`);
  }
  const data = (await res.json()) as {
    access_token: string;
    expires_in: number;
    token_type?: string;
  };
  const record: TokenRecord = {
    access_token: data.access_token,
    expires_at: now() + Math.max(60, data.expires_in) * 1000,
  };
  const ttl = Math.max(60, Math.floor(data.expires_in));
  await deps.kv.put(TOKEN_KV_KEY, JSON.stringify(record), { expirationTtl: ttl });
  return record.access_token;
}

async function productById(
  base: string,
  upc: string,
  token: string,
  fetchFn: typeof fetch,
): Promise<Response> {
  return fetchFn(`${base}/v1/products/${encodeURIComponent(upc)}`, {
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${token}`,
    },
  });
}

/** Fallback when path ID 404s — `filter.term` accepts a UPC string. */
async function searchByTerm(
  base: string,
  upc: string,
  token: string,
  fetchFn: typeof fetch,
): Promise<Response> {
  const url = `${base}/v1/products?filter.term=${encodeURIComponent(upc)}&filter.limit=1`;
  return fetchFn(url, {
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${token}`,
    },
  });
}
