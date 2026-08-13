/**
 * Go-UPC barcode database client — aggregator pack shots by GTIN.
 *
 * Sits after the retailer tiers (Kroger, Walmart) and before Open Food Facts:
 * measured 86% image coverage on a sample of products our retailer tiers miss,
 * including store brands (Kirkland, Trader Joe's, Aldi) that no single retailer
 * API carries. Coverage is US-centric — UK/CA barcodes hit far less often, so
 * OFF remains the fallback behind this tier.
 *
 * Inert until credentials are configured:
 *   GOUPC_API_KEY   — key from go-upc.com/account (plan-limited monthly quota)
 *
 * Auth:  Authorization: Bearer {key}
 * Lookup:
 *   GET {base}/code/{gtin}
 *   → 200 { code, codeType, product: { name, imageUrl, brand, … }, inferred }
 *   → 400 invalid code · 401 bad key · 404 not found · 429 rate/quota
 *
 * Quota discipline: the caller's negative cache (MISS_TTL) plus the shared R2
 * image cache mean we spend a lookup once per new barcode, not once per scan.
 * `inferred: true` responses describe a guessed product rather than a catalog
 * match, so they are treated as a miss.
 */

export const DEFAULT_GOUPC_BASE_URL = "https://go-upc.com/api/v1";

/** Documented ceiling across all plans; we stay under it with a small gap. */
export const GOUPC_MAX_REQUESTS_PER_SECOND = 2;

export interface GoUPCImageHit {
  url: string;
  /** Go-UPC serves a single catalog front image per product. */
  isFrontImage: boolean;
  estimatedWidth: number;
}

export type GoUPCFetchResult =
  | { kind: "hit"; image: GoUPCImageHit }
  | { kind: "miss" }           // 400/404, inferred match, or no image
  | { kind: "rate_limited" }   // 429 / 5xx — caller should back off
  | { kind: "unavailable" };   // no key configured, or key rejected (401)

export interface GoUPCDeps {
  apiKey: string | null;
  /** e.g. https://go-upc.com/api/v1 — no trailing slash. */
  baseUrl?: string;
  fetchFn?: typeof fetch;
}

/**
 * Go-UPC accepts UPC-A, EAN-13, EAN-8 and GTIN-14 as-is, so we only normalize
 * away non-digits and reject codes too short to be a real GTIN.
 */
export function goupcCode(raw: string): string | null {
  const digits = String(raw ?? "").replace(/\D/g, "");
  if (digits.length < 8 || digits.length > 14) return null;
  return digits;
}

interface GoUPCProduct {
  name?: string;
  imageUrl?: string;
  brand?: string;
}

interface GoUPCResponse {
  product?: GoUPCProduct;
  /** True when Go-UPC guessed the product rather than matching its catalog. */
  inferred?: boolean;
}

export async function fetchGoUPCImage(
  barcode: string,
  deps: GoUPCDeps,
): Promise<GoUPCFetchResult> {
  if (!deps.apiKey) return { kind: "unavailable" };
  const code = goupcCode(barcode);
  if (!code) return { kind: "miss" };

  const fetchFn: typeof fetch = deps.fetchFn ?? ((i, o) => fetch(i, o));
  const base = (deps.baseUrl ?? DEFAULT_GOUPC_BASE_URL).replace(/\/$/, "");

  let res: Response;
  try {
    res = await fetchFn(`${base}/code/${encodeURIComponent(code)}`, {
      headers: {
        Authorization: `Bearer ${deps.apiKey}`,
        Accept: "application/json",
      },
    });
  } catch (err) {
    console.log(JSON.stringify({ event: "goupc_fetch_error", barcode, error: String(err) }));
    return { kind: "rate_limited" };
  }

  if (res.status === 404 || res.status === 400) return { kind: "miss" };
  if (res.status === 401 || res.status === 403) {
    // A bad/expired key must not burn the retry budget on every barcode.
    console.log(JSON.stringify({ event: "goupc_auth_error", status: res.status }));
    return { kind: "unavailable" };
  }
  if (res.status === 429 || res.status >= 500) return { kind: "rate_limited" };
  if (!res.ok) {
    console.log(JSON.stringify({ event: "goupc_http_error", barcode, status: res.status }));
    return { kind: "miss" };
  }

  let body: GoUPCResponse;
  try {
    body = await res.json();
  } catch {
    return { kind: "miss" };
  }

  // An inferred record is a guess, not a catalog match — its image (when any)
  // is not trustworthy as *this* product's pack shot.
  if (body.inferred === true) return { kind: "miss" };

  const url = body.product?.imageUrl?.trim();
  if (!url || !/^https:\/\//i.test(url)) return { kind: "miss" };

  return {
    kind: "hit",
    image: { url, isFrontImage: true, estimatedWidth: 600 },
  };
}
