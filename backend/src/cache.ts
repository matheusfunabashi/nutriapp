// KV cache (L2 shared). Product snapshots + bucketed explanations.
import type { OFFProduct } from "./off";

const PRODUCT_TTL_SECONDS = 60 * 60 * 24 * 30; // 30 days

// --- Product snapshots ---

export function productKey(barcode: string): string {
  // v2: snapshots carry the widened scoring-v4 field set (labels, packaging,
  // origins, ingredient percents, completeness…). New prefix so v1-shaped
  // entries aren't served to clients expecting the richer payload.
  return `product:v2:${barcode}`;
}

export async function getProduct(kv: KVNamespace, barcode: string): Promise<OFFProduct | null> {
  return await kv.get<OFFProduct>(productKey(barcode), "json");
}

export async function putProduct(kv: KVNamespace, barcode: string, product: OFFProduct): Promise<void> {
  await kv.put(productKey(barcode), JSON.stringify(product), { expirationTtl: PRODUCT_TTL_SECONDS });
}

// --- Name-search results ---
// Short TTL: OFF's catalog changes slowly, but a day keeps typo-cache small
// and popular queries (shared across users) nearly always warm.

const SEARCH_TTL_SECONDS = 60 * 60 * 24; // 1 day

export interface SearchHit {
  code: string;
  name: string;
  brand: string;
  quantity: string | null;
  imageURL: string | null;
}

export function searchKey(query: string): string {
  // v2: results are deduped by brand+name and carry quantity — new prefix so
  // stale v1 cache entries aren't served during the TTL window.
  return `search:v2:${query}`;
}

export async function getSearch(kv: KVNamespace, query: string): Promise<SearchHit[] | null> {
  return await kv.get<SearchHit[]>(searchKey(query), "json");
}

export async function putSearch(kv: KVNamespace, query: string, hits: SearchHit[]): Promise<void> {
  await kv.put(searchKey(query), JSON.stringify(hits), { expirationTtl: SEARCH_TTL_SECONDS });
}

// --- Explanations (bucketed by class) ---
// Key = exp:<version>:<barcode>:<classHash>. No TTL — invalidated by bumping
// EXPLANATION_VERSION when the prompt or scoring model changes.

export function explanationKey(version: string, barcode: string, classHash: string): string {
  return `exp:${version}:${barcode}:${classHash}`;
}

export async function getExplanation(kv: KVNamespace, key: string): Promise<string | null> {
  return await kv.get(key, "text");
}

export async function putExplanation(kv: KVNamespace, key: string, text: string): Promise<void> {
  await kv.put(key, text);
}
