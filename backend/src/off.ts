// Open Food Facts lookup. Returns the raw OFF `product` object so the iOS app's
// existing mapper stays the single source of truth for parsing. The Worker is a
// thin caching proxy over OFF (with Go-UPC as a premium fallback — TODO).

const FIELDS = [
  "code", "product_name", "brands", "quantity",
  "nutriscore_grade", "nova_group", "nutriments",
  "additives_tags", "ingredients_analysis_tags", "allergens_tags",
  "ingredients_text", "categories_tags",
  "image_front_url", "image_url",
].join(",");

export type OFFProduct = Record<string, unknown>;

export async function fetchOFF(barcode: string): Promise<OFFProduct | null> {
  const url =
    `https://world.openfoodfacts.org/api/v2/product/${encodeURIComponent(barcode)}.json?fields=${FIELDS}`;

  const res = await fetch(url, {
    headers: { "User-Agent": "Sage/1.0 (backend proxy; contact@sage.app)" },
  });

  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`OFF ${res.status}`);

  const data = (await res.json()) as { product?: OFFProduct };
  const p = data.product;
  if (!p) return null;
  // Treat empty shells as not-found.
  if (!p["product_name"] && !p["nutriments"]) return null;
  return p;
}

export function hasImage(p: OFFProduct | null): boolean {
  return !!(p && (p["image_front_url"] || p["image_url"]));
}
