# SCORING V5 — health-only score

**Ruleset version:** `2026.08-v5.5.0`  
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
| `bread` | S1 16, S2 14 (`bread`), wholeGrain 16 (`bread`), S12 14 (`grain`), S3 10 (`bread`), S4 12 (`bread`), S5 6, S14 8, S15 4 — **no S13** |
| `grains` (formerly `breads`: cereals, pasta, rice, oats, flours) | S1 18, wholeGrain 12, S3 8, S4 8, S2 16, S12 12, S13 4, S14 14, S15 8 |
| `meat_fresh` | S12 24 (`meatProtein`), S5 20 (`meat` 1.2/4/8), S1 10, S13 10 (`meat` prior), meatForm 10, S4 8, S14 8, S2 6 (`meat` markers), S15 4 |
| `meat_processed` | meatForm 18, S4 18 (`meatProcessed` 400/900/1500), S1 14 (cure additives exempt — the form rule owns curing), S12 14 (`meatProtein`), S5 10 (`meat`), S2 8 (`meat`), S14 8, S3 6 (`foods`), S13 4 (`meat` prior ×0.8) |
| `seafood` | S12 18 (`meatProtein`), omega3 12, S1 14, S14 12, S2 10 (`meat`), S4 10 (`seafood` 250/700/1400), S13 8 (`meat` prior), meatForm 6, S5 6 (`meat`), S15 4 |
| `dairy_milk` | S12 22 (`dairy`), S1 18, S14 14, S2 12 (`dairy` markers), dairyProcessing 10, S3 10 (free sugar), S13 8 (`dairy` prior), S5 6 — **no S15** |
| `dairy_fermented` | S3 26 (`dairy` free sugar), S12 18 (`dairyDense`), S1 14, S14 12, S6 8 (`dairy`), dairyForm 6, S13 6 (`dairy` prior), S5 6, S4 4 (`fermented` prior 0.9) — **no S15** |
| `dairy_cheese` | S4 24 (`cheese` 150/500/1000), S12 18 (`dairyCheese`), S5 14 (`cheese` 6/14/22), S1 12, S14 12, dairyForm 10, S13 6 (`dairy` prior), S3 4 — **no S15** |
| `dairy_cream` | S5 34 (`cream` 1.5/5/10), S1 12, S3 12 (`dairy`), S14 10, S12 12 (`dairyDense`), S2 12 (`dairy` markers), dairyProcessing 6, S13 4 (`dairy` prior) — **no S15** |
| `plant_milk` | S1 20, S10 16, contaminantRisk 8, S3 10, S5 4, S12 12, S2 10, S14 14, S15 6 |
| `tea_coffee` | S1 28, S2 24, brewMaterial 12, S3 8 (`foods`), S12 14 (`dryBrew` — redistributes: beans/leaves never carry a micronutrient panel), S14 14 |
| `drinks` | S1 23, S3 43 (`drinksServing`), S8 15 (caffeine), S6 13 (tiered sweeteners), S4 6 — **no S2, no S7** |
| `juice_100` | same weights as `drinks`; dose-aware S3 + juice sugar cap + flat +3 micronutrient boost |
| `protein_bars` | S12 26 (`proteinBar`), S3 16 (`proteinBar`), S6 10 (`proteinBar`), S2 10 (`proteinBar`), S1 8, S14 10 (`proteinBar`), S15 8, S5 8, S4 2 (`proteinBar`), S13 2 |

## V5.7.0 Meat & seafood (three forms)

Audit of the meat scoring against the live engine (49 archetype fixtures,
52 hydrated top-scanned US OFF records) and Oasis' meat & seafood methodology
(contaminants 60 / lab-indexed 15 / packaging 10 / certs 5 / welfare 10 —
nutrition 0%). Findings: one `meat` profile served everything from chicken
breast to salami to swordfish to Beyond burgers; purity rules carried 66/100
points and every clean whole cut maxed them (ribeye 84 > sockeye 83, pork
belly 79 "Excellent"); the generic S12 (fiber + FVN = 60% of the rule) was
structurally dead for animal products; a no-list chuck roast scored 41 vs 82
for identical listed ground beef; cured bacon 28 vs celery-powder "uncured"
bacon 55 (same nitrite chemistry); no omega-3 use (decoded since V5.3, only
ever read for eggs); no mercury concept (swordfish 82, unflagged); deli
turkey 26 < Spam 34 on raw additive count; real franks with `en:undefined`
categories fell to `general`; meat-analogues routed INTO `meat`.

**Stance** (the egg/dairy line): health only. Welfare, feed, wild-vs-farmed
sustainability, certifications, packaging and lab-report transparency never
score (chips at most). From Oasis we keep only the *severity-tier idea* and
species mercury — the one contaminant that is species-deterministic, where
the name on the pack is the evidence. Cure chemistry is judged by what it
is: celery powder / celery juice / cultured celery is a nitrate cure, and
"uncured" is a labeling word, not a food.

- **Three forms** — `meat_fresh` (whole cuts, ground, organ; rotisserie
  stays here — S1 prices its additives), `meat_processed` (cured / smoked /
  dried / fermented / restructured / breaded), `seafood` (all fish and
  shellfish, every pack form). Meat-analogues route to `general`.
- **S12 `meatProtein`** — 0.55 × absolute protein (22 g full) + 0.45 ×
  protein share of energy (55% full). The share axis is what separates a
  lean cut from a fatty one. Protein declared 0 = empty OFF panel → unknown.
- **meatForm** — fresh: poultry 1.0 / pork 0.8 / red meat 0.75 (IARC 2A +
  fish-and-poultry-first guidance; a step, not a demonization) / organ 0.5
  (vitamin A / purine portion caution). Processed: emulsified 0.10 / cured
  0.15 / smoked, dried 0.35 / cooked-salted 0.6; worst match binds. Seafood:
  plain (fresh / frozen / **canned**) 1.0 / smoked, cured 0.45–0.6 /
  breaded 0.5 / surimi 0.2.
- **Processed ceiling** — cure, smoke, dry or restructure evidence (text,
  additives e249–e252, group-1 tags like `cured-meats` / `jerky`, or named
  cured products: prosciutto, salami, pepperoni, pastrami…) → Overall cap
  54; cooked-and-salted only → 58. Cure additives are exempt from S1 on
  this profile — the ceiling and form rule own curing, so a celery-powder
  label can't buy back 27 points (calibration: cured 44 vs "uncured" 50).
- **S13 `meat` prior** (egg pattern) — organ 0.95, oily fish 0.85, red meat
  0.80, shellfish 0.80, pork 0.75, lean fish 0.72, poultry 0.70; ×0.8 on
  processed; lifts for declared iron / potassium / vitamin D / B12 (cap
  +0.10). Red meat's higher prior is honest (heme iron, B12, zinc) — the
  red-meat health step lives in meatForm, not here.
- **omega3** (seafood) — declared `omega3_g` first (≥1.0 → 1.0, ≥0.4 → 0.8,
  ≥0.1 → 0.55, else 0.45), species-class prior otherwise (oily 0.9,
  shellfish 0.55, lean 0.5). Lean fish earns partial credit, never a
  penalty — cod is not worse food for being lean.
- **Mercury** — FDA/EPA "avoid" species (king mackerel, swordfish, shark,
  tilefish, marlin, orange roughy, bigeye tuna) → cap 54 + chip; "good
  choice" species (albacore, yellowfin, halibut…) → cap 84. Smoked fish →
  cap 68; sodium ≥ 2 000 mg (anchovies, lox) → cap 64.
- **Identity gate** — no list + no additives + species named + panel inside
  the form envelope (fresh: 60–560 kcal, 9–40 g protein, ≤2 g sugar,
  ≤150 mg Na; seafood: ≤300 kcal, ≤500 mg Na) → S1 unknown 0.85, S2 prior
  0.90. Most fresh-meat UPCs print no list (USDA-path scans); the packaged-
  food 0.20 unknown was punitive there (chuck roast 41 → 77, within 5 of
  the listed cut). Zero-filled panels (kcal 0 + protein 0) read as
  undeclared, not as food with no energy.
- **S2 `meat`** — marker families off the list (mechanically separated,
  added sugars, flavor enhancers, modified starch, BHA/BHT, flavorings,
  isolate binders). Canning, cooking and salt are NOT ultra-processing:
  "sardines, olive oil, salt" is clean whatever NOVA tag the can carries.
  Processed clean ceiling 0.8 (charcuterie is never "unprocessed").
- **Routing** — processed tags before fresh (order matters); composition
  guard (protein ≥7 when declared, ≤700 kcal, ≤25 g sugar; baby-tagged
  never meat); plant evidence → `general` (labels / name words / first
  ingredient — deliberately NOT OFF's vegan analysis flags: a bacon whose
  printed list forgets the pork reads vegan there); cure/smoke/dry/breaded
  evidence promotes fresh tags to processed; junk-tag name rerail (franks /
  sausage / deli words + species + composition) and fresh-evidence rerail
  (species in name + first ingredient + envelope) rescue `en:undefined`
  records. Smoke evidence is the product's NAME / labels / tags — a dash of
  "smoke flavor" in a salmon burger is seasoning (S2 flavoring family), and
  matching it flipped the same product across profiles on a spelling change.
- **Generic fixes** — cure-system auxiliaries tiered honestly (E301 sodium
  ascorbate = vitamin C → exempt; E316 erythorbate, E325/E326/E327
  lactates, E262 diacetate → soft): deli turkey 54 > Spam 46, restoring
  sanity. S14: species + cut whitelist (~90 entries: sockeye salmon, chicken
  thighs, ground beef, albacore…), catch/origin/trim qualifiers
  (wild-caught / atlantic / boneless / skinless / ground / lean —
  "roasted"/"grilled" deliberately excluded: mid-token stripping would turn
  "dry roasted peanuts" into "dry peanuts" and unmatch the nut whitelist);
  salt / water / broth / dry seasonings neutral in meat lists.
- **Calibration** (fixtures + real records): chicken breast 97 (listed or
  not), pork loin 93, lean ground beef 90, thighs 81, 80/20 74, ribeye 75,
  lamb 69, pork belly 58, liver 94 · sockeye 99, sardines 96, mackerel 93,
  farmed salmon 94, cod/tilapia/shrimp 90–92, canned tuna 85–90 (same-food
  record spread narrowed from 31 to ~7 pts), albacore 84 (Hg), swordfish 54
  (Hg), smoked salmon 68, fish sticks 55, anchovies 64, imitation crab 43 ·
  clean deli turkey 58, conventional deli 54, uncured dog 54, jerky 53,
  breakfast sausage 51, "uncured" bacon 50, salami 47, Spam 46, bacon 44,
  hot dogs 42, turkey pepperoni 40. Cross-shelf drift ≤ ±0.1 mean; only
  intended movers (baby purées off meat, seaweed off meat).
- Deliberately unscored: welfare / housing / feed, wild-vs-farmed
  sustainability, MSC / ASC / BAP, packaging, lab-report transparency,
  antibiotic / hormone claims, grilling HCAs (preparation, not product).
  Grass-fed's omega shift is real but unverifiable per pack.

## V5.6.0 Dairy (four forms, one family)

Audit of the dairy scoring against the live engine (77 archetype fixtures,
400 top-scanned US OFF records, the Milks / Yogurt / Cheese Top Rated shelves)
and Oasis SCR_DAIRY v4.7.0. Findings: creams routed to `fats` (Daisy sour
cream 95, half-and-half 97 — the highest dairy scores in the app); one
`yogurt_cheese` profile served two foods with different risk axes, so
S1+S14 (38 pts) outranked added sugar (10 pts) — Noosa honey 85 > Chobani
strawberry 75, Yakult 76 "Excellent"; lactose was scored as sugar while the
intrinsic ×0.7 discount double-counted *declared* added sugar; dairyProcessing
returned 0.85 on 199/200 real yogurts/cheeses; S13 was 0.35 on every milk;
S15 handed +6 to anything listing "cream"; infant formula scored 34 "Bad" on
`general`; a plain milk with no ingredient list scored 61; OFF's junk
`low-sugars` tag substring-tripped the free-sugar cap (grated parmesan 34).
Ruleset `2026.08-v5.6.0`; tests `DairyScoringV56Tests`; shapes in
`DairyScoring.swift`; config in the ruleset `dairy` block.

Stance (V5.2/V5.3, now written down): **health only** — fat level is
preference (whole = skim in Overall, personalized in Your Score); unknown is
a confidence haircut with a form-appropriate prior, never a guess; raw fluid
/ fresh-fermented milk is a safety cap (54); no points for sourcing, welfare,
packaging or certification (Oasis' axes, deliberately not adopted — grass-fed
/ organic / A2 / raw +6 have no human-outcome evidence a health score can
carry; raw milk is the opposite of a bonus).

- **Four forms** — `dairy_milk` (fluid, UF/UHT, powders reconstituted,
  buttermilk, evaporated), `dairy_fermented` (yogurt, Greek, skyr, kefir,
  quark, labneh, drinkable), `dairy_cheese` (fresh / aged / processed),
  `dairy_cream` (new: heavy/light cream, half-and-half, sour cream, crème
  fraîche, whipped; `creams` no longer routes to `fats`; mascarpone is cream
  by composition). Router order: milks → specific fermented → cream → cheese
  → generic `fermented-milk-products` (OFF stamps that ancestor on cheeses
  and sour creams too).
- **S3 = free sugar** — declared added sugar wins when sane (a value above
  total sugar is an OFF entry error and is ignored); otherwise total minus a
  lactose allowance (milk/cream 4.8/3.0, yogurt 4.0, strained 3.0, cheese
  2.0 g/100 g — WHO's free-sugar definition excludes milk sugars). The
  intrinsic ×0.7 discount is retired on dairy. Thresholds `dairy` 3/8/13.
  **Free-sugar caps**: ≥5 g → 74, ≥8 → 64, ≥11 → 54 (a dessert yogurt is
  never Excellent); tier-1 NNS on fermented/cream → cap 58; cheese ≥1200 mg
  sodium → cap 54.
- **S2 `dairy` (milk, cream)** — marker families read off the
  fortification-stripped list (sugars, NNS, oils, starches, emulsifiers,
  emulsifying salts, hydrocolloids, flavors, colors, protein fillers,
  preservatives): 0 → 1.0 … ≥4 → 0.2. Evidence-NOVA: a list that is dairy
  base + {cultures, enzymes/rennet, salt, lactase, vitamins} is NOVA 1
  whatever OFF says.
- **dairyForm (fermented, cheese)** replaces the dead dairyProcessing weight:
  live cultures declared 1.0 · fermented w/o culture claim 0.9 ·
  heat-treated after culturing 0.6 · natural cheese 1.0 · anti-caking 0.9 ·
  raw-milk aged cheese 0.8 (no fluid cap — 60-day rule) · emulsifying salts
  0.35 · vegetable oil in a "cheese" 0.1.
- **dairyProcessing (milk, cream)** — HTST/vat 1.0 (pasteurized-by-law
  default is *evidence*, so plain milk sheds the provisional banner), UHT /
  ultra-pasteurized / sterilized 0.7, ultrafiltered 0.7 (0.6 if also UHT),
  evaporated / condensed / powder 0.7, raw 0.5 + cap. UF milk is no longer
  triple-docked (was processing 0.25 + NOVA-4 zero + S14 miss = −20).
- **S13 `dairy` reference prior** (egg pattern): milk/fermented 0.70, cheese
  0.70, cream 0.40; declared lifts vitamin D ≥1 µg +0.10, potassium ≥130 mg
  +0.05, B12 ≥0.4 µg +0.05, calcium ≥ form target +0.05.
- **S12** — `dairy` (protein 3.3 g + calcium 120 mg per 100 ml),
  `dairyDense` unchanged (fermented, cream; cream protein declared exactly 0
  is serving-rounding → unknown), new `dairyCheese` (0.7 × protein
  [abs 20 g + 15 g/100 kcal density blend] + 0.3 × calcium 600 mg). Milk-
  derived proteins (MPC, whey concentrate, milk powder) are exempt from the
  isolate ×0.5 on dairy profiles.
- **Identity gate (sparse records)** — tag + form nutrient envelope + no
  additive tags → S1 unknown 0.75 (off-envelope 0.45, generic 0.20 stays for
  everything else), S2 prior 0.85; plausibility guard rescales per-serving
  panels entered as per-100 g through the declared serving (150 kcal "whole
  milk", 8000 kcal grated parmesan).
- **S14** — dairy neutral tokens (salt, enzymes, rennet, lactase, vitamins);
  culture-family tokens are whole food ("live active yogurt cultures",
  "l. bulgaricus", "ferments lactiques"; cultured dextrose / celery excluded);
  qualifiers strippable mid-token and extended (certified, usda organic, a2,
  grass-fed, ultra-filtered, lactose-free, part-skim, fat-free, vitamin d …);
  multilingual dairy whitelist (lait, leche, latte, milch, mjölk, "milk and
  cream", "sheep and goat milk"); tokenizer splits ". " between ingredients
  (but never "l. bulgaricus") and drops "contains: milk" boilerplate.
- **Routing evidence** — plant-based riding dairy tags leaves the family
  (word-bounded: goat milk ≠ oat milk; "non-vegan" labels don't count):
  milk-tagged → `plant_milk`, others → `general`. Sweetened flavored protein
  shakes tagged `milks` (protein ≥6 g/100 ml + shake/protein name + flavor
  or sweetener) → `drinks`. Infant formula → **unsupported** with its own
  copy (was 34 "Bad" on `general`) behind a formula-evidence guard so junk
  `baby-milks` tags on shakes don't unscore them.
- **Generic fixes that rode along** — `isCaloricSweetener` no longer
  substring-matches OFF nutrition-level tags (`low-sugars` capped a 0 g-sugar
  parmesan at 34) and requires sugar ≥25 g when a panel exists; negated
  labels ("no-sucralose", "no aspartame") no longer read as sweetener hits
  on the drinks path (siggi's vanilla took the tier-1 cap for a "no
  sucralose" claim); benign additive tiers — hydrocolloids, gelatin, plant
  pigments (annatto), natamycin, cellulose, modified starches, lecithin →
  soft; GRAS acidulants/coagulants (citric/lactic/acetic/malic, CaCl₂, GDL,
  agar) → exempt; fortification exemption extended (folic acid, B-complex,
  DHA/algal oil, choline, GOS/inulin, calcium salts).
- **Calibration:** plain milk 97 (whole = skim ±1), lactose-free 98, goat 98,
  UHT 94, ultrafiltered 95, buttermilk 97, powder (as prepared) 91,
  evaporated 74, raw 54, sweetened condensed 34 · plain yogurt 92, Greek 0%
  96, skyr 96, kefir 92, quark 95, labneh 91, Siggi's strawberry 91, Chobani
  strawberry 74, Yoplait 64, Noosa honey 64 (cap), Yakult 64 (cap), Light &
  Fit 58 (NNS cap), Oikos Triple Zero 88 · cottage 83–87, Swiss 86,
  mozzarella 82, fresh mozzarella 83, ricotta 85, paneer 84, cheddar 71,
  gouda 71, parmesan 75, brie 72, feta 70, blue 65, halloumi 54 (Na cap),
  Laughing Cow 51, American singles 46, Velveeta 42 · half-and-half 74, sour
  cream 65, crème fraîche 56, heavy cream 51–56, whipped topping 32–39,
  mascarpone 54 · no-list plain milk 89 / cheddar 65 (provisional).
  Deliberately unscored: sourcing, welfare, organic, grass-fed, A2,
  packaging, lab testing (see the audit's Oasis comparison).
- One-shot migration `rulesetV560Rescored`; backend ruleset copy must be
  redeployed (`cp Sage/RulesetV5.json backend/src/ruleset.json`).

## V5.5.0 Protein bars (dedicated profile)

Protein bars rode `snacks` or `general` depending on whether OFF happened to
tag `snacks` — OFF files `protein-bars` under *bodybuilding-supplements*, not
*snacks* — so a harness pass over 390 real OFF protein bars found the same
RXBAR scoring **54–68 across barcodes**, Fulfil 36 (NOVA 4) vs 73 (no NOVA),
and every real protein bar clustered 35–50 while a 4 g-protein date bar sat
at 94 (FVN ≈ 100 laundered 40 g/100 g of date sugar to S3 = 1.0). Protein —
the product's purpose — carried 4 % of the snacks profile, and the isolates
that make a protein bar were docked **four times** (S1 `whey protein isolate`
text signal, S2 NOVA-4 = 0, S12 isolate ×0.5, S14 isolate score). Oasis
scores bars 60 % ingredient grading / 25 % protein-source quality / 30 %
packaging + sourcing and reads nothing off the nutrition panel; what Sage
takes from it is the idea of **source quality** (DIAAS-style, collagen is not
full protein) and **amount-ordered ingredient weighting** — and keeps its own
identity: health only, panel-aware, no packaging / sourcing.

Stance (as a nutritionist would rank protein bars): protein *delivery* is the
single largest factor but not a majority; the sugar / sweetener system wrapped
around the protein is the usual failure mode; processing and additives matter
but isolated protein is never itself the processing sin; fat quality and
saturated fat separate nut-based bars from palm-kernel-coated ones.

- **Routing** — router `protein-bars` / `protein-energy-bars` → `protein_bars`
  (ahead of the cereal / snack entries), behind a **composition guard**
  (`proteinBars.gate`: 200–650 kcal, ≤ 55 g protein/100 g — OFF's tag is
  inherited by powders and shakes). A tag-independent **evidence gate** rerails
  a product tag-routed to `snacks` / `general` / `breads` / `whole_foods` (or
  untagged) when it is a bar (bar-family tag or bar word in the name) inside
  the envelope and either marketed on protein (protein word in the name and
  ≥ 12 % of energy from protein — the EU "source of protein" claim floor) or
  genuinely high-protein (≥ 20 % of energy, the EU "high protein" claim, and
  ≥ 10 g/100 g). Name or tag alone never qualifies; dairy / meat / drinks
  never rerail. KIND Nuts & Sea Salt (12 %, not marketed on protein), Clif
  Bar (17 %), Larabar (8 %) stay on `snacks`; KIND Protein, RXBAR, Perfect
  Bar, Nature Valley Protein, Nakd Protein come across.
- **S12 `proteinBar`** (26) = 0.8 × protein + 0.2 × fiber.
  *Protein* = amount × (0.6 + 0.4 × quality). **Amount** is the mean of
  grams-per-serving credit (full at 20 g — the dose that maximally stimulates
  muscle protein synthesis in most adults; 10 g = the US "high in protein"
  RACC threshold = half credit) and protein share of energy (full at 35 %),
  so a calorie-padded 100 g bar cannot buy credit with size. Serving grams
  come from OFF `serving_size` ("1 bar (60 g)", oz accepted, `fl oz`
  rejected), else a single-bar pack size (20–120 g), else 50 g flagged
  estimated. **Quality** is a DIAAS-style source table (`s12.sources`: whey /
  milk protein / casein / egg 1.0 · soy 0.9 · potato 0.9 · pea 0.82 · pea +
  rice blend 0.9 (`complementaryPairs`) · pumpkin / hemp 0.6–0.65 · rice
  0.55 · whole nuts / seeds 0.4–0.6 · **collagen / gelatin 0.25** — FDA
  PDCAAS 0, not a complete protein), weighted by label position × typical
  protein density so a 25 %-protein peanut listed first does not outweigh a
  90 % isolate behind it; parenthetical blends contribute their specific
  sources. Quality scales the amount credit (floor 0.6) rather than being
  averaged in, so a 4 g date-and-nut bar banks no quality prior and a
  collagen pad scales a real 20 g down. **Fiber** full at 8 g/100 g; an
  isolated fiber (soluble corn / tapioca fiber, IMO, polydextrose, inulin,
  chicory root…) in the first three ingredients halves it (`isolatedFiberDamp`)
  — FDA accepts these as fiber but the evidence is weaker than for intrinsic
  fiber. The generic S12 isolate discount is **off** on this profile.
- **S2 `proteinBar`** (10) — evidence-based processing: every protein bar is
  NOVA 4 by construction, so OFF's tag separated nothing but tag luck. Distinct
  ultra-processing **marker families** in the list (flavorings, non-nutritive
  sweeteners, sugar alcohols, humectants, refined syrups, isolated fibers,
  emulsifiers, thickeners & gums, refined hard fats, compound coatings,
  colors, preservatives, modified starch — text in EN/FR/ES/IT/PT/DE/NL/SV/DA/
  NO/FI/PL/CS plus E-codes) step the credit 1.0 → 0.8 / 0.62 / 0.46 / 0.32 /
  0.2 / 0.1. **Protein isolates are never a marker.** A list with < 30 %
  recognizable tokens (`minRecognizedShare`: OCR'd nutrition tables,
  best-before lines, uncovered languages — field QA: "Spear & P2:01 81 Energi
  Fedt…" scored 87) is unknown, not clean; S6 follows the same guard. No list
  → NOVA fallback (4 → 0.2, 3 → 0.5, 1–2 → 0.8, none → 0.3 unknown).
- **S3 `proteinBar`** (16) — foods thresholds, but the fruit/veg/nut sugar
  discount is capped at 50 % (`s3.fvnDiscountCap`): date paste is free sugar
  under the UK SACN/PHE definition and at best borderline under WHO's; at
  least half counts. Declared added sugars are used as-is. The
  sweetener-substitution cap does **not** apply here (S6 grades the sweetener
  system; no stacking, as on drinks).
- **S6 `proteinBar`** (10) — the drinks sweetener tiers (Tier-1 sucralose /
  ace-K / aspartame → 0.10, polyols −0.25 each with erythritol −0.10 extra,
  stevia / monk fruit → 0.70) plus a **declared-polyol load** dock from the
  new `Nutrients.polyols_g` (OFF `polyols_100g`, EU "of which polyols"):
  ≥ 10 g/100 g ×0.85, ≥ 20 g ×0.70 (EU mandates the laxative warning above
  10 % polyols; maltitol bars routinely carry 20–45 g/100 g).
- **S14 `proteinBar`** (10) — `IngredientIntegrity.evaluate` with protein
  sources **neutral** (dropped from the whole-food ratio, neither whole food
  nor dock) and protein isolate markers exempt from the isolate score; syrups,
  maltodextrin, modified starch still count. **S1** skips the three isolate
  text signals on this profile. **S4** (2) treats > 3 000 mg/100 g as a unit
  error (Perfect Bar 161 538 mg). Generic changes shipped alongside:
  `sugar` / `cane sugar` removed from the S14 whole-food whitelist (a
  refined NOVA-2 ingredient cannot be "real food" — "Oat, Cane sugar, Cocoa
  paste" scored S14 = 1.00); plural nuts / seeds, nut butters, dried fruit,
  milk / egg powders, cocoa mass added; `palm kernel oil` / palm fat /
  fractionated palm family added to the S15 low tier (82 % saturated, always
  refined — it was invisible and a palm-kernel-coated bar scored S15 = no data)
  and `mixed nuts` to the high tier. Shelf drift outside bars: nut butters
  +4 (plural "peanuts" now real food), cereal / chocolate +0.8, cookies /
  ice cream −0.3/−0.6 (sugar off the whitelist), everything else ≤ ±0.4 mean,
  no routing changes except 51 snack-bar rows moving to `protein_bars`.
- **Calibration (fixtures, label values):** egg-white + nut bar with no sugar
  or sweeteners 92 · RXBAR 73–79 (Excellent; whole-food protein, date sugar
  half-counted) · Aloha 73 · Perfect Bar 70 (clean list, 27 g added sugar) ·
  Quest 67 (35 g protein, 1.7 g sugar, but sucralose + stevia + erythritol and
  23 g isolated fiber) · Built / ONE 65 · Nature Valley Protein 62 · Pure
  Protein 62 · Kirkland 61 · Barebells 59 (maltitol + sucralose + glycerol +
  palm fat, collagen second) · Grenade 58 · think! 56. Same bar = same score
  whatever the tags / NOVA (RXBAR 54–68 → one number). Real OFF set: the
  390 bars spread 27–87 with junk-list outliers removed by the recognition
  guard; Isostar "energy sport bar" tagged protein-bars (5 g protein, 35 g
  sugar) bottoms out at 27 — honest.
- **Deliberately not scored:** packaging, sourcing / certifications, lab
  testing (Oasis factors — ethics / hygiene, not health); protein "quality"
  beyond the DIAAS-style source table (no leucine claims); caffeine
  (`energyDrinkEvidence` still rerails a caffeinated bar to drinks only if it
  is a liquid — bars keep S8 off).
- `rulesetV550Rescored` one-shot migration; overview cache stays `exp-v9`.
  `RulesetV509.json` untouched (kill-switch path keeps bars on `snacks`).
  Builder: `generate_candidates.py` now pulls `serving_size` and
  `polyols_100g`; `AlternativeCandidate` decodes `serving_size` (pre-v5.5
  datasets fall back to the pack size / 50 g).

## V5.4.0 Bread (dedicated profile)

Bread used to ride the shared `breads` grains profile (cereals, pasta, rice,
oats, flours — renamed **`grains`** in this release so it cannot be confused
with `bread`) and the shipped shelf compressed into **50–75**: Mestemacher
whole-kernel rye (rye, water, salt, yeast) scored 69, white sourdoughs made
from fortified refined flour 65–71, Wonder white 50, and brioche (6 g sat fat,
10 g sugar) outscored plain sourdough. Four structural causes, found with the
CLI harness over the 96-product shelf, 27 archetype fixtures and ~400 real
OFF records (US / UK / FR / DE / CA):

1. **`wholeGrain` was a binary keyword hit** on name + ingredients + tags —
   2 % rye flour in a white sourdough, "sprouted", "oat" (also matching
   "goat"), or a `whole-wheat-breads` tag earned the full 12 points; 85 / 96
   shelf breads scored 1.0 on it.
2. **Generic S12** spends 40 % on protein per kcal against a 15 g/100 kcal
   anchor (bread: ~3.5) and 25 % on fruit/veg share (bread: 0) — the
   fiber axis that the whole-grain literature actually runs on carried 35 %
   of 12 points.
3. **S2 read OFF's NOVA tag**, which is noisy on bread (an M&S baguette
   tagged NOVA 1; Ezekiel tagged 3 on one barcode and 4 on the next), and
   NOVA 3 is the *best* class a traditional bread can be (flour + water +
   salt + leaven is group 3 by definition), so every honest loaf lost 9.6
   points with zero discrimination among them.
4. **S14's whitelist accepted refined "wheat flour" but not "whole wheat
   flour"** (the `whole` prefix is deliberately not strippable), counted
   water as a non-real ingredient, and treated "raisin juice concentrate"
   as an isolate protein (S12 ×0.5). US enriched flour's niacin and
   riboflavin were also S1 penalties (E375 / E101 resolved to the knowledge
   base's "low" risk → mild tier) — ~3 points on every US loaf for vitamins.

Oasis' bread methodology (SCR_BREADS v4.7.0) is 85 % amount-weighted
ingredient grades (A whole / B refined / C filler / D engineered, with caps
for C/D ingredients and industrial oils), 15 % packaging, 15 % sourcing
signals, lab testing as a badge — and **no nutrition panel at all** (no
fiber, no salt, no sugar). What Sage borrows is the *amount-ordered* reading
of the label (first ingredients weigh most; declared percentages override
position; water excluded from the ratio; added vitamins/minerals neutral).
What Sage deliberately does not: packaging, sourcing certifications and
testing badges (not health pathways), and ignoring the panel — fiber per
100 g, sodium and sat fat are exactly where bread health evidence lives
(DGA whole-grain guidance, Nutri-Score 2023 bread fiber/salt points, UK
2024 salt targets).

- **`bread` profile** — S1 16, S2 14 (`bread`), wholeGrain 16 (`bread`),
  S12 14 (`grain`), S3 10 (`bread` 2 / 6 / 12 g), S4 12 (`bread`), S5 6,
  S14 8, S15 4. **No S13**: the micronutrients that whole grains actually
  deliver (Mg, Zn, Se) are almost never declared, so the rule could only
  ever reward fortified white flour (UK mandatory calcium/iron) — which
  would rank white above whole. S5 added (brioche, naan, shortening
  tortillas have real sat fat; plain bread trivially scores 1.0). Routing:
  all bread tags (`breads` + white / whole-wheat / whole-grain / sliced /
  special / flat / baguettes / sandwich / buns / bagels / toasts / rye /
  sourdough / pita / tortillas / wraps / naans / crispbreads / english
  muffins / rolls / ciabattas / focaccias / brioches / pumpernickel) →
  `bread`; cereals, pasta, rice, oats and flours **stay on the grains
  profile** (`breads` → `grains`, rules and weights untouched).
- **wholeGrain `bread` (graded, `BreadScoring.wholeGrainShare`)** — grain
  tokens are classified whole / partial (0.5: rye flour, spelt flour,
  barley, cornmeal, bran, ancient-grain flours) / refined from a
  multilingual vocabulary (EN / FR / DE / IT / ES / PT / NL / SE); non-grain
  tokens (gluten, malt extract, seeds, nut flours, yeast…) are ignored.
  Parenthetical sub-lists are read ("Grains (whole kernel rye, whole grain
  rye flour)"; "rye (flour, bran)" → rye flour, rye bran), weights are
  rank-halving × list position, and a **declared percentage overrides**
  position ("Sprouted Whole Spelt (2.5 %)" is a 2.5 % weight; Hovis
  Granary's 11 % malted wheat flakes on white flour → 0.07). A regulated /
  explicit front-label claim ("100 % whole wheat", UK "wholemeal") lifts a
  whole-first list to 0.9 — never a refined-first one. **Fiber
  cross-check**: a whole-first list declaring < 3.5 g fiber is capped at
  0.35 (brown-washing or label error), < 5 g at 0.7. No list → tag / name
  prior 0.6 / 0.2, unknown-tier.
- **S2 `bread` (evidence-based, `BreadScoring.s2Credit`)** — 16
  ultra-processing **marker families** (HFCS / glucose syrups, modified
  starch, mono-/diglycerides, DATEM, stearoyl lactylates, lecithin,
  polysorbates, gums & thickeners, dough conditioners, flavors, colors,
  sweeteners, protein isolates, hydrogenated / interesterified fat, flavor
  enhancers, bulking fibers), matched by text phrase *or* additive code and
  counted once per family. 0 families → **0.70** (traditional NOVA 3 — the
  ceiling for bread, deliberately above the generic 0.40); 1 → 0.40; 2 →
  0.25; 3 → 0.12; 4+ → 0. Preservatives (calcium propionate, sorbic acid,
  vinegar, cultured wheat flour), ascorbic acid, enzymes, raising agents,
  UK flour fortification and **vital wheat gluten** are not markers
  (strict NOVA would count gluten; the UPF cohort evidence for bread is
  weak — Cordova 2023 EPIC, Chen 2024 BMJ — and gluten is in nearly every
  US whole-wheat loaf, so counting it would penalise the whole-grain
  category wholesale without an outcome behind it). No list → OFF NOVA,
  capped at 0.70 (a bread tagged NOVA 1 is a data error).
- **S12 `grain`** — `0.7 · fiberCredit + 0.3 · proteinCredit`; fiber per
  100 g linear 1.5 g → 0, 7 g → 1 (Nutri-Score 2023 tops out at 7.4 g;
  white 2–2.7, whole wheat 6–7, whole rye 8+, crispbread 15+); protein
  /12 g. Isolated fibers (oat fiber, cellulose, polydextrose, inulin,
  resistant starch…) on a non-whole base earn half (FDA 2016: weaker
  evidence than intrinsic cereal fiber) — a 45-calorie cellulose loaf does
  not out-fiber whole wheat. Fiber undeclared → prior 0.55 / 0.20 from the
  whole-grain evidence, unknown-tier. No kcal axis, so the kcal confidence
  haircut does not apply. Overview topic **"fiber and protein"**.
- **S4 `bread`** — anchors 200 / 450 / 700 mg (UK 2024 target 1.0 g salt =
  400 mg; typical loaves 380–600): 300 mg → 0.84, 450 → 0.60, 600 → 0.42,
  700 → 0.30. Bread is the top dietary sodium source, hence weight 12.
  **Plausibility guard**: sodium < 40 mg on a loaf that lists salt (OFF
  "salt 0.001 g") → unknown 0.30, never full credit; an unsalted corn
  tortilla at 45 mg keeps 1.0.
- **Generic fixes (all profiles)** — S14 whitelist gains whole-grain
  flours / rye / spelt / oats / seeds / yeast / sourdough / vinegar / malt
  / semolina in eight languages; strippable qualifiers gain unbleached /
  enriched / fortified / stone ground / sprouted / toasted / rolled /
  malted…; **water is excluded from the whole-food ratio** (not from the
  count); `hasIsolateProtein` requires *protein* concentrate;
  `tokens(from:)` cuts trailing allergen / back-of-pack boilerplate
  ("Allergen advice", "Contains:", "If you have any questions…");
  marketing prose in the ingredients field (≥ 9 words per token *and*
  brand-voice words) is treated as missing; **nutrient fortificants**
  (E101, E375, E300, E170, E306/307) are `exempt` in S1 regardless of the
  knowledge-base display risk. Shelf drift outside bread: 511 / 1 776
  products move, all +1…+7 (pasta mean +5: durum semolina is real food;
  cereal +3.6: oats), one garbage-list bar −21 → unknown-tier; no routing
  changes outside bread.
- **Calibration (fixtures + real OFF):** Ezekiel sprouted 94, corn tortilla
  92, seeded whole-grain loaf 90, Wasa rye crispbread 90, Mestemacher whole
  rye 88, whole-wheat pita 88, pumpernickel 87, whole-wheat sourdough 87,
  Dave's 21 Whole Grains 83 (11 g sugar), Silver Hills soft wheat 76,
  Nature's Own 100 % whole wheat 64 (DATEM / monoglycerides / soybean
  oil), white sourdough 63, baguette / white pita 61, plain bagel 59,
  brioche 58, naan 56, gluten-free starch bread 45, Hawaiian rolls 39,
  light cellulose bread 39, brown-washed "honey wheat" 36, keto isolate
  bread 34, Wonder white 33, mass-market flour tortilla 33. Real shelf:
  44–94 (was 50–75), mean 75; UK supermarket white sourdoughs 62–70,
  Warburtons / Hovis sliced whites 37–44, Schär gluten-free 52–57, Mission
  flour tortillas 23–35. Tests: `BreadScoringV54Tests`.
- **Deliberately not scored:** sourdough fermentation (GI / phytate
  evidence is modest and "sourdough" is an unregulated marketing word —
  a clean levain list already earns the traditional S2 credit), organic,
  packaging, sourcing, lab testing, glycemic index (not on labels),
  "ancient grain" marketing (spelt / einkorn / kamut flours are partial
  credit unless labelled whole).
- `rulesetV540Rescored` one-shot migration; overview cache stays `exp-v9`
  (invalidated by the migration flag). `RulesetV509.json` untouched (kill
  switch keeps bread on the frozen `breads` grains profile).

## V5.4.0 Bread (dedicated profile)

Bread used to ride the shared `breads` grains profile (cereals, pasta, rice,
oats, flours — renamed **`grains`** in this release so it cannot be confused
with `bread`) and the shipped shelf compressed into **50–75**: Mestemacher
whole-kernel rye (rye, water, salt, yeast) scored 69, white sourdoughs made
from fortified refined flour 65–71, Wonder white 50, and brioche (6 g sat fat,
10 g sugar) outscored plain sourdough. Four structural causes, found with the
CLI harness over the 96-product shelf, 27 archetype fixtures and ~400 real
OFF records (US / UK / FR / DE / CA):

1. **`wholeGrain` was a binary keyword hit** on name + ingredients + tags —
   2 % rye flour in a white sourdough, "sprouted", "oat" (also matching
   "goat"), or a `whole-wheat-breads` tag earned the full 12 points; 85 / 96
   shelf breads scored 1.0 on it.
2. **Generic S12** spends 40 % on protein per kcal against a 15 g/100 kcal
   anchor (bread: ~3.5) and 25 % on fruit/veg share (bread: 0) — the
   fiber axis that the whole-grain literature actually runs on carried 35 %
   of 12 points.
3. **S2 read OFF's NOVA tag**, which is noisy on bread (an M&S baguette
   tagged NOVA 1; Ezekiel tagged 3 on one barcode and 4 on the next), and
   NOVA 3 is the *best* class a traditional bread can be (flour + water +
   salt + leaven is group 3 by definition), so every honest loaf lost 9.6
   points with zero discrimination among them.
4. **S14's whitelist accepted refined "wheat flour" but not "whole wheat
   flour"** (the `whole` prefix is deliberately not strippable), counted
   water as a non-real ingredient, and treated "raisin juice concentrate"
   as an isolate protein (S12 ×0.5). US enriched flour's niacin and
   riboflavin were also S1 penalties (E375 / E101 resolved to the knowledge
   base's "low" risk → mild tier) — ~3 points on every US loaf for vitamins.

Oasis' bread methodology (SCR_BREADS v4.7.0) is 85 % amount-weighted
ingredient grades (A whole / B refined / C filler / D engineered, with caps
for C/D ingredients and industrial oils), 15 % packaging, 15 % sourcing
signals, lab testing as a badge — and **no nutrition panel at all** (no
fiber, no salt, no sugar). What Sage borrows is the *amount-ordered* reading
of the label (first ingredients weigh most; declared percentages override
position; water excluded from the ratio; added vitamins/minerals neutral).
What Sage deliberately does not: packaging, sourcing certifications and
testing badges (not health pathways), and ignoring the panel — fiber per
100 g, sodium and sat fat are exactly where bread health evidence lives
(DGA whole-grain guidance, Nutri-Score 2023 bread fiber/salt points, UK
2024 salt targets).

- **`bread` profile** — S1 16, S2 14 (`bread`), wholeGrain 16 (`bread`),
  S12 14 (`grain`), S3 10 (`bread` 2 / 6 / 12 g), S4 12 (`bread`), S5 6,
  S14 8, S15 4. **No S13**: the micronutrients that whole grains actually
  deliver (Mg, Zn, Se) are almost never declared, so the rule could only
  ever reward fortified white flour (UK mandatory calcium/iron) — which
  would rank white above whole. S5 added (brioche, naan, shortening
  tortillas have real sat fat; plain bread trivially scores 1.0). Routing:
  all bread tags (`breads` + white / whole-wheat / whole-grain / sliced /
  special / flat / baguettes / sandwich / buns / bagels / toasts / rye /
  sourdough / pita / tortillas / wraps / naans / crispbreads / english
  muffins / rolls / ciabattas / focaccias / brioches / pumpernickel) →
  `bread`; cereals, pasta, rice, oats and flours **stay on the grains
  profile** (`breads` → `grains`, rules and weights untouched).
- **wholeGrain `bread` (graded, `BreadScoring.wholeGrainShare`)** — grain
  tokens are classified whole / partial (0.5: rye flour, spelt flour,
  barley, cornmeal, bran, ancient-grain flours) / refined from a
  multilingual vocabulary (EN / FR / DE / IT / ES / PT / NL / SE); non-grain
  tokens (gluten, malt extract, seeds, nut flours, yeast…) are ignored.
  Parenthetical sub-lists are read ("Grains (whole kernel rye, whole grain
  rye flour)"; "rye (flour, bran)" → rye flour, rye bran), weights are
  rank-halving × list position, and a **declared percentage overrides**
  position ("Sprouted Whole Spelt (2.5 %)" is a 2.5 % weight; Hovis
  Granary's 11 % malted wheat flakes on white flour → 0.07). A regulated /
  explicit front-label claim ("100 % whole wheat", UK "wholemeal") lifts a
  whole-first list to 0.9 — never a refined-first one. **Fiber
  cross-check**: a whole-first list declaring < 3.5 g fiber is capped at
  0.35 (brown-washing or label error), < 5 g at 0.7. No list → tag / name
  prior 0.6 / 0.2, unknown-tier.
- **S2 `bread` (evidence-based, `BreadScoring.s2Credit`)** — 16
  ultra-processing **marker families** (HFCS / glucose syrups, modified
  starch, mono-/diglycerides, DATEM, stearoyl lactylates, lecithin,
  polysorbates, gums & thickeners, dough conditioners, flavors, colors,
  sweeteners, protein isolates, hydrogenated / interesterified fat, flavor
  enhancers, bulking fibers), matched by text phrase *or* additive code and
  counted once per family. 0 families → **0.70** (traditional NOVA 3 — the
  ceiling for bread, deliberately above the generic 0.40); 1 → 0.40; 2 →
  0.25; 3 → 0.12; 4+ → 0. Preservatives (calcium propionate, sorbic acid,
  vinegar, cultured wheat flour), ascorbic acid, enzymes, raising agents,
  UK flour fortification and **vital wheat gluten** are not markers
  (strict NOVA would count gluten; the UPF cohort evidence for bread is
  weak — Cordova 2023 EPIC, Chen 2024 BMJ — and gluten is in nearly every
  US whole-wheat loaf, so counting it would penalise the whole-grain
  category wholesale without an outcome behind it). No list → OFF NOVA,
  capped at 0.70 (a bread tagged NOVA 1 is a data error).
- **S12 `grain`** — `0.7 · fiberCredit + 0.3 · proteinCredit`; fiber per
  100 g linear 1.5 g → 0, 7 g → 1 (Nutri-Score 2023 tops out at 7.4 g;
  white 2–2.7, whole wheat 6–7, whole rye 8+, crispbread 15+); protein
  /12 g. Isolated fibers (oat fiber, cellulose, polydextrose, inulin,
  resistant starch…) on a non-whole base earn half (FDA 2016: weaker
  evidence than intrinsic cereal fiber) — a 45-calorie cellulose loaf does
  not out-fiber whole wheat. Fiber undeclared → prior 0.55 / 0.20 from the
  whole-grain evidence, unknown-tier. No kcal axis, so the kcal confidence
  haircut does not apply. Overview topic **"fiber and protein"**.
- **S4 `bread`** — anchors 200 / 450 / 700 mg (UK 2024 target 1.0 g salt =
  400 mg; typical loaves 380–600): 300 mg → 0.84, 450 → 0.60, 600 → 0.42,
  700 → 0.30. Bread is the top dietary sodium source, hence weight 12.
  **Plausibility guard**: sodium < 40 mg on a loaf that lists salt (OFF
  "salt 0.001 g") → unknown 0.30, never full credit; an unsalted corn
  tortilla at 45 mg keeps 1.0.
- **Generic fixes (all profiles)** — S14 whitelist gains whole-grain
  flours / rye / spelt / oats / seeds / yeast / sourdough / vinegar / malt
  / semolina in eight languages; strippable qualifiers gain unbleached /
  enriched / fortified / stone ground / sprouted / toasted / rolled /
  malted…; **water is excluded from the whole-food ratio** (not from the
  count); `hasIsolateProtein` requires *protein* concentrate;
  `tokens(from:)` cuts trailing allergen / back-of-pack boilerplate
  ("Allergen advice", "Contains:", "If you have any questions…");
  marketing prose in the ingredients field (≥ 9 words per token *and*
  brand-voice words) is treated as missing; **nutrient fortificants**
  (E101, E375, E300, E170, E306/307) are `exempt` in S1 regardless of the
  knowledge-base display risk. Shelf drift outside bread: 511 / 1 776
  products move, all +1…+7 (pasta mean +5: durum semolina is real food;
  cereal +3.6: oats), one garbage-list bar −21 → unknown-tier; no routing
  changes outside bread.
- **Calibration (fixtures + real OFF):** Ezekiel sprouted 94, corn tortilla
  92, seeded whole-grain loaf 90, Wasa rye crispbread 90, Mestemacher whole
  rye 88, whole-wheat pita 88, pumpernickel 87, whole-wheat sourdough 87,
  Dave's 21 Whole Grains 83 (11 g sugar), Silver Hills soft wheat 76,
  Nature's Own 100 % whole wheat 64 (DATEM / monoglycerides / soybean
  oil), white sourdough 63, baguette / white pita 61, plain bagel 59,
  brioche 58, naan 56, gluten-free starch bread 45, Hawaiian rolls 39,
  light cellulose bread 39, brown-washed "honey wheat" 36, keto isolate
  bread 34, Wonder white 33, mass-market flour tortilla 33. Real shelf:
  44–94 (was 50–75), mean 75; UK supermarket white sourdoughs 62–70,
  Warburtons / Hovis sliced whites 37–44, Schär gluten-free 52–57, Mission
  flour tortillas 23–35. Tests: `BreadScoringV54Tests`.
- **Deliberately not scored:** sourdough fermentation (GI / phytate
  evidence is modest and "sourdough" is an unregulated marketing word —
  a clean levain list already earns the traditional S2 credit), organic,
  packaging, sourcing, lab testing, glycemic index (not on labels),
  "ancient grain" marketing (spelt / einkorn / kamut flours are partial
  credit unless labelled whole).
- `rulesetV540Rescored` one-shot migration; overview cache stays `exp-v9`
  (invalidated by the migration flag). `RulesetV509.json` untouched (kill
  switch keeps bread on the frozen `breads` grains profile).

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
