// Open Food Facts lookup. Returns the raw OFF `product` object so the iOS app's
// existing mapper stays the single source of truth for parsing. The Worker is a
// thin caching proxy over OFF, with USDA FoodData Central as a gap-fill backfill
// (see usda.ts) when OFF is absent or has no nutrition table.

import type { SearchHit } from "./cache.ts";
import { upgradeOFFThumbURL } from "./offImage.ts";

// Scoring v4 (SCORING_V4.md §2) widened this list: labels/certifications,
// packaging, origins, per-ingredient percents, eco grade, data-completeness
// signals, serving size, and market countries all feed the rule engine.
const FIELDS = [
  "code", "product_name", "brands", "quantity",
  "nutriscore_grade", "nova_group", "nutriments",
  "additives_tags", "ingredients_analysis_tags", "allergens_tags",
  "ingredients_text", "categories_tags",
  "image_front_url", "image_front_small_url", "image_url",
  "selected_images", "images", "lang",
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
  if (!p) return false;
  if (p["image_front_url"] || p["image_url"] || p["image_front_small_url"]) return true;
  const selected = p["selected_images"] as
    | { front?: { display?: Record<string, string> } }
    | undefined;
  return !!(selected?.front?.display && Object.keys(selected.front.display).length > 0);
}

// --- Free-text name search -------------------------------------------------
// OFF's search endpoint does the "contains the typed words" matching
// server-side (full-text over name/brand). NOTE: it is rate-limited harder
// than product reads (~10 req/min/IP), which is why /search sits behind the
// Worker's KV cache and the app debounces keystrokes.
//
// Results are post-filtered to:
//   • English-speaking markets only (US, UK, or Canada in `countries_tags`)
//   • Scoreable products (enough nutrition / ingredient signal for the
//     on-device engine — empty shells that open to "insufficient data" are
//     dropped so the typeahead never teases a dead end)

const SEARCH_FIELDS = [
  "code", "product_name", "brands", "quantity",
  "image_front_small_url", "image_front_url",
  "countries_tags", "nutriments", "nova_group",
  "additives_tags", "categories_tags",
  // Ranking signals: data-richness tiebreak reads ingredients_text; the
  // fine-grained tiebreak reads OFF's own completeness score (0–1).
  "ingredients_text", "completeness",
].join(",");
const SEARCH_UA = { "User-Agent": "Sage/1.0 (backend proxy; contact@sage.app)" };
// Sage targets English-speaking markets; search is filtered to these three.
const ALLOWED_COUNTRY_TAGS = ["en:united-states", "en:united-kingdom", "en:canada"];
/** Bare OFF category tags Sage routes to `unsupported` (language prefix stripped). */
const UNSUPPORTED_BARE_TAGS = new Set([
  "waters", "mineral-waters", "spring-waters", "flavored-waters",
  "natural-mineral-waters", "table-waters", "drinking-water", "drinking-waters",
  "alcoholic-beverages", "beers", "wines", "spirits", "ciders",
]);

/** Core per-100g fields that mirror `Product.hasNutritionData` on iOS. */
const CORE_NUTRIMENT_KEYS = [
  "energy-kcal_100g",
  "sugars_100g",
  "saturated-fat_100g",
  "sodium_100g",
  "proteins_100g",
  "fiber_100g",
] as const;

export async function searchOFF(query: string, pageSize = 12): Promise<SearchHit[]> {
  // Over-fetch: US + scorability filters drop a chunk of OFF hits, and we
  // re-rank across the whole survivor set (below) rather than taking OFF's
  // order, so a wide pool matters more than it used to.
  const fetchSize = Math.min(Math.max(pageSize * 4, 40), 60);
  const raw = (await searchModern(query, fetchSize).catch(() => null))
           ?? (await searchLegacy(query, fetchSize));

  // Collect every survivor (deduped) with its ranking signals, THEN sort —
  // we can't truncate mid-iteration anymore or the richest matches past the
  // cutoff would be lost. Dedup still keeps the first (highest upstream)
  // occurrence of a brand|name pair.
  const seen = new Set<string>();
  const ranked: RankedHit[] = [];
  for (const p of raw) {
    if (!isAllowedMarket(p)) continue;
    if (isUnsupportedCategory(p)) continue;
    if (!isScorableForSearch(p)) continue;
    const hit = toSearchHit(p);
    if (!hit) continue;
    const key = `${hit.brand.toLowerCase()}|${hit.name.toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    ranked.push({
      hit,
      relevance: nameRelevance(query, hit.name, hit.brand),
      richness: dataRichness(p),
      completeness: offCompleteness(p),
    });
  }

  return rankHits(ranked).slice(0, pageSize);
}

interface RankedHit {
  hit: SearchHit;
  /** Name/brand match strength for the query (higher = tighter match). */
  relevance: number;
  /** Count of populated data fields, 0–5 (how much the app can show/score). */
  richness: number;
  /** OFF's own completeness score, 0–1. */
  completeness: number;
}

/**
 * Orders results the way the user asked for: name relevance is the primary
 * key (a product actually named like the query always wins), and "how much
 * information is available" only breaks ties — first the count of populated
 * data fields, then OFF's finer-grained completeness score. Array.sort is
 * stable, so equal-ranked hits keep their upstream (OFF relevance) order.
 */
export function rankHits(ranked: RankedHit[]): SearchHit[] {
  return [...ranked]
    .sort((a, b) =>
      b.relevance - a.relevance ||
      b.richness - a.richness ||
      b.completeness - a.completeness)
    .map((r) => r.hit);
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Relevance of a hit's name (and brand) to the typed query. Tiered so an
 * exact / prefix name match always outranks an incidental substring, and a
 * product whose *brand* is the query (name carries only the variant, e.g.
 * brand "Cheetos" / name "Crunchy") still scores well. OFF has already
 * full-text matched, so 0 is rare (query matched some other field).
 */
export function nameRelevance(query: string, name: string, brand: string): number {
  const q = query.trim().toLowerCase();
  if (!q) return 0;
  const n = name.toLowerCase();
  const b = brand.toLowerCase();
  const hay = `${b} ${n}`.trim();
  const wordRe = new RegExp(`(^|[^a-z0-9])${escapeRegExp(q)}([^a-z0-9]|$)`);

  if (n === q || b === q) return 100;              // exact name or brand
  if (n.startsWith(q)) return 90;                  // "cheetos crunchy"
  if (b.startsWith(q)) return 80;                  // brand "Cheetos", name "Crunchy"
  if (wordRe.test(n)) return 70;                   // "flamin hot cheetos"
  if (wordRe.test(hay)) return 60;                 // whole word across brand+name
  if (n.includes(q)) return 50;                    // substring in name
  if (hay.includes(q)) return 40;                  // substring in brand+name
  const tokens = q.split(/\s+/).filter(Boolean);   // multi-word: all tokens present
  if (tokens.length > 1 && tokens.every((t) => hay.includes(t))) return 20;
  return 0;
}

/**
 * "Number of informations available" as a 0–5 count of the data the app can
 * actually show and score: a nutrition panel (≥3 core nutriments), an
 * ingredients list, additive tags, a known NOVA group, and a front image.
 */
export function dataRichness(p: Record<string, unknown>): number {
  let score = 0;
  const nut = (p["nutriments"] && typeof p["nutriments"] === "object")
    ? (p["nutriments"] as Record<string, unknown>)
    : {};
  let core = 0;
  for (const key of CORE_NUTRIMENT_KEYS) {
    const v = nut[key];
    if (typeof v === "number" && Number.isFinite(v)) core += 1;
  }
  if (core >= 3) score += 1;
  const ing = p["ingredients_text"];
  if (typeof ing === "string" && ing.trim().length > 0) score += 1;
  if (tagList(p["additives_tags"]).length > 0) score += 1;
  const nova = Number(p["nova_group"]);
  if (Number.isFinite(nova) && nova >= 1 && nova <= 4) score += 1;
  if (p["image_front_small_url"] || p["image_front_url"] || p["image_url"]) score += 1;
  return score;
}

/** OFF's own 0–1 completeness score; 0 when absent or malformed. */
export function offCompleteness(p: Record<string, unknown>): number {
  const c = Number(p["completeness"]);
  return Number.isFinite(c) ? c : 0;
}

async function searchModern(query: string, pageSize: number): Promise<Record<string, unknown>[]> {
  // search-a-licious combines full-text + field filters in `q` (implicit AND);
  // the market filter is an OR across the allowed countries.
  const countries = ALLOWED_COUNTRY_TAGS.map((t) => `"${t}"`).join(" OR ");
  const q = `${query} countries_tags:(${countries})`;
  const url =
    "https://search.openfoodfacts.org/search" +
    `?q=${encodeURIComponent(q)}&page_size=${pageSize}&fields=${SEARCH_FIELDS}`;
  const res = await fetch(url, { headers: SEARCH_UA });
  if (!res.ok) throw new Error(`OFF search-a-licious ${res.status}`);
  const data = (await res.json()) as { hits?: Record<string, unknown>[] };
  return data.hits ?? [];
}

async function searchLegacy(query: string, pageSize: number): Promise<Record<string, unknown>[]> {
  const url =
    // The CGI can't OR multiple countries, so this rare fallback fetches
    // unfiltered and relies on the isAllowedMarket post-filter (over-fetched).
    "https://world.openfoodfacts.org/cgi/search.pl?action=process&json=1&search_simple=1" +
    `&search_terms=${encodeURIComponent(query)}&page_size=${pageSize}&fields=${SEARCH_FIELDS}`;
  const res = await fetch(url, { headers: SEARCH_UA });
  if (!res.ok) throw new Error(`OFF search ${res.status}`);
  const data = (await res.json()) as { products?: Record<string, unknown>[] };
  return data.products ?? [];
}

function tagList(value: unknown): string[] {
  if (Array.isArray(value)) return value.map((t) => String(t).toLowerCase());
  if (typeof value === "string" && value.trim()) {
    return value.split(/[,|]/).map((t) => t.trim().toLowerCase()).filter(Boolean);
  }
  return [];
}

function bareCategoryTags(p: Record<string, unknown>): string[] {
  return tagList(p["categories_tags"]).map((t) => {
    const i = t.lastIndexOf(":");
    return i >= 0 ? t.slice(i + 1) : t;
  });
}

/** Strict market check — OFF's query filter leaks other-market hits occasionally. */
export function isAllowedMarket(p: Record<string, unknown>): boolean {
  const tags = tagList(p["countries_tags"]);
  return ALLOWED_COUNTRY_TAGS.some((t) => tags.includes(t));
}

export function isUnsupportedCategory(p: Record<string, unknown>): boolean {
  return bareCategoryTags(p).some((t) => UNSUPPORTED_BARE_TAGS.has(t));
}

/**
 * Mirrors `Product.hasMinimumData`: ≥3 core nutrients / 100g, or a known
 * NOVA group, or at least one additive tag. Ingredient text alone is never
 * enough (same rule as the iOS engine).
 */
export function isScorableForSearch(p: Record<string, unknown>): boolean {
  const nut = (p["nutriments"] && typeof p["nutriments"] === "object")
    ? (p["nutriments"] as Record<string, unknown>)
    : {};
  let core = 0;
  for (const key of CORE_NUTRIMENT_KEYS) {
    const v = nut[key];
    if (typeof v === "number" && Number.isFinite(v)) core += 1;
  }
  if (core >= 3) return true;

  const nova = p["nova_group"];
  const novaN = typeof nova === "number" ? nova : Number(nova);
  if (Number.isFinite(novaN) && novaN >= 1 && novaN <= 4) return true;

  const additives = tagList(p["additives_tags"]);
  return additives.length > 0;
}

/// Both endpoints share field names, but search-a-licious returns `brands`
/// as an array while the CGI returns a comma-joined string.
function toSearchHit(p: Record<string, unknown>): SearchHit | null {
  const code = typeof p["code"] === "string" ? p["code"] : "";
  const name = p["product_name"] != null ? String(p["product_name"]).trim() : "";
  if (!code || !name) return null;
  const brands = p["brands"];
  const brand = Array.isArray(brands)
    ? String(brands[0] ?? "").trim()
    : typeof brands === "string" ? brands.split(",")[0]!.trim() : "";
  return {
    code,
    name,
    brand,
    quantity: typeof p["quantity"] === "string" && p["quantity"] !== ""
      ? (p["quantity"] as string).trim() : null,
    imageURL: upgradeOFFThumbURL(
      (p["image_front_small_url"] ?? p["image_front_url"] ?? null) as string | null
    ),
  };
}
