**Follow [design.md](design.md) for all UI work** — typography scale, color tokens, radii, spacing grid, and interaction rules. No raw hex values, off-scale font sizes, or ad-hoc radii in views.

# Session Changelog — 2026-08-23 — Dairy in four forms (v5.6.0)

Audit of the dairy scoring against the live engine (CLI harness: 77 archetype
fixtures + 400 top-scanned US OFF records + the Milks/Yogurt/Cheese shelves)
and Oasis SCR_DAIRY v4.7.0, then the full V5.6.0 respec. Findings: creams
routed to `fats` (sour cream 95, half-and-half 97 = highest dairy scores in
the app); one `yogurt_cheese` profile meant S1+S14 (38 pts) outranked added
sugar (10) — Noosa honey 85 > Chobani strawberry 75, Yakult 76 Excellent;
lactose scored as sugar while the intrinsic ×0.7 discount double-counted
declared added sugar; dairyProcessing/S13/S15 were dead or noise (≈22 pts);
infant formula = 34 "Bad" on `general`; no-list plain milk 61; OFF's
`low-sugars` tag substring-tripped the free-sugar cap (grated parmesan 34
Bad); "no-sucralose" labels read as tier-1 sweetener hits. Full audit
artifact: "Sage Dairy Scoring Audit". Ruleset `2026.08-v5.6.0`; rationale
SCORING_V5.md §"V5.6.0 Dairy"; tests `DairyScoringV56Tests`; engine shapes
in `DairyScoring.swift` + ruleset `dairy` block.

- **Four forms**: `dairy_milk` (tuned), `dairy_fermented`, `dairy_cheese`,
  `dairy_cream` (new — creams/sour cream/half-and-half/whipped/mascarpone off
  the oils profile). Router order matters: specific fermented → cream →
  cheese → generic `fermented-milk-products` (OFF stamps it on cheeses too).
- **Free sugar** everywhere on dairy: declared added wins (ignored when >
  total — OFF entry errors), else total − lactose allowance (4.8/4.0/3.0/2.0
  g by form); caps ≥5 g → 74, ≥8 → 64, ≥11 → 54; tier-1 NNS on
  fermented/cream → 58; cheese ≥1200 mg Na → 54.
- **New rules**: S2 `dairy` marker families + evidence-NOVA (pure dairy list
  = NOVA 1); `dairyForm` (live cultures 1.0 / heat-treated 0.6 / processed
  cheese 0.35 / oil analogue 0.1 / raw-milk aged 0.8); S13 `dairy` reference
  prior (egg pattern) + declared lifts; S12 `dairyCheese` variant;
  processing HTST=1.0 (evidence — milk sheds the provisional banner), UHT/UF
  0.7, raw 0.5+cap54 (now also raw fermented). S15 dropped on all dairy.
- **Identity gate** for sparse records (envelope → S1 unknown 0.75, S2 0.85)
  + per-serving-as-per-100g plausibility rescale (8000 kcal parmesan).
- **S14**: dairy neutral tokens (salt/enzymes/rennet/lactase/vitamins),
  culture-family whole-food match, mid-token qualifier stripping
  ("certified organic grade a milk", "reduced fat ultra-filtered milk"),
  multilingual milk whitelist, ". "-separator tokenization.
- **Routing gates**: plant-based off dairy (word-bounded — goat ≠ oat;
  "non-vegan" label ≠ vegan), protein shakes tagged `milks` → drinks,
  infant formula → unsupported (new UnsupportedView copy) behind evidence
  guard (junk `baby-milks` tags on shakes stay scored).
- **Generic fixes**: `isCaloricSweetener` tag-substring bug (D12); negated
  labels off the sweetener haystack (drinks path too); benign additive tiers
  (annatto/natamycin/cellulose/gelatin/modified starch/lecithin → soft,
  GRAS acidulants → exempt); fortification exemption extended (folic acid,
  DHA, choline, GOS). MPC exempt from the S12 isolate halving on dairy.
- **Calibration** (fixtures + 400 real records): milk 97, UHT 94, UF 95,
  raw 54 · plain yogurt 92, Greek 96, skyr 96, Chobani strawberry 74,
  Noosa/Yakult 64, Light & Fit 58 · cottage 83–87, Swiss 86, cheddar 71,
  feta 70, halloumi 54, American 46, Velveeta 42 · half-and-half 74, sour
  cream 65, heavy cream ~55, mascarpone 54. Cross-shelf drift outside dairy
  ≤ ±1.5 mean (one +65: the D12 junk-tag cap bug un-capping a 3 kcal drink).
- Migration `rulesetV560Rescored`; `backend/src/ruleset.json` copied —
  **needs a Worker deploy**. Legacy tests updated (UHT 0.7, processing
  default = evidence, raw-cheese dock on dairyForm, routes renamed,
  provisional-milk expectation inverted).
- Not done (follow-ups): Top Rated Milks/Yogurt/Cheese shelves not re-pulled
  (rows re-score live; `precomputed_score` stale until regen; consider a
  Creams shelf); `butters`/ghee still on `fats` pending F01; plant yogurts/
  cheeses land on `general` (fine until a plant-food profile exists);
  drinkable protein "yogurts" stay on fermented; pt-BR strings for the new
  UnsupportedView copy.

---

# Session Changelog — 2026-08-22 — Scout-pass: product page, Key ingredients, Home rails

Teardown of Scout's UI (six screenshots) against Sage's live simulator
screens, then a five-commit pass on branch `feat/product-page-scout-pass`
(one commit per item so any piece reverts alone). What Scout did better:
one product hero, score that never leaves the screen, per-ingredient
verdicts, a scannable tally before the prose, far fewer containers, photos
as UI on Home. What we kept on purpose: Your Score vs Overall (demoted to a
caption, never dropped), evidence-tiered language (no "Very Bad"), the
nutrient table, Pantry Score, our palette/typeface, native chrome.

- **Header** (`ResultView`): large pack shot on a soft tinted glow (no glow
  and a 120pt quiet tile when the record has no photo — `ProductImageView`
  skeleton is `fillQuiet` at ≥120pt and takes the card radius), name + brand
  left, **one** ring right (Your Score when present, else Overall) with
  "FOR YOU" eyebrow + tier word; caption "Overall 93 · +1 for you" (+ cap
  chip); Compare / How we score as `fillMuted` capsules. Two-dial card,
  "EXCELLENT" pills, boxed Overview removed. Overview is a collapsible
  16pt prose section. **Sticky compact nav title** past 300pt
  (`onScrollGeometryChange`, iOS 18): thumb · name · `MiniScoreRing`
  (new in `Shared.swift`).
- **Flattening**: every section = `sectionHeader(title) { trailing }`
  (18pt semibold, 20pt gutters) + hairline rows on the background; cards
  only for alerts and the Better-options rail. Breakdown tiles → **Processing**
  header with NOVA pill + per-group explainer + "grades processing, not
  nutrition" footnote + Nutri-Score row (`NutriScoreCard`/`NovaCard` deleted).
  Nutrition header carries "Per 100 g / ml ⓘ"; Additives header carries
  "4 detected / may be undercounted"; Full ingredients is prose without a card;
  `NutrientRow`/`AdditiveRow` gained `horizontalPadding`.
- **Key ingredients** (`KeyIngredients.swift`, `KeyIngredientsView.swift`,
  `IngredientKnowledgeBase.json`, tests `KeyIngredientsTests`): tokens via
  `IngredientIntegrity.tokens`, classified in order — detected additives
  (risk → Avoid/Limit/Fine, row opens `AdditiveDetailSheet`;
  `AdditiveDetector.matchTerms(forCode:)` exposes the file-private synonym
  table; class stems so "caramel color" ↔ E150c), curated KB (57 entries,
  longest match wins: "organic cane sugar" → sugar, "whole wheat flour" beats
  "wheat flour"; KB beats the S14 whitelist so honey/wheat flour/butter read
  Limit/Fine/Fine, not Good), then engine tables (S15 tiers, sweetener
  systems, whitelist, isolate markers); unknown → Fine, never guessed.
  Verdicts Good / Fine / Limit / Avoid with evidence-tiered copy (refined seed
  oil = Limit "not as a toxin"; flavorings Fine; hydrogenated Avoid). UI:
  tally rows under Overview ("Whole-food ingredients N" / "Worth limiting N"),
  "Key ingredients · N" rows (avoid→limit→good→fine, recipe order within, 8
  then "+ N more"), `IngredientDetailSheet` (verdict, "In this product" with
  position + declared/estimated share + reason, About, four-word legend).
  Additive rows show the curated additive name, not OFF's OCR token.
- **Home** (`ScannerHomeView`): Browse rail = 76pt pack shots with the shelf
  name under (no capsule); Recent scans = photo rail (`RecentScanTile`, 128pt
  shot, `CompactScoreRing` in the corner) replacing the stacked rows.
- **Tab bar** (`ContentView`): `.tabBarMinimizeBehavior(.onScrollDown)`
  behind `#available(iOS 26)` via `TabBarMinimizeOnScroll`. Compiles against
  the 26.5 SDK; **not visually verified on an iOS 26 simulator** (none
  created on this Mac).
- Verified in the iPhone 16 Pro (iOS 18.4) sim, light and dark: header,
  sticky title, Processing/Nutrition/Additives, Key ingredients + sheet on
  Coke Zero / Danish Butter Cookies, Home browse rail. Recent-scans rail only
  compile-checked (no real scans in the sim profile).
- Sim workflow gotcha: the fresh install resets onboarding + Superwall gate;
  the `hasAccess = true` hack (see memory) was kept out of every commit.
  `xcodebuild test` shuts the booted simulator down — reboot before
  screenshotting again.
- **Owner feedback pass (same day)**: Overview took too much room → 15pt,
  clamped to 3 lines until tapped (header chevron / tap toggles), and the
  template (`OverviewTemplate`) no longer repeats the NOVA group, the additive
  count or avoid-list hits (each has its own row now); the personal sentence is
  one short clause ("4 points lower for you: …") and is omitted when the delta
  is 0. Backend prompt (`backend/src/explanation.ts`) tightened to 2–3
  sentences, ≤ 55 words, no additive/NOVA enumeration, no sentence at delta 0 —
  **needs a Worker deploy**; cached overviews on devices refresh when
  `overviewStale` flips. The tinted, stroked banners (avoid list "Seed oils —
  on your avoid list", diet-conflict "caps your score", allergen, trans fat)
  didn't fit the flattened page → all four are `FlagRow`s (tinted icon, title,
  detail, hairline) grouped directly under the tallies (diet-conflict rows
  moved up from the page bottom).
- **Welcome screen redesign (2026-08-24, from a designer mock)**: sky-scene
  hero rebuilt in SwiftUI (`OnboardingSky` palette in OnboardingComponents —
  gradient + blurred cloud/meadow ellipses + fade into `Theme.background`;
  rendered via `.background(_:)` on the content so the oversized blurs never
  drive layout — a ZStack sibling inflated the screen to 700pt wide). White
  DM Sans title + white SageMark lockup, glass scan card ("Scan any label" /
  "Sage reads the ingredients, not the marketing") with the owner's in-aisle
  Chobani photo (`onboarding-scan-photo` asset, cropped from IMG_4431) filled
  in a rounded frame + white `ScanBrackets`, annotated with real scan output (Sugar 3.6 g GOOD,
  "No additives detected", MiniScoreRing 93 · YOUR SCORE · Excellent) instead
  of the mock's placeholder weight/tracking chips; no Apple/Google sign-in
  (unsupported), single Get Started; 4.9★/1.2M stats row dropped with the
  mock. Card ink is fixed dark (`OnboardingSky.cardInk`) — the glass is
  always light.
- **Welcome feedback (2026-08-24)**: blue sky gradient → **brand greens**
  (`OnboardingSky` now 1C7A50 → 57A87E → DCEDE2 mint; the blue read as a
  different app). Chips anchor to the **photo**, not the card (fixed card
  offsets let the Sugar chip cover the caption on other iPhones); the score
  chip cascades below the additives pill (collided at 375pt); the caption
  wraps; SE-class heights (<750pt) get a compact rhythm (smaller photo,
  tighter paddings) via GeometryReader. Verified on iPhone 16 Pro + a
  created-then-deleted SE 3rd-gen sim. Back arrow on the first chromed step
  fixed (was disabled until step 2). Then **inverted on request**: light
  near-background top (dark ink title, green SageMark lockup) → deep brand
  green grounding the CTA (the inverted white pill); card fill + hairline
  both live in the card background — an .overlay stroke drew a line across
  the chips that hang past the card edge.
- **Owner feedback #2 (2026-08-24)**: the owner missed the two dials →
  Overall is back as a **smaller muted ring** ("OVERALL" eyebrow, 56pt,
  `neutralMuted`, gray tier word) beside the FOR YOU hero ring — the
  onboarding "what everyone sees" metaphor, not the old boxed card. Shown
  only when a personalized score exists. The caption slims to the delta
  ("−29 for you" / "Same as overall") + cap chip since the dial now carries
  the Overall number.
- Not done (follow-ups): onboarding screens still show **screenshots of the
  old product page** (two-dial card) — re-shoot `OnboardingScreens` assets;
  `StarterPickCard` still boxes its thumb (could drop the tile like the
  rails); tally "Whole-food" count uses the KB verdicts, which are stricter
  than S14's whitelist (butter/wheat flour count for the engine, not here) —
  decide which the copy should follow; Key ingredients KB has no pt-BR yet;
  Compare is now a capsule under the caption (watch its tap rate); consider
  showing the brand's parent company (Scout's "owned by") from OFF
  `brand_owner`.

---

# Session Changelog — 2026-08-22 — Better Options v2 (gates, fit, reasons, UI)

Audit of the "Better options" feature against the live engine (CLI harness:
simulate scanning every US candidate on every shelf, run
`Alternatives.suggest`, flag what comes back) plus Yuka / Fooducate / Oasis
teardown. Findings: Top Rated gated on evidence, Better Options never did —
a NOVA-less, OCR-ingredient *Diet Mountain Dew* re-scored **100** and was
suggested to every soda (incl. Olipop 74); Hungarian Coke Zero (no
ingredients, 73), Tropicana OJ (no nutrition table, 71), nuun caffeine
*tablets* (61) likewise. OFF community country tags stamped Hungarian /
Indian / Polish / Israeli / Latvian / German / UK SKUs as `us`. Similarity was
shelf-only: cheddar → cottage cheese ×3, cookies → Larabar + oatcakes, bars →
baking chocolate, Cheerios → raw oats ×3, loaf → tortillas, pasta → ramen,
oat milk ↔ cow's milk. No restriction / allergen / avoid-list filter. Rows
compared Overall in a "Your Score" pill, no reason given. Full rationale:
ALTERNATIVES_SPEC.md §3.5; tests `AlternativesTests`.

- **Gates** (`Alternatives.rankOutcome`): evidence (`TopRated.isEligible`),
  market (`countries` ∋ us **and** barcode evidence: UPC/UPC-E 000–139,
  ALDI-US / Lidl-US prefixes, Asian import prefixes on `instantNoodles`
  only — "declared added sugars" tried and rejected), safety (engine
  restrictions + `AllergenMatcher` + avoid-list), fit (`isSwapCompatible`),
  better (margin 10 on **Your Score** when personalized, else Overall; Good
  floor preference), useful (1 per brand, `listKey` dedupe, anchor tag →
  form → score).
- **Forms** (`SageCategoryShelf.swift`): per-shelf tag + name-regex form table
  with compatibility groups and non-suggestible forms (formula, baking
  chocolate / 100 % cocoa, crackers & bars in cookies, lemon juice,
  popsicles, caffeine tablets; plant vs dairy milks & yogurts; fresh vs
  firm vs soft cheese; hot vs RTE cereal; loaf / flat / bagel / bun;
  noodle vs pasta; novelty vs tub). Routing fixes: `chips` no longer roots
  on `chips-and-fries`, `instantNoodles` only on the instant family,
  `babyFood` no longer on `baby-milks` / `infant-formulas`, `yogurt` def
  before `milks` (kefir / yogurt drinks are cross-tagged `dairy-drinks` and
  were told to buy plain milk), `milks` also roots on `milk-substitutes`
  (Elmhurst / Three Trees / soy beverages carried no `plant-milks` tag).
- **Reasons** (`AlternativeReasons`): ≤ 2 label-derived, thresholded lines
  (less sugar, minimally/less processed, no/fewer additives, no artificial
  sweeteners, less sodium / sat fat, more protein / fiber, no trans fat).
- **UI** (`ResultView`): Scout-style horizontal rail of compact cards
  (photo + score ring in the corner, brand + name, one reason line), "See
  all" in the header (`onOpenShelf` → `TopRatedListView`); already-top is a
  one-line seal row that opens the ranking. Selection moved to `.task`
  off-main. (A first pass used a stacked list with subtitle / delta / footer;
  the owner asked for something cleaner — keep it to one reason per card.)
- **Dataset pipeline**: `generate_candidates.py` pulls `allergens_tags`,
  `ingredients_analysis_tags`, `countries_tags`, `unique_scans_n`; shelf
  hygiene for formula / baking chocolate / crackers & bars / lemon juice /
  tablets; `TopRatedBuilder` applies the same evidence + US-barcode gates at
  build time, US cap 80. `mapCandidate` gained optional `allergensTags:` /
  `ingredientsAnalysisTags:`; `AlternativeCandidate` decodes them.
  Regenerated `Alternatives.json` US-only (19 shelves, 80 max/shelf, image
  annotated) — UK/CA rows were never surfaced and are gone.
- **Gotcha**: the Xcode `TopRatedBuilder` target links the PIL dylibs from
  `TopRatedBuilder/.imgenv` (LIBRARY_SEARCH_PATHS + synchronized folder) and
  the binary won't launch; build it with `swiftc` (see README) until that
  search path is removed.
- Not done (follow-ups): engine-side confidence haircut so a thin record
  can't score 100 at all (the provisional banner is the only guard today);
  per-form quotas at build time (some forms have < 3 peers); more shelves
  (crackers, yogurt drinks, sauces, deli meat); `PC` / Canadian brands still
  pass the UPC test; re-annotate images after every regen.

---

# Session Changelog — 2026-08-21 — Protein bar scoring (v5.5.0)

Audit of protein-bar scoring against the live engine (CLI harness over 390
real OFF protein-bar records US/UK/world + 18 label fixtures) and Oasis'
SCR_PROTEIN_BARS v4.7.0. There was no profile: bars rode `snacks` (283) or
`general` (102) on tag luck — OFF files `protein-bars` under
*bodybuilding-supplements*, not *snacks* — so RXBAR scored 54–68 across
barcodes, protein carried 4 % of the score, the isolates that define the
category were docked four separate times, and a 4 g-protein date bar topped
the shelf at 94 (FVN ≈ 100 laundered its sugar). Ruleset `2026.08-v5.5.0`;
full rationale in SCORING_V5.md §"V5.5.0 Protein bars"; tests
`ProteinBarScoringV55Tests`; shapes in `ProteinBarScoring.swift`.

- **`protein_bars` profile** — S12 26 (`proteinBar`: protein delivery =
  grams per serving + share of energy, × DIAAS-style source quality with
  collagen 0.25, + fiber with isolated fibers halved), S3 16 (fruit-sugar
  discount capped at 50 %, no sweetener cap), S6 10 (drinks sweetener tiers
  + declared-polyol load), S2 10 (ultra-processing marker *families*, never
  protein isolates; unrecognized OCR/foreign lists are unknown, not clean),
  S1 8 (isolate text signals exempt), S14 10 (protein sources neutral),
  S15 8, S5 8, S4 2 (> 3 000 mg = unit error), S13 2.
- **Routing** — `protein-bars` / `protein-energy-bars` router entries behind
  a composition guard (200–650 kcal, ≤ 55 g protein — powders / shakes stay
  out) plus a tag-independent evidence gate (bar tag or bar word + protein
  word & ≥ 12 % energy from protein, or ≥ 20 % & ≥ 10 g/100 g) that only
  rerails from `snacks` / `general` / `grains` / `whole_foods`.
- **Generic fixes** — `sugar` / `cane sugar` no longer count as whole food in
  S14; plural nuts / seeds / nut butters / dried fruit / milk & egg powders /
  cocoa mass whitelisted; `palm kernel oil` & palm fat family → S15 low tier,
  `mixed nuts` → high tier; `Nutrients.polyols_g` (OFF `polyols_100g`) and
  `serving_size` plumbed through OFF decode, `AlternativeCandidate`,
  `TopRatedBuilder` and `generate_candidates.py` (`mapCandidate` gained an
  optional `servingSize:`). Shelf drift outside bars ≤ ±0.6 mean (nut
  butters +4 — plural "peanuts" is real food); 51 snack-bar rows move to
  `protein_bars`.
- **Calibration** — clean egg-white + nut bar 92 · RXBAR 73–79 · Perfect
  Bar 70 · Quest 67 · Barebells 59 · think! 56; same bar = same score
  whatever the tags / NOVA. `rulesetV550Rescored` migration.
- Not done (follow-ups): re-pull the `snackBars` shelf so rows carry
  `serving_size` (pre-v5.5 rows fall back to pack size / 50 g); the generic
  `snacks` S3 still lets FVN ≈ 100 date bars launder 40 g sugar (Larabar 94
  as a *snack*); plain `palm oil` is still invisible to S15 (only the kernel
  / fractionated family was added); OCR junk `ingredients_text` reaches every
  profile — only `protein_bars` guards against it.

---

# Session Changelog — 2026-08-21 — Bread scoring (v5.4.0)

Audit of bread scoring against the live engine (CLI harness over the
96-product shelf, 27 archetype fixtures, ~400 real OFF records US/UK/FR/DE/CA)
and Oasis' SCR_BREADS v4.7.0. The shipped shelf compressed into 50–75:
whole-kernel rye tied with white sourdough, brioche beat plain sourdough,
and 85/96 breads got the full binary whole-grain credit (2 % rye flour,
"sprouted", "oat" matching "goat"). Ruleset `2026.08-v5.4.0`; full
rationale in SCORING_V5.md §"V5.4.0 Bread"; tests `BreadScoringV54Tests`.

- **`bread` profile** (S1 16, S2 14 `bread`, wholeGrain 16 `bread`, S12 14
  `grain`, S3 10, S4 12 `bread`, S5 6, S14 8, S15 4; no S13) routed from all
  bread tags; cereals / pasta / rice / oats / flours stay on the legacy grains
  profile, **renamed `breads` → `grains`** (rules untouched). New `Sage/BreadScoring.swift`.
- **Graded whole-grain share**: position-weighted, declared-% override,
  parenthetical sub-lists, multilingual whole / partial / refined vocab,
  name-claim lift only for whole-first lists, fiber cross-check caps.
- **Evidence-based S2**: 16 UPF marker families from text or E-codes; 0
  families → 0.70 (traditional NOVA 3 is bread's ceiling); preservatives,
  ascorbic acid, fortification and vital wheat gluten are not markers.
- **S12 `grain`** fiber/100 g + protein (isolated fiber on refined base ×0.5);
  **S4 `bread`** 200/450/700 mg + sodium plausibility guard; **S5** added;
  S13 dropped (only ever rewarded fortified white flour).
- **Generic fixes**: S14 whitelist (whole-grain flours, oats, seeds, yeast,
  sourdough, semolina…), water excluded from the real-food ratio,
  `hasIsolateProtein` needs *protein* concentrate, allergen / boilerplate
  tails cut from tokens, marketing prose in the ingredients field → missing,
  enrichment vitamins (E101/E375/E300/E170/E306) exempt from S1. Drift outside
  bread: 511/1 776 move, all +1…+7 (pasta +5, cereal +3.6), one garbage list
  −21; no routing changes.
- Calibration: Ezekiel 94, whole rye 88, whole-wheat sourdough 87, Dave's 83,
  Nature's Own 100 % WW 64, white sourdough 63, baguette 61, brioche 58,
  gluten-free 45, Hawaiian rolls 39, Wonder 33, mass tortilla 33. Real shelf
  44–94 (mean 75). Deliberately unscored: sourdough fermentation, organic,
  packaging, sourcing, GI.
- Not done (follow-ups): the legacy binary `wholeGrain` still serves cereals
  / pasta / rice (same "oat"→"goat" substring issue); crispbreads are judged
  per 100 g dry (fiber and sodium both inflated vs fresh bread); Top Rated
  bread shelf ordering changed (re-check the `bread-tr` hero pick);
  Alternatives.json `precomputed_score` for bread is stale until regenerated.

---

# Session Changelog — 2026-08-21 — Egg scoring (v5.3.0)

Audit of egg scoring against the live engine (CLI harness over 29 real OFF
records + 40 fixtures) and Oasis' egg methodology. Eggs rode `whole_foods`,
whose S12 is 80 % fiber+FVN — structurally zero for an egg — so real eggs
scored 47–76 on label luck and the overview called them "limited nutritional
quality". Oasis scores eggs on sourcing (housing/feed/practices/packaging);
Sage keeps only the measurable health outcome. Ruleset `2026.08-v5.3.0`;
full rationale in SCORING_V5.md §"V5.3.0 Eggs"; tests `EggScoringV53Tests`.

- **`eggs` profile** (S2 18, S1 12, S3 4, S4 10, S5 8, S12 18 `egg`, S13 12
  `egg`, S14 12, S15 6) with an egg-dominance routing guard (scotch eggs,
  egg pasta, egg salad fall through) and a tag-independent `eggEvidence`
  gate for untagged US liquid-egg cartons.
- **S12 `egg`** = protein per 100 g vs a reference egg (no fiber axis;
  overview topic "protein"). **S13 `egg`** = reference prior by form
  (whole/yolk 0.85, whites 0.45) + enrichment lift (declared vitamin D /
  B12 / omega-3 / selenium ≥ ~2× reference; +0.05 each, cap +0.10). Ordinary
  full panels lift nothing — label completeness can't separate identical eggs.
- **Evidence-based NOVA**: egg-only ingredient list (or no list + no NOVA)
  → NOVA 1; egg powders scored as reconstituted.
- **S14 generic fixes**: trailing punctuation + OFF `_allergen_` underscores
  stripped from tokens; egg qualifiers strippable; multilingual egg whitelist.
  Shelf drift 64/1 775, all +1/+2 (two +6/+7 single-ingredient lists), no
  routing changes.
- New `Nutrients` fields (vitamin D, B12, choline, selenium, omega-3) decoded
  from OFF with implausibility guards.
- Calibration: plain eggs 97–98 regardless of housing/organic claims,
  enriched 99, whites 91, hard-boiled clean = liquid = shell, HB with
  preservatives 81, pickled 74, Egg Beaters-type 60. Cholesterol, housing,
  feed, packaging, lab testing deliberately unscored (see SCORING_V5.md).
- **Top Rated "Eggs" shelf** — `SageCategory.eggs` (🥚, hero asset
  `eggs-tr` — drop an `eggs-tr.imageset` into Assets like the other `-tr`
  shots; until then the tile shows the shelf's top product photo), shelf
  routing (after pasta: OFF cross-tags egg pasta under `en:eggs`), StarterPicks
  for protein / less-processed goals, builder `SHELF_TAGS` / `SHELF_EXCLUDE`
  / name filter (frittatas, scotch eggs, substitutes, pasta out). Pulled
  US/UK/CA candidates, scored, image-annotated, merged into `Alternatives.json`
  (other shelves' `precomputed_score` restamped under v5.3.0; OFF not
  re-pulled). `generate_candidates.py` gained a search-a-licious +
  product-endpoint fallback for when OFF's search backend is down.
  `SageCategory.swift` UIKit import is now `#if canImport(UIKit)` so the macOS
  builder compiles again.
- **DEBUG logger data race fixed** — `DrinksScanDebug.last` / `lastRerail`
  were unsynchronized statics written from `OpenFoodFactsService.map`; under
  Swift Testing's parallel suites this segfaulted (`outlined destroy of
  Snapshot?`) and took all of `AlternativesTests` down with it. Now
  `NSLock`-protected. Pre-existing and intermittent, not egg-related.
- Not done (follow-ups): pasteurized-shell badge, cholesterol / vitamin D rows
  on the product page, `meat` profile has the same dead-S12 structure.

---

# Session Changelog — 2026-08-20 — Design-system audit & consolidation

Audited the app against an app-design playbook (design-as-trust-signal:
one type scale, tokens everywhere, squircles, funnel-ordered polish) via a
full simulator walkthrough in both schemes. Wrote **design.md** (the system
of record; header line above enforces it) and fixed what the audit found.
All changes build clean; verified visually in the simulator.

- **Light by default is a product decision** — the seed profile's
  `appearance: "light"` is intentional: fresh installs open light regardless
  of the device setting; users opt into Dark/System in Preferences. (Was
  briefly flipped to "system" during this audit and reverted on request.)
- **Onboarding CTA visible in dark mode** — the pill was "locked to black
  regardless of color scheme", i.e. invisible on the dark background.
  `OnboardingCTAButton` now flips black/white by environment scheme.
- **Results-screen pinned CTA** ("Here's where you stand") moved from a
  ZStack overlay to `.safeAreaInset(edge: .bottom)` + gradient scrim — the
  "WE'LL WATCH FOR" section could never scroll clear of the pill.
- **Dead fake paywall removed** — `PaywallView` (unreachable; "Start free
  trial" just dismissed) + `Overlay.paywall`. The real paywall is Superwall's
  remote `app_access` template; its broken price interpolation ("Subscribe
  for /" with a dead button when products don't load) must be fixed in the
  Superwall dashboard, not here.
- **Radius tokens** — `Theme.Radius` (panel 22 / card 18 / control 14 /
  chip 8), all 76 call sites migrated, stragglers (24/20/16/12/10/8/3)
  snapped, last non-continuous corners fixed, deprecated `.cornerRadius()`
  modifier replaced.
- **Gray tokens** — `Theme.fillQuiet/.fillMuted/.fillTrack/.outline`
  replace ~30 scattered `Color.black/white.opacity(…)` and `dark ?`
  ternaries; near-duplicate hexes (`1F8A5B`, `C9442B`, `D4A02D`, `D4A437`,
  `3FBF7B`) folded into `Theme.accent` / score-band tokens. Nutri-Score and
  NOVA ladders deliberately keep their own palettes.
- **Type scale closed** — outlier sizes snapped (9→10, 17→16, 19→20,
  26→24, emoji 34→32); `sageBold(28)`→`.sageHeadline`,
  `sageBold(34)`→`.sageDisplay`; scale documented in `Typography.swift`.
- **Spacing on-grid** — odd paddings/spacings (3/5/7/9/13/26/30) snapped to
  the 2·4pt grid.
- **Top Rated grid** — the five categories with no bundled `-tr` pack shot
  (cookies, nut butters, instant noodles, fats & oils, baby food) showed
  emoji next to nine photo tiles; they now resolve their shelf's
  highest-ranked product *with an image* via `ProductThumb` (emoji only as
  load/offline fallback). Ideal endgame: curated pack-shot assets like the
  other nine. Ranked-row names now wrap to 2 lines (were truncating).
- Known cosmetic nit kept as-is: demo reveal ring at 55 is green because
  Good ≥55 — band color, not a bug.
- **Pantry controls** — the two stacked segmented pickers (History/Favorites,
  All/Good/Avoid) read as a form. Now `SageUnderlineTabs` (sliding accent
  underline, App Store / Spotify pattern) for the mode switch and `SageChip`
  capsules with tabular counts for the filter (Airbnb / Uber Eats pattern);
  both in `Shared.swift`.
- **Product page** — "Add to favorites" button under Compare replaced by a
  heart in the nav bar (top-right, accent-filled when saved, bounce +
  selection haptic on toggle).
- **First-run empty states** (research: Mobbin empty-state collection, Spotify
  genre cards, Gemini suggestion cards, Airbnb Wishlist) — no more icon-in-a-void:
  Home shows a goal-aware "Top picks" rail of real scored products + a
  "Sage is watching for" chip strip until the first real scan; History is
  seeded with the onboarding demo scan and, when empty, shows a compact
  top-anchored intro card + "Meanwhile, worth a look" rows; Favorites shows
  the same intro + "Worth saving" rows with inline hearts. Filter chips hide
  at zero items. All from bundled shelves via `StarterPicks.swift`.
- **Home restructure** (competitor teardown of Oasis + Mobbin home patterns):
  the green scan card became a **Pantry Score hero** — `ScoreRing` of the
  average Your Score over the last 20 real scans with a weekly trend line and
  the Scan CTA folded in; before 3 scored scans it's an unlock-progress ring
  ("0/3"), never a demotivating zero. A **Browse top rated** rail of pack-shot
  chips sits under search (tap → that shelf's list). **Top picks** cards now
  carry a one-line "why for you" from `ScoringEngine.signedFactors` and an
  inline heart. Deliberately not borrowed from Oasis: sky-gradient half-screen
  hero, community/trending (no social layer), corner glass buttons, search FAB.
- **Top Rated pack shots** — `-tr` hero assets wired for cookies / nut-butter /
  instant-noodles / fats-oils / baby-food via `bundledTopRatedHeroAsset`
  (falls back to the live top product photo if the imageset is missing).

---

# Session Changelog — 2026-08-14 — Dairy-aware milk scoring (v5.2.0)

Milk scoring audit against the engine's live per-rule output (CLI harness) found
five bugs and one structural flaw; all fixed under ruleset `2026.08-v5.2.0`.
Full rationale in SCORING_V5.md §"V5.2.0 Dairy milk"; tests in
`MilkScoringV52Tests.swift`.

- **dairyProcessing table never matched** real OFF tags (`raw-milks` vs
  `raw-milk` etc.) — every milk fell to the 0.85 unknown default; raw milk
  escaped its 0.5 credit. Table now carries OFF plural forms + explicit
  pasteurized/fresh entries (0.85, evidenced).
- **Raw milk safety gate** — new `hardGates.rawMilk` cap 54 + chip (kind
  `rawMilk`). V4's promised "mandatory safety chip" had been lost in V5.
- **S12 `dairy` variant** — protein+calcium per 100 ml replaces fiber/FVN
  (structurally zero for milk; the profile's biggest weight was 85% dead and
  compressed all milks into 74–78). Whole vs skim is now a deliberate near-tie.
- **Fortification exemption** — vitamin D/A + lactase no longer cost ~9 points
  (NOVA cascade); ultrafiltered is explicitly not laundered.
- **S14 qualifier stripping** — "organic milk" / "goat milk" / "raw milk" no
  longer lose 6 points to the whitelist prefix-match; whitelist expanded.
- **S13 dataFloor** — declared micros never score below the unknown credit
  (reporting calcium used to *lower* milk by 2 points).
- **Powder reconstitution** — milk powders scored per 100 ml as prepared.
- **Flavored milks route to `drinks`** (chocolate-milks etc. before `milks` in
  the router) — the RTD path with lactose allowance and satFat cap fits them.
- `isV510` is now `>=` so v5.1.0 paths survive version bumps; `Product.novaGroup`
  is `var` for normalization; one-shot `rulesetV520Rescored` migration.
- **yogurt_cheese extension**: S12 `dairyDense` variant (protein blend of
  absolute per-100 g + per-kcal density, plus calcium — see SCORING_V5.md for
  why neither half works alone); reweight S12 14→8 / S5 8→12 / S4 8→10;
  `raw-milk-cheeses` gets the 0.5 processing dock but not the fluid-milk cap;
  fortification stripping extends, powder reconstitution does not; whitelist
  gains cultures/rennet. Yogurts 88–93, cheeses 68–77 (`YogurtCheeseV52Tests`).
- Calibration: plain milk 93 (Excellent), vat 94, UHT 88, ultrafiltered 73,
  raw 54, chocolate milk 65. Deliberately NOT adopted from the Oasis-style doc:
  farming/welfare/packaging inputs (ethics, not health), whole-over-skim
  penalties, and raw-milk "benefits" claims (lactase/vitamin C myths).

---

# Session Changelog — 2026-07-27 — Native SwiftUI chrome pass

Design review called the UI "a copy of Oasis" and asked for more default SwiftUI
components. The app had rebuilt every piece of platform chrome by hand, which is
what made it read as a template. This pass deletes the hand-rolled chrome and
adopts the system equivalents. Net **−900 lines**.

## Navigation — `NavigationStack` replaces the manual overlay stack
**Files:** `ContentView.swift`, and every pushed screen

`ContentView` drove a `ZStack` with `@State stack: [Overlay]` and a hand-written
`.transition(.move(edge: .trailing))`. Now each tab owns a `NavigationStack(path:)`
and every screen resolves through one `navigationDestination(for: Overlay.self)`.

This restores interactive swipe-back, real push transitions, large-title collapse,
and per-tab stack persistence. `SubHeader` plus four inline copies of a fake nav bar
(each with a `Color.clear.frame(width: 42)` spacer to fake title centering) are gone,
replaced by `.navigationTitle` / `.toolbar`. `onBack` closures deleted throughout.

## Tab bar — `TabView` replaces `TabBar`
**Files:** `ContentView.swift`, `Shared.swift`

Native `TabView(selection:)` with iOS 18 `Tab` values. Scan is a pseudo-tab: the
selection binding intercepts `.scan`, opens the camera, and leaves the current tab
selected. `AppTab.activeIcon` is gone — the system owns filled/unfilled variants.

## Lists — `List` / `Form` replace stacked `CardView`s
**Files:** `ProfileView`, `ProfileSubScreens`, `HistoryView`, `TopRatedView`, `SearchView`

Inset-grouped `List` on the brand background (`.scrollContentBackground(.hidden)`),
so the beige/white look survives while the system supplies separators, row insets,
press highlights, and swipe actions. Specifically:

- `CustomToggle` → `Toggle` + `.tint`
- appearance tiles → inline `Picker`
- priority segmented control → `Picker(.segmented)`
- objective radio circles → system checkmark
- search field → `.searchable` in the nav bar
- empty states → `ContentUnavailableView`
- history delete → `.swipeActions`; clear-all → toolbar `Menu`
- `MethodologyModal` / `DisclaimerModal` (z-indexed overlays) → `.sheet` + detents
- `ErrorToast` → `.alert`
- camera → `.fullScreenCover`
- `PillButton` / `CircleIconButton` → `.borderedProminent` + toolbar buttons

## Theming — dynamic colors, and "System" appearance actually works
**File:** `Theme.swift` (+ ~25 views)

Colors were picked by a `dark: Bool` threaded manually through every view.
`Color(light:dark:)` wraps a `UIColor` dynamic provider, so `Theme.background`,
`.card`, `.ink`, `.inkSecondary`, `.hairline`, `.ringTrack` resolve themselves —
including inside UIKit-backed chrome where a SwiftUI flag never reaches. All ~196
`Theme.foo(dark)` call sites migrated; the `Bool` overloads are deleted.

`AppStore.darkMode` is replaced by `colorScheme: ColorScheme?`, which returns `nil`
for "system". Previously `.preferredColorScheme(store.darkMode ? .dark : .light)`
pinned the app to one scheme, so the System tile in Preferences never worked.

## Typography — Dynamic Type
**File:** `Typography.swift`

`Font.custom(_:size:)` opts out of Dynamic Type entirely. Every sized variant now
passes `relativeTo:`, mapped from the design point size to the nearest system text
style. `sageFixedBold/Medium` opt out deliberately for numerals inside fixed
geometry (score rings), which carry their own accessibility labels. The app clamps
at `accessibility2` — past that the dials stop being readable rather than more so.

## Haptics
`.sensoryFeedback` on scan success/failure — the one moment that should be felt.

### Superseded from the 2026-07-09/10 entry below
- item 3's `topBar` → toolbar; item 5's browse-category card grid → `List` section.

---

# Session Changelog — 2026-07-09/10

Summary of the UI/bug-fix changes made in this session. All changes build clean
(`xcodebuild ... -scheme Sage`, **BUILD SUCCEEDED**).

---

## 1. Build fix — `ProductThumb` argument order
**File:** `Sage/ResultView.swift`

The product header called `ProductThumb(... imageURL:, neutral:)` but the struct
declares `neutral` before `imageURL`, so Swift's synthesized initializer rejected
it (*"Argument 'neutral' must precede argument 'imageURL'"*). Reordered the call
to `neutral: true, imageURL: product.imageURL`.

## 2. Search → product "Back" button not working on first tap
**File:** `Sage/SearchView.swift`

When a search result was tapped, the keyboard was still up as the `ResultView`
overlay got pushed. iOS installs a tap-to-dismiss gesture over the new view that
swallows the **first** tap, so the back arrow appeared dead on first press.
Fix: set `focused = false` (dismiss keyboard) before calling `onSelect(hit.code)`.

## 3. Product detail header — two-dial score comparison card
**File:** `Sage/ResultView.swift`

Rebuilt the header to match the target design (the previous two-dial version was
uncommitted work wiped by a `git pull` fast-forward and was not recoverable):

- New `scoreComparisonCard` with two side-by-side `scorePanel`s:
  - **OVERALL** — neutral panel, animated `ScoreRing` + tier label pill.
  - **YOUR SCORE** — tinted/bordered panel with a floating green **★ FOR YOU**
    badge, an **ⓘ** info button (opens methodology), ring + label pill.
  - **Compare with another** button now lives inside this card.
- `productHeader` simplified to thumbnail + brand + name + size (removed the inline
  single dial and the "Overall · universal score" text row; thumbnail uses the
  neutral backdrop). Removed the now-unused `yourScoreRing` / `overallStatRow`.
- `aiAdviceSection`: label renamed **"Overview" → "AI ADVICE"**; the delta badge is
  now a signed, tinted pill (e.g. red `-9`, green `+n`).
- Top bar shows **"SAVED"** centered when the product is saved, else "Sage".

## 4. Onboarding — removed the "Life stage" section
**File:** `Sage/Onboarding/OnboardingScreens.swift`

Removed the LIFE STAGE block (None / Pregnant / Breastfeeding / Managing a
condition) from the "A bit more about you" screen — deleted the single
`StaggeredAppear(index: 3) { lifeStageSection }` line. Data model and all other
sections (DOB, Gender) left untouched.

## 5. Search page — browse-categories opener
**File:** `Sage/SearchView.swift`

The idle state (empty search field) now shows a 2-column grid of tappable category
cards under a **BROWSE** header, replacing the plain "Find any food" hint. Tapping
a card drops its term into the search field, firing the existing debounced
typeahead pipeline. Food categories only (app searches Open Food Facts): Soda,
Water, Chocolate, Cookies, Cereal, Cheese, Yogurt, Bread, Juice, Chips, Coffee,
Pasta, Ice cream, Baby food. Card list is a static array at the top of `SearchView`.

## 6. HIGH additives — red instead of brown
**File:** `Sage/ResultView.swift`

HIGH-risk additives only turned red when `allowAlarmRed` was set (false when the
product's own score is already "bad"), otherwise falling back to the same brown as
MODERATE. Made **HIGH always resolve to `Color.scoreBad` (red)** in all three
resolvers: `riskFg` (badge/row), `barColor` (severity bar), and `RiskDot`.
MODERATE / LOW / UNRATED unchanged.

## 7. HIGH nutrient badges (PER 100G / 100ML) — red
**File:** `Sage/ResultView.swift`

Changed `NutrientRow.Tag` `.bad` tone from `Color.cautionMuted` (brown) to
`Color.scoreBad` (red), matching the additive HIGH color. LOW (green), MOD (amber),
neutral, and green-HIGH (`.good` tone, e.g. high Protein) badges unchanged.

## 8. Scanner — "Align the label" in label mode
**File:** `Sage/ScanCameraView.swift`

The scanner guidance text was hardcoded "Align the barcode" for both modes. Now it
reads **"Align the label"** in label mode and **"Align the barcode"** in barcode
mode: `Text(mode == .barcode ? "Align the barcode" : "Align the label")`.

---

### Files touched this session
- `Sage/ResultView.swift` — items 1, 3, 6, 7
- `Sage/SearchView.swift` — items 2, 5
- `Sage/Onboarding/OnboardingScreens.swift` — item 4
- `Sage/ScanCameraView.swift` — item 8