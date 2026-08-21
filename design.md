# Sage design system

Follow this file for all UI work. Every rule here is enforced by tokens in
code — if you find yourself typing a raw number or hex value into a view,
you're about to create drift; use the token or pick the nearest scale step.

## Typography

- **One family:** DM Sans (`SageTypeface`), four weights (regular, medium,
  semiBold, bold). DM Serif Display is bundled but unused in-app; personality
  belongs in marketing surfaces, not screens.
- **Closed size scale:** 10 · 11 · 12 · 13 · 14 · 15 · 16 · 18 · 20 · 22 ·
  24 · 28 (`.sageHeadline`) · 34 (`.sageDisplay`) · 88 (single hero numeral).
  Never introduce a new size — pick the neighbor.
- Every sized variant (`.sageBold(15)` etc.) is anchored to a system text
  style via `relativeTo:`, so Dynamic Type works app-wide. `sageFixedBold` /
  `sageFixedMedium` opt out deliberately and only for numerals inside fixed
  geometry (score rings), which carry their own accessibility labels.
- **Tabular numerals** (`.monospacedDigit()`) on every counter, score, timer,
  and stat that can change while visible.

## Color

All colors live in `Theme.swift`. **No hex literals in views.**

- Surfaces: `Theme.background`, `Theme.card`, `Theme.cardEdge`.
- Text: `Theme.ink`, `Theme.inkSecondary`.
- Grays (all dynamic light/dark): `Theme.hairline`, `Theme.outline`,
  `Theme.fillQuiet`, `Theme.fillMuted`, `Theme.fillTrack`, `Theme.ringTrack`.
  Never write `Color.black.opacity(…)` in a view — that's how an app ends up
  with six shades of gray.
- Brand: `Theme.accent`.
- Score semantics: `Color.scoreGood` / `.scoreOk` / `.scoreBad`,
  `ScoreBandColor.*` (mid variants for compact rings), `scoreColor(_:)` /
  `scoreTier(_:)` for band lookups. Bands are Excellent ≥75 · Good ≥55 ·
  OK ≥35 · Bad — a 55 ring is *green* by design.
- Domain ladders (Nutri-Score A–E, NOVA 1–4) keep their own palettes in
  `ResultView` — they are external grading scales, not theme colors.
- Onboarding inverted steps use `OnboardingInverted.*` — hard-coded
  white-on-green by design, not scheme-resolved.

Every token is a `Color(light:dark:)` pair. A color that only works in one
scheme is a bug; check both before shipping.

**Default appearance is light** (seed profile `appearance: "light"`) — a
deliberate product choice. Dark and System are user opt-ins in Preferences, so
dark mode must still be fully correct, it just isn't the default.

## Shape

- Corner radii come from `Theme.Radius`: `panel` 22 (hero cards, score
  panels), `card` 18 (standard cards), `control` 14 (inputs, banners, inner
  tiles), `chip` 8 (glyph squares, tags). Always `style: .continuous`
  (Apple's squircle curve — plain rounded rects read as web).
- Pill-shaped things are `Capsule()`, not a big radius.
- Tiny geometric accents (the 6pt NOVA bars) keep literal radii — they're
  shape, not corner rounding.

## Spacing

- 4pt base grid: 4 · 8 · 12 · 16 · 20 · 24 · 28 · 32 · 36 · 40. The 2pt
  half-step (2, 6, 10, 14, 18, 22) is allowed inside tight rows and chips.
- Odd values (3, 5, 7, 9, 13…) are drift. Snap to the neighbor.
- Screen gutters: 16pt for cards, 20–24pt for text blocks.

## Elevation & icons

- One shadow: `.cardShadow()` — the one card per screen that should read as
  raised. Dark mode gets none (shadows are invisible on near-black). Never
  decorate with ad-hoc `.shadow(…)`.
- One icon set: SF Symbols. No mixed icon libraries; product photos come from
  bundled `-tr` pack shots or `ProductThumb` (which owns the glyph fallback —
  "no image" is a designed state, never an error).

## Interaction

- Every tappable custom view uses `.pressable` (scale 0.96 + opacity dip) or
  sits in a `List` row that supplies its own highlight. A dead press reads as
  a broken interface.
- Haptics via `.sensoryFeedback` on meaningful actions only: scan outcome,
  favorite toggle, destructive clears, selection in onboarding.
- Minimum hit area 44pt (`minHitArea(44)` where the visual is smaller).
- Native chrome always: `NavigationStack`, `.navigationTitle`, `TabView`
  (5 tabs), `.sheet` + detents, `.alert`, `.searchable`, swipe actions,
  `ContentUnavailableView` for empty states.

## Screens with pinned CTAs

A pinned primary button must be a `.safeAreaInset(edge: .bottom)` on the
scroll container (with a background-colored gradient scrim), never a ZStack
overlay — content has to be able to scroll fully clear of the pill.

## Funnel priority (where polish effort goes first)

1. App Store icon + screenshots
2. Onboarding + paywall (the paywall template lives in the Superwall
   dashboard — price strings must have a loading/fallback state there)
3. First 10 seconds in-app: Home, scan flow, product detail header
4. Everything else
