// USDA FoodData Central (Branded Foods) — OFF backfill.
//
// OFF is the primary source; USDA gap-fills nutriments OFF lacks (see
// mergeUSDA), except added sugars which USDA may always provide. USDA is free
// + public domain. It has NONE of OFF's classification layer (NOVA, additive
// tags, categories, Nutri-Score), so this is always gap-fill for macros/micros.
//
// Field-priority (SCORING_V5 data-source table):
//   NOVA / additives / categories / Nutri-Score  → OFF (USDA has none)
//   Nutrition facts                              → OFF first; USDA fills gaps
//   added sugars                                 → USDA may always provide
//   Ingredient text                               → present-or-USDA
//   Image                                         → OFF (USDA has none)

import type { OFFProduct } from "./off";

const SEARCH = "https://api.nal.usda.gov/fdc/v1/foods/search";

// FDC nutrientNumber → OFF nutriments key. FDC Branded `foodNutrients` are
// per-100g, matching OFF's `*_100g` convention. Units: macros + kcal align;
// OFF stores sodium/calcium in GRAMS per 100g while FDC gives milligrams, so
// those scale by 1/1000.
const NUTRIENT_MAP: Record<string, { key: string; scale: number }> = {
  "208": { key: "energy-kcal_100g", scale: 1 },
  "203": { key: "proteins_100g", scale: 1 },
  "204": { key: "fat_100g", scale: 1 },
  "606": { key: "saturated-fat_100g", scale: 1 },
  "605": { key: "trans-fat_100g", scale: 1 },
  "205": { key: "carbohydrates_100g", scale: 1 },
  "291": { key: "fiber_100g", scale: 1 },
  "269": { key: "sugars_100g", scale: 1 },
  "539": { key: "added-sugars_100g", scale: 1 },
  "307": { key: "sodium_100g", scale: 0.001 }, // mg → g
  "301": { key: "calcium_100g", scale: 0.001 }, // mg → g
  // Beneficial micronutrients — FDC gives mg, OFF stores grams, so scale mg → g.
  // The Swift decoder reads these OFF keys and scales back to mg for scoring S13.
  "303": { key: "iron_100g", scale: 0.001 }, // mg → g
  "306": { key: "potassium_100g", scale: 0.001 }, // mg → g
  "304": { key: "magnesium_100g", scale: 0.001 }, // mg → g
  "309": { key: "zinc_100g", scale: 0.001 }, // mg → g
  "401": { key: "vitamin-c_100g", scale: 0.001 }, // mg → g
};

interface FdcNutrient {
  nutrientNumber?: string;
  value?: number;
  // FDC returns BOTH a per-100g and a per-serving entry per nutrient; the
  // description distinguishes them ("...per 100 unit measure" vs "...per
  // serving size measure"). We must take the per-100g one.
  derivationDescription?: string;
}
interface FdcFood {
  gtinUpc?: string;
  description?: string;
  brandOwner?: string;
  brandName?: string;
  ingredients?: string;
  servingSize?: number;
  servingSizeUnit?: string;
  foodNutrients?: FdcNutrient[];
}

/// Barcode lookup against FDC Branded Foods. FDC stores GTINs zero-padded to
/// 14 digits and its search only matches that form — a raw 12-digit UPC finds
/// nothing — so we query the padded GTIN-14. We still exact-match the result's
/// gtinUpc (leading zeros stripped) as a guard against fuzzy hits.
export async function fetchUSDA(barcode: string, apiKey: string): Promise<OFFProduct | null> {
  const digits = barcode.replace(/\D/g, "");
  const strip = (s: string) => s.replace(/^0+/, "") || "0";

  // USDA stores GTINs inconsistently — some as the raw 12-digit UPC, some
  // zero-padded to 14 — and its search only matches the exact stored string,
  // so try the raw digits first, then the 14-padded form.
  const forms = [...new Set([digits, digits.padStart(14, "0")])];
  let food: FdcFood | undefined;
  for (const q of forms) {
    const url =
      `${SEARCH}?query=${encodeURIComponent(q)}` +
      `&dataType=Branded&pageSize=10&api_key=${encodeURIComponent(apiKey)}`;
    const res = await fetch(url, {
      headers: { "User-Agent": "Sage/1.0 (backend proxy; contact@sage.app)" },
    });
    if (res.status === 404) continue;
    if (!res.ok) throw new Error(`USDA ${res.status}`);
    const data = (await res.json()) as { foods?: FdcFood[] };
    food = (data.foods ?? []).find(
      (f) => f.gtinUpc && strip(f.gtinUpc) === strip(digits),
    );
    if (food?.description) break;
    food = undefined;
  }
  if (!food?.description) return null;

  // FDC Branded `foodNutrients` values are per-100g (the derivation text just
  // says how they were computed). A nutrient can have two entries — one "given
  // per 100" and one "calculated per serving" — that occasionally disagree, so
  // we prefer the explicit per-100 entry when both exist.
  const chosen: Record<string, { value: number; per100: boolean }> = {};
  for (const n of food.foodNutrients ?? []) {
    const m = n.nutrientNumber ? NUTRIENT_MAP[n.nutrientNumber] : undefined;
    if (!m || typeof n.value !== "number") continue;
    const per100 = (n.derivationDescription ?? "").includes("100");
    const prev = chosen[m.key];
    if (!prev || (per100 && !prev.per100)) {
      chosen[m.key] = { value: n.value * m.scale, per100 };
    }
  }
  const nutriments: Record<string, number> = {};
  for (const [k, v] of Object.entries(chosen)) nutriments[k] = v.value;

  // Defensive: a few records slip through per-serving. Energy per 100g can't
  // exceed ~900 kcal (pure fat) — if it does, rescale everything by the serving.
  const kcal = nutriments["energy-kcal_100g"];
  const ss = food.servingSize;
  const unit = (food.servingSizeUnit ?? "").toLowerCase();
  if (kcal && kcal > 900 && ss && ss > 0 && ["g", "grm", "ml", "mlt"].includes(unit)) {
    const factor = ss / 100;
    for (const k of Object.keys(nutriments)) nutriments[k] = nutriments[k] / factor;
  }

  // OFF-shaped so the iOS mapper consumes it unchanged; `_source` marks provenance.
  return {
    code: barcode,
    product_name: food.description,
    brands: food.brandName || food.brandOwner || "",
    ingredients_text: food.ingredients ?? "",
    nutriments,
    _source: "usda",
  } as OFFProduct;
}

/// Worth a USDA call? USDA only carries US products, so we skip the request
/// for anything OFF marks as sold outside the US — it could never match. OFF
/// absent or with no country info stays eligible (could be a US product).
export function plausiblyUS(off: OFFProduct | null): boolean {
  if (!off) return true;
  const countries = off["countries_tags"];
  if (!Array.isArray(countries) || countries.length === 0) return true;
  return countries.some((t) => typeof t === "string" && t.includes("united-states"));
}

/// Field-level merge: USDA gap-fills nutriments OFF lacks, EXCEPT added sugars
/// which USDA may always provide (S3 prefers addedSugar_g). Classification
/// layer (NOVA, additives, categories, Nutri-Score) stays OFF. Ingredient text
/// stays OFF's (what NOVA + additives were derived from); USDA fills it only
/// when OFF lacks it.
export function mergeUSDA(off: OFFProduct | null, usda: OFFProduct): OFFProduct {
  if (!off) return usda;
  const merged: OFFProduct = { ...off };

  const offNutr = (off["nutriments"] as Record<string, unknown>) ?? {};
  const usdaNutr = (usda["nutriments"] as Record<string, unknown>) ?? {};
  const mergedNutr: Record<string, unknown> = { ...offNutr };
  for (const [key, value] of Object.entries(usdaNutr)) {
    if (value == null) continue;
    const isAddedSugar = key === "added-sugars_100g" || key.startsWith("added-sugars");
    if (isAddedSugar || mergedNutr[key] == null) {
      mergedNutr[key] = value;
    }
  }
  merged["nutriments"] = mergedNutr;

  if (!off["ingredients_text"] && usda["ingredients_text"]) {
    merged["ingredients_text"] = usda["ingredients_text"];
  }
  merged["_source"] = "off+usda";
  return merged;
}
