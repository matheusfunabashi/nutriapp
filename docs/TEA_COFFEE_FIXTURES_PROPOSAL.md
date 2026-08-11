# Task 3 — Tea & Coffee: fixture proposal (NOT yet implemented)

**Status: proposal awaiting review.** Per the handoff working rules, fixtures and
expected ranges are proposed *before* implementation. Nothing in this document
is wired into the engine. Every "today" score below is measured on the current
engine at `feat/drinks-packaging-badge` (post-Track-2, post-F1), not estimated.

## What the probe changed about Task 3's premise

The handoff assumed `tea_coffee` was an RTD profile to be built. It is not:

- `tea_coffee` is a **dry-goods** profile (beans, ground, instant, loose tea)
  with its own weights (S1 28, S2 24, brewMaterial 12, S3 8 `foods`, S12 14, S14 14).
- RTD coffee/tea (`iced-coffees`, `coffee-drinks`, `iced-teas`) already routes
  to `drinks`.

So Task 3 is not "build a profile" — it is five targeted fixes across the two
existing paths, each born with its fixtures.

## Measured today (current engine)

| # | Fixture | Route today | Score today | What's wrong |
|---|---|---|---:|---|
| D1 | Ground coffee, NOVA 1, 500 g | `tea_coffee` | 73 | S12=0.00 drags −14; S14=0.55 for a single-ingredient product |
| D2 | Loose green tea, NOVA 1, 100 g | `tea_coffee` | 80 | same S12/S14 drag |
| D3 | Plain instant coffee, NOVA 4, 100 g | `tea_coffee` | 49 | same, plus full NOVA-4 S2 zero |
| D4 | Chicory substitute, NOVA 3, 200 g | `tea_coffee` | 58 | same |
| D5 | 3-in-1 sweetened mix, 60 g sugar/100 g powder | **`drinks` (bug)** | 20 | plausibility stub fires on a *powder*; engine invents a 355 ml liquid serving → "213 g sugar/serving" |
| R1 | RTD black cold brew, 355 ml, 149 mg caffeine | `drinks` | 57 | caffeine curve+cap calibrated for energy drinks; EFSA has no concern at this dose |
| R2 | RTD unsweetened latte, 330 ml, sugars 4.8 g/100 ml all lactose | `drinks` | 61 | lactose scored as free sugar; WHO excludes intrinsic milk sugars |
| R3 | RTD matcha latte, 330 ml, 7.5 g/100 ml (≈4.5 lactose + ≈3 added) | `drinks` | 33 | ditto — sugarCap binds on lactose it shouldn't count |
| R4 | RTD Frappuccino-class, 405 ml, 11 g/100 ml + 2.5 g/100 ml satfat | `drinks` | 20 | score OK, but cream is invisible (no satfat signal) — right answer, partly wrong reason |
| R5 | Mislabeled sweet RTD wearing dry-tea tags, 500 ml, 8 g/100 ml | `tea_coffee`→`drinks` rerail | 20 | already correct — pin it |

## Proposed mechanisms

**M1 — Liquid gate on plausibility reroutes.** The `tea_coffee` envelope
(`maxSugarGPer100ml: 5`) compares per-100 *g* of powder against a per-100 *ml*
liquid bound. Add `requiresLiquid: true` to the envelope: it fires only when the
product's size/serving parses as a volume. Dry mixes stay on the dry profile,
whose `foods` S3 variant already handles sugar per 100 g honestly. Fixes D5;
guards every future envelope (handoff: "every new envelope is born guarded").

**M2 — Lactose allowance in drinks S3 (RTD dairy only).** For RTDs with dairy
ingredient evidence (milk/leite/latte in ingredients): free sugar = max(0,
total − min(4.8 g/100 ml, total)). Trust `addedSugar` when present and sane
(≤ total). Config mirrored in both rulesets. WHO free-sugar definition excludes
intrinsic milk sugars; this is the same capped-discount pattern as the existing
FVN juice discount. Fixes R2/R3.

**M3 — Saturated-fat cap for drinks (data-present only).** Cream must be
visible: satFat per effective serving ≤2 g → no cap; 2→10 g linear 92→45;
≥10 g → 45. Named constants, cap-style like sugar/caffeine (missing data →
no cap, existing `lowDataConfidence` machinery). Keeps R4 at soda level for the
right reason; docks the latte class a few points for cream-heavy variants.

**M4 — Non-energy coffee/tea caffeine handling.** For RTDs with coffee/tea tags
where `energyDrinkEvidence` does NOT fire: a gentler S8 credit curve
(candidate anchors: 0→1.0, 80→0.95, 150→0.72, 250→0.40, 400→0) and the caffeine
cap starts at 200 mg instead of 60. EFSA: single doses ≤200 mg and ≤400 mg/day
without safety concern; moderate coffee/tea intake is neutral-to-favorable in
large cohorts. Energy drinks are untouched — the evidence gate outranks tags
(precedence already implemented in v2.4), so a stimulant-stacked product wearing
tea tags keeps the strict path. Fixes R1.

**M5 — Dry-goods S12/S14 correction.** S12 (micronutrients) is 0.00 for every
dry coffee/tea — data that will never exist for beans. Treat S12 as
`hadData=false` on `tea_coffee` (weight redistributes, the same mechanism S14/S15
already use elsewhere), and review the S14 Real Food misfire that gives a
single-ingredient "roasted ground coffee" only 0.55. Lifts D1–D4 out of a
systematic ~14-point hole.

## Proposed fixtures and ranges

Ranges assume M1–M5 land as described; candidate curve anchors get finalized
against these ranges at implementation time. **If a fixture cannot land in its
range without violating a mechanism's stated constraint (e.g. EFSA anchoring,
WHO lactose exclusion), STOP and report — do not bend the curve.**

| # | Fixture | Today | Proposed range | Mechanism |
|---|---|---:|---|---|
| D1 | Ground coffee NOVA 1 | 73 | **78–92** | M5 |
| D2 | Loose green tea NOVA 1 | 80 | **85–95** | M5 |
| D3 | Plain instant coffee NOVA 4 | 49 | **50–68** | M5 (S2 processing dock stays) |
| D4 | Chicory substitute NOVA 3 | 58 | **60–75** | M5 |
| D5 | 3-in-1 sweetened mix | 20 (fiction) | **25–40** | M1 → dry profile, `foods` S3 on 60 g/100 g |
| R1 | RTD black cold brew 355 ml / 149 mg | 57 | **88–96** | M4 |
| R2 | RTD unsweetened latte (lactose only) | 61 | **78–90** | M2 + M3 |
| R3 | RTD matcha latte (≈9 g added/serving) | 33 | **58–72** | M2 (added sugar still counts fully) |
| R4 | RTD Frappuccino-class | 20 | **12–20** | M3 reinforces sugarCap; must stay soda-class |
| R5 | Mislabeled sweet RTD, dry-tea tags | 20 | **15–22** | pin existing rerail + log format |
| — | Unsweetened iced tea (existing golden) | 99 | **95–100** | non-regression pin |

Resulting ladder (extends I23): tea 99 ≥ coffee ~93 > latte ~85 > matcha ~68 >
diet soda ~42 > Frappuccino/soda 20. Every step ≥5 points.

## Proposed invariants

- **I24** — an unsweetened, non-energy coffee/tea RTD (≤200 mg caffeine/serving)
  beats every diet soda by ≥30 points.
- **I25** — lactose-only latte beats Frappuccino-class by ≥30; lightly sweetened
  matcha sits strictly between them.
- **I26** — a product whose size does not parse as a liquid volume never
  produces a drinks breakdown with a liquid effective serving (kills the D5
  class of bug permanently).
- **I27** — `energyDrinkEvidence` outranks the gentle coffee curve: Red Bull
  wearing tea/chicory tags stays within 3 points of canonical Red Bull
  (extends I21 parity to the M4 path).
- **I28** — M2 never *raises* free sugar: for non-dairy drinks, scores are
  byte-identical with and without M2 (no-leak guard, like the F1 verification).

## Open design question (the one thing to decide at review)

R2 (plain latte) lands ~88 under M2+M3 — above kombucha (81). A milk coffee
beating kombucha is defensible (protein/calcium vs. residual sugar) but it is a
judgment call. If it feels too generous, the lever is M3's lower knee (2 g →
1.5 g/serving), which pulls the latte class to ~82–85 without touching anything
else. Decide at review, not mid-implementation.

## Out of scope for Task 3

- Erythritol tier promotion, acidity/dental signal, FVN-discount removal (F4 backlog)
- Stacking-drag continuous-function refactor (F3)
- Brew-material data coverage for tea bags (uses existing rule as-is)

## Definition of done for Task 3

M1–M5 implemented with fixtures above green, I24–I28 passing, I1–I23 untouched,
rulesets byte-identical, rerail log format unchanged, `SCORING_V5.md` updated,
and the non-drinks suite showing zero new failures against a pre-change baseline.
