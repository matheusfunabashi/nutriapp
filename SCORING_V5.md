# SCORING V5 — health-only score

**Ruleset version:** `2026.07-v5.1.0`  
**Engine:** `ScoringEngineV4.engineVersion = "v5"` (Swift type name retained; behavior is V5)  
**Config:** `Sage/RulesetV5.json` ↔ `backend/src/ruleset.json` (must stay byte-identical)  
**Frozen fallback:** `Sage/RulesetV509.json` (`2026.07-v5.0.9`) when `flags.rulesetV510Enabled` is false  
**Sync test:** `RulesetSyncTests.bundledMatchesBackendRulesetBytes`  
**Overview cache:** `exp-v9`

## Identity

Sage’s score measures **health only**. Packaging, certifications, animal welfare,
origin, organic labels, and similar ethics/environment factors are removed unless
they have a direct documented health pathway:

| Kept (reframed) | Pathway |
|---|---|
| `brewMaterial` | Microplastic exposure from plastic tea/coffee bags in hot water |
| `contaminantRisk` | Arsenic risk for rice plant milks (rice → 0.4; else 1.0) |
| `S15` Fat Quality | Refining process + fatty-acid source (not “natural is better”) |

## Kill switch (V5.1.0)

`flags.rulesetV510Enabled` in the ruleset JSON (default `true`, cached in
`UserDefaults`). When false, `RulesetStore.current` serves frozen
`RulesetV509.json` and v5.1.0 engine paths (S15, sweetener substitution cap,
global isolate discount, intrinsic dairy discount) stay off.

## Formula

For profile rules with weights \(w_i\) and fractions \(f_i \in [0,1]\):

\[
\text{score} = \max\bigl(10,\; \mathrm{round}(100 \cdot \sum w_i f_i / \sum w_i)\bigr)
\]

Every profile has \(\sum w = 100\). Missing S14/S15 data redistributes weight out
of \(\sum w\). Confidence haircuts apply for missing nutrition inputs (floor 60%).

## V5.1.0 Real Food axes

- **S14 Real Food** — ingredient integrity (whole-food ratio, short list,
  sweetener/isolate systems). On all food profiles except drinks.
- **S15 Fat Quality** — ingredient-list fat tiers (high / low / zero) with
  refining ×0.75. No fat sources → `hadData=false` (redistribute).
- **S3 sweetenerSubstitutionCap** (foods): `min(f, 0.50)` when sweetener-system
  keywords match. Does not stack with drinks NNS floor.
- **S12 isolate discount** ×0.5 on all food profiles when isolate/concentrate
  protein markers are present.
- **S3 intrinsicDiscount** ×0.7 on the penalty for ≤6 ingredients, 0 additives,
  dairy/fruit/honey sugar sources: \(f = 1 - 0.7\cdot(1-f)\).
- **Band color/label** always follow the numeric score (Excellent ≥75, Good ≥55,
  OK ≥35, Bad &lt;35). No display-only UPF/Nutri-Score band caps.

## Profile weights (Σ = 100)

| Profile | Weights |
|---|---|
| `fats` | S15 34, S5 18, S2 14, S1 12, S14 12, S4 6, S13 4 |
| `ice_cream` | S1 20, S3 16, S5 10, S2 20, S12 6, S13 4, S14 16, S15 8 |
| `snacks` | S1 20, S2 24, S3 10, S4 12, S5 6, S12 4, S13 2, S14 14, S15 8 |
| `whole_foods` | S2 20, S12 22, S3 14, S1 8, S4 6, S5 8, S13 6, S14 16 |
| `general` | S1 20, S2 22, S3 8, S4 8, S5 4, S12 11, S13 5, S14 14, S15 8 |
| `breads` | S1 18, wholeGrain 12, S3 8, S4 8, S2 16, S12 12, S13 4, S14 14, S15 8 |
| `meat` | S1 30, S2 14, S4 10, S5 6, S12 14, S13 4, S14 14, S15 8 |
| `dairy_milk` | S1 24, dairyProcessing 10, S3 6, S5 6, S2 6, S12 20, S13 8, S14 14, S15 6 |
| `yogurt_cheese` | S1 24, dairyProcessing 8, S3 10, S4 8, S5 8, S12 14, S13 8, S14 14, S15 6 |
| `plant_milk` | S1 20, S10 16, contaminantRisk 8, S3 10, S5 4, S12 12, S2 10, S14 14, S15 6 |
| `tea_coffee` | S1 28, S2 24, brewMaterial 12, S3 8, S12 14, S14 14 |
| `drinks` | unchanged (S1 20, S2 16, S3 42, S4 6, S5 4, S12 8, S13 4) |

## Migration

- `rulesetV510Rescored` — one-shot lazy rescore when v5.1.0 is enabled.
- Overview cache stays on `exp-v9`.

## Calibration

See `V5CalibrationSnapshotTests` / live engine under `2026.07-v5.1.0`. Seed oils
must fall ≥30 vs v5.0.9 and rank below EVOO / coconut / butter. Ice-cream
fixtures: Protein Pints ≤48 (band OK); Honey Honey ≥61 (Good) and ranks above.
