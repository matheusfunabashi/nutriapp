// USDA FoodData Central (Branded Foods) — OFF backfill.
//
// OFF is the primary source; USDA fills the gap when OFF is absent or has no
// nutrition table (see index.ts). USDA is free + public domain (no caching
// restrictions, no premium gate), and unlike Go-UPC it carries full label
// nutrition, so a USDA-sourced product is genuinely scorable. It has NONE of
// OFF's classification layer (NOVA, additive tags, categories, Nutri-Score),
// so this is always gap-fill, never an override of OFF data.
//
// Field-priority (SCORING_V4 data-source table):
//   NOVA / additives / categories / Nutri-Score  → OFF (USDA has none)
//   Nutrition facts (US products)                 → USDA (manufacturer label)
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

/// Barcode lookup against FDC Branded Foods. Search is fuzzy, so we require an
/// exact GTIN match (GTINs are often zero-padded to 14 digits).
export async function fetchUSDA(barcode: string, apiKey: string): Promise<OFFProduct | null> {
  const url =
    `${SEARCH}?query=${encodeURIComponent(barcode)}` +
    `&dataType=Branded&pageSize=10&api_key=${encodeURIComponent(apiKey)}`;

  const res = await fetch(url, {
    headers: { "User-Agent": "Sage/1.0 (backend proxy; contact@sage.app)" },
  });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`USDA ${res.status}`);

  const data = (await res.json()) as { foods?: FdcFood[] };
  const strip = (s: string) => s.replace(/^0+/, "");
  const food = (data.foods ?? []).find(
    (f) => f.gtinUpc && strip(f.gtinUpc) === strip(barcode),
  );
  if (!food?.description) return null;

  // Prefer per-100g values; keep per-serving only as a fallback for nutrients
  // that lack a per-100g entry.
  const per100: Record<string, number> = {};
  const perServing: Record<string, number> = {};
  for (const n of food.foodNutrients ?? []) {
    const m = n.nutrientNumber ? NUTRIENT_MAP[n.nutrientNumber] : undefined;
    if (!m || typeof n.value !== "number") continue;
    const is100 = (n.derivationDescription ?? "").includes("100");
    (is100 ? per100 : perServing)[m.key] = n.value * m.scale;
  }

  const nutriments: Record<string, number> = { ...per100 };
  // Convert any per-serving-only nutrient to per-100g when the serving is a
  // mass/volume we can scale by (grams or millilitres).
  const ss = food.servingSize;
  const unit = (food.servingSizeUnit ?? "").toLowerCase();
  if (ss && ss > 0 && ["g", "grm", "ml", "mlt"].includes(unit)) {
    for (const [k, v] of Object.entries(perServing)) {
      if (!(k in nutriments)) nutriments[k] = v * (100 / ss);
    }
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

/// Field-level merge that PREFERS USDA nutrition (manufacturer label data is
/// more complete/accurate than OFF's transcribed photos for US products).
/// OFF keeps everything USDA doesn't have — the classification layer (NOVA,
/// additives, categories, Nutri-Score), the image, and OFF-only nutriment
/// fields like the fruit/veg/nuts estimate. Ingredient text stays OFF's (it's
/// what NOVA + additives were derived from); USDA fills it only when OFF lacks it.
export function mergeUSDA(off: OFFProduct | null, usda: OFFProduct): OFFProduct {
  if (!off) return usda;
  const merged: OFFProduct = { ...off };

  const offNutr = (off["nutriments"] as Record<string, unknown>) ?? {};
  const usdaNutr = (usda["nutriments"] as Record<string, unknown>) ?? {};
  // USDA wins on overlapping nutrients; OFF-only fields (e.g. the fvn estimate,
  // which USDA has no equivalent for) survive.
  merged["nutriments"] = { ...offNutr, ...usdaNutr };

  if (!off["ingredients_text"] && usda["ingredients_text"]) {
    merged["ingredients_text"] = usda["ingredients_text"];
  }
  merged["_source"] = "off+usda";
  return merged;
}
