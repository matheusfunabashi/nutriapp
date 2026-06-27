// KV cache (L2 shared). Product snapshots + bucketed explanations.
import type { OFFProduct } from "./off";

const PRODUCT_TTL_SECONDS = 60 * 60 * 24 * 30; // 30 days

// --- Product snapshots ---

export function productKey(barcode: string): string {
  return `product:${barcode}`;
}

export async function getProduct(kv: KVNamespace, barcode: string): Promise<OFFProduct | null> {
  return await kv.get<OFFProduct>(productKey(barcode), "json");
}

export async function putProduct(kv: KVNamespace, barcode: string, product: OFFProduct): Promise<void> {
  await kv.put(productKey(barcode), JSON.stringify(product), { expirationTtl: PRODUCT_TTL_SECONDS });
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
