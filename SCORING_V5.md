# SCORING V5 — health-only score

**Ruleset version:** `2026.08-v5.3.0`  
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
| ~~`S7` packaging~~ | **Removed from scoring (F1)** — kept as a sustainability badge only. Container-leaching evidence has no dose-response basis for ranking one clean liquid above another. |
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
| `eggs` | S2 18, S1 12, S3 4, S4 10, S5 8, S12 18 (`egg`), S13 12 (`egg`), S14 12, S15 6 |
| `general` | S1 20, S2 22, S3 8, S4 8, S5 4, S12 11, S13 5, S14 14, S15 8 |
| `breads` | S1 18, wholeGrain 12, S3 8, S4 8, S2 16, S12 12, S13 4, S14 14, S15 8 |
| `meat` | S1 30, S2 14, S4 10, S5 6, S12 14, S13 4, S14 14, S15 8 |
| `dairy_milk` | S1 24, dairyProcessing 10, S3 6, S5 6, S2 6, S12 20 (`dairy`), S13 8, S14 14, S15 6 |
| `yogurt_cheese` | S1 24, dairyProcessing 8, S3 10, S4 10, S5 12, S12 8 (`dairyDense`), S13 8, S14 14, S15 6 |
| `plant_milk` | S1 20, S10 16, contaminantRisk 8, S3 10, S5 4, S12 12, S2 10, S14 14, S15 6 |
| `tea_coffee` | S1 28, S2 24, brewMaterial 12, S3 8 (`foods`), S12 14 (`dryBrew` — redistributes: beans/leaves never carry a micronutrient panel), S14 14 |
| `drinks` | S1 23, S3 43 (`drinksServing`), S8 15 (caffeine), S6 13 (tiered sweeteners), S4 6 — **no S2, no S7** |
| `juice_100` | same weights as `drinks`; dose-aware S3 + juice sugar cap + flat +3 micronutrient boost |

## V5.3.0 Eggs (dedicated profile)

Eggs used to route to `whole_foods` (fruit/veg blend). Its S12 is 80 %
fiber + FVN — axes an egg can never earn — so a whole egg scored S12 ≈ 0.12
and the overview told users one of the most nutrient-dense whole foods had
"limited nutritional quality". Real OFF eggs scored **47–76** depending on
label luck: no NOVA (a fifth of OFF eggs) → 47–51; "Eggs." with a trailing
period or "Hen eggs" / "Œufs de poules élevées en plein air" → −6 on S14;
`general` fallback for hard-boiled / liquid eggs. Oasis scores eggs almost
entirely on sourcing (housing 30 / feed 30 / practices 25 / packaging 15) —
welfare and farming inputs that Sage's health-only identity excludes. What
Sage keeps from that line of thinking is the *measurable outcome*: nutrient
enrichment declared in the egg, never the feed or housing claim.

- **`eggs` profile** — S2 18, S1 12, S3 4, S4 10, S5 8, S12 18, S13 12,
  S14 12, S15 6. Sugar is structurally ~0.5 g so S3 is small; sodium is
  weighted up (brines / pickling are the real egg-product sodium story);
  S15 stays for formulated products that add oils (redistributes on a plain
  egg, as everywhere).
- **Routing** — router `eggs` → `eggs`, gated by an **egg-dominance guard**
  (`eggs.guard`): OFF's `eggs` tag is inherited by scotch eggs, egg pasta
  and dishes. With a list, the first ingredient must be an egg word
  (`eggs.eggWords`, multilingual); without one, composition must look like
  an egg (protein 8–18 g, ≤220 kcal, ≤3 g sugar). Declared protein under
  8 g/100 g (egg salad, quiche) falls through to `general` either way. A
  tag-independent **`eggEvidence` gate** (egg word in the NAME *and* as the
  first ingredient *and* the guard) catches OFF US imports that carry no
  categories at all (field QA: a "Liquid Eggs" carton with `categories:
  ["undefined"]`). Name or list alone never qualifies ("egg noodles",
  "eggnog").
- **Normalization** (`eggNormalized`, `eggs` route only) — (1) egg powders
  are judged per 100 g as reconstituted (×0.25, keyword + kcal ≥ 400 trigger,
  mirrors `dairyPowder`); (2) **evidence-based NOVA**: a list that is nothing
  but egg words with no additives is NOVA 1 by NOVA's own definition
  (pasteurization is group-1 processing) regardless of the OFF tag, and a
  plain egg with no list and no NOVA is NOVA 1 too. A preserved list
  ("eggs, water, citric acid, sodium benzoate") is never inferred.
- **S12 `egg`** — protein per 100 g against a reference large egg
  (`proteinTargetG` 12 — the US label value; USDA 12.6). Absolute, not per
  kcal, so whites-vs-whole is answered by S13, not here. Unknown → 0.5.
  Fiber/kcal confidence haircuts don't apply (no fiber axis). Overview topic
  is relabelled **"protein"** (never "protein and fiber").
- **S13 `egg`** — reference-composition **prior by form** (`s13Prior`:
  whole/yolk 0.85, whites 0.45; form from tags → first ingredient / name
  words → no-yolk-fat envelope) plus an **enrichment lift**: declared
  vitamin D ≥ 4 µg, B12 ≥ 1.8 µg, omega-3 ≥ 0.3 g or selenium ≥ 60 µg per
  100 g (≈2× a reference egg — what feed programs actually change in the egg)
  adds 0.05 each, capped at +0.10. A full *ordinary* panel (vitamin D 2 µg,
  choline 294 mg, selenium 31 µg) is the reference egg and lifts nothing —
  label completeness must not separate identical eggs. The prior is marked
  `hadData` (the form is evidenced), sits below full credit on purpose
  (assumption < evidence), and declared values can only raise it. New
  `Nutrients` fields: `vitaminD_ug`, `vitaminB12_ug`, `choline_mg`,
  `selenium_ug`, `omega3_g` (OFF g/100 g → µg/mg with implausibility guards).
- **S3 prior** — undeclared sugars on an `eggs`-routed product → 0.95
  (`s3UnknownCredit`, unknown-tier): sugars in an egg are bounded far below
  the first threshold; a label omission is not a risk.
- **S14 fixes (generic)** — `IngredientIntegrity.tokens` now strips trailing
  sentence punctuation and OFF allergen underscores (`"Eggs."`,
  `"_Œufs_ frais"`, `"honey*"`); before, the last token of *every*
  period-terminated list failed the whitelist. Qualifier stripping gains
  housing / size / form words (free range, cage free, pasture raised, barn,
  hen, liquid, hard boiled, boiled, cooked, large, medium, grade aa);
  whitelist gains whole egg / egg white(s) / yolk / hen / quail / duck eggs
  and FR / ES / PT / IT / DE / NL egg terms. Shelf-wide drift: 64 / 1 775
  Alternatives products move, all +1/+2 except "MANGO." baby food +7,
  "grade A nonfat _milk_" yogurt +6, one noodle −2 (a now-detected palm-oil
  token); **no routing changes**.
- **Overview** — S12 topic "protein" for eggs; template / Worker negative
  phrase "limited protein credit"; the fiber-claim validator rejects fiber
  prose for eggs automatically (no fiber topic in payload).
- **Calibration (harness, real OFF records):** plain shell eggs 97–98 regardless of organic / free-range / pasture claims;
  enriched (Eggland's Best: vitamin D 12 µg + B12 2 µg) 99; hard-boiled
  clean = 100 % liquid = shell; egg whites 91; yolks 94; duck / quail 97–98;
  hard-boiled with citric acid + sodium benzoate 81; century egg 76; pickled
  74–75; formulated whites with gums / colors (Egg Beaters type) 60–61;
  scotch eggs / egg salad → `general` (48 / 53); plant-based substitutes
  untouched (not eggs). Eggs with no NOVA / no list now 98 (were 47–51).
- **Deliberately not scored:** housing (cage-free / free-range / pasture —
  welfare, and the measured nutrient differences are small and not on the
  label), feed claims (corn-&-soy-free, organic feed), antibiotics, yolk
  colorants, packaging, lab testing; **cholesterol** (DGA 2020–25 dropped the
  300 mg cap; AHA 2019: up to an egg a day compatible with heart health for
  most people — a dose / individual matter, not a product-ranking axis);
  pasteurized-shell safety (a badge candidate, not points). Whole egg ≈ 98
  vs plain milk 93: the framework places a clean single-ingredient animal
  food near the ceiling; cholesterol is the only caveat and is documented,
  not scored.
- `rulesetV530Rescored` one-shot migration; overview cache stays `exp-v9`
  (invalidated by the migration flag). `RulesetV509.json` untouched (kill
  switch path keeps eggs on `whole_foods`).

## V5.2.0 Dairy milk (health-only, dairy-aware)

Fixes a category where the generic rules were structurally wrong for the food:

- **S12 `dairy` variant** — fiber and FVN are 60% of generic S12 and milk can
  never earn them, which compressed every milk into 74–78. The dairy variant is
  `0.5·min(1, protein/3.4 g) + 0.5·min(1, calcium/125 mg)` per 100 ml
  (`s12Dairy` config). Protein is per **volume**, not per kcal, so whole vs
  skim stays deliberately neutral (fat level is preference → Your Score; S5
  still scores saturated fat). Missing calcium falls back to protein alone.
  The fiber/kcal confidence haircuts don't apply to the dairy variant.
- **dairyProcessing matches real OFF tags** — the table previously listed
  `raw-milk` / `uht` / `ultrafiltered` while OFF emits `raw-milks`,
  `uht-milks`, etc., so no entry ever fired and every milk fell to the 0.85
  unknown default. The table now carries the plural OFF forms plus
  `sterilized`, `microfiltered` (0.9), and explicit `pasteurised-milks` /
  `fresh-milks` at 0.85 — same value as the default but **evidenced**
  (hadData, confidence).
- **Raw-milk safety gate** (`hardGates.rawMilk`, cap 54) — unpasteurized fluid
  milk caps at OK-band with a chip. Nutritionally raw ≈ pasteurized; the risk
  is microbial (Listeria / STEC / Salmonella) and no barcode metadata can
  verify herd testing, so unknown ≠ low risk. Copy stays factual and cites
  vulnerable groups; no "toxic"-style language.
- **Fortification exemption** (`dairyFortification`) — vitamin D/A and lactase
  tokens are stripped before S14/S15, and when the remaining list is pure
  whole food the product returns to NOVA 1 for S2. Vitamin D milk and
  lactose-free milk previously lost ~9 points to the NOVA-3 cascade;
  fortifying milk is a public-health win, not processing. Ultrafiltered milk
  is *not* laundered — "ultrafiltered milk" is not whitelisted, so its NOVA-4
  identity and 0.25 processing credit stand.
- **Powder reconstitution** (`dairyPowder`) — milk powders are judged per
  100 ml as prepared (×0.125), not as 38 g/100 g "sugar". Trigger requires a
  powder keyword in name/ingredients (never category tags — OFF's
  `milks-liquid-and-powder` ancestor rides on liquids) **and** kcal ≥ 200.
- **S13 dataFloor** (`micronutrients.dataFloor`) — a declared micronutrient
  panel never scores below the 0.35 unknown credit. Milk's 120 mg calcium
  earned f 0.08, so reporting calcium scored *worse* than silence.
- **S14 qualifier stripping** — `IngredientIntegrity.isWholeFoodToken` strips
  identity-preserving prefixes (organic / raw / fresh / grade a / pasteurized
  …) before a whitelist retry; "organic milk" no longer costs 6 points. The
  whitelist gains goat/sheep/buttermilk/fat-level variants. "whole" is
  deliberately not strippable (whole wheat flour ≠ wheat flour).
- **Flavored milks route to `drinks`** — `flavoured-milks` / `chocolate-milks`
  / `milkshakes` entries precede `milks` in the router. The drinks path is
  purpose-built for sugary RTDs: M2 lactose allowance, per-serving S3, satFat
  cap, +3 dairy-nutrition merit. Chocolate milk ≈ 65 vs plain milk ≈ 93.
- **Calibration:** plain milks (whole = semi = skim ±1) ≈ 93 Excellent;
  vat-pasteurized 94; UHT 88; ultrafiltered ~73; raw capped 54. Ladder guard:
  vat ≥ pasteurized > UHT > ultrafiltered > raw (`MilkScoringV52Tests`).
- `isV510` is now `version >= "2026.07-v5.1.0"` so v5.1.0 engine paths stay on
  across later version bumps. One-shot migration: `rulesetV520Rescored`.

### yogurt_cheese extension (same release)

- **S12 `dairyDense`** (`s12DairyDense`: protein 6 g, calcium 150 mg) — protein
  credit is the mean of absolute per-100 g and per-kcal density (15 g/100 kcal
  anchor). Absolute alone ranks cream cheese above plain yogurt (5.9 vs 3.5 g);
  density alone breaks whole-vs-nonfat yogurt neutrality. The blend keeps
  whole = nonfat within a point and yogurt above cream cheese.
- **Reweight** S12 14→8, S5 8→12, S4 8→10 — the dead S12 was accidentally doing
  the sat-fat/sodium rules' job of separating cheeses; now they do it openly.
- **Raw-milk cheese** (`raw-milk-cheeses` tag) takes the graded 0.5 processing
  dock but **not** the fluid-milk 54 cap — aged cheese is a different risk
  class (60-day rules); the gate stays scoped to `dairy_milk` routing.
- Fortification stripping extends to yogurt_cheese; **powder reconstitution
  does not** (processed cheeses legitimately list "milk powder" and are dense
  per 100 g by nature — `includePowder: false`).
- Whitelist gains traditional fermentation terms (cultures / rennet variants);
  "salt" and generic "enzymes" deliberately stay off.
- **Calibration:** plain whole = nonfat yogurt 90, Greek 92–93, kefir 88,
  cottage 86, sweetened yogurt ~80, mozzarella 77, cream cheese 72,
  cheddar 71 (was 64), raw-milk cheddar 68 (`YogurtCheeseV52Tests`).

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
  else declared serving if 100–600 ml, **floored at the category-typical dose**
  (field QA: a 1 L cola declaring a 250 ml serving scored 29 vs 20 for the
  identical liquid in a can — declared servings below the typical dose are
  raised to it and flagged estimated); else **355 ml** + `estimatedServing`.
  Containers under 30 ml and minus-signed quantities are junk data, not servings.
- **S3 (drinks):** sugar per effective serving. Track 2 anchors (`s3DrinksServingCurve`
  in both rulesets): ≤1 g → 100%, 5 g → 60%, 8 g → 48%, 16 g → 25%, ≥30 g → 0%.
  The low end is steep so a lightly sweetened soda stops scoring like plain water.
  **Lactose allowance (M2):** for RTDs with dairy ingredient evidence (plant-milk
  phrases stripped first, so "oat milk" never qualifies), up to 4.8 g/100 ml of
  total sugar is treated as intrinsic lactose and excluded from S3 and the sugar
  cap — WHO's free-sugar definition excludes milk sugars. A *positive* declared
  added-sugars value is trusted instead when sane; OFF's bogus `added-sugars: 0`
  stays untrusted. Config: `dairyLactoseAllowance` in both rulesets.
  No FVN discount anywhere on the drinks path — WHO counts juice sugars fully
  as free sugars; the lactose allowance above is the only sanctioned exemption.
- **S3 (`juice_100`):** raw total sugar, no FVN discount. Curve ≤6 → 100%,
  10 → 55%, 14 → 25%, ≥18 → 0%. Entry requires FVN ≥95%, no added sugar, no
  sweeteners, additives limited to ascorbic / citric acid.
- **S8** caffeine (measured or category default; energy drinks never default to 0).
  Steeper credit above ~80–150 mg/serving; energy drinks stack extra S8 drag
  plus stimulants (taurine / guarana / mate). **Non-energy coffee/tea RTDs (M4)**
  use an EFSA-anchored gentle curve instead (no meaningful dock ≤100 mg, moderate
  to 200 mg, steep beyond 300) and a caffeine cap that starts at the 200 mg
  single-dose mark. `energyDrinkEvidence` outranks the tag match (I27), so a
  stimulant-stacked product wearing tea tags stays on the strict path.
- **S6** three tiers (heavy NNS / sugar alcohols / stevia–monk); allulose neutral.
  Erythritol carries an extra −0.10 within Tier 2 — prospective cohorts associate
  circulating erythritol with higher cardiovascular event risk, evidence the
  other polyols don't share (precautionary; copy constraints in §6 apply).
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
  below the caps instead of flattening on them. **F3:** the drag and the
  sugar-cap undercut are piecewise-linear (named anchor tables), not stepwise —
  a 1 mg / 0.2 g data revision can never flip a product across a cliff.
  Continuity is guarded by dedicated sweep tests and a score-level fuzz sweep.
- **Merit layer (drinks only):** the profile is otherwise deficit-only, so two
  small evidence-anchored credits exist: **+3 unsweetened brew** (non-energy
  tea/coffee RTD, ≤2 g free sugar, no sweeteners — coffee/tea polyphenol
  cohort evidence) and **+3 dairy nutrition** (dairy evidence + protein
  ≥2.5 g/100 ml — protein and calcium credited, not just lactose excused).
  Merit applies BEFORE caps: a capped product (Frappuccino) can never merit
  its way up — safety nets outrank bonuses, no health-washing. Kombucha's
  fermentation stays deliberately uncredited: trial evidence is too weak.
- **Serving hardening:** minus-signed quantities never parse ("-5 ml" is junk,
  not 5 ml) and containers under 30 ml are treated as data errors, not
  servings — both found by the property fuzzer.
- **Caps (drinks):** sugar (≤16 → none; 16–30 → 55→20; ≥30 → 20); caffeine
  (Track 2: ≤60 → none; 60–160 → 100→52; 160–200 → 52→40; 200–300 → 40→25;
  ≥300 → 25 — monotonic by construction, guarded by I20; non-energy coffee/tea
  class: ≤200 → none; 200–300 → 100→70; 300–400 → 70→40); Tier-1 → 55;
  Tier-2/3 → 74 above 2 g sugar/serving; **satFatCap (M3, cream visibility,
  data-present only)**: ≤2 g/serving → none; 2→8 g → 95→40; ≥12 g → 25.
  Heavy sugar + caffeine may undercut below `sugarCap` so energy drinks land
  below plain sugary soda.
- **Caps (`juice_100` sugar only):** ≤20 g → none; 20–40 g → 60→36; ≥40 g → 36
  (J-shaped dose-response: glass-sized servings more favorable than large
  single-serve bottles; sugars in juice still count as free sugars). Flat **+3**
  micronutrient boost; if sugar/serving ≥20 g, weighted is clamped **&lt; 55**.
- **Diet soda ordering:** scored above sugary soda (substitution evidence) and
  well below unsweetened drinks (cohort risk signals plus WHO precaution).
- **Packaging is not scored (F1).** The leach-pathway credit (glass > carton/alu >
  PET > PS/PVC; missing → 0.40) still resolves and is surfaced on the breakdown as
  `packagingCredit` / `packagingHadData` for a **sustainability badge**, but it no
  longer contributes to the health score. Microplastic and antimony-migration
  evidence has no dose-response basis for ranking one clean liquid above another,
  and at 6% it was swinging a flawless drink by 4.5 points — more than kombucha's
  entire sugar load cost it. Its weight was redistributed **proportionally** across
  the surviving rules (22/40/14/12/6 → 23/43/15/13/6). Proportional matters: S4
  sodium is ~1.000 for nearly every beverage, so weighting it up by hand handed
  near-free points to zero-sugar energy drinks and broke I16.
- Flags: `lowDataConfidence`, `estimatedServing`, `bindingCapId` on the product /
  breakdown model for UI chips later.

`plant_milk` still uses per-100 ml `drinks` S3 thresholds; only profiles
`drinks` / `juice_100` use this path.

## Drinks routing (v2.4)

Precedence, highest first:

1. **Alcohol exclusions** (`alcoholic-beverages`, beers / wines / spirits / ciders) → `unsupported`. Untouched by evidence gates.
2. **Evidence gates**
   - `energyDrinkEvidence`: measured caffeine ≥ 25 mg/100 ml **and** a stimulant ingredient (taurine / guarana / mate, configurable) → `drinks` with `isEnergyDrink = true` for stacking, caffeine defaults, and compound risk. OR'd with `energy-drinks` tags.
   - `plainWaterEvidence`: a water word in the product NAME (multi-language, configurable) + ≤5 kcal and ≤0.5 g sugar/100 ml + no flavor evidence, additives, caffeine, or sweeteners → `unsupported`, regardless of tags. Field QA: a US S.Pellegrino wearing Spanish category tags ("Aguas", "Bebidas") matched no router entry and scored 77. Name-only matching on purpose — "carbonated water" leads every soda's ingredient list. Guarded by I29.
   - `flavoredWaterEvidence`: waters-family tags + flavor word in the name or flavoring term in ingredients → `drinks` (not `unsupported`).
3. **Category tag matches** (most-specific-first router).
4. **Catch-all** `beverages` → `drinks`, else `general`.

A product tagged `tea_coffee` that fires `energyDrinkEvidence` therefore scores as an energy drink on `drinks`. Nutritional plausibility envelopes (`routingPlausibility`) still rerail after a tag match (e.g. `plant_milk` caffeine/sugar; `tea_coffee` sugar ≥ 5 g/100 ml for sweetened RTDs). Evidence outranks those tag matches. **Liquid gate (M1):** an envelope with `requiresLiquid: true` fires only when the product's size or serving parses as a volume — per-100 ml bounds must never be applied to a powder (a 3-in-1 coffee mix at 60 g sugar/100 g is not a 60 g/100 ml liquid, and must not be handed a fictional 355 ml serving). Guarded by I26.

**Merge order:** Track 2 (S3 low-end, Tier 3 0.70, 60 mg caffeine-cap start, I19–I20) before building the `tea_coffee` drinks profile. Calibrating that profile against pre-Track-2 curves forces a second fixture pass.

**Resolved — the pre-Track-2 targets for three fixtures were wrong, not the curve.**
LaCroix, unsweetened iced tea, and kombucha were specced to land well below where
Track 2 puts them, and no curve change could have reached those targets:

- LaCroix and iced tea contain **zero sugar and no sweeteners**, so their S3 and
  S6 credits are already 1.000. A sugar or sweetener change cannot lower a rule
  at full credit. Their scores are simply the ceiling for a flawless drink.
- Kombucha's old target contradicted Track 2's own anchors. It is flawless except
  for sugar (59.6 points before S3), so ≤75 required an S3 credit ≤0.385, while
  Track 2 specifies 0.48 at 8 g. No drink with ≤8 g sugar and otherwise perfect
  credits can score ≤75; a flawless drink first reaches 75 at ~11.3 g. Kombucha
  has 6.0 g.

The ranges were therefore re-derived from measured scores (LaCroix and every
flavored-water variants and iced tea 95–100 after F1, kombucha 77–87). Because widening
ranges weakens them as a signal, **I23** now asserts the ladder those ranges rest
on directly: unsweetened zero-sugar > kombucha > lightly sweetened > diet soda >
sugary soda, each by 5+ points. Run `printCalibrationTable` for per-rule numbers.

**Plain vs flavored water.** Genuinely unflavored water — still or sparkling —
stays `unsupported`: it is not a product choice to rate. Flavored sparkling water
**is** scored, via `flavoredWaterEvidence`, because the flavoring makes it one.
The line is flavor evidence in the name or ingredients, nothing else.

## Migration

- `rulesetV510Rescored` — one-shot lazy rescore when v5.1.0 is enabled.
- Overview cache stays on `exp-v9`.

## Calibration

See `V5CalibrationSnapshotTests` / live engine under `2026.07-v5.1.0`. Seed oils
must fall ≥30 vs v5.0.9 and rank below EVOO / coconut / butter. Ice-cream
fixtures: Protein Pints ≤48 (band OK); Honey Honey ≥61 (Good) and ranks above.
