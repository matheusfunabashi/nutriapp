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
