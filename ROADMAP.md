# Sage — Project Handoff / Context

> Context doc for picking up work across sessions. Updated at the end of Phase 4a.

## What this is
**Sage** — a SwiftUI iOS app (target iOS 18.2) that scans food barcodes, looks them
up in Open Food Facts, and shows a universal **Overall Score** plus a personalized
**Your Score** with explanations, additive risk, and allergen warnings. A single
`AppStore` (`@EnvironmentObject`) backs the UI; custom overlay-stack navigation lives
in `ContentView`.

## Branch / commit state (nothing merged to `main` yet)
Each branch builds on the previous; all pushed to `origin`.

| Branch | Commit | Contents |
|---|---|---|
| `phase-1` | `2792f8f` | SwiftData persistence |
| `phase-2` | `de2e219` | Open Food Facts + barcode scanning |
| `phase-3` | `092532c` | Scoring engine |
| `phase-4-allergens` | `935bec5` | Allergen profiles + warnings ("Phase 4a") |

> Uncommitted: a `DEVELOPMENT_TEAM` signing ID in `project.pbxproj` (local Xcode setting).

## Phase status

| Phase | Status | Notes |
|---|---|---|
| **1 — Local persistence (SwiftData)** | ✅ Done | `@Model` records in `Persistence.swift`; `AppStore` loads/saves profile, products, history. Profile persists on every change. |
| **2 — Open Food Facts + barcode** | ✅ Done | `OpenFoodFactsService` (fetch + testable mapper), `Additives.json` (~90 E-numbers), live barcode detection. **Mapper tests passed.** ⚠️ Barcode scanning only testable on a real device. |
| **3 — Scoring engine** | ✅ Done | `ScoringEngine.swift`. Overall + Your Score. Tests written, **run not yet confirmed**. |
| **4a — Allergens** | ✅ Done | `AllergenMatcher.swift`, allergen UI in Dietary screen, warnings + disclaimer in ResultView. Deterministic (no LLM). Tests written, **run not yet confirmed**. |
| **4b — LLM explanations + cache** | ⏳ **Not started** | Designed in detail; **blocked on backend-hosting decision.** |
| **5 — Search** | ⏳ Not started | Connect Search tab to OFF search endpoint. |
| **6 — Edge cases/cleanup** | ⏳ Not started | Offline handling, dup-scan prevention, delete/clear history, optional Sign in with Apple. |
| **Later** | ⏳ | Frontend polish → Onboarding → Paywall (placeholders exist). |

## Key decisions already made
- **Data source:** Open Food Facts (free, no key). No premium OFF tier exists. Possible
  **commercial fallback** for coverage/images (Go-UPC, Nutritionix, FatSecret) —
  *layered behind OFF on cache-miss only*, not built. Go-UPC pricing: $74.95/5k,
  $245/45k, $795/450k requests/mo.
- **Persistence:** local-only SwiftData. Optional Sign in with Apple (not built).
- **Scoring:** Overall = Nutri-Score-anchored + NOVA/additives/trans-fat adjustments.
  Your Score = Overall + personalization swing (objective + preferences), **capped ±35**;
  restriction conflict **hard-caps to ≤20** + banner. Driven by **goal**, not age.
  (Open: optional light age nudges = "Option B".) 4 goals: `lose weight`, `maintain`,
  `build muscle`, `eat healthier`.
- **Allergens: deterministic, never LLM** (safety). Top-8 allergens + free-text. Warnings
  always paired with a "check the packaging / data may be incomplete" disclaimer.
  Allergen matches **do not change the score** (binary safety signal).
- **Phase 4b LLM:** **GPT-4o-mini** chosen over Claude Haiku — task is a one-sentence
  explanation, quality is a wash, and GPT-4o-mini is ~7× cheaper (~$0.00008/call vs
  ~$0.00058). Build behind a **provider-agnostic `ExplanationProvider`** interface,
  **version-pinned model**, **`max_tokens` capped**. Keep rule-based templates as
  offline/fallback. LLM only fires on a meaningful score delta.
- **Caching (the cost lever):** bucket by a **`ScoreClass`** = hash of the score-relevant
  profile projection (objective + sorted preferences + sorted scoring-restrictions +
  toggles). Cache key = `version:barcode:classHash`. **Allergies excluded from the key**
  (kept deterministic → keeps cardinality low). Two layers: **on-device L1** (free,
  per-user) + **backend proxy shared L2** (cross-user reuse). Bump `version` to invalidate.
- **Product image:** OFF provides images (`image_front_url` etc.) — **not yet pulled into
  the app**; will need a fallback for missing/low-quality (keep existing emoji glyph).

## Open decisions (need team input before building 4b)
1. **Cache/key architecture:** on-device vs backend proxy. **Recommendation: both
   (L1 + L2).** Backend is required for key security + cross-user savings.
2. **Backend hosting:** **Cloudflare Workers + KV** (recommended: cheap, global,
   scale-to-zero) vs **Railway/Render + Redis** (simpler, always-on).
3. **Age in scoring:** keep goal-only (current) vs add light, capped age nudges
   (sodium/protein/sat-fat).
4. **Commercial DB fallback:** whether to add Go-UPC/Nutritionix/FatSecret behind OFF
   for coverage + better images.

## What's missing / next steps
- Build **Phase 4b** once #1–#2 above are decided (provider interface → backend proxy →
  2-layer versioned cache → async wiring so the explanation streams into an already-
  rendered result).
- **Product images** on the result page (add image field to OFF fetch + async load +
  fallback).
- **Phase 5 (Search)**, **Phase 6 (edge cases)**, onboarding, paywall.
- **Confirm test runs** for Phase 3 + 4a (see below) — the simulator kept choking; only
  Phase 2 mapper tests are confirmed green.

## How to run the tests
```bash
cd /Users/matheusfunabashi/Downloads/nutriapp
xcodebuild test -project nutriapp.xcodeproj -scheme nutriapp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:nutriappTests
```
Or run via Xcode `⌘U` (clearer output). If slow/flaky, free disk: `xcrun simctl delete unavailable`.
Test files: `OpenFoodFactsMappingTests` (passed), `ScoringEngineTests`, `AllergenMatcherTests`
(run pending). The app itself **builds cleanly** on all branches — only the test
*execution* is unconfirmed for 3 & 4a.

## File map
- `ScoringEngine.swift` — Overall + Your Score logic
- `OpenFoodFacts.swift` — service, mapper, `AdditiveCatalog`, OFF DTOs
- `Additives.json` — E-number → name/risk/note
- `AllergenMatcher.swift` — `AllergenCatalog` + matching
- `Persistence.swift` — SwiftData `@Model` records
- `Theme.swift` — `AppStore` (persistence-backed facade) + theme tokens
- `ContentView.swift` — root coordinator, scan flow, lookup overlays
- `ResultView.swift` — score page, nutrients, additives, allergen banners
- `ProfileSubScreens.swift` — Dietary (restrictions/preferences/allergens), Objective, etc.
- `ScoreClass` — **designed but NOT in repo yet** (the cache-bucket logic for 4b)
