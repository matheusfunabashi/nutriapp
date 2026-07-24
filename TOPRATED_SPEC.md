# Sage — "Top Rated Items" feature spec

**Status: DRAFT for review.** A home-screen entry point → a grid of product
categories → the 20 best-scoring products in the chosen category, ranked by
**Overall** score (universal, same for every user).

The headline: **this is a UI-only feature.** The data, categories, scoring, and
navigation it needs already exist — nothing new is required in the backend, the
offline pipeline, or the scoring engine.

---

## 0. What already exists (and is reused as-is)

| Need | Already in the repo |
|---|---|
| The 14 categories | `SageCategory` (soda, water, chocolate, cookies, cereal, cheese, yogurt, bread, juice, chips, coffee, pasta, ice cream, baby food) — each with `displayName` + `emoji`. Created *for this feature* ("Browse / Top Rated categories"); currently consumed only by Alternatives. |
| The ranked product data | `AlternativesStore.current` — **12 shelves × 25 candidates**, already gated (data quality), deduped, and sorted by score, each carrying its scoring inputs. Bundled + background-refreshed from `/alternatives`. |
| Scoring on Overall | The candidates' `precomputed_score` is Overall under a neutral profile (= same for every user). Re-scoreable on-device via `mapCandidate` + `scoreProduct` under the current ruleset. |
| Tap → open a product | `ContentView.openAlternative(_:)` — caches an already-scored `Product` and pushes its `ResultView`. |
| Category → OFF routing | Not needed here; the data is already keyed by `SageCategory.rawValue`. |

**⇒ Top Rated = a new browse UI over `AlternativesStore`.** No new data file, no
new worker route, no new pipeline. (See §7 for the one small decision this hinges
on.)

---

## 1. Data source

Read directly from `AlternativesStore.candidates(for: shelf)` (the same store the
Alternatives feature refreshes). Per category:

```
topRated(shelf) = AlternativesStore.candidates(for: shelf)
                    .prefix(20)          // already sorted by score desc
```

Candidates carry `name`, `brand`, `image_url`, `precomputed_score`, and full
scoring inputs — enough for both the **list** (display) and the **tap-to-open**
(re-score → `ResultView`). No separate `top-rated.json` is needed; it is
superseded by `alternatives.json`, which is a superset (25 ≥ 20, plus inputs).

---

## 2. Categories

The grid shows `SageCategory.allCases`. But two of the 14 have **no data**:

- **water** → `unsupported` (Sage doesn't score water) — no top-rated list.
- **coffee** → deliberately shelf-excluded (`TopRatedBuilder` skips it, same team
  decision as water/alcohol) — no top-rated list.

So **12 of the 14 categories are populated.** [OPEN §7] decides whether the grid
hides these two or shows them with a "Not rated" empty state.

---

## 3. Screens & navigation

Add two cases to `ContentView.Overlay` and two SwiftUI views; push onto the
existing overlay stack.

1. **Entry point** — a "Top Rated Items" button/card on the home screen
   (`ScannerHomeView`), alongside Search / Scan. Tapping pushes `.topRated`.
2. **Category grid** (`TopRatedCategoriesView`) — a 2-column grid of category
   tiles (emoji + `displayName`), styled like the existing browse cards. Tapping
   a tile pushes `.topRatedCategory(shelf)`.
3. **Category list** (`TopRatedListView`) — a ranked list (1…20) of products in
   that category: rank + `ProductThumb` + brand + name + score pill (reuse the
   `AlternativeRow` / `HistoryRow` layout). Tapping a row opens its `ResultView`
   via `openTopRated(_:)` (a thin wrapper over the existing `openAlternative`).

```swift
enum Overlay {
    // …existing…
    case topRated
    case topRatedCategory(shelf: String)   // SageCategory.rawValue
}
```

---

## 4. Ranking & scoring

- **Axis: Overall.** Confirmed same for every user — no personalization, no
  profile dependence.
- **List:** show the candidates in stored order (already ranked by score). Show
  the score pill from a fresh on-device Overall re-score under
  `RulesetStore.current` (cheap; keeps the list number consistent with the detail
  screen and the current ruleset). [OPEN §7: re-score vs. trust `precomputed_score`.]
- **Rank number** = position in the sorted list (1…20).
- **Tap** re-scores the candidate under the current ruleset (so the detail matches
  a fresh scan), caches it, and opens `ResultView`.

---

## 5. Reused components (no new infra)

`SageCategory` · `AlternativesStore` · `OpenFoodFactsService.mapCandidate` ·
`ScoringEngineV4.scoreProduct` · `ProductThumb` · `YourScorePill` ·
`SectionTitle` · `AlternativeRow` layout · `ContentView.openAlternative` ·
the `Overlay` stack.

---

## 6. What's actually new to build (small)

1. `SageCategory` helper: `populatedForTopRated` (all cases minus empty ones) or
   a per-case `hasTopRated` flag.
2. `TopRated` reader: `TopRated.items(for: shelf, ruleset:)` → `[Alternative]`
   (re-score top 20; reuses `Alternatives`' mapping/scoring path — factor the
   shared "candidate → scored Alternative" step out of `Alternatives.rank`).
3. Home-screen button in `ScannerHomeView` + wiring in `ContentView`.
4. Two views: `TopRatedCategoriesView`, `TopRatedListView`.
5. Two `Overlay` cases + their `overlayView(for:)` arms.
6. Tests: category population (12 vs 14), list ordering/top-20 cap, empty-state
   for water/coffee. (Pure logic — same CLI-harness style as `AlternativesTests`.)

No backend, pipeline, or scoring-engine changes.

---

## 7. Open decisions

1. **Empty categories (water, coffee):** hide the two tiles, or show them
   disabled with a "Not rated yet" state? *Recommendation: hide* — cleaner, and
   consistent with Sage not scoring them. (Revisit coffee if the team ever
   un-excludes it.)
2. **List score = re-score vs. `precomputed_score`:** *Recommendation: re-score
   on-device* (cheap; the list number then always matches the detail screen and
   the current ruleset, even after a ruleset refresh).
3. **Home-screen placement/label:** button vs. card; "Top Rated Items" vs. "Top
   Rated" vs. "Browse". *Recommendation: a card under Scan/Search labeled "Top
   Rated".* [needs your eye]
4. **Count:** 20 per the request (data has 25, so headroom exists). Confirm 20.

---

## 8. Phasing

- **v1 (this spec):** home entry → 12-category grid → top-20 list → tap to detail,
  Overall, reusing `AlternativesStore`. US-only (the data is US-only today).
- **v2:** more categories as coverage grows (shared with Alternatives §7 of that
  spec); optional "sort/filter" within a category; multi-country.
