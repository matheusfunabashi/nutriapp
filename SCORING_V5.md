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
| `S7` packaging (drinks only) | Container leaching / microplastics for ready-to-drink beverages |
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
| `drinks` | S1 22, S3 40 (`drinksServing`), S8 14 (caffeine), S6 12 (tiered sweeteners), S4 6, S7 6 — **no S2** |
| `juice_100` | same weights as `drinks`; dose-aware S3 + juice sugar cap + flat +3 micronutrient boost |

## Drinks profile v2.3 (cap-based)

Ready-to-drink beverages (`sodas`, energy drinks, iced teas/coffees, sports
drinks, kombucha, nectars / juice drinks, catch-all `beverages`) use
`DrinksScoring.swift`. Eligible **100% juices** route to `juice_100` instead.

```
earned        = Σ(credit × weight)   // juice_100: +3 then may clamp <55
weightedScore = earned − stackingDrag // diet/energy spread; juice_100 drag = 0
finalScore    = min(weightedScore, sugarCap, caffeineCap, sweetenerCap)
              // sugar+caffeine may undercut sugarCap further on energy drinks
```

Credits first, caps as safety nets. Caps should rarely bind on diet/energy;
identical scores across distinct products usually mean a cap plateau.

- **Effective serving:** container ≤600 ml → whole container (anti-gaming);
  else declared serving if 100–600 ml; else **355 ml** + `estimatedServing`.
- **S3 (drinks):** sugar per effective serving. Track 2 anchors (`s3DrinksServingCurve`
  in both rulesets): ≤1 g → 100%, 5 g → 60%, 8 g → 48%, 16 g → 25%, ≥30 g → 0%.
  The low end is steep so a lightly sweetened soda stops scoring like plain water.
  FVN discount max **15%** only for leftover juice-like products (nectars /
  juice drinks). No micronutrient boost on the regular profile.
- **S3 (`juice_100`):** raw total sugar, no FVN discount. Curve ≤6 → 100%,
  10 → 55%, 14 → 25%, ≥18 → 0%. Entry requires FVN ≥95%, no added sugar, no
  sweeteners, additives limited to ascorbic / citric acid.
- **S8** caffeine (measured or category default; energy drinks never default to 0).
  Steeper credit above ~80–150 mg/serving; energy drinks stack extra S8 drag
  plus stimulants (taurine / guarana / mate).
- **S6** three tiers (heavy NNS / sugar alcohols / stevia–monk); allulose neutral.
  Tier-1 is a strong per-sweetener credit hit (first → 0.10, each extra −0.10);
  Tier-3 stevia/monk is a real penalty after Track 2 (first → 0.70, each extra
  −0.10), no longer a rounding nudge. Tier-1 also sets
  **sweetenerCap = 55** as a net, and Tier-2/Tier-3 set **74** — one point below
  Excellent — once the drink carries more than 2 g sugar per effective serving.
  A genuinely sugar-free stevia drink stays Excellent-eligible; a sweetened one
  does not. This is the mechanism behind I19. Artificial sweeteners are score-limited as a
  precautionary signal: WHO conditionally recommends against non-sugar
  sweeteners for long-term weight control, and large cohorts associate high
  diet-beverage intake with modestly higher cardiovascular risk. IARC lists
  aspartame as “possibly carcinogenic (2B)” on limited evidence; JECFA and FDA
  maintain that intake at normal levels (many cans/day) remains within safe
  limits. App copy must not say sweeteners “cause cancer”, are a “carcinogenic
  ingredient”, “toxic”, or “proven harmful” — prefer “score-limited”,
  “precautionary”, and “evidence is limited and contested”.
- **Stacking drag (drinks only):** post-rule points subtracted so Tier-1 count,
  sports+NNS, and energy (caffeine / stimulants / sugar) separate products
  below the caps instead of flattening on them.
- **Caps (drinks):** sugar (≤16 → none; 16–30 → 55→20; ≥30 → 20); caffeine
  (Track 2: ≤60 → none; 60–160 → 100→52; 160–200 → 52→40; 200–300 → 40→25;
  ≥300 → 25 — monotonic by construction, guarded by I20); Tier-1 → 55;
  Tier-2/3 → 74 above 2 g sugar/serving.
  Heavy sugar + caffeine may undercut below `sugarCap` so energy drinks land
  below plain sugary soda.
- **Caps (`juice_100` sugar only):** ≤20 g → none; 20–40 g → 60→36; ≥40 g → 36
  (J-shaped dose-response: glass-sized servings more favorable than large
  single-serve bottles; sugars in juice still count as free sugars). Flat **+3**
  micronutrient boost; if sugar/serving ≥20 g, weighted is clamped **&lt; 55**.
- **Diet soda ordering:** scored above sugary soda (substitution evidence) and
  well below unsweetened drinks (cohort risk signals plus WHO precaution).
- **S7** packaging leach pathway (glass > carton/alu > PET > PS/PVC; missing → 0.40).
- Flags: `lowDataConfidence`, `estimatedServing`, `bindingCapId` on the product /
  breakdown model for UI chips later.

`plant_milk` still uses per-100 ml `drinks` S3 thresholds; only profiles
`drinks` / `juice_100` use this path.

## Drinks routing (v2.4)

Precedence, highest first:

1. **Alcohol exclusions** (`alcoholic-beverages`, beers / wines / spirits / ciders) → `unsupported`. Untouched by evidence gates.
2. **Evidence gates**
   - `energyDrinkEvidence`: measured caffeine ≥ 25 mg/100 ml **and** a stimulant ingredient (taurine / guarana / mate, configurable) → `drinks` with `isEnergyDrink = true` for stacking, caffeine defaults, and compound risk. OR'd with `energy-drinks` tags.
   - `flavoredWaterEvidence`: waters-family tags + flavor word in the name or flavoring term in ingredients → `drinks` (not `unsupported`).
3. **Category tag matches** (most-specific-first router).
4. **Catch-all** `beverages` → `drinks`, else `general`.

A product tagged `tea_coffee` that fires `energyDrinkEvidence` therefore scores as an energy drink on `drinks`. Nutritional plausibility envelopes (`routingPlausibility`) still rerail after a tag match (e.g. `plant_milk` caffeine/sugar; `tea_coffee` sugar ≥ 5 g/100 ml stub for Frappuccino-class RTD). Evidence outranks those tag matches.

**Merge order:** Track 2 (S3 low-end, Tier 3 0.70, 60 mg caffeine-cap start, I19–I20) before building the `tea_coffee` drinks profile. Calibrating that profile against pre-Track-2 curves forces a second fixture pass.

## Migration

- `rulesetV510Rescored` — one-shot lazy rescore when v5.1.0 is enabled.
- Overview cache stays on `exp-v9`.

## Calibration

See `V5CalibrationSnapshotTests` / live engine under `2026.07-v5.1.0`. Seed oils
must fall ≥30 vs v5.0.9 and rank below EVOO / coconut / butter. Ice-cream
fixtures: Protein Pints ≤48 (band OK); Honey Honey ≥61 (Good) and ranks above.
