// Go-UPC premium fallback. Used only when OFF has no product AND the user is
// premium. Go-UPC is an *identity* database (name / brand / image / category),
// so nutriment fields are usually absent — we normalize into an OFF-shaped
// object so the iOS app's existing mapper parses it unchanged. The app/scoring
// degrade gracefully when nutriments are missing.
//
// ToS note: data may be cached while the subscription is active, must be deleted
// on cancellation (tracked via product_meta.go_upc_fetched), and must never be
// redistributed or exposed publicly.

import type { OFFProduct } from "./off";

const ENDPOINT = "https://go-upc.com/api/v1/code";

interface GoUpcProduct {
  name?: string;
  brand?: string;
  description?: string;
  imageUrl?: string;
  category?: string;
}

export async function fetchGoUPC(barcode: string, apiKey: string): Promise<OFFProduct | null> {
  const res = await fetch(`${ENDPOINT}/${encodeURIComponent(barcode)}`, {
    headers: { Authorization: `Bearer ${apiKey}` },
  });

  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Go-UPC ${res.status}`);

  const data = (await res.json()) as { product?: GoUpcProduct };
  const gp = data.product;
  if (!gp?.name) return null;

  const categories = gp.category
    ? [`en:${gp.category.toLowerCase().trim().replace(/\s+/g, "-")}`]
    : [];

  // OFF-shaped so the existing iOS mapper consumes it; `_source` marks provenance.
  return {
    code: barcode,
    product_name: gp.name,
    brands: gp.brand ?? "",
    image_url: gp.imageUrl ?? null,
    image_front_url: gp.imageUrl ?? null,
    categories_tags: categories,
    ingredients_text: gp.description ?? "",
    nutriments: {},
    _source: "go_upc",
  } as OFFProduct;
}
