**Follow [design.md](design.md) for all UI work** — typography scale, color tokens, radii, spacing grid, and interaction rules. No raw hex values, off-scale font sizes, or ad-hoc radii in views.

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