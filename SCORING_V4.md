# Sage Scoring System — v4 (reconciled spec)

**Category-aware product scoring built on Open Food Facts (OFF)**
Draft for team review · July 2026 · supersedes both the v3 engine notes in
ROADMAP.md and the "Sage Scoring System v1.0" proposal once approved.

> **Status: DRAFT — needs sign-off.** This document merges the team's v1.0
> category-aware proposal with the decisions taken afterwards. Everything the
> two sources disagreed on is resolved here and marked **[DECIDED]** with the
> reasoning; genuinely unresolved items are marked **[OPEN]** and collected in
> §14. Nothing in this spec is implemented yet.

---

## 0. Decision log (what changed and why)

| # | Topic | v1.0 proposal | v4 resolution |
|---|---|---|---|
| 1 | Positive nutrition | Absent — all rules were penalty-avoidance; the app's four objectives (build muscle / lose weight / maintain / eat healthier) had no levers | **[DECIDED]** New shared rule **S12 Nutrient quality** (protein density, fiber, whole-food content — the proven v3 blocks) joins every food profile. The four objectives stay and act through S12 + rule multipliers (§7) |
| 2 | Scale philosophy | Harsh (90/80/70/60 bands; scores can hit 0) | **[DECIDED, revised 2026-07-11]** **Harsh, Yuka-aligned scale** (team reversal of the earlier centered decision): mainstream ultra-processed food should cluster in the bottom half, "Good" is earned. **Floor at 10 stays — a score is never 0.** Harshness comes primarily from the Tier-A additive cap (§3.5), not from band placement alone. Bands provisional until calibration (§12) |
| 3 | Rule math | Absolute penalty points "calibrated for a 45-pt max", rescaled per category — the worked example scaled in the wrong direction | **[DECIDED]** Every rule returns a **fraction ∈ [0, 1]** and never knows its point value; profiles own the weights. No rescaling step exists, so the bug class is structurally impossible (§3) |
| 4 | Personalization inputs | Continuous priority sliders + free-text avoid list | **[DECIDED]** All personalization inputs are **discrete and few-optioned** (3-step sliders, fixed avoid-list vocabulary) so ScoreClass explanation-cache bucketing survives (§7.4) |
| 5 | Where scoring runs | Unspecified | **[DECIDED]** **On-device Swift engine + versioned JSON rulesets** (bundled default, background-refreshed from the Worker, never blocking launch or scans, fully offline-capable). Ruleset version joins the explanation cache key (§10) |
| 6 | PT-BR / INS additive parsing layer | Required (Brazilian market) | **[DECIDED]** Descoped — target market is English-speaking countries, where OFF's parser is at its strongest. Idea preserved in the roadmap for a LATAM expansion (§15) |
| 7 | Band cutoffs | Fixed up front | **[DECIDED]** Provisional until the Phase-B calibration run over the OFF dump; locked afterwards as part of the ruleset version (§12) |

Everything else from the v1.0 proposal — category router, shared rule library,
two-tier unknown policy, Data Confidence, hard gates, ODbL obligations, the
"Sage Verified" lab layer as future work — is adopted as written, with the
detail-level corrections noted inline below.

---

## 1. Design principles

1. **Category-specific rulesets.** Water, tea, chips, and milk are judged by
   different rules with different weights. A router maps every product to
   exactly one category profile.
2. **Transparent weighted math.** Each rule returns a fraction of what it
   could earn; the category profile weights the rules. The score is always
   decomposable into "which rule earned what".
3. **Unknowns are never rewarded — but data gaps aren't punished as secrecy.**
   Voluntary claims (certifications, welfare labels) earn zero when absent.
   Label-mandated or contributor-dependent data (nutrition table, packaging)
   earns an explicit partial "unknown tier" and lowers **Data Confidence**.
4. **Positive nutrition matters.** A product is not merely the absence of bad
   ingredients; protein density, fiber, and whole-food content earn points
   (S12). This keeps the goal-based personalization meaningful.
5. **Harsh, floored scale (Yuka-aligned).** A "Good" verdict is earned, not
   default: clean whole foods reach the top bands, mainstream ultra-processed
   products cluster in the bottom half, and a major-concern additive caps the
   score outright (§3.5). 10 = floor (never 0); 100 = attainable.
   Personalization *tunes* the base verdict, it doesn't replace it.
6. **No fake data.** OFF has no lab results; Sage never implies it does. The
   Data Confidence chip + methodology page carry that honesty.
7. **Scope:** food and beverages only. Non-food `categories_tags` (pet food,
   cosmetics, supplements without food categorization) → "Unsupported", no
   score rendered.

---

## 2. Data foundation

Adopted from v1.0 §2 unchanged (the OFF field/reliability table holds). Fields
the current backend/mapper must **add** to the fetch list and product cache:

`labels_tags`, `packagings[].material` / `packaging_materials_tags`,
`origins_tags`, `manufacturing_places`, `ingredients[]` (with `percent` /
`percent_estimate`), `nutriments["added-sugars"]`, `ecoscore_grade` (a.k.a.
environmental score — check both field names), `completeness`, `states_tags`,
`last_modified_t`, `serving_size`, `countries_tags`.

The KV product cache key bumps to `product:v2:` so v1-shaped snapshots are not
served into the v4 engine.

**Market focus [DECIDED]:** English-speaking countries (US, UK, CA, AU, IE,
NZ). Consequences: OFF's English ingredient parser is trusted as-is
(`additives_tags` is authoritative; no custom text-parsing layer), and the
calibration sample (§12) filters `countries_tags` to these markets.

---

## 3. Core math

Every category profile is an ordered set of rules. Rule *i* has weight `w_i`
(from the profile) and returns fraction `f_i ∈ [0, 1]` (from product data).

```
raw       = Σ (w_i × f_i) / Σ w_i × 100
BaseScore = max(10, round(raw))          // floor: never 0, never negative
```

- **Rules never see weights; profiles never see rule internals.** All
  penalties inside a rule are expressed as fractions of that rule (§5), so
  changing a weight never requires touching a rule and vice versa.
- Weights need not total 100 (normalization handles it), but keeping profiles
  near 100 keeps them readable.
- Personalization multiplies weights and renormalizes — same formula (§7).

### 3.1 Unknown policy (two tiers, adopted from v1.0)

- **Tier 1 — voluntary claims** (certifications, grass-fed, organic, welfare,
  BPA-free, origin): absence ⇒ `f = 0`. If it were true, it would be printed.
- **Tier 2 — mandated/contributor data** (ingredient list, nutrition facts,
  packaging material): absence ⇒ the rule's explicit **unknown fraction**
  (listed per rule) **and** a Data Confidence hit.

### 3.2 Data Confidence

```
Confidence = Σ (w_i where rule i had real data) / Σ w_i
```

- **High ≥ 0.80** — score shown normally.
- **Medium 0.50–0.79** — score + "some data missing" chip.
- **Low < 0.50** — score shown as provisional ("~68") + prompt to photograph
  the label (feeds OFF; see §13).
- Fallback data (e.g. total sugars standing in for added sugars) counts as
  "had data" but the rule flags the imprecision in its chip.

### 3.3 Minimum data requirement (RMP) [DECIDED]

Never render a number computed purely from unknown tiers. If a product has
**neither** an ingredient list **nor** a nutrition table → "insufficient data"
state: show name/brand/photo, no score, and the photograph-the-label prompt.

### 3.4 Score bands — PROVISIONAL [OPEN until §12 calibration]

Yuka-aligned working set: **75–100 Excellent · 50–74 Good · 25–49 Mediocre ·
10–24 Bad**. All UI components (`scoreTier`, `CompactScoreRing`, methodology
copy) must read from **one** band definition in the ruleset — the current
three-way divergence is a bug this spec removes.

### 3.5 Severity caps — **[DECIDED 2026-07-11: NOT adopted]**

The team chose interpretation 1: Yuka-aligned **bands only** (75/50/25), no
hard caps. The score is always the weighted sum; a Tier-A additive hurts
through S1's −0.33 fraction but never overrides the average. (Proposal kept
below for the record in case calibration reopens it.)

> Rejected proposal: Tier-A additive → Base capped at 24; 2× Tier-B → 49.

**Consequence (important):** all harshness must now come from rule weights
and calibration. First hand-run finding: under the provisional §6 weights, an
additive-clean ultra-processed snack (NOVA 4) could still reach ~64 "Good".
**Resolved by the 2026-07-11 calibration run** (ruleset `2026.07-b2`): NOVA
promoted to the second-biggest rule in all three Phase-B profiles → 81.8% of
NOVA-4 products land below 50 while whole foods hold at median 81. Details in
§12.7. Residual trait of interpretation 1: the "Bad" band (<25) is sparse —
soda/candy land ~33 "Mediocre", not "Bad"; only near-worst-case products
reach the bottom band.

---

## 4. Category router

Adopted from v1.0 §5.12 unchanged: resolve from `categories_tags`,
most-specific-first:

```
waters → tea/coffee (dry) → plant-based milks → dairy milks →
yogurts/cheeses → sweeteners → breads & grains → ice cream/frozen desserts →
meat & seafood → snacks → other beverages → general packaged food (fallback)
```

- First match wins; the ordering separates leaf tea from bottled iced tea.
- Non-food → Unsupported.
- Router decisions are **logged** (misrouting is the #1 bug source in
  category-aware systems), and the result page gets a manual "wrong category?"
  recategorize control whose corrections are logged for ruleset fixes.
- The router table lives in the JSON ruleset (§10) so misroutes are fixable
  without an app release.

---

## 5. Shared rule library

Rules are written once, reused across profiles with different weights.
Notation: `unknown → x` is the Tier-2 unknown fraction. All penalties are
**fractions of the rule**.

### S1 · Ingredient & additive risk *(the workhorse)*

Start at `f = 1`. Subtract per flagged item from `additives_tags` /
`ingredients[]`; floor at 0. After the **third** flagged item, further items
count at 50% (dampening). Tier fractions (same 15:8:4:2 ratios as v1.0, now
scale-free):

| Tier | Fraction | Contents (unchanged from v1.0 §S1) |
|---|---|---|
| A — major | **−0.33** | E924, E927a, E171, nitrites/nitrates in cured meat (E249–252), BHA E320, TBHQ E319, partially hydrogenated oils, E443, Red 3 E127 |
| B — moderate | **−0.18** | aspartame E951, saccharin E954, Southampton azo dyes (E102/104/110/122/124/129), caramel III/IV (E150c/d), BHT E321, polysorbate 80 E433, carrageenan E407, HFCS (text detection) |
| C — mild | **−0.09** | sucralose E955, acesulfame-K E950, CMC E466, mono-/diglycerides E471, added phosphates (E338–452), maltodextrin, dextrose-as-filler, artificial flavors |
| D — soft | **−0.045** | thickener gums (E410/412/415/418 — **count max 2**), undisclosed "natural flavors", refined seed oils as added oil (*contested science — small in Base, escalatable in Your Score*) |

**Exempt (never penalized):** stevia E960, monk fruit, allulose, erythritol,
citric/ascorbic acid, lecithins E322, pectin E440, agar E406, and intrinsic
components of the base food (milk fat in milk, caffeine in coffee/tea).

`no ingredient list → 0.20` + Confidence hit.

**Additive table maintenance:** tiers live in the JSON ruleset, versioned,
reviewed against EFSA/FDA/IARC updates ("Active ruleset: YYYY.MM" shown in
the methodology page).

### S2 · Processing level (NOVA)

`nova_group`: 1 → **1.0** · 2 → **0.75** · 3 → **0.40** · 4 → **0.0**.
`unknown →` ingredient-count fallback: 1–3 → 0.85 · 4–7 → 0.55 · 8–15 → 0.25 ·
16+ → 0.0. (No ingredient list either → 0.40 + Confidence hit.)

### S3 · Added sugar

Prefer `added-sugars`. Fallback: **total sugars discounted by fruit/veg/nuts
content** — `effective = sugars × (1 − fvn/100)` — the v3 rule that stops an
apple juice being scored like a soda **[DECIDED**, carried over; v1.0 lacked
this and would have re-penalized intrinsic fruit/dairy sugar].
**Per-100g/ml is primary**; per-serving is a refinement only when
`serving_size` parses cleanly **[DECIDED** — inverted from v1.0: OFF serving
data is free-text and too unreliable to be the default].
Threshold sets (per 100 g/ml unless noted) and credit steps as in v1.0 §S3:
full → 1.0, partial → 0.60, reduced → 0.30 (ice cream 0.40/0.15), zero → 0.
`both unknown → 0.25` + Confidence hit.

### S4 · Sodium

Per 100 g: ≤ 120 mg → 1.0 · 120–400 → 0.60 · 400–800 → 0.30 · > 800 → 0.
`unknown → 0.30` + Confidence hit.

### S5 · Saturated fat

Standard per 100 g: ≤ 3 g → 1.0 · 3–8 → 0.60 · 8–15 → 0.30 · > 15 → 0.
Soft variant (ice cream/dairy): ≤ 4 / 4–8 / 8–14 / > 14.
`unknown → 0.40` + Confidence hit.

### S6 · Artificial sweeteners (drinks-type profiles)

Detect E950/951/954/955/961/962/969. First hit → 0.60; each further hit −0.40
(floor 0). Stevia / monk fruit / allulose exempt. `no ingredient list → 0.50`.

### S7 · Packaging material

Worst material wins in compound packaging. Glass 1.0 · paper/cardboard 0.90 ·
lined carton 0.70 · can + `en:bpa-free` 0.80 · can lining unknown 0.55 ·
HDPE/PP 0.40 · generic "plastic" 0.30 · PET 0.25 · PS/PVC 0.0.
`no packaging data → 0.30` + Confidence hit.
*Note: OFF packaging data is sparse; S7 weights are kept small outside the
water profile, and calibration (§12) checks whether S7 is measuring packaging
or merely data coverage.*

### S8 · Recognized certifications — binary

Any of: USDA/EU Organic, Non-GMO Project, Fair Trade, Certified Humane,
Regenerative Organic, Demeter, Glyphosate Residue Free, Rainforest Alliance,
MSC/ASC/BAP → 1.0. None → 0 (Tier-1 unknown).

### S9 · Organic (headline-risk categories: tea, breads/oats, high-risk plant milks)

`en:organic` family in `labels_tags` → 1.0, else 0.

### S10 · Hero-ingredient density (plant milks, nut butters)

From hero `percent` (declared) or `percent_estimate` (× 0.75 trust factor):
> 15% → 1.0 · 10–15% → 0.80 · 5–10% → 0.50 · 2–5% → 0.20 · < 2% → 0.
`no percent data → 0.20` + Confidence hit.

### S11 · Origin transparency (tea, coffee, honey)

Disclosed single origin → 1.0 · "blend of various origins" → 0.60 · nothing
→ 0 (Tier-1).

### S12 · Nutrient quality **[NEW in v4 — restores positive nutrition]**

The v3 quality blocks, verbatim (per 100 g/ml, kcal < 5 guard applies):

```
protDens = min(1, (protein_g / (kcal/100)) / 15)     // protein per 100 kcal
fiber    = min(1, fiber_g / 8)
fvn      = min(1, fvn_estimate / 100)                // whole-food fraction
f(S12)   = 0.40·protDens + 0.35·fiber + 0.25·fvn
```

`kcal missing → protDens = 0` and Confidence hit; other components use what
exists. S12 joins every **food** profile (not water; tiny in tea/coffee). It
is also the primary lever for the build-muscle / lose-weight objectives (§7).

---

## 6. Category profiles (provisional weights — calibration tunes them)

Weights shown per rule; score = Σ(w·f)/Σw regardless of totals.

| Profile | Weights |
|---|---|
| **General packaged food** (fallback) — **calibrated, ruleset 2026.07-b2** | S1 28 · **S2 26** · S3 12 · S4 6 · S5 6 · **S12 18** · S7 5 · S8 3 |
| **Snacks** — **calibrated, ruleset 2026.07-b2** | S1 24 · **S2 26** · S3 14 · S4 10 · S5 9 · **S12 12** · S7 5 · S8 3 |
| **Drinks** (sodas, juices, kombucha, energy, RTD) — **calibrated, ruleset 2026.07-b2** | S1 28 · S3 22 (drink thresholds) · S6 12 · **S2 24** · **S12 5** · S7 8 · S8 5 |
| **Bottled water** | Water source 30 (mineral 1.0 · spring 0.80 · well 0.70 · purified/RO 0.40 · unknown 0 Tier-1) · S7 30 · S1 20 · Mineral profile disclosed 10 (Ca/Mg in `nutriments` → 1.0 else 0) · S8/labels 10 |
| **Plant-based milks** | S1 30 · S10 15 · Crop pesticide risk 12 (organic 1.0 · non-org low-risk crop 0.60 · non-org high-risk crop [oat/soy/rice/wheat/corn] 0.20 · rice base capped 0.40) · S3 12 · **S12 8** · S2 8 · S7 8 · S8 5 |
| **Dairy milk** (yogurt/cheese: S3 weight 15, yogurt thresholds) | S1 25 · Dairy quality labels 18 (organic +5 · grass-fed +5 · pasture-raised +5 · no-added-hormones +3 · Certified Humane +2, cap = rule max; Tier-1) · Processing 12 (vat 1.0 · pasteurized 0.85 · UHT 0.40 · ultra-filtered 0.25 · **raw 0.50 + mandatory safety chip**) · S3 10 · **S12 12** · S7 10 · S8 5 · Milk-fat level deliberately unscored (preference → Your Score) |
| **Tea & coffee (dry)** | S1 32 · S9 20 · Brew-contact material 20 (loose/whole-bean 1.0 · paper bags 0.85 · unknown bag 0.40 · "silken"/pyramid mesh 0.15 · nylon/PET 0 · plastic/alu pods 0.30 · compostable pods 0.70) · S11 10 · S2 8 · S8 5 · **S12 5** |
| **Sweeteners** | Type 25 (raw honey/pure maple/stevia leaf/monk fruit 1.0 · coconut 0.85 · turbinado 0.70 · brown 0.50 · white/agave 0.30 · corn syrup 0.15 · HFCS 0) · Authenticity 20 ("blend"/"flavored"/"syrup product" → 0) · S1 (filler calibration) 25 · Processing 10 · S7 10 · S8+S9 10 |
| **Breads & grains** | S1 35 · Whole grain 12 · Flour oxidizers 10 (none of E924/E927a in a full list → 1.0 · present → 0 · no list → 0.30) · S3 10 (bread thresholds) · S4 8 · S2 8 · **S12 12** · S7 4 · S8 4 |
| **Ice cream & frozen desserts** | S1 35 · Stabilizers 10 (per-item fractions scaled from v1.0) · S3 15 (ice-cream thresholds) · S5 5 (soft) · Dairy quality 8 (plant-based → neutral 0.5, never penalized for not being dairy) · S2 8 · **S12 7** · S7 5 · S8 5 |
| **Meat & seafood** | S1 40 (nitrites → Tier A) · Welfare & source 15 (label credits as v1.0; plant-based alternatives → neutral 0.47) · S2 12 · S4 8 · **S12 12** · S7 4 · S8 8 |

---

## 7. "Your Score" — personalization

Base answers "how good is this, on what we can verify?"; Your Score answers
"how good is this **for you**?" Both always shown; every delta decomposable
into chips.

### 7.1 Profile inputs — ALL discrete [DECIDED]

1. **Objective** (existing single-select, kept): build muscle · lose weight ·
   maintain · eat healthier.
2. **Health goals** (multi-select, fixed): blood sugar · heart/BP · gut
   health · pregnancy · young child · none.
3. **Diet pattern** (single): vegan · vegetarian · low-sodium · keto/low-carb
   · none.
4. **Allergens** — deterministic on-device matching, **never** in the class
   hash or the LLM prompt (unchanged from today).
5. **Avoid-list** — fixed checkbox vocabulary **[OPEN: final list]**,
   proposal: carrageenan · aspartame · sucralose · seed oils · palm oil ·
   caffeine · artificial colors · added phosphates · HFCS · titanium dioxide.
   No free text.
6. **Priority sliders** — 3 positions each (Low ×0.5 · Balanced ×1.0 · High
   ×2.0): clean ingredients · nutrition · packaging/environment · animal
   welfare.

### 7.2 Mechanics — weight multipliers, renormalized

```
YourScore = max(10, round( Σ (w_i × m_i × f_i) / Σ (w_i × m_i) × 100 ))
```

Provisional multiplier table **[OPEN: values to confirm in calibration]**:

| Input | Effect |
|---|---|
| Build muscle | S12 ×2.0 (protein component ×1.5 inside it) · S3 ×1.2 |
| Lose weight | S3 ×2.0 · S12 ×1.5 · S6 ×0.5 (zero-cal sweeteners matter less when cutting — preserves the "Coke Zero rises a little for weight loss" behavior) |
| Eat healthier | S2 ×1.5 · S1 ×1.3 · S12 ×1.2 |
| Maintain | all ×1.0 (Your Score ≈ Base) |
| Blood sugar | S3 ×2.0 · S2 ×1.3 · maltodextrin/HFCS hits in S1 ×1.5 |
| Heart/BP | S4 ×2.0 · S5 ×2.0 |
| Gut health | emulsifier/sweetener hits in S1 (E407, E433, E466, E471, E951, E955) ×2.0 |
| Packaging/env slider High | adds Eco-Score rule (w 15: A → 1.0 … E → 0) — **Your Score only, never Base** |
| Animal-welfare slider High | welfare/dairy-quality rules ×2.0 |
| Seed-oil avoidance (avoid-list) | seed-oil hits escalate Tier D → Tier B (honest: preference, not settled science) |

### 7.3 Hard gates (override the number; hierarchy top-down) [OPEN: cap values]

1. **Allergen match** (`allergens_tags`) → "Contains **milk** — Avoid"
   overlay, numeric score suppressed. `traces_tags` → amber "may contain"
   chip, score still shown.
2. **Diet-pattern conflict** (vegan user × non-vegan product, etc.) → Your
   Score capped at **20** (current behavior, kept).
3. **Avoid-list ingredient present** → capped at **49** + red chip naming it
   (softer than a diet conflict: "you said avoid, not can't-eat").
4. **Pregnancy mode** → informational public-health gates (raw milk,
   high-mercury seafood categories, alcohol, caffeine caution) — category-level
   guidance, UI copy must say it is not a measurement.
5. **Child mode** → S1 Tier C treated as Tier B, sugar ×2, honey-under-12-months
   and rice-arsenic caution chips.

### 7.4 ScoreClass / explanation-cache bucketing [DECIDED]

Every input above except allergens enters the `ScoreClass` hash exactly as
today (canonicalized string → SHA-256 → 16 hex). The discrete-inputs rule
keeps realized cardinality tiny (defaults dominate); the LLM is still paid
once per product × class × ruleset-version. **Approval rule for any future
input: discrete, few-optioned, score-relevant — or it stays out of the hash.**

### 7.5 Explanation chips + LLM

Chips derive from per-rule `(w·m·f)` deltas between Base and Your Score —
the same "single source" contract as today's signedFactors, so the `/explain`
pipeline (prompt, bucketing, EXPLANATION_VERSION) survives with a version
bump. Never show a personalized number the user can't decompose.

---

## 8. Worked example (recomputed — replaces v1.0 §7, which contained the scaling error)

**Product:** oat milk, non-organic, carton. Ingredients: water, oats (10%),
canola oil, dipotassium phosphate, gellan gum, salt, vitamins. NOVA 4. Sugars
4 g/100 ml (no added-sugars field). ~45 kcal, 1 g protein, 0.8 g fiber /100 ml.

Profile: plant-based milks. Σw = 98.

| Rule | w | f | w·f | Why |
|---|---|---|---|---|
| S1 | 30 | 0.82 | 24.6 | canola D −0.045 · phosphate C −0.09 · gellan D −0.045 (gum cap ok) → 1 − 0.18 |
| S10 | 15 | 0.80 | 12.0 | 10% oats declared |
| Crop risk | 12 | 0.20 | 2.4 | non-organic oat (high-risk crop) |
| S3 | 12 | 0.60 | 7.2 | fallback: total sugars 4 g/100 ml, fvn ≈ 0 (oats aren't fvn) → partial |
| S12 | 8 | 0.09 | 0.7 | protDens 0.15 · fiber 0.10 · fvn 0 |
| S2 | 8 | 0.00 | 0.0 | NOVA 4 |
| S7 | 8 | 0.70 | 5.6 | carton |
| S8 | 5 | 0.00 | 0.0 | none |
| **Σ** | **98** | | **52.5** | |

`raw = 52.5 / 98 × 100 = 53.6` → **Base 54 · "Good" band (Yuka-aligned
75/50/25) · Confidence High** (every rule had data; S3 chip notes the
total-sugar fallback).

Sanity check vs. v1.0: same product landed 54 there too — but there it read
"Poor" and the S1 math inside was wrong in a way that grows with every
non-45-weight category. Here the math has no scaling step, and the harshness
comes from weight calibration (no severity caps — §3.5) rather than band
lettering.

Personalization spot-checks: a **lose-weight** user (S3 ×2, S12 ×1.5, S6 ×0.5)
→ ≈ 55 (+1: low sugar helps, weak nutrition holds it back). A **gut-health**
user (emulsifier hits ×2) → ≈ 50, chip: *"−4 · emulsifiers weigh double for
your gut-health goal."*

---

## 9. What this replaces in the current codebase (impact map)

- `ScoringEngine.swift` — v3 blocks/adjustments engine → v4 rule engine
  (S-rules as pure functions over a `Product`, profiles/weights from the
  ruleset). S12 reuses the existing block math verbatim.
- `Product` model — grows: labels, packaging, origins, ingredient percents,
  added-sugars, eco-grade, completeness, last-modified, serving, category
  route + confidence + per-rule breakdown (for chips). All optional/back-compat.
- `ScoreClass` — new fields (goals, pattern, sliders, avoid-list), same
  mechanism. Cardinality guarded by §7.4.
- `/explain` contract — factors now derive from rule deltas; bump
  `EXPLANATION_VERSION`; key gains the ruleset version.
- Backend `/lookup` — extended OFF field list; `product:v2:` KV keys; serves
  the ruleset version + JSON (§10).
- UI — one band definition source; Data Confidence chip; insufficient-data
  state; recategorize control; methodology page rewrite ("Active ruleset:
  YYYY.MM", no-lab-data honesty, ODbL attribution).
- Tests — `ScoringEngineTests` v3 expectations retired, replaced by the
  anchor suite (§12) + per-rule unit tests + router tests.

---

## 10. JSON ruleset (on-device, versioned) [DECIDED]

Engine logic = Swift, shipped via App Store. All *tunable data* = one JSON
document, bundled as default and background-refreshed:

```jsonc
{
  "version": "2026.07",
  "bands": { "excellent": 80, "good": 60, "ok": 40 },   // floor is engine-fixed at 10
  "additiveTiers": { "en:e171": "A", "en:e407": "B", "en:e955": "C", "en:e415": "D", ... },
  "tierFractions": { "A": 0.33, "B": 0.18, "C": 0.09, "D": 0.045 },
  "ruleParams": { "S3": { "drinks": [1, 4, 8] }, "S4": [120, 400, 800], ... },
  "profiles": { "plant_milk": { "S1": 30, "S10": 15, "cropRisk": 12, ... }, ... },
  "router": [ { "match": "en:waters", "profile": "water" }, ... ],
  "multipliers": { "lose_weight": { "S3": 2.0, "S12": 1.5, "S6": 0.5 }, ... }
}
```

Refresh flow: on launch, a **detached background task** (never awaited on the
launch or scan path) asks the Worker for the current version (~100 B, edge-
cached); on mismatch it downloads the ruleset (a few KB), stores it, and it
applies from the next scan. Offline ⇒ silent skip, existing ruleset keeps
working; the bundled default guarantees first-launch-offline works. The
ruleset version is part of the explanation cache key, so scores and cached
explanations always match the math that produced them.

---

## 11. Latency & offline guarantees (engineering contract)

- Scoring is synchronous, on-device, offline — as today.
- Ruleset refresh is fire-and-forget; **any spinner attributable to remote
  config is a bug**.
- History rescoring on profile change stays on-device and instant.
- A client at ruleset N−1 is *correct as of N−1*; staleness is bounded by
  launch frequency and is acceptable by design (rulesets change ~monthly).

---

## 12. Calibration & band placement (Phase-B gate) [DECIDED process, OPEN outcome]

1. **Corpus:** OFF daily dump (never the API for bulk — OFF policy), filtered
   to target-market `countries_tags` + RMP-satisfying products; ~5–10k sample
   across all router categories.
2. **Run:** the reference implementation (same engine + ruleset the app
   ships) scores the corpus; output = product, category, raw, confidence.
3. **Inspect:** distributions overall and per category (medians, clusters,
   category bunching — e.g. "all waters ≥ 85" or "all snacks ≤ 45" means that
   profile's weights need work, not the bands).
4. **Anchor list** (acceptance criteria, becomes an automated golden-test
   suite) — Yuka-aligned expectations: rolled oats, chicken breast, apple,
   plain Greek yogurt, canned beans, olive oil → **Excellent/Good (75+)** ·
   white bread, granola bar, flavored yogurt → **Mediocre (25–49)** · Coke
   Zero, Cheetos, gummy candy, regular soda, maple-flavored corn syrup →
   **bottom bands**, with S1 tier fractions plus rebalanced NOVA/S12 weights
   doing the work (no severity caps — §3.5). Distribution target: the median
   mainstream ultra-processed product lands in the **bottom half**. **[OPEN:
   extend to ~25–30 products during Phase B.]**
5. **Tune weights → rerun** (2–3 iterations typical). Fixes go to weights and
   rule params; bands are placed **last**, where the wholesome/junk clusters
   actually sit on a centered scale.
6. **Freeze:** weights + bands lock into ruleset `2026.MM`; the distribution
   snapshot is stored so every future ruleset change ships with a diff
   ("moves median snack −4; changes bands for 12% of corpus").

### 12.7 First calibration run — 2026-07-11 (ruleset 2026.07-b2)

- **Corpus:** 8,157 unique EN-market products sampled from the official OFF
  dataset (HF parquet via the rows API — dump channel, not the product API);
  7,250 scored, 907 failed the minimum-data requirement (11% — validates the
  RMP gate).
- **Change:** NOVA (S2) promoted to the second-biggest rule in all three
  Phase-B profiles; S1 reduced, S12 raised (tables in §6).
- **Results (baseline → b2):** NOVA-4 share below 50: 37.6% → **81.8%**;
  NOVA-4 median 53 → **40**; whole foods (NOVA 1–2) median 82 → **81**, share
  ≥60 92.8% → 88.6% — harshness achieved almost entirely without collateral
  damage to real food.
- **Anchors (baseline → b2):** chicken 84→83 · apple 84→83 · oats 88→87 ·
  yogurt 84→83 (all Excellent) · white bread 62→**49** · cheese puffs
  57→**43** · cola 43→**33** · cola zero 45→**39** · gummy candy 42→**33**.
- **Bands kept at 75/50/25** — the harsh distribution came from weights, so
  band placement needed no change from the Yuka-aligned provisional set.
- Reference implementation: `scratchpad/calibrate.py` mirror of the Swift
  engine, driven by the identical RulesetV4.json; Swift anchor tests updated
  to the b2 numbers (`ScoringV4Tests`).

---

## 13. Data-gap rescue (adopted from the follow-up analysis, EN-market scoped)

- **Insufficient-data state** (§3.3) prompts the user to photograph the label.
- **v4.1 — OCR rescue:** on-device OCR (Vision) extracts ingredients +
  nutrition from the photos → provisional score immediately → photos/data
  contributed back to OFF via its write API (app account; OFF's own
  recommended flow). Turns OFF's gaps into a contribution loop (ODbL-aligned).
- **v4.1 — sibling-barcode inheritance:** when another barcode of the same
  product (same country via `countries_tags` + same brand + normalized name)
  has complete data, offer "inherit from the 350 ml version" with a visible
  provenance label and Confidence capped at Medium. **Never inherit across
  countries** (formulations differ — e.g. the same soda brand uses different
  sweetener systems per market).

---

## 14. Open items for team sign-off

| # | Item | Proposal on the table |
|---|---|---|
| 1 | Band cutoffs | Yuka-aligned 75/50/25 provisional; locked after §12 |
| 0 | ~~Severity caps~~ | **Resolved 2026-07-11: not adopted** — bands only; harshness via weights/calibration (§3.5) |
| 2 | Avoid-list vocabulary | 10-item list in §7.1 |
| 3 | Multiplier values | Table in §7.2; validated during calibration |
| 4 | Hard-gate cap values | 20 (diet conflict) / 49 (avoid-list) |
| 5 | Profile weights | §6 tables; calibration tunes |
| 6 | Anchor list (full ~25–30 products) | Seed list in §12.4 |
| 7 | Keep or drop the search "browse categories" ↔ router category naming alignment | (small UX consistency question) |

## 15. Known limitations & roadmap (carried from v1.0, amended)

- **No lab data** — scores reflect label-level signals; say it plainly in the
  methodology page. "Sage Verified" (indexed brand COAs/lab reports) remains
  the v2 lab layer; until then, don't fake it.
- **`added-sugars` is mostly US** — fallback is flagged, and fvn-discounted.
- **`percent_estimate` is a heuristic** — 0.75 trust factor.
- **Stale data** — surface `last_modified_t` ("data updated X months ago").
- **Wrong category tags** — recategorize control + logs.
- **Contested science** (seed oils, NNS) — small in Base, explicit opt-in
  escalation in Your Score.
- **Descoped, kept for LATAM expansion:** PT-BR/INS ingredient-text additive
  detection layer; per-country formulation handling beyond the
  never-inherit-across-countries rule.
- **Licensing:** OFF is ODbL — visible attribution required; share-alike
  likely applies to any republished derived database. Confirm with counsel
  before launch. Scoring *ideas* from third-party systems aren't
  copyrightable, but all user-facing prose must be Sage's own (this document
  complies).

## 16. Phased implementation plan

- **Phase A — data foundation.** Extended OFF fields end-to-end (Worker
  fields + `product:v2` cache + iOS DTO/model), Confidence computation, RMP
  insufficient-data state. *No scoring change yet* — v3 keeps running.
- **Phase B — engine + first profiles.** v4 rule engine + JSON ruleset
  (bundled only), router + three profiles (general fallback, drinks, snacks);
  reference implementation + calibration run (§12); bands locked. Ships
  behind a ruleset flag once anchors pass.
- **Phase C — full profiles + ruleset refresh.** Remaining category profiles;
  Worker-served ruleset with background refresh; methodology page rewrite.
- **Phase D — personalization v4.** New profile inputs (discrete), multiplier
  engine, hard-gate hierarchy, ScoreClass v2, `/explain` factor derivation
  from rule deltas, EXPLANATION_VERSION bump.
- **Phase E — rescue loop.** OCR label capture + OFF write-back; sibling
  inheritance; recategorize control feeding router fixes.
