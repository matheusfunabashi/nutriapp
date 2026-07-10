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
