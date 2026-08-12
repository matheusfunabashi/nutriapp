# TopRatedBuilder — offline alternatives / Top Rated generation

Builds `alternatives.json` (and `top-rated.json`) from a `candidates.json`
pulled from Open Food Facts. The app and Worker ship the same
`alternatives.json` byte-for-byte.

## Prerequisites

- Xcode (macOS target `TopRatedBuilder`)
- Python 3
- Network access to `world.openfoodfacts.org`

## Standard regeneration (US + UK + CA)

From the repo root:

```bash
# 1) Pull popularity-ranked OFF candidates per shelf per market.
#    150/shelf gives the app-side Top Rated eligibility gate headroom.
#    The script pages the API (100/page), drops off-shelf products via
#    SHELF_EXCLUDE tags, and EXITS NON-ZERO if any shelf×market pull comes
#    back empty — never ship a file from a failed run.
cd TopRatedBuilder
python3 generate_candidates.py --countries us,uk,ca --per-shelf 150 \
    --out fixtures/candidates-live.json

# 2) Score with the bundled ruleset (must match RulesetV5 / live app version),
#    keep the top 50 (us) / 25 (uk, ca) per shelf per market, write
#    alternatives.json
xcodebuild -project ../Sage.xcodeproj -scheme TopRatedBuilder -configuration Release build
BUILD=$(ls -d ~/Library/Developer/Xcode/DerivedData/Sage-*/Build/Products/Release/TopRatedBuilder | head -1)
"$BUILD" fixtures/candidates-live.json

# 3) Annotate image quality (good / low / missing per candidate). Top Rated
#    fills its slots from `good` first, so community kitchen-counter photos
#    stop reaching the top 10. Needs a venv with Pillow:
#      python3 -m venv .imgenv && .imgenv/bin/pip install pillow
.imgenv/bin/python annotate_image_quality.py fixtures/alternatives.json

# 4) Install into app + Worker (byte-identical)
cp fixtures/alternatives.json ../Sage/Alternatives.json
cp fixtures/alternatives.json ../backend/src/alternatives.json
```

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
