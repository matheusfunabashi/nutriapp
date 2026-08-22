# TopRatedBuilder — offline alternatives / Top Rated generation

Builds `alternatives.json` (and `top-rated.json`) from a `candidates.json`
pulled from Open Food Facts. The app and Worker ship the same
`alternatives.json` byte-for-byte.

## Prerequisites

- Xcode (macOS target `TopRatedBuilder`)
- Python 3
- Network access to `world.openfoodfacts.org`

## Standard regeneration (US)

Top Rated and Better Options are US-only, so the shipped file is US-only
(2026-08-22; the UK/CA rows it used to carry were never surfaced). From the
repo root:

```bash
# 1) Pull popularity-ranked OFF candidates per shelf.
#    150/shelf gives the build-time evidence + US-barcode gates headroom.
#    The script pages the API (100/page), drops off-shelf products via
#    SHELF_EXCLUDE / SHELF_NAME_EXCLUDE, and EXITS NON-ZERO if any shelf pull
#    comes back empty — never ship a file from a failed run (OFF's search
#    backend flakes for hours; just rerun).
cd TopRatedBuilder
python3 generate_candidates.py --countries us --per-shelf 150 \
    --out fixtures/candidates-live.json

# 2) Score with the bundled ruleset (must match RulesetV5 / live app version),
#    drop rows that fail the Top Rated / Better Options evidence gate
#    (ingredients + NOVA + nutrition table + confidence ≥ 0.80) or lack US
#    barcode evidence (UPC / UPC-E, ALDI-US / Lidl-US prefixes, Asian import
#    prefixes on instantNoodles), keep the top 80 per shelf, write
#    alternatives.json.
#
#    NOTE: the Xcode `TopRatedBuilder` target currently links the PIL dylibs
#    from `.imgenv` (LIBRARY_SEARCH_PATHS) and the resulting binary fails to
#    launch ("Library not loaded: /DLC/PIL/…"). Until that search path is
#    removed from the project, build it directly with swiftc:
SDK=$(xcrun --show-sdk-path --sdk macosx); SRC=../Sage
swiftc -O -sdk "$SDK" -target arm64-apple-macosx14.0 -module-name TopRatedBuilder \
  $SRC/AdditiveTier+Codable.swift $SRC/AdditiveDetector.swift $SRC/AdditiveKnowledgeBase.swift \
  $SRC/AvoidListMatcher.swift $SRC/BreadScoring.swift $SRC/DrinksScoring.swift $SRC/FatQuality.swift \
  $SRC/IngredientIntegrity.swift $SRC/MockData.swift $SRC/Models.swift $SRC/NutrientLevels.swift \
  $SRC/OFFImageResolver.swift $SRC/OpenFoodFacts.swift $SRC/ProteinBarScoring.swift \
  $SRC/SageCategory.swift $SRC/ScoringV4.swift BuilderStubs.swift TopRatedBuilder.swift \
  -o /tmp/TopRatedBuilder
for r in RulesetV5.json RulesetV509.json Additives.json AdditiveKnowledgeBase.json \
         ingredient_integrity_keywords.json fat_quality_keywords.json; do cp $SRC/$r /tmp/; done
/tmp/TopRatedBuilder fixtures/candidates-live.json

# 3) Annotate image quality (good / low / missing per candidate). Top Rated
#    fills its slots from `good` first, so community kitchen-counter photos
#    stop reaching the top 10. Needs a venv with Pillow:
#      python3 -m venv .imgenv && .imgenv/bin/pip install pillow
.imgenv/bin/python annotate_image_quality.py fixtures/alternatives.json

# 4) Install into app + Worker (byte-identical)
cp fixtures/alternatives.json ../Sage/Alternatives.json
cp fixtures/alternatives.json ../backend/src/alternatives.json
```

When `world.openfoodfacts.org/api/v2/search` is down (it serves an HTML
"temporarily unavailable" page for hours at a time), `generate_candidates.py`
falls back automatically: popularity-sorted codes from search-a-licious
(`search.openfoodfacts.org`) hydrated one by one from the product endpoint
(paced ~1.2 s — it 429s after ~30 rapid calls). Slower, same output.

`generate_candidates.py` stamps each row with `countries: ["us"]` / `["uk"]` /
`["ca"]` (merged when the barcode appears in multiple pulls). `TopRatedBuilder`
keeps the per-market top N, then merges by barcode. The **Top Rated browse tab
is US-only**; the UK/CA candidates feed Better Alternatives.

### Category hygiene

`SHELF_TAGS` says what each shelf pulls; `SHELF_EXCLUDE` says what it must
never contain even when OFF's community-tagged hierarchy leaks it in (skyr
under cheeses, squash concentrate under sodas, coffee creamer under
plant-milks…). When a wrong product shows up on a shelf, fix it here — not in
the app.

The builder additionally rejects unusable names ("Unknown product", empty,
barcode-as-name) and dedupes size/language SKU variants.

## When to regenerate

- Every **ruleset version bump** (`AlternativesSyncTests` fails if
  `ruleset_version` ≠ bundled `RulesetV4.version`)
- Roughly monthly for OFF freshness

## Single-market (legacy)

```bash
python3 generate_candidates.py --countries us --out fixtures/candidates.json
```
