# TopRatedBuilder — offline alternatives / Top Rated generation

Builds `alternatives.json` (and `top-rated.json`) from a `candidates.json`
pulled from Open Food Facts. The app and Worker ship the same
`alternatives.json` byte-for-byte.

## Prerequisites

- Xcode (macOS target `TopRatedBuilder`)
- Python 3
- Network access to `world.openfoodfacts.org`

## Two-country regeneration (US + Brazil)

From the repo root:

```bash
# 1) Pull popularity-ranked OFF candidates per shelf for US and BR
cd TopRatedBuilder
python3 generate_candidates.py --countries us,br --out fixtures/candidates-live.json

# 2) Score with the bundled ruleset (must match RulesetV5 / live app version),
#    keep top 25 per shelf *per country*, write alternatives.json
xcodebuild -project ../Sage.xcodeproj -scheme TopRatedBuilder -configuration Release build
BUILD=$(ls -d ~/Library/Developer/Xcode/DerivedData/Sage-*/Build/Products/Release/TopRatedBuilder | head -1)
"$BUILD" fixtures/candidates-live.json

# 3) Install into app + Worker (byte-identical)
cp fixtures/alternatives.json ../Sage/Alternatives.json
cp fixtures/alternatives.json ../backend/src/alternatives.json
```

`generate_candidates.py` stamps each row with `countries: ["us"]` / `["br"]`
(or both when the barcode appears in both pulls). `TopRatedBuilder` keeps up
to 25 scored candidates per market per shelf, then merges by barcode.

## When to regenerate

- Every **ruleset version bump** (`AlternativesSyncTests` fails if
  `ruleset_version` ≠ bundled `RulesetV4.version`)
- Roughly monthly for OFF freshness

## Single-market (legacy)

```bash
python3 generate_candidates.py --countries us --out fixtures/candidates.json
```
