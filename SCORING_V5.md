# SCORING V5 — health-only score

**Ruleset version:** `2026.07-v5.0.7`  
**Engine:** `ScoringEngineV4.engineVersion = "v5"` (Swift type name retained; behavior is V5)  
**Config:** `Sage/RulesetV5.json` ↔ `backend/src/ruleset.json` (must stay byte-identical)  
**Sync test:** `RulesetSyncTests.bundledMatchesBackendRulesetBytes`  
**Overview cache:** `exp-v8`

## Identity

Sage’s score measures **health only**. Packaging, certifications, animal welfare,
origin, organic labels, and similar ethics/environment factors are removed unless
they have a direct documented health pathway:

| Kept (reframed) | Pathway |
|---|---|
| `brewMaterial` | Microplastic exposure from plastic tea/coffee bags in hot water |
| `contaminantRisk` | Arsenic risk for rice plant milks (rice → 0.4; else 1.0) |

Removed: S7 packaging, S8 certifications, S9 organic, S11 origin, welfare,
dairyLabels, dairyQuality, water profile, flourOxidizers, ice-cream stabilizers
(double-count with S1), **S6** (NNS handled via S3 drinks floor).

Organic preference is display-only: when the user opts in **and** OFF labels
confirm a certification (`organic` / `eu-organic` / `usda-organic`), the result
card shows a neutral `Organic ✓` chip — no score multiplier.

## Formula

For profile rules with weights \(w_i\) and fractions \(f_i \in [0,1]\):

\[
\text{score} = \max\bigl(10,\; \mathrm{round}(100 \cdot \sum w_i f_i / \sum w_i)\bigr)
\]

Every profile has \(\sum w = 100\). Confidence = \(\sum(w \text{ with data}) / \sum w\).
`dairyProcessing` default and `brewMaterial` unknown report `hadData = false`.

Your Score multiplies rule weights by objective × goal × slider × **preference**
factors (clamped per-rule to \([0.5, 2.0]\)). Preference map (V5.0.4): high
protein/fiber → S12×1.25; low sugar → S3×1.3; low sodium → S4×1.3; low fat →
S5×1.3; minimally processed → S2×1.25. Organic has no multiplier.

**V5.0.6:** `eat healthier` also multiplies S3/S4/S5 ×1.2 (in addition to S2/S1/S12).

## FVN inference (V5.0.5)

When OFF omits `fvn`, the engine infers 100 for NOVA 1–2 products tagged as
fruits/fresh-fruits/berries/tropical-fruits, vegetables/fresh-vegetables/salads,
nuts, or legumes. This normalization happens before profile rules and caps, so
S12 receives a data-backed FVN axis and S3 applies the intrinsic-sugar discount
even when a whole fruit is misrouted to another profile. NOVA 3/4 never infer.
Debug output distinguishes provenance, e.g. `fvn: 100 (inferred: fruits)`.
Bare `fvn: 100.00` (no inferred annotation) means measured OFF data.

## Bands (single source of truth)

| Band | Cut |
|---|---|
| Excellent | ≥ 75 |
| Good | ≥ 55 |
| OK | ≥ 35 |
| Bad | else |

UI (`scoreTier`, CompactScoreRing, Overview, Methodology) reads these cuts —
no local constants.

## Caps

| Gate | Applies to | Trigger | Cap |
|---|---|---|---|
| `transFat` | **Overall** | Industrial TFA only: (`transFat_g > 0.2` ∧ NOVA 4) **or** ingredients match `partially hydrogenated` / `parcialmente hidrogenad`. Ruminant profiles (`dairy_milk`, `yogurt_cheese`, `meat`) need `transFat_g > 2.0` on the numeric path; text path always fires. | 35 |
| `freeSugarCeiling` | **Overall** (foods only) | caloric-sweetener category **or** (`sugar_g ≥ 50` ∧ `fvn < 80`). Dried fruit with high FVN is exempt. Pure table sweeteners are **unscored** (V5.0.7), so this gate no longer produces a dial for them — it still caps candy/sugary foods. | 35 |
| `nnsCeiling` | **Overall** (dead path) | Kept in ruleset; table NNS products route to `unscored_sweetener` so the ceiling never binds a dial. | 58 |
| `dietConflictCap` / tapers | Your Score | restriction conflict | 20 (or tapered) |
| `avoidListCap` | Your Score | avoid-list hit | 49 |

Stacked preference caps: `effectiveCap = min(fired)`; chip only when binding.

**V5.0.6:** Overall health caps (`overallFiredCaps` / `overallBindingCap`) are stored
and explained separately from Your Score preference caps (`firedCaps` /
`bindingCap`). Overview leads with plain-language overall-cap attribution when
a health cap binds; “on your list” claims may only name avoid/restriction items.

## Whole foods

- **S1 bypass:** NOVA ∈ {1,2}, no additives, no textSignals → \(f=1\) even if
  `ingredients_text` is missing.
- **Profile `whole_foods` (V5.0.6):** S2 24, S12 24 (`produce`), S3 18, S1 10,
  S4 8, **S5 10**, S13 6. S5 raised so sat fat is a real whole-food risk axis
  without distorting near-zero-satfat produce.
  Router tags (narrow only): fruits, fresh-fruits, berries, vegetables,
  fresh-vegetables, salads, eggs, legumes, nuts. No `*-and-their-products`
  umbrellas. **NOVA gate:** whole_foods matches require NOVA ∈ {0,1,2}; NOVA 3/4
  fall through (peanut butter with ancestral `nuts` → general).
- **Noodles:** `instant-noodles` / `noodles` → snacks **before** `pastas` → breads.
- **S12 `produce`:** \(f = 0.20\cdot\mathrm{protDens} + 0.30\cdot\mathrm{fiber} + 0.50\cdot\mathrm{fvn}\)

## Continuous `stepped()`

Piecewise-linear through anchors \(f(t_0)=1\), \(f(t_1)=0.60\), \(f(t_2)=0.30\),
\(f(1.5\cdot t_2)=0\).

## Juice free sugar + NNS (S3 drinks)

FVN discount capped at 30%. When `addedSugar_g` present and FVN ≥ 80,
effective = `max(addedSugar_g, sugar_g · 0.70)`.
After computing \(f\), if any non-nutritive sweetener is present (E-codes
e950/e951/e954/e955/e957/e959/e960–e962/e969 or stevia/sucralose/aspartame/acesulfame
in text), \(f = \min(f, 0.30)\).

Drinks weights: S1 20, S2 16, S3 42, S4 6, S5 4, S12 8, S13 4; thresholds `[0.5, 2, 4]`.

## Profile weights (Σ = 100)

See `RulesetV5.json` `profiles`.

- `snacks`: S1 26, S2 28, S3 12, S4 16, S5 10, S12 5, S13 3.
- `fats` (V5.0.6): S5 **54** (`fats`), S2 16, S1 12, S4 10, S13 **8**.
  Its S5 thresholds are `[8, 20, 40]`, reaching zero at 60 g. S12 is excluded
  so saturated fat is not double-counted or mislabeled as “protein and fiber.”
  Lower S13 weight clears provisional on oils when only micronutrients are unknown.

## Overview truthfulness (V5.0.6)

- Exclude S3/S4/S5 from positives when the nutrient badge is HIGH.
- Negatives require potential loss ≥ 2.0 (`w·m·(1−f)` when personalized).
- Unknown-tier rules may only be described as missing data (never measured
  deficiency like “held back by micronutrients”).
- S12 negatives with GOOD/HIGH protein/fiber badges use density phrasing.
- Cache bump: `exp-v7` → `exp-v8` (lazy regen).

## Pipeline notes

- OFF `caffeine_100g` is grams → map ×1000 to `caffeine_mg`.
- USDA gap-fills missing nutriments; may always supply `added-sugars_100g`.
- Caffeine avoid also matches coffee/tea/energy/cola/mate categories (unless decaf).
- Additive UI risk follows scoring tier unless KB overrides; e960/e961/e962/e969 = C.
- Overview positives/negatives are mutually exclusive (higher rank wins; tie → negative).

## Unscored sweeteners (V5.0.7)

Pure sweeteners (honey, sugar, syrups, agave, molasses, table NNS) route to
`unscored_sweetener` instead of a weighted profile. Sage withholds Overall /
Your Score / band / caps / Overview — a 0–100 health number would only mislead.
Diet restrictions and avoid-list hits still evaluate (without “cap” copy).
Qualitative “Among sweeteners” notes reuse `sweetenerType` / `authenticity` /
`sweetenerProcessing` tables (the weighted `sweeteners` profile is removed).

## Migration

- `rulesetV506Rescored` — V5.0.6 weight/overview truthfulness; overviews under `exp-v8`.
- `rulesetV507Rescored` — one-shot: saved sweeteners become `unscored(reasonKey: "sweetener")`
  with scores/caps/overview cleared; other products rescore with expected Δ0.
  No global `/explain` cache bump — the client never POSTs `/explain` for unscored.

Product KV cache unchanged (raw data, not scores). Boot prefers the bundled
ruleset when a persisted download is older.

## Calibration snapshot

Fixture engine scores for ruleset `2026.07-v5.0.7` (from `V5CalibrationSnapshotTests`).
Every row is produced by executing the live engine at test time.

**Changed vs v5.0.6:** only three movers — `white sugar`, `raw honey`, and
`stevia tablets` → **unscored**. All other rows Δ0.

| Product | Overall | Δ vs v5.0.6 | Band | Fired caps |
|---|---:|---:|---|---|
| apple | 86 | 0 | Excellent | — |
| banana | 87 | 0 | Excellent | — |
| chicken breast (no text) | 88 | 0 | Excellent | — |
| chicken breast (with text) | 88 | 0 | Excellent | — |
| plain green tea | 79 | 0 | Excellent | — |
| OJ | 48 | 0 | OK | — |
| Coke | 24 | 0 | Bad | — |
| Diet Coke | 34 | 0 | Bad | — |
| white sugar | unscored | — | — | — |
| raw honey | unscored | — | — | — |
| stevia tablets | unscored | — | — | — |
| cheddar | 64 | 0 | Good | — |
| extra-virgin olive oil | 84 | 0 | Excellent | — |
| unsalted butter | 44 | 0 | OK | — |
| salted butter | 38 | 0 | OK | — |
| margarine | 35 | 0 | OK | transFatCap:35 |
| coconut oil | 37 | 0 | OK | — |
| fresh coconut | 82 | 0 | Excellent | — |
| whole milk | 70 | 0 | Good | — |
| dates | 86 | 0 | Excellent | — |
| salted nuts | 87 | 0 | Excellent | — |
| unsalted nuts | 91 | 0 | Excellent | — |
| ramen | 28 | 0 | Bad | — |
| Jif | 48 | 0 | OK | — |
| Cheerios | 58 | 0 | Good | — |
| Nature Valley | 48 | 0 | OK | — |
| Yorgus | 59 | 0 | Good | — |

Standing calibration rule: every new profile must add its permanent reference
fixtures to this snapshot in the same change.
