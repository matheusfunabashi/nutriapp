/**
 * Walmart Content Provider (Affiliate) API client — official pack shots by UPC.
 *
 * Slots between Kroger and OFF in the image chain: Walmart's US grocery
 * catalog covers many products Kroger doesn't stock (energy drinks, niche
 * brands), and its images are studio pack shots.
 *
 * Requires Walmart.io affiliate approval (walmart.io → Affiliate APIs). Inert
 * until credentials are configured:
 *   WALMART_CONSUMER_ID   — consumer ID from the Walmart.io app
 *   WALMART_PRIVATE_KEY   — PKCS#8 PEM private key (the public half is
 *                           uploaded to Walmart.io)
 *   WALMART_KEY_VERSION   — key version shown on Walmart.io (default "1")
 *
 * Auth (per Walmart.io "Walmart Affiliate API" quickstart): each request sends
 *   WM_CONSUMER.ID, WM_CONSUMER.INTIMESTAMP (epoch ms),
 *   WM_SEC.KEY_VERSION, and WM_SEC.AUTH_SIGNATURE =
 *   base64(RSA-SHA256 over "{consumerId}\n{timestamp}\n{keyVersion}\n").
 *
 * Lookup:
 *   GET {base}/api-proxy/service/affil/product/v2/items?upc={12-digit UPC}
 *   → { items: [{ name, upc, largeImage, mediumImage, thumbnailImage,
 *                 imageEntities: [{ entityType, largeImage, … }] }] }
 *
 * NOTE: endpoint shape captured from Walmart.io docs; validate against the
 * live API when the first real key lands (see walmart.test.ts for the
 * contract this module assumes).
 */

export const DEFAULT_WALMART_BASE_URL = "https://developer.api.walmart.com";

export interface WalmartCredentials {
  consumerId: string;
  /** PKCS#8 PEM ("-----BEGIN PRIVATE KEY-----…"). */
  privateKeyPem: string;
  keyVersion: string;
}

export interface WalmartImageHit {
  url: string;
  isFrontImage: boolean;
  /** Walmart large images are ~1000-2000px studio shots. */
  estimatedWidth: number;
}

export type WalmartFetchResult =
  | { kind: "hit"; image: WalmartImageHit }
  | { kind: "miss" }           // not in catalog or no usable image
  | { kind: "rate_limited" }   // 429 / 5xx — caller should back off
  | { kind: "unavailable" };   // no credentials configured

export interface WalmartDeps {
  credentials: WalmartCredentials | null;
  /** e.g. https://developer.api.walmart.com — no trailing slash. */
  baseUrl?: string;
  fetchFn?: typeof fetch;
  now?: () => number;
}

/** 12-digit UPC-A for the `upc` query param, or null when not representable. */
export function walmartUPC(raw: string): string | null {
  const digits = String(raw ?? "").replace(/\D/g, "");
  if (digits.length === 12) return digits;
  if (digits.length === 13 && digits.startsWith("0")) return digits.slice(1);
  if (digits.length === 14 && digits.startsWith("00")) return digits.slice(2);
  if (digits.length === 11) return digits.padStart(12, "0"); // dropped leading 0
  return null;
}

interface WalmartItem {
  name?: string;
  upc?: string;
  largeImage?: string;
  mediumImage?: string;
  thumbnailImage?: string;
  imageEntities?: {
    entityType?: string;
    largeImage?: string;
    mediumImage?: string;
    thumbnailImage?: string;
  }[];
}

/** Best image URL from a Walmart item — PRIMARY entity first, largest size. */
export function pickWalmartImage(item: WalmartItem): WalmartImageHit | null {
  const primary = (item.imageEntities ?? []).find(
    (e) => (e.entityType ?? "").toUpperCase() === "PRIMARY",
  );
  const url = primary?.largeImage || item.largeImage
    || primary?.mediumImage || item.mediumImage;
  if (!url) return null;
  const isLarge = url === (primary?.largeImage || item.largeImage);
  return { url, isFrontImage: true, estimatedWidth: isLarge ? 1000 : 350 };
}

async function signature(
  creds: WalmartCredentials,
  timestamp: number,
): Promise<string> {
  const pem = creds.privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false, ["sign"],
  );
  const payload = `${creds.consumerId}\n${timestamp}\n${creds.keyVersion}\n`;
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(payload),
  );
  return btoa(String.fromCharCode(...new Uint8Array(sig)));
}

export async function fetchWalmartImage(
  barcode: string,
  deps: WalmartDeps,
): Promise<WalmartFetchResult> {
  if (!deps.credentials) return { kind: "unavailable" };
  const upc = walmartUPC(barcode);
  if (!upc) return { kind: "miss" };

  const fetchFn: typeof fetch = deps.fetchFn ?? ((i, o) => fetch(i, o));
  const now = deps.now ?? Date.now;
  const base = (deps.baseUrl ?? DEFAULT_WALMART_BASE_URL).replace(/\/$/, "");
  const timestamp = now();

  let sig: string;
  try {
    sig = await signature(deps.credentials, timestamp);
  } catch (err) {
    console.log(JSON.stringify({ event: "walmart_sign_error", error: String(err) }));
    return { kind: "unavailable" };
  }

  const url = `${base}/api-proxy/service/affil/product/v2/items?upc=${encodeURIComponent(upc)}`;
  let res: Response;
  try {
    res = await fetchFn(url, {
      headers: {
        "WM_CONSUMER.ID": deps.credentials.consumerId,
        "WM_CONSUMER.INTIMESTAMP": String(timestamp),
        "WM_SEC.KEY_VERSION": deps.credentials.keyVersion,
        "WM_SEC.AUTH_SIGNATURE": sig,
        Accept: "application/json",
      },
    });
  } catch (err) {
    console.log(JSON.stringify({ event: "walmart_fetch_error", barcode, error: String(err) }));
    return { kind: "rate_limited" };
  }

  if (res.status === 404) return { kind: "miss" };
  if (res.status === 429 || res.status >= 500) return { kind: "rate_limited" };
  if (!res.ok) {
    console.log(JSON.stringify({ event: "walmart_http_error", barcode, status: res.status }));
    return { kind: "miss" };
  }

  let body: { items?: WalmartItem[] };
  try {
    body = await res.json();
  } catch {
    return { kind: "miss" };
  }
  const item = (body.items ?? []).find((i) =>
    !i.upc || i.upc.replace(/\D/g, "").endsWith(upc),
  );
  if (!item) return { kind: "miss" };
  const image = pickWalmartImage(item);
  if (!image) return { kind: "miss" };
  return { kind: "hit", image };
}
