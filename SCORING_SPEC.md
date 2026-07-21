# Sage Scoring Specification

**Document type:** audit-grade implementation specification  
**Ruleset version:** `2026.08-e1` (`Sage/RulesetV4.json`, mirrored at `backend/src/ruleset.json`)  
**Primary engine:** `Sage/ScoringV4.swift` — `ScoringEngineV4`  
**Live app path:** scan/search → `BackendService.lookup` → `OpenFoodFactsService.map` → `ScoringEngineV4.scoreProduct` (`ContentView` / `AppStore`)  
**Generated from:** current source and config (code wins over comments/docs when they disagree).  

⚠ Findings are marked inline. This document describes what **is**, not what should be.

---

## 1. Data acquisition

### 1.1 Pipeline

```
UI (ContentView / SearchView)
  → BackendService.lookup(barcode)          # Sage/BackendService.swift
    → POST Worker /lookup                   # backend/src/index.ts
      → KV cache hit? return cached OFF-shaped product
      → fetchOFF(barcode)                   # backend/src/off.ts
      → if USDA_API_KEY && plausiblyUS(off):
           fetchUSDA → mergeUSDA(off, usda) # backend/src/usda.ts
      → KV put; return { source, product }
  → OpenFoodFactsService.makeProduct → map # Sage/OpenFoodFacts.swift
  → ScoringEngineV4.scoreProduct            # on-device only
```

The Worker does **not** compute scores. Scoring is entirely on-device.

### 1.2 Sources

| Source | Role | Cite |
|--------|------|------|
| Open Food Facts v2 | Primary product record | `backend/src/off.ts:fetchOFF`; fields list L9–20 |
| USDA FoodData Central (Branded) | Nutrition backfill / override for US-plausible barcodes | `backend/src/usda.ts:fetchUSDA`, `mergeUSDA`, `plausiblyUS` |
| Cloudflare KV | Product cache | `backend/src/cache.ts` |
| Go-UPC | **Not implemented** (removed; legacy mentions in README/`Models.swift` comments) | — |

OFF fields requested (Worker ≡ iOS legacy list): `code`, `product_name`, `brands`, `quantity`, `nutriscore_grade`, `nova_group`, `nutriments`, `additives_tags`, `ingredients_analysis_tags`, `allergens_tags`, `ingredients_text`, `categories_tags`, `image_front_url`, `image_url`, `labels_tags`, `packagings`, `packaging_materials_tags`, `origins_tags`, `manufacturing_places`, `ingredients`, `ecoscore_grade`, `environmental_score_grade`, `completeness`, `states_tags`, `last_modified_t`, `serving_size`, `countries_tags`, `unknown_ingredients_n`.

⚠ Finding: `manufacturing_places` and `states_tags` are requested but **not mapped** into `Product`.

### 1.3 Merge / priority (`mergeUSDA`)

Cite: `backend/src/usda.ts:mergeUSDA` (L149–163), policy comments L10–14 / L143–148.

| Field class | Winner |
|-------------|--------|
| NOVA, additives tags, categories, Nutri-Score, image | OFF (USDA has none) |
| Overlapping nutriments | **USDA overwrites OFF** (`{...offNutr, ...usdaNutr}`) |
| `ingredients_text` | OFF if present; else USDA |
| Provenance | `_source`: `"usda"` or `"off+usda"` → `Product.dataSource` |

USDA is called when `USDA_API_KEY` is set **and** `plausiblyUS(off)` is true: OFF null, or `countries_tags` empty/absent, or any tag contains `"united-states"`.

⚠ Finding: comments/README describe USDA as “gap-fill when OFF has no nutrition,” but `index.ts` prefers USDA nutrition whenever US-plausible even if OFF already has a full table.

USDA nutrient map (`NUTRIENT_MAP`): FDC→OFF keys with scale 1 for macros/kcal; sodium/calcium/iron/K/Mg/Zn/vitamin-C scale **0.001** (mg→g for OFF storage). iOS then scales those minerals back ×1000 to mg in `OpenFoodFacts.map`.

⚠ Finding: USDA also writes `fat_100g` and `carbohydrates_100g`; iOS `OFFNutriments` does **not** decode them.

### 1.4 Field mapping into `Product` (`OpenFoodFacts.map`)

Cite: `Sage/OpenFoodFacts.swift:map` (~L207–287).

| Domain | Mapping |
|--------|---------|
| Sodium | Prefer `sodium_100g×1000` mg; else `(salt_100g/2.5)×1000` |
| Energy | `energy-kcal_100g`, else `energy-kj_100g/4.184` |
| Ca, Fe, K, Mg, Zn, vitamin C | OFF g/100g × 1000 → mg |
| Caffeine | `caffeine_100g` copied to `caffeine_mg` **without** ×1000 |
| Trans fat flag | `(trans-fat_100g ?? 0) > 0` → `transFats`; store `transFat_g` |
| Categories / labels / origins / countries | Strip language prefix via `AdditiveCatalog.normalize` |
| Packaging | `packagings` materials + `packaging_materials_tags`, normalized; empty → nil |
| Ingredient shares | `ingredients[].id` normalized; `percent` / `percent_estimate` |
| Scores at map time | `placeholderScore` from Nutri-Score/NOVA (overwritten by engine) |

Missing nutriment keys remain `nil` (no numeric defaults in the mapper).

### 1.5 Additive detection

Cite: `Sage/AdditiveDetector.swift:scan`, `OpenFoodFacts.scanAdditives`, `AdditiveCatalog`, `AdditiveKnowledgeBase`.

Order:
1. OFF `additives_tags` → canonical E-number (source `.offTag`).
2. Regex E/INS codes in ingredients text (source `.code`).
3. Synonym matches in normalized text (source `.name`).
4. `collapseToParents`: roman subtypes `E452i`→`E452`; letter subtypes `E150d` kept; `detectedAs` preserves subtypes.

**Undercount flag** (`undercountSuspected`):
```
hasUnrecognizedIngredients || weAddedBeyondOff
```
where `hasUnrecognizedIngredients` = `unknown_ingredients_n > 0` OR any ingredient `is_in_taxonomy == 0`; `weAddedBeyondOff` = any hit whose source ≠ `.offTag`.

Also sets `additiveIngredientTextMissing` when ingredients text is empty/whitespace.

KB risk (if present) wins for UI `ProductAdditive.risk`; else detector tier → risk. Codes on `Product` are lowercase (`e951`).

### 1.6 Seed-oil detection (informational + avoid)

Cite: `AvoidListMatcher.containsSeedOils`, wired from `OpenFoodFacts.detectSeedOils`.

Crops: canola, rapeseed, soybean, soya, sunflower, cottonseed, grapeseed, safflower, rice bran, corn (not olive/avocado/coconut/palm). Phrases include EN oils, parenthetical “rapeseed and soybean”, and pt-BR óleo names. Bare crop names only if vegetable/hydrogenated oil context is present.

---

## 2. Gates and routing

### 2.1 Gate predicates

Cite: `Sage/Models.swift` `Product` extension.

| Gate | Exact predicate |
|------|-----------------|
| `hasIngredientData` | non-empty `ingredientsText` **OR** non-empty `ingredientShares` |
| `hasNutritionData` | ≥ 3 of `{kcal, sugar_g, satFat_g, sodium_mg, protein_g, fiber_g}` non-nil |
| `hasKnownNova` | `novaGroup ∈ {1,2,3,4}` |
| `hasScoreableIngredientSignal` | `hasKnownNova` **OR** `!additives.isEmpty` |
| `hasMinimumData` | `hasNutritionData` **OR** `hasScoreableIngredientSignal` |

Implications: ingredient text alone is never enough; `novaGroup == 0` (map default) is not “known NOVA.”

`scoreProduct` outcomes (`ScoringEngineV4.scoreProduct`):
- `!hasMinimumData` → `.insufficientData`
- `route == "unsupported"` → `.unsupported`
- missing profile key → `.insufficientData`

### 2.2 Category router

Cite: `ScoringEngineV4.route` — first match in `RulesetV4.json:router` order against `Set(categories)`; else `"general"`.

Total router entries: **163**. Full ordered list:

| # | match | profile |
|---|-------|---------|
| 1 | `waters` | `unsupported` |
| 2 | `mineral-waters` | `unsupported` |
| 3 | `spring-waters` | `unsupported` |
| 4 | `flavored-waters` | `unsupported` |
| 5 | `alcoholic-beverages` | `unsupported` |
| 6 | `beers` | `unsupported` |
| 7 | `wines` | `unsupported` |
| 8 | `spirits` | `unsupported` |
| 9 | `ciders` | `unsupported` |
| 10 | `iced-teas` | `drinks` |
| 11 | `iced-coffees` | `drinks` |
| 12 | `coffee-drinks` | `drinks` |
| 13 | `energy-drinks` | `drinks` |
| 14 | `sodas` | `drinks` |
| 15 | `soft-drinks` | `drinks` |
| 16 | `sports-drinks` | `drinks` |
| 17 | `kombucha` | `drinks` |
| 18 | `teas` | `tea_coffee` |
| 19 | `green-teas` | `tea_coffee` |
| 20 | `black-teas` | `tea_coffee` |
| 21 | `white-teas` | `tea_coffee` |
| 22 | `oolong-teas` | `tea_coffee` |
| 23 | `herbal-teas` | `tea_coffee` |
| 24 | `flavored-teas` | `tea_coffee` |
| 25 | `fruit-teas` | `tea_coffee` |
| 26 | `rooibos-teas` | `tea_coffee` |
| 27 | `coffees` | `tea_coffee` |
| 28 | `ground-coffees` | `tea_coffee` |
| 29 | `coffee-beans` | `tea_coffee` |
| 30 | `instant-coffees` | `tea_coffee` |
| 31 | `arabica-coffees` | `tea_coffee` |
| 32 | `robusta-coffees` | `tea_coffee` |
| 33 | `roasted-coffees` | `tea_coffee` |
| 34 | `plant-based-beverages` | `plant_milk` |
| 35 | `plant-based-milk-alternatives` | `plant_milk` |
| 36 | `milk-substitutes` | `plant_milk` |
| 37 | `oat-milks` | `plant_milk` |
| 38 | `almond-milks` | `plant_milk` |
| 39 | `soy-milks` | `plant_milk` |
| 40 | `soya-milks` | `plant_milk` |
| 41 | `rice-milks` | `plant_milk` |
| 42 | `coconut-milks-and-creams` | `plant_milk` |
| 43 | `cashew-milks` | `plant_milk` |
| 44 | `hazelnut-milks` | `plant_milk` |
| 45 | `hemp-milks` | `plant_milk` |
| 46 | `pea-milks` | `plant_milk` |
| 47 | `nut-milks` | `plant_milk` |
| 48 | `milks` | `dairy_milk` |
| 49 | `whole-milks` | `dairy_milk` |
| 50 | `semi-skimmed-milks` | `dairy_milk` |
| 51 | `skimmed-milks` | `dairy_milk` |
| 52 | `uht-milks` | `dairy_milk` |
| 53 | `pasteurised-milks` | `dairy_milk` |
| 54 | `fresh-milks` | `dairy_milk` |
| 55 | `raw-milks` | `dairy_milk` |
| 56 | `lactose-free-milks` | `dairy_milk` |
| 57 | `goat-milks` | `dairy_milk` |
| 58 | `milks-liquid-and-powder` | `dairy_milk` |
| 59 | `buttermilks` | `dairy_milk` |
| 60 | `fermented-milk-products` | `yogurt_cheese` |
| 61 | `fermented-milk-drinks` | `yogurt_cheese` |
| 62 | `yogurts` | `yogurt_cheese` |
| 63 | `yoghurts` | `yogurt_cheese` |
| 64 | `greek-yogurts` | `yogurt_cheese` |
| 65 | `drinkable-yogurts` | `yogurt_cheese` |
| 66 | `cheeses` | `yogurt_cheese` |
| 67 | `cow-cheeses` | `yogurt_cheese` |
| 68 | `goat-cheeses` | `yogurt_cheese` |
| 69 | `sheep-cheeses` | `yogurt_cheese` |
| 70 | `cheddar-cheese` | `yogurt_cheese` |
| 71 | `cream-cheeses` | `yogurt_cheese` |
| 72 | `cottage-cheeses` | `yogurt_cheese` |
| 73 | `sliced-cheeses` | `yogurt_cheese` |
| 74 | `grated-cheese` | `yogurt_cheese` |
| 75 | `soft-cheeses` | `yogurt_cheese` |
| 76 | `hard-cheeses` | `yogurt_cheese` |
| 77 | `kefir` | `yogurt_cheese` |
| 78 | `quark` | `yogurt_cheese` |
| 79 | `fromage-blanc` | `yogurt_cheese` |
| 80 | `fromages-blancs` | `yogurt_cheese` |
| 81 | `curds` | `yogurt_cheese` |
| 82 | `sugars` | `sweeteners` |
| 83 | `cane-sugar` | `sweeteners` |
| 84 | `granulated-sugars` | `sweeteners` |
| 85 | `brown-sugars` | `sweeteners` |
| 86 | `icing-sugars` | `sweeteners` |
| 87 | `honeys` | `sweeteners` |
| 88 | `maple-syrups` | `sweeteners` |
| 89 | `agave-syrups` | `sweeteners` |
| 90 | `syrups` | `sweeteners` |
| 91 | `simple-syrups` | `sweeteners` |
| 92 | `molasses` | `sweeteners` |
| 93 | `table-sweeteners` | `sweeteners` |
| 94 | `sweeteners` | `sweeteners` |
| 95 | `golden-syrups` | `sweeteners` |
| 96 | `breads` | `breads` |
| 97 | `white-breads` | `breads` |
| 98 | `wheat-breads` | `breads` |
| 99 | `whole-wheat-breads` | `breads` |
| 100 | `whole-grain-breads` | `breads` |
| 101 | `sliced-breads` | `breads` |
| 102 | `special-breads` | `breads` |
| 103 | `flatbreads` | `breads` |
| 104 | `baguettes` | `breads` |
| 105 | `sandwich-breads` | `breads` |
| 106 | `buns` | `breads` |
| 107 | `hamburger-buns` | `breads` |
| 108 | `bagels` | `breads` |
| 109 | `toasts` | `breads` |
| 110 | `breakfast-cereals` | `breads` |
| 111 | `mueslis` | `breads` |
| 112 | `oatmeals` | `breads` |
| 113 | `pastas` | `breads` |
| 114 | `stuffed-pastas` | `breads` |
| 115 | `fresh-pastas` | `breads` |
| 116 | `rices` | `breads` |
| 117 | `cereal-grains` | `breads` |
| 118 | `flours` | `breads` |
| 119 | `oats` | `breads` |
| 120 | `frozen-desserts` | `ice_cream` |
| 121 | `ice-creams-and-sorbets` | `ice_cream` |
| 122 | `ice-creams` | `ice_cream` |
| 123 | `ice-cream-tubs` | `ice_cream` |
| 124 | `ice-cream-bars` | `ice_cream` |
| 125 | `ice-cream-cones` | `ice_cream` |
| 126 | `sorbets` | `ice_cream` |
| 127 | `gelatos` | `ice_cream` |
| 128 | `frozen-yogurts` | `ice_cream` |
| 129 | `mochi-ice-cream` | `ice_cream` |
| 130 | `vanilla-ice-cream-tubs` | `ice_cream` |
| 131 | `meats-and-their-products` | `meat` |
| 132 | `meats` | `meat` |
| 133 | `prepared-meats` | `meat` |
| 134 | `poultry` | `meat` |
| 135 | `poultries` | `meat` |
| 136 | `beef` | `meat` |
| 137 | `pork` | `meat` |
| 138 | `chicken` | `meat` |
| 139 | `chickens` | `meat` |
| 140 | `turkeys` | `meat` |
| 141 | `turkey-breasts` | `meat` |
| 142 | `hams` | `meat` |
| 143 | `sausages` | `meat` |
| 144 | `bacons` | `meat` |
| 145 | `salami` | `meat` |
| 146 | `cured-meats` | `meat` |
| 147 | `fishes-and-their-products` | `meat` |
| 148 | `fishes` | `meat` |
| 149 | `seafood` | `meat` |
| 150 | `fatty-fishes` | `meat` |
| 151 | `hamburgers` | `meat` |
| 152 | `frozen-meats` | `meat` |
| 153 | `fresh-meats` | `meat` |
| 154 | `meat-alternatives` | `meat` |
| 155 | `meat-analogues` | `meat` |
| 156 | `snacks` | `snacks` |
| 157 | `salty-snacks` | `snacks` |
| 158 | `sweet-snacks` | `snacks` |
| 159 | `chips-and-fries` | `snacks` |
| 160 | `crisps` | `snacks` |
| 161 | `fruit-juices` | `drinks` |
| 162 | `juices` | `drinks` |
| 163 | `beverages` | `drinks` |

**Critical first-match notes:**
- `waters` / alcohol tags → `unsupported` before catch-all `beverages` → `drinks`.
- `iced-teas` → `drinks` before `teas` → `tea_coffee`.
- Plant milks before `milks`.
- Final catch-alls: `fruit-juices`, `juices`, `beverages` → `drinks`.

⚠ Finding: profile `water` exists in `profiles` (Σw=100) but router never returns `"water"` (waters → `unsupported`). Rules `waterSource` / `mineralDisclosure` are unreachable in production routing.

### 2.3 Floor

`ScoringEngineV4.floorScore = 10` — applied to overall and yourScore (`max(10, Int(rounded))`).

---

## 3. Profiles and rules

### 3.1 Aggregation and bands

**Overall (base):**
```
raw = Σ(w · f) / Σw × 100
overall = max(10, Int(raw.rounded()))   // Swift .rounded() = half away from zero
```
Cite: `ScoringEngineV4.scoreProduct`.

**Ruleset bands** (`RulesetV4.json:bands` / `RulesetV4.bandLabel`):
- Excellent: score ≥ **75**
- Good: score ≥ **50**
- Mediocre: score ≥ **25**
- Bad: otherwise

⚠ Finding: UI dials use a **different** scale in `Theme.scoreTier`: ≥80 Excellent, ≥60 Good, ≥40 OK (“poor”), else Bad. Overview payload uses ruleset `bandLabel`, not `scoreTier`. `CompactScoreRing` uses yet another map (81/61/31).

### 3.2 Confidence

```
confidence = Σ(w for rules with hadData) / Σw
```

`isProvisionalScore`: `confidence < 0.80` **OR** any rule with `w ≥ 10` and `hadData == false`.

Affects: ResultView provisional banner; Overview template provisional lead-in; OverviewValidator thin-data ban when confidence≥0.80 and all tiers `"data"`.

⚠ Finding: `Product.dataConfidenceScore` (Phase-A checklist, undercount −0.20) exists in `Models.swift` but the live banner uses `isProvisionalScore`, not `dataConfidence`.

### 3.3 Profiles (exact weights)

Cite: `RulesetV4.json:profiles`.

#### `general` — Σw = **109**

| rule | w | variant |
|------|--:|---------|
| `S1` | 28 | — |
| `S2` | 26 | — |
| `S3` | 12 | `foods` |
| `S4` | 6 | — |
| `S5` | 6 | — |
| `S12` | 18 | — |
| `S13` | 5 | — |
| `S7` | 5 | — |
| `S8` | 3 | — |

#### `snacks` — Σw = **108**

| rule | w | variant |
|------|--:|---------|
| `S1` | 24 | — |
| `S2` | 26 | — |
| `S3` | 14 | `foods` |
| `S4` | 10 | — |
| `S5` | 9 | — |
| `S12` | 12 | — |
| `S13` | 5 | — |
| `S7` | 5 | — |
| `S8` | 3 | — |

#### `drinks` — Σw = **104**

| rule | w | variant |
|------|--:|---------|
| `S1` | 28 | — |
| `S3` | 22 | `drinks` |
| `S6` | 12 | — |
| `S2` | 24 | — |
| `S12` | 5 | — |
| `S7` | 8 | — |
| `S8` | 5 | — |

#### `water` — Σw = **100**

| rule | w | variant |
|------|--:|---------|
| `waterSource` | 30 | — |
| `S7` | 30 | — |
| `S1` | 20 | — |
| `mineralDisclosure` | 10 | — |
| `S8` | 10 | — |

#### `plant_milk` — Σw = **100**

| rule | w | variant |
|------|--:|---------|
| `S1` | 28 | — |
| `S10` | 15 | — |
| `cropRisk` | 12 | — |
| `S3` | 12 | `drinks` |
| `S12` | 8 | — |
| `S2` | 12 | — |
| `S7` | 8 | — |
| `S8` | 5 | — |

#### `dairy_milk` — Σw = **94**

| rule | w | variant |
|------|--:|---------|
| `S1` | 30 | — |
| `dairyLabels` | 8 | — |
| `dairyProcessing` | 15 | — |
| `S3` | 10 | `foods` |
| `S12` | 18 | — |
| `S13` | 5 | — |
| `S7` | 5 | — |
| `S8` | 3 | — |

#### `yogurt_cheese` — Σw = **98**

| rule | w | variant |
|------|--:|---------|
| `S1` | 30 | — |
| `dairyLabels` | 8 | — |
| `dairyProcessing` | 14 | — |
| `S3` | 15 | `yogurt` |
| `S12` | 18 | — |
| `S13` | 5 | — |
| `S7` | 5 | — |
| `S8` | 3 | — |

#### `tea_coffee` — Σw = **100**

| rule | w | variant |
|------|--:|---------|
| `S1` | 42 | — |
| `S9` | 6 | — |
| `brewMaterial` | 12 | — |
| `S11` | 4 | — |
| `S2` | 22 | — |
| `S12` | 9 | — |
| `S8` | 5 | — |

#### `sweeteners` — Σw = **100**

| rule | w | variant |
|------|--:|---------|
| `sweetenerType` | 25 | — |
| `authenticity` | 20 | — |
| `S1` | 25 | — |
| `sweetenerProcessing` | 10 | — |
| `S7` | 10 | — |
| `S8` | 10 | — |

#### `breads` — Σw = **104**

| rule | w | variant |
|------|--:|---------|
| `S1` | 28 | — |
| `wholeGrain` | 10 | — |
| `flourOxidizers` | 5 | — |
| `S3` | 12 | `bread` |
| `S4` | 8 | — |
| `S2` | 16 | — |
| `S12` | 12 | — |
| `S13` | 5 | — |
| `S7` | 4 | — |
| `S8` | 4 | — |

#### `ice_cream` — Σw = **98**

| rule | w | variant |
|------|--:|---------|
| `S1` | 35 | — |
| `stabilizers` | 10 | — |
| `S3` | 15 | `icecream` |
| `S5` | 5 | `soft` |
| `dairyQuality` | 8 | — |
| `S2` | 8 | — |
| `S12` | 7 | — |
| `S7` | 5 | — |
| `S8` | 5 | — |

#### `meat` — Σw = **103**

| rule | w | variant |
|------|--:|---------|
| `S1` | 46 | — |
| `welfare` | 6 | — |
| `S2` | 12 | — |
| `S4` | 9 | — |
| `S12` | 18 | — |
| `S13` | 5 | — |
| `S7` | 4 | — |
| `S8` | 3 | — |

### 3.4 Shared helpers

**`stepped(value, [t0,t1,t2], unknownCredit)`** (`ScoringEngineV4.stepped`):
- nil / bad thresholds → `(unknownCredit, false)`
- ≤t0 → 1.0; ≤t1 → 0.60; ≤t2 → 0.30; else 0.0 (all `hadData true` when value present)

**`tierFractions`:** {'A': 0.33, 'B': 0.18, 'C': 0.09, 'D': 0.045}
**`dampening`:** afterCount=3, factor=0.5

### 3.5 Rule catalog

Evidence: `hadData` → Overview `evidenceTier` `"data"` / `"unknown-tier"`.
`driverKind` / `displayName` from `RulesetV4.json:ruleMeta` (see table below).

#### S1 — additives (`s1`)
- Missing: `additiveIngredientTextMissing == true` OR `!hasIngredientData` → **(0.20, false)**.
- Else: sum penalties from additive tiers (detector major→A … soft→D; unclassified→C; exempt skip; else `additiveTiers[code]`; else C); max **2** gums from `gumCodes`; plus one `textSignals` hit per needle; sort desc; first `afterCount` full, rest × `factor`; `f = max(0, 1−total)`.
- gumCodes: ['e410', 'e412', 'e415', 'e418']
- textSignals: {"high fructose corn syrup": "B", "high-fructose corn syrup": "B", "artificial flavor": "C", "artificial flavour": "C", "natural flavor": "D", "natural flavour": "D", "canola oil": "D", "rapeseed oil": "D", "sunflower oil": "D", "soybean oil": "D", "cottonseed oil": "D", "corn oil": "D"}

#### S2 — processing (`s2`)
- NOVA 1/2/3/4 → 1.0 / 0.75 / 0.40 / 0.0 (`true`).
- Else ingredient share count 1–3→0.85; 4–7→0.55; 8–15→0.25; 16+→0.0 (`true`).
- Else **(0.40, false)**.

#### S3 — sugar (`s3`)
- Thresholds: {'foods': [5, 12.5, 22.5], 'drinks': [1, 4, 8], 'yogurt': [4, 8, 12], 'bread': [2, 6, 12], 'icecream': [6, 12, 18]}
- Prefer `addedSugar_g` stepped unknownCredit **0.25**; else `sugar_g × (1 − min(1, fvn/100))`; else **(0.25, false)**.

#### S4 — sodium — thresholds [120, 400, 800] mg; unknownCredit **0.30** hardcoded.

#### S5 — sat fat — {'standard': [3, 8, 15], 'soft': [4, 8, 14]}; unknownCredit **0.40**; variant default `standard`.

#### S6 — sweeteners — codes ['e950', 'e951', 'e954', 'e955', 'e961', 'e962', 'e969']; no ingredients → (0.50,false); 0 hits → 1.0; else `max(0, 0.60 − 0.40×(hits−1))`.

#### S7 — packaging — materials map {"glass": 1.0, "paper": 0.9, "cardboard": 0.9, "pulp": 0.9, "tetra-pak": 0.7, "carton": 0.7, "aluminium": 0.55, "aluminum": 0.55, "steel": 0.55, "hdpe": 0.4, "polypropylene": 0.4, "pet": 0.25, "polystyrene": 0.0, "pvc": 0.0, "plastic": 0.3}; empty → (0.30,false); unrecognized material credit 0.30; **min** credit wins.

#### S8 — certifications — labels ['organic', 'eu-organic', 'usda-organic', 'organic-certification', 'non-gmo-project', 'no-gmos', 'fair-trade', 'fairtrade', 'fairtrade-international', 'fair-trade-usa', 'certified-humane', 'regenerative-organic-certified', 'demeter', 'glyphosate-residue-free', 'rainforest-alliance', 'sustainable-seafood-msc', 'msc', 'asc', 'responsible-aquaculture-asc', 'best-aquaculture-practices']; hit→1.0 else 0.0; always `hadData true`.

#### S9 — **code is organic labels**, not caffeine
- `organicLabels = {organic, eu-organic, usda-organic}`; disjoint → 0.0 else 1.0; always true.
- ⚠ Finding: `ruleMeta.S9.displayName` is `"caffeine"` / hygiene, but evaluator `s9` checks organic labels only. Caffeine field is unused by S9.

#### S10 — hero ingredients — crops from cropRisk low+high; heroCredit [[15, 1.0], [10, 0.8], [5, 0.5], [2, 0.2]]; pct = percent ?? estimate×0.75; miss → (0.20,false).

#### S11 — origin — non-empty `origins` → 1.0 else 0.0; always true.

#### S12 — protein/fiber/FVN (hardcoded)
```
protDens = 0 if kcal<5; else min(1, (protein_g/(kcal/100))/15) if kcal>0; else 0
fiber = min(1, fiber_g/8); fvn = min(1, fvn/100)  // nil→0
f = 0.40·protDens + 0.35·fiber + 0.25·fvn
hadData = kcal!=nil || fiber_g!=nil || fvn!=nil
```

#### S13 — micros — cfg {"dv": {"iron_mg": 18, "potassium_mg": 4700, "calcium_mg": 1300, "magnesium_mg": 420, "zinc_mg": 11, "vitaminC_mg": 90}, "capPerNutrient": 0.5, "target": 1.2, "unknownCredit": 0.35}; none present → (unknownCredit 0.35, false); else min(1, Σ min(cap, v/dv) / target).

#### Category-specific
- `waterSource`: [{'match': 'mineral-waters', 'credit': 1.0}, {'match': 'spring-waters', 'credit': 0.8}, {'match': 'artesian-waters', 'credit': 0.7}, {'match': 'purified-waters', 'credit': 0.4}, {'match': 'distilled-waters', 'credit': 0.4}]; no match → (0.0, true).
- `mineralDisclosure`: `calcium_mg != nil` → 1.0 else 0.0 (Ca only).
- `cropRisk`: {"lowRisk": ["coconut", "almond", "hemp", "cashew", "macadamia", "pea"], "highRisk": ["oat", "soy", "soya", "rice", "wheat", "corn"], "lowCredit": 0.6, "highCredit": 0.2, "riceCap": 0.4}; organic→1.0; unidentified mid 0.4; rice capped.
- `dairyLabels` / `dairyQuality`: points {'points': {'organic': 5, 'eu-organic': 5, 'usda-organic': 5, 'grass-fed': 5, 'pasture-raised': 5, 'no-added-hormones': 3, 'rbst-free': 3, 'certified-humane': 2}, 'denominator': 20}; dairyQuality uses same config with `plantAware:true` but **no `plantNeutral` in JSON** → plant branch never fires.
- `dairyProcessing`: [{'match': 'raw-milk', 'credit': 0.5}, {'match': 'uht', 'credit': 0.4}, {'match': 'ultrafiltered', 'credit': 0.25}, {'match': 'vat-pasteurized', 'credit': 1.0}]; default 0.85.
- `brewMaterial`: [{'kw': 'loose', 'credit': 1.0}, {'kw': 'whole-bean', 'credit': 1.0}, {'kw': 'whole bean', 'credit': 1.0}, {'kw': 'compostable', 'credit': 0.7}, {'kw': 'plastic-free', 'credit': 0.85}, {'kw': 'paper', 'credit': 0.85}, {'kw': 'cellulose', 'credit': 0.85}, {'kw': 'silken', 'credit': 0.15}, {'kw': 'pyramid', 'credit': 0.15}, {'kw': 'mesh', 'credit': 0.15}, {'kw': 'nylon', 'credit': 0.0}, {'kw': 'pod', 'credit': 0.3}, {'kw': 'capsule', 'credit': 0.3}]; default 0.4 with hadData **false**.
- `sweetenerType`: [{'kw': 'raw honey', 'credit': 1.0}, {'kw': 'manuka', 'credit': 1.0}, {'kw': 'maple', 'credit': 1.0}, {'kw': 'stevia', 'credit': 1.0}, {'kw': 'monk fruit', 'credit': 1.0}, {'kw': 'honey', 'credit': 0.9}, {'kw': 'coconut sugar', 'credit': 0.85}, {'kw': 'turbinado', 'credit': 0.7}, {'kw': 'demerara', 'credit': 0.7}, {'kw': 'brown sugar', 'credit': 0.5}, {'kw': 'agave', 'credit': 0.3}, {'kw': 'high fructose', 'credit': 0.0}, {'kw': 'hfcs', 'credit': 0.0}, {'kw': 'corn syrup', 'credit': 0.15}]; default 0.3 (true).
- `sweetenerProcessing`: [{'kw': 'raw', 'credit': 1.0}, {'kw': 'unpasteurized', 'credit': 1.0}, {'kw': 'unpasteurised', 'credit': 1.0}, {'kw': 'bleached', 'credit': 0.2}, {'kw': 'refined', 'credit': 0.2}]; default 0.6 (true).
- `authenticity`: bad phrases ['blend', 'flavored', 'flavoured', 'syrup product', 'honey product', 'pancake'] → 0; single share → 1.0; else **0.6** hardcoded.
- `wholeGrain`: keywords ['whole-wheat', 'whole wheat', 'whole-grain', 'whole grain', 'wholemeal', 'integral', 'sprouted', 'rye', 'spelt', 'einkorn', 'oat'] → 1/0, true.
- `flourOxidizers`: no ingredients → (0.30,false); e924/e927a → 0 else 1.
- `stabilizers`: penalties {'e407': 0.4, 'e433': 0.4, 'e471': 0.2, 'e466': 0.2, 'e412': 0.2, 'e410': 0.1, 'e415': 0.1}; no ingredients → (0.30,false); f=max(0,1−Σ).
- `welfare`: {"points": {"grass-fed": 5, "pasture-raised": 5, "organic": 4, "eu-organic": 4, "usda-organic": 4, "no-antibiotics": 4, "antibiotic-free": 4, "certified-humane": 2, "wild-caught": 5, "msc": 5, "sustainable-seafood-msc": 5, "asc": 5, "best-aquaculture-practices": 5}, "denominator": 15, "plantNeutral": 0.47}; plantNeutral 0.47 when vegan flag or haystack contains `plant-based`.
- Unknown rule id → **(0, false)**.

### 3.6 ruleMeta

| id | displayName | driverKind |
|----|-------------|------------|
| `S1` | additives | merit |
| `S10` | hero ingredients | merit |
| `S11` | origin | merit |
| `S12` | protein and fiber | merit |
| `S13` | micronutrients | merit |
| `S2` | degree of processing | merit |
| `S3` | sugar | merit |
| `S4` | sodium | merit |
| `S5` | saturated fat | merit |
| `S6` | sweeteners | hygiene |
| `S7` | packaging | merit |
| `S8` | certifications | merit |
| `S9` | caffeine | hygiene |
| `authenticity` | authenticity | merit |
| `brewMaterial` | brew material | merit |
| `cropRisk` | crop sourcing | hygiene |
| `dairyLabels` | quality labels | merit |
| `dairyProcessing` | processing | hygiene |
| `dairyQuality` | quality labels | merit |
| `flourOxidizers` | flour treatment agents | hygiene |
| `mineralDisclosure` | mineral disclosure | merit |
| `stabilizers` | stabilizers | hygiene |
| `sweetenerProcessing` | sweetener processing | hygiene |
| `sweetenerType` | sweetener type | hygiene |
| `waterSource` | water source | merit |
| `welfare` | animal welfare | merit |
| `wholeGrain` | whole grain content | merit |

Overview positives: only `driverKind == merit` and `f ≥ 0.55`. Missing displayName → rule excluded from prose payload (fail closed) but still scored.

---

## 4. Personalization

### 4.1 Your Score formula

Cite: `ScoringEngineV4.scoreProduct`.

If `!personalizeScoring`: your = overall; no multipliers/caps/nudge.

Else:
```
m[rule] = product of objective × goals × sliders (default 1)
your0 = max(10, Int((Σ(w·m·f)/Σ(w·m)×100).rounded()))
your1 = clamp(your0 + nutrientNudge(objective, nutrients), 10, 100)
your  = applyCaps(your1, …).capped
```

Multipliers are **not** profile-aware: maps are global; only rules present in the active profile receive `m` (`mult[r.rule] ?? 1`). Orphan multipliers for absent rules have no effect.

### 4.2 Multiplier maps (exact)

Cite: `RulesetV4.json:multipliers`.

```json
{
  "objective": {
    "build muscle": {
      "S3": 1.2
    },
    "lose weight": {
      "S3": 2.0,
      "S6": 0.5
    },
    "eat healthier": {
      "S2": 1.5,
      "S1": 1.3,
      "S12": 1.2
    }
  },
  "goal": {
    "blood sugar": {
      "S3": 2.0,
      "S2": 1.3
    },
    "heart": {
      "S4": 2.0,
      "S5": 2.0
    },
    "gut health": {
      "S6": 2.0,
      "S1": 1.3
    },
    "young child": {
      "S3": 2.0,
      "S1": 1.3
    }
  },
  "slider": {
    "clean": {
      "2": {
        "S1": 1.5
      },
      "0": {
        "S1": 0.6
      }
    },
    "nutrition": {
      "2": {
        "S12": 1.5
      },
      "0": {
        "S12": 0.6
      }
    },
    "environment": {
      "2": {
        "S8": 1.5
      },
      "0": {
        "S8": 0.6
      }
    },
    "welfare": {
      "2": {
        "welfare": 2.0,
        "dairyLabels": 2.0
      },
      "0": {
        "welfare": 0.6
      }
    }
  }
}
```

### 4.3 Nutrient nudge (hardcoded)

Cite: `ScoringEngineV4.nutrientNudge`.
- **build muscle:** `Int(((dens−0.35)×16).rounded())` with `dens=min(1,(protein/(kcal/100))/15)`, requires kcal>5.
- **lose weight:** `Int(((light×sugarGate−0.3)×12).rounded())` with `light=clamp((500−kcal)/450,0,1)`, `sugarGate=1−min(1,sugar/25)`.
- else 0.

### 4.4 Caps

Cite: `RulesetV4.json:hardGates`, `ScoringEngineV4.taperedDietCap`, `dietCapValue`, `applyCaps`.

```json
{
  "avoidListCap": 49,
  "dietConflictCap": 20,
  "dietConflictTapers": {
    "low-sugar diet": {
      "metric": "sugar_g",
      "taperStart": 15,
      "taperEnd": 25,
      "minCap": 20
    },
    "low-sodium diet": {
      "metric": "sodium_mg",
      "taperStart": 400,
      "taperEnd": 800,
      "minCap": 20
    }
  }
}
```

Taper: ≤start → cap 100 (does not fire); ≥end → minCap; between linear:
`Int((100 − (100−minCap)×(amount−start)/(end−start)).rounded())`.

Restriction fire (`evalRestriction`): with taper present, low-sugar fires when `sugar_g > taperStart` (15); low-sodium when `sodium_mg > taperStart` (400). Legacy fallbacks if taper missing: sugar>12.5, sodium>400. Vegan/vegetarian/gluten-free/dairy-free use diet flags; flat cap = `dietConflictCap` (20).

Stacked: `firedCaps` = all firing; `effectiveCap = min(values)`; `your = min(weighted, effective)`; `bindingCap` = min-value cap among those that actually limit (`weighted > effective`), else nil.

Avoid id: `seedOilCap` if hit contains `"seed"`, else `avoidListCap`; value = `avoidListCap` (49).

Caps apply to **yourScore only**, never overall.

### 4.5 Avoid-list matching

Cite: `RulesetV4.json:avoidList`, `AvoidListMatcher.matches`, `ScoringEngineV4.avoidListHits`.

Order per item: special-case seed oils (`product.seedOils` / re-scan); else codes ∩ additive codes; else labels ∩ product labels; else text needles in ingredients + share names (hydrogenated needles require co-present seed crop).

```json
{
  "carrageenan": {
    "codes": [
      "e407"
    ]
  },
  "aspartame": {
    "codes": [
      "e951"
    ]
  },
  "sucralose": {
    "codes": [
      "e955"
    ]
  },
  "seed oils": {
    "text": [
      "canola oil",
      "sunflower oil",
      "soybean oil",
      "rapeseed oil",
      "corn oil",
      "cottonseed oil",
      "soya oil",
      "grapeseed oil",
      "safflower oil",
      "rice bran oil",
      "rice-bran oil",
      "rapeseed and soybean",
      "rapeseed & soybean",
      "soybean and rapeseed",
      "\u00f3leo de soja",
      "oleo de soja",
      "\u00f3leo de canola",
      "oleo de canola",
      "\u00f3leo de girassol",
      "oleo de girassol",
      "\u00f3leo de milho",
      "oleo de milho",
      "\u00f3leo de algod\u00e3o",
      "oleo de algodao"
    ]
  },
  "palm oil": {
    "text": [
      "palm oil"
    ],
    "labels": [
      "palm-oil"
    ]
  },
  "caffeine": {
    "text": [
      "caffeine"
    ]
  },
  "artificial colors": {
    "codes": [
      "e102",
      "e104",
      "e110",
      "e122",
      "e124",
      "e127",
      "e129",
      "e131",
      "e132",
      "e133"
    ]
  },
  "added phosphates": {
    "codes": [
      "e338",
      "e339",
      "e340",
      "e341",
      "e343",
      "e450",
      "e451",
      "e452"
    ]
  },
  "hfcs": {
    "text": [
      "high fructose corn syrup",
      "high-fructose corn syrup"
    ]
  },
  "titanium dioxide": {
    "codes": [
      "e171"
    ]
  }
}
```

---

## 5. Presentation layer contracts

### 5.1 Overview

Payload: `ScoringEngineV4.OverviewContext` (see engine). Client: `BackendService.ExplainPayload` → POST `/explain`. Cache: `exp:<EXPLANATION_VERSION|exp-v6>:<barcode>:<classHash>` (`backend/src/index.ts`, `cache.ts`). Client invalidate: UserDefaults `overviewExpV6Invalidated` (`AppStore.invalidateOverviewsForExpV6IfNeeded`).

Validator (`OverviewValidator` / `explanation.ts:validateOverview`): ban em/en dashes; ban known rule ids + camelCase; additive-presence claims without ingredient signal; packaging claims if S7 unknown; thin-data phrases when fully confident; `1 points` when |delta|=1.

Fallback: LLM fail/reject → `OverviewTemplate.generate` (Swift) / `buildTemplateOverview` (TS). Binding hardGate only for personalization attribution.

### 5.2 Nutrient badges (`NutrientLevels`)

| nutrient | ≤t1 low | ≤t2 moderate | else high |
|----------|--------:|-------------:|-----------|
| sugar (g) | 5 | 12.5 | high |
| sodium (mg) | 120 | 400 | high |
| satFat (g) | 1.5 | 5 | high |
| fiber (g) | 3 | 6 | high |
| protein (g) | 5 | 12 | high |
| calcium (mg) | 60 | 120 | high |
| iron (mg) | 2 | 4.5 | high |
| potassium (mg) | 300 | 700 | high |

⚠ Finding: badge sat-fat cut points (1.5/5) ≠ S5 scoring thresholds (3/8/15). Sugar badge aligns with S3 foods t0/t1 but scoring has a third step at 22.5. Calcium has a badge but is omitted from `promptLines`.

### 5.3 UI thresholds outside ruleset

| Location | Threshold / behavior |
|----------|----------------------|
| `Theme.scoreTier` | 80 / 60 / 40 |
| `CompactScoreRing.style` | 81 / 61 / 31 |
| `yourScoreIsWorstSignal` | scoreTier == bad (<40) |
| Additive HIGH color | always `scoreBad` |
| Trans-fat card | `showsTransFatFlag` = `transFat_g > 0` |
| Avoid chip / Detected seed oils on list | copy uses `avoidListCap` (49) |
| Binding chip | only if `bindingCap != nil` |
| Restriction banner whitelist | vegan, vegetarian, pescatarian, low-sugar diet, low-sodium diet, gluten-free, dairy-free |
| Provisional banner | `isProvisionalScore` |
| Overview positive cutoff | f ≥ 0.55 merit |
| Overview negative cutoff | potential loss > 0.01 |

### 5.4 MethodologyView vs code

⚠ Finding: Methodology still describes v3 (“starts at neutral 50, adds/subtracts points”) and tier copy 80/60/40/10, while live scoring is v4 Σ(w·f)/Σw with ruleset bands 75/50/25 for overview text.

---

## 6. Known gaps

1. Profile `water` unreachable (router → unsupported).
2. S9 labeled caffeine, implements organic.
3. Three band systems (ruleset / scoreTier / CompactScoreRing).
4. USDA merge prefers nutrition vs “gap-fill” docs.
5. `dairyQuality` plantNeutral never activates (missing JSON field).
6. `mineralDisclosure` is Ca-only.
7. `deltaReasonV4` defined but unused.
8. Header comment in `ScoringV4.swift` still says “NOT yet wired”; app uses v4.
9. `Product.dataConfidenceScore` unused by provisional banner.
10. Multiplier orphans per profile (e.g. S6×0.5 on profiles without S6) — no effect.
11. sweetenerCodes e961/e962/e969 not in `additiveTiers` → S1 fallback C if unclassified.
12. Go-UPC referenced in docs, not in code.
13. Avoid UI always cites cap 49 even when dietConflict is the binding ceiling.
14. `allowAlarmRed` barely changes HIGH additive appearance (always red).
15. SCORING_V4.md profile weight tables disagree with live JSON (doc stale).

Could not determine from code alone:
- Live OFF/USDA payloads for barcodes at audit time (examples below use reconstructed fixtures run through the engine).
- Whether Worker secrets / USDA_API_KEY are set in production.

---

## 7. Worked examples

Profile used for both dumps: `objective = "eat healthier"`, `personalizeScoring = true`, `autoFlagRestrictions = true`, `restrictions = ["Low-sugar diet"]`, `avoidList = ["Seed oils"]` (matches `MockData.user` shape).

⚠ Finding: nutrient/additive inputs are **reconstructed fixtures** keyed to reference barcodes (not a live `/lookup` capture at document generation time). Per-rule w/f/m and finals are from `ScoringEngineV4.debugText` on those fixtures under ruleset `2026.08-e1`.

### 7.1 Jif-like (barcode `0051500255162`) — clean-data path

**Inputs (fixture):** NOVA 4; sugar 9.1 g; sodium 393 mg; satFat 3.2 g; fiber 6.1 g; protein 21.9 g; kcal 633; addedSugar 3.1 g; Fe/K/Mg present; packaging `plastic`; additive e471; seed oils true; categories include `spreads` / nut butters (no earlier router hit) → **`general`**.

**Gates:** hasNutritionData true; hasScoreableIngredientSignal true (NOVA+additives); hasMinimumData true.

**Per-rule (Σw=109):**

| rule | w | f | contrib | evidence |
|------|--:|--:|--------:|----------|
| S1 | 28 | 0.910 | 25.48 | data |
| S2 | 26 | 0.000 | 0.00 | data (NOVA 4) |
| S3 | 12 | 1.000 | 12.00 | data (addedSugar 3.1 ≤5) |
| S4 | 6 | 0.600 | 3.60 | data (393 ≤400) |
| S5 | 6 | 0.600 | 3.60 | data (3.2 ≤8) |
| S12 | 18 | 0.359 | 6.46 | data |
| S13 | 5 | 0.512 | 2.56 | data |
| S7 | 5 | 0.300 | 1.50 | data (plastic) |
| S8 | 3 | 0.000 | 0.00 | data |

confidence **100%**; raw 50.65 → **overall 51** (band Good).

**Personalization:** multipliers S1×1.30, S2×1.50, S12×1.20; weighted raw 47.87 → 48. Low-sugar does **not** fire (9.1 ≤ 15). Seed-oil avoid fires (cap 49) but **does not bind** (48 ≤ 49). **yourScore = 48**. bindingCap nil; firedCaps = [seedOilCap:49].

**Displayed (UI):** dials use scoreTier → overall 51 = OK (poor), your 48 = OK; no binding chip; avoid chip still shows “Caps your score at 49”; Detected seed oils same copy if on list.

### 7.2 Yorgus-like (barcode `7898571520514`) — missing ingredients

**Inputs (fixture):** sugar 2 g; sodium 40; satFat 0; fiber 0; protein 11.5; calcium 95; kcal 54; **no** ingredientsText/shares/additives; nova 0; categories `yogurts`, `fermented-milk-products` → first hit → **`yogurt_cheese`**.

**Gates:** hasNutritionData true (≥3 macros); hasScoreableIngredientSignal **false**; hasMinimumData true via nutrition.

**Per-rule (Σw=98):**

| rule | w | f | contrib | evidence |
|------|--:|--:|--------:|----------|
| S1 | 30 | 0.200 | 6.00 | **unknown-tier** |
| dairyLabels | 8 | 0.000 | 0.00 | data |
| dairyProcessing | 14 | 0.850 | 11.90 | data (default) |
| S3 | 15 | 1.000 | 15.00 | data (yogurt variant, 2≤4) |
| S12 | 18 | 0.400 | 7.20 | data |
| S13 | 5 | 0.061 | 0.30 | data (Ca only) |
| S7 | 5 | 0.300 | 1.50 | **unknown-tier** |
| S8 | 3 | 0.000 | 0.00 | data |

confidence **64.3%** (backed w = 63/98); raw 42.76 → **overall 43** (Mediocre). Provisional: yes (conf<0.80 and S1 w=30 unknown).

**Personalization:** S1×1.30, S12×1.20 (S2×1.50 orphan — no S2 in profile); weighted raw 40.82 → **yourScore 41**. No diet cap (sugar 2); no avoid hit. bindingCap nil; firedCaps nil.

**Displayed:** provisional banner; Overview should lead with limited-data wording; no cap chip.

---

## Appendix A — Additive tier table (ruleset)

```json
{
  "e924": "A",
  "e927a": "A",
  "e171": "A",
  "e249": "A",
  "e250": "A",
  "e251": "A",
  "e252": "A",
  "e320": "A",
  "e319": "A",
  "e443": "A",
  "e127": "A",
  "e951": "B",
  "e954": "B",
  "e102": "B",
  "e104": "B",
  "e110": "B",
  "e122": "B",
  "e124": "B",
  "e129": "B",
  "e150c": "B",
  "e150d": "B",
  "e321": "B",
  "e433": "B",
  "e407": "B",
  "e955": "C",
  "e950": "C",
  "e466": "C",
  "e471": "C",
  "e338": "C",
  "e339": "C",
  "e340": "C",
  "e341": "C",
  "e343": "C",
  "e450": "C",
  "e451": "C",
  "e452": "C",
  "e410": "D",
  "e412": "D",
  "e415": "D",
  "e418": "D"
}
```

## Appendix B — Citation index

| Area | Primary cites |
|------|----------------|
| Lookup/merge | `backend/src/index.ts`, `off.ts`, `usda.ts` |
| Mapping | `Sage/OpenFoodFacts.swift` |
| Additives | `AdditiveDetector.swift`, `AdditiveKnowledgeBase.swift` |
| Avoid | `AvoidListMatcher.swift`, `RulesetV4.json:avoidList` |
| Engine | `Sage/ScoringV4.swift` |
| Config | `Sage/RulesetV4.json` (`2026.08-e1`) |
| Gates model | `Sage/Models.swift` |
| Badges | `Sage/NutrientLevels.swift` |
| UI tiers | `Sage/Theme.swift:scoreTier` |
| Overview | `OverviewValidator.swift`, `OverviewTemplate.swift`, `backend/src/explanation.ts` |

*End of specification.*