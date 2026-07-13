// Open Food Facts lookup. Returns the raw OFF `product` object so the iOS app's
// existing mapper stays the single source of truth for parsing. The Worker is a
// thin caching proxy over OFF, with USDA FoodData Central as a gap-fill backfill
// (see usda.ts) when OFF is absent or has no nutrition table.

// Scoring v4 (SCORING_V4.md §2) widened this list: labels/certifications,
// packaging, origins, per-ingredient percents, eco grade, data-completeness
// signals, serving size, and market countries all feed the rule engine.
const FIELDS = [
  "code", "product_name", "brands", "quantity",
  "nutriscore_grade", "nova_group", "nutriments",
  "additives_tags", "ingredients_analysis_tags", "allergens_tags",
  "ingredients_text", "categories_tags",
  "image_front_url", "image_url",
  "labels_tags", "packagings", "packaging_materials_tags",
  "origins_tags", "manufacturing_places", "ingredients",
  "ecoscore_grade", "environmental_score_grade",
  "completeness", "states_tags", "last_modified_t",
  "serving_size", "countries_tags", "unknown_ingredients_n",
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

/// True when OFF carries a usable nutrition table. When false, the product is
/// a candidate for USDA backfill (index.ts) — this is the gate that keeps the
/// USDA budget spent only on genuine gaps.
export function hasNutrition(p: OFFProduct | null): boolean {
  const n = p?.["nutriments"] as Record<string, unknown> | undefined;
  if (!n) return false;
  return ["energy-kcal_100g", "proteins_100g", "sugars_100g",
          "fat_100g", "carbohydrates_100g"]
    .some((k) => typeof n[k] === "number");
}

// --- Free-text name search -------------------------------------------------
// OFF's search endpoint does the "contains the typed words" matching
// server-side (full-text over name/brand). NOTE: it is rate-limited harder
// than product reads (~10 req/min/IP), which is why /search sits behind the
// Worker's KV cache and the app debounces keystrokes.

import type { SearchHit } from "./cache";

const SEARCH_FIELDS = "code,product_name,brands,quantity,image_front_small_url,image_front_url";
const SEARCH_UA = { "User-Agent": "Sage/1.0 (backend proxy; contact@sage.app)" };

export async function searchOFF(query: string, pageSize = 20): Promise<SearchHit[]> {
  // Primary: search-a-licious (fast, powers the OFF website). Fallback: the
  // legacy CGI search, which is slower and 503s under load.
  const raw = (await searchModern(query, pageSize).catch(() => null))
           ?? (await searchLegacy(query, pageSize));

  // Collapse size/regional/case variants of the same product (same brand +
  // name, different barcodes — e.g. 400g vs 750g Nutella). Per-100g nutrition
  // is the same across pack sizes, so one row represents them all. We
  // over-fetch then trim so dedup doesn't leave a sparse list.
  const seen = new Set<string>();
  const deduped = raw.filter((h) => {
    const key = `${h.brand.toLowerCase()}|${h.name.toLowerCase()}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  return deduped.slice(0, 12);
}

async function searchModern(query: string, pageSize: number): Promise<SearchHit[]> {
  const url =
    "https://search.openfoodfacts.org/search" +
    `?q=${encodeURIComponent(query)}&page_size=${pageSize}&fields=${SEARCH_FIELDS}`;
  const res = await fetch(url, { headers: SEARCH_UA });
  if (!res.ok) throw new Error(`OFF search-a-licious ${res.status}`);
  const data = (await res.json()) as { hits?: Record<string, unknown>[] };
  return mapHits(data.hits ?? []);
}

async function searchLegacy(query: string, pageSize: number): Promise<SearchHit[]> {
  const url =
    "https://world.openfoodfacts.org/cgi/search.pl?action=process&json=1&search_simple=1" +
    `&search_terms=${encodeURIComponent(query)}&page_size=${pageSize}&fields=${SEARCH_FIELDS}`;
  const res = await fetch(url, { headers: SEARCH_UA });
  if (!res.ok) throw new Error(`OFF search ${res.status}`);
  const data = (await res.json()) as { products?: Record<string, unknown>[] };
  return mapHits(data.products ?? []);
}

/// Both endpoints share field names, but search-a-licious returns `brands`
/// as an array while the CGI returns a comma-joined string.
function mapHits(items: Record<string, unknown>[]): SearchHit[] {
  return items
    .filter((p) => typeof p["code"] === "string" && p["code"] !== "" && p["product_name"])
    .map((p) => {
      const brands = p["brands"];
      const brand = Array.isArray(brands)
        ? String(brands[0] ?? "").trim()
        : typeof brands === "string" ? brands.split(",")[0].trim() : "";
      return {
        code: p["code"] as string,
        name: String(p["product_name"]).trim(),
        brand,
        quantity: typeof p["quantity"] === "string" && p["quantity"] !== ""
          ? (p["quantity"] as string).trim() : null,
        imageURL: (p["image_front_small_url"] ?? p["image_front_url"] ?? null) as string | null,
      };
    });
}
