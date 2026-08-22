# Sage — "Better Alternatives" feature spec

**Status: shipped (v1 2026-07, v2 gates 2026-08-22).** After every scan, show up to three products of the
same kind that score genuinely better. Grounded in the V5 engine + the
`TopRatedBuilder` / `SageCategory` infrastructure already in the repo.

Goals (from the product owner): **low latency · accurate/similar · genuinely
better.** Non-goals for v1: cross-category swaps ("candy bar → protein bar"),
collaborative filtering, LLM-generated picks.

---

## 0. Core decision — precompute, never live-search

Live OFF category search measured at **2.6s / 1.1s(503) / 2.5s** — too slow and
too flaky for a per-scan surface. Instead, alternatives are served from
**precomputed, pre-ranked, pre-gated per-shelf lists** built offline by
`TopRatedBuilder`, then re-scored on-device for the final comparison.

```
OFFLINE (build/cron)            DELIVERY                 ON SCAN (device, sync)
candidates.json  ──►  Top-      alternatives.json  ──►   map product → shelf
 (per shelf,          Rated      (versioned, bundled      + finest OFF tag
  scoring inputs)     Builder     default + bg-refresh)   ├─ re-score candidates
                     score+gate                           │   (RulesetStore.current)
                     +dedupe                               ├─ exclude self, margin
                     +rank                                 ├─ prefer shared tag
                                                           └─ top 3  (else hide)
```

Everything on the scan path is a local lookup + arithmetic → **sub-millisecond,
offline-capable**, same guarantees as scoring itself.

---

## 1. Category model

The 14 shelves already exist in `SageCategory` (soda, water, chocolate, cookies,
cereal, cheese, yogurt, bread, juice, chips, coffee, pasta, iceCream, babyFood).
Two functions to add on `SageCategory`:

```swift
extension SageCategory {
    /// OFF category tags (normalized, no `en:` prefix) that map to this shelf,
    /// most-specific-first — same exact-tag matching style as the ruleset router.
    static let shelfTags: [SageCategory: [String]]   // e.g. .juice: ["fruit-juices","juices",...]

    /// Which shelf a scanned product belongs to (first shelf whose tags the
    /// product's categories intersect), or nil if none of the 14 apply.
    static func shelf(for p: Product) -> SageCategory?

    /// The product's most-specific OFF tag within its shelf, for same-subtype
    /// refinement (e.g. "grape-juices"). nil when the shelf tag is the only match.
    static func anchorTag(for p: Product, shelf: SageCategory) -> String?
}
```

`shelfTags` is the one hand-maintained table; mine it from OFF the same way the
ruleset router tags were mined. Coarse shelf = coverage; `anchorTag` = precision.

---

## 2. Data schemas

### 2.1 Candidate record (`alternatives.json`)

Extends the current display-only `TopRatedProduct` with the **scoring inputs**
needed to re-score on-device (exactly the arguments of
`OpenFoodFactsService.mapCandidate`). Keep it to what the engine reads.

```jsonc
// alternatives.json — versioned, per shelf, per country
{
  "version": 1,
  "ruleset_version": "2026.07-v5.0.7",   // the ruleset the offline scores used
  "generated_at": "2026-07-20T00:00:00Z",
  "country": "us",
  "shelves": {
    "juice": [
      {
        "barcode": "0000000000000",
        "name": "…", "brand": "…", "image_url": "https://…",
        "precomputed_score": 78,          // Overall under ruleset_version (ordering hint only)
        "categories_tags": ["en:fruit-juices","en:grape-juices"],
        // --- scoring inputs (mapCandidate) ---
        "ingredients_text": "…",
        "additives_tags": ["en:e300"],
        "nova_group": 1,
        "nutriscore_grade": "b",
        "labels_tags": ["en:organic"],
        "nutriments": { "sugars_100g": 12.0, "proteins_100g": 0.5, ... }
      }
      // … top ~25 per shelf, gated + deduped + ranked
    ]
  }
}
```

Ship **~25 per shelf** (not 10) so the "better than scanned" filter has headroom.
Payload is a few KB/shelf; the whole file is small enough to bundle.

### 2.2 Runtime result

```swift
struct Alternative { let product: Product; let score: Int; let sharedTag: Bool }
// score = re-scored Overall (or Your Score in v2) under RulesetStore.current
```

---

## 3. On-device selection contract

> **v2 (2026-08-22 audit).** The v1 algorithm below still describes the shape;
> the gates in §3.5 are what actually decide a suggestion today. Rationale for
> each gate lives in the header of `Sage/Alternatives.swift`.

### 3.5 What a suggestion must clear (v2)

| # | Gate | Why |
|---|------|-----|
| 1 | **Evidence** — `TopRated.isEligible`: ingredients, known NOVA, a real nutrition table, rule confidence ≥ 0.80, no unknown core rule ≥ 20 w. | Thin OFF records score high *because* information is missing (the shipped soda shelf had a NOVA-less "Diet Mountain Dew" with an OCR ingredient list re-scoring **100**, suggested to every soda incl. Olipop 74; Tropicana OJ with no nutrition table 71; nuun caffeine *tablets* 61). Top Rated already gated this; Better Options never did. |
| 2 | **Market** — `countries` contains `us` **and** barcode evidence: UPC / UPC-E prefix 000–139, an ALDI-US / Lidl-US store-brand prefix, or (instant-noodle shelf only) an Asian import prefix. | OFF's community country tags leaked Hungarian Coke, Indian Thumbs Up, Polish Hortex, Hebrew juice, Latvian curd snacks, German oats and UK M&S crisps into the `us` pull. "Declared added sugars" was tried as a US-label signal and rejected (community-typed zeros on EU records). |
| 3 | **Safety** — no restriction conflict (engine `restrictions`), no allergen hit (`AllergenMatcher`), no avoid-list hit. | A nut-allergic or vegan shopper must never be handed almond butter / cottage cheese as a "better option". |
| 4 | **Fit** — same shelf, `SageCategory.isSwapCompatible` (form groups), not the scanned barcode or a size/region SKU (`TopRated.listKey`). | Cheddar → cottage cheese ×3, cookies → Larabar + oatcakes + energy bar, chocolate bars → baking bar / Lindt 100 %, Cheerios → raw rolled oats ×3, loaf → Ezekiel *tortillas*, pasta → ramen, apple juice → tomato juice, oat milk ↔ cow's milk, formula → fruit pouch. Forms: per-shelf tag + name-regex table in `SageCategoryShelf.swift`; non-suggestible forms (formula, baking chocolate, crackers/bars in cookies, lemon juice, popsicles, caffeine tablets). |
| 5 | **Better** — `axis ≥ baseline + 10`, preferring picks ≥ 55 ("Good"), margin-only fallback on junk shelves. Axis = **Your Score** when personalization is on (the number the page emphasizes), else Overall. | Rows used to show Overall in a "Your Score" pill next to a page built around Your Score. |
| 6 | **Useful** — one pick per brand, near-duplicate names collapsed, same anchor tag first, then same form, then score; max 3. | poppi cola ×2, Häagen-Dazs ×2, RXBAR ×3, Ezekiel ×3. |

Each pick carries `delta` (on the axis) and up to two `reasons`
(`AlternativeReasons`: less sugar / minimally or less processed / no or fewer
additives / no artificial sweeteners / less sodium / less saturated fat / more
protein / more fiber / no trans fat) — label-derived, thresholded per 100 g/ml
so 0.2 g vs 0.1 g never reads as "less sugar".

Routing fixes that rode along: `chips` no longer roots on `chips-and-fries`
(frozen fries got crisps), `instantNoodles` only on the instant family (plain
`noodles` / dehydrated soups / dried meals fell in), `babyFood` no longer
roots on `baby-milks` / `infant-formulas` (formula → `.noShelf`), `yogurt`
is matched before `milks` (kefir / yogurt drinks carry `dairy-drinks`), and
`milks` also roots on `milk-substitutes`.


```swift
enum Alternatives {
    /// Up to 3 same-shelf products that beat `scanned` by a margin, best first.
    /// Pure + synchronous; runs after the result screen renders.
    static func suggest(for scanned: Product,
                        from store: AlternativesStore = .current,
                        profile: UserProfile,
                        ruleset: RulesetV4 = RulesetStore.current) -> [Alternative]
}
```

Algorithm:

1. `shelf = SageCategory.shelf(for: scanned)` — nil ⇒ return `[]` (no shelf).
2. Load `store.candidates(for: shelf)`; if empty ⇒ `[]`.
3. For each candidate: `mapCandidate(...)` → `ScoringEngineV4.scoreProduct(_, for: profile, ruleset:)`.
   Keep only `.scored`; drop `.unsupported` / `.insufficientData`.
   **Compare axis v1 = `overallScore`** (universal). v2 switch to `yourScore`.
4. Exclude the scanned barcode and any brand+name near-duplicate of it.
5. Keep candidates with `score >= scanned.overallScore + MARGIN` (default `10`).
   **The `GOOD_FLOOR` (55) is a *preference*, not a hard gate** — apply it
   per-scan, not per-shelf:
   - First take the margin-passing candidates that also reach `GOOD_FLOOR`.
   - If that set is empty (junk shelves — soda, candy, where nothing is "Good"),
     **fall back to the margin-only set** so guilty-pleasure scans still get a
     less-bad pick. This is data-driven, so no shelf ever needs tagging as
     "junk". `MARGIN` / `GOOD_FLOOR` live in config, tunable without a release.
6. Rank: (a) `sharedTag` first (candidate shares `anchorTag(for: scanned)`),
   then (b) score desc, then (c) higher data confidence. Take top 3.
7. Empty result ⇒ render nothing (see §5).

Re-scoring on-device (step 3) is the key correctness move: it makes the
comparison **ruleset-version-consistent** with the live scan and unlocks
personalization for free. `precomputed_score` is only used offline to choose the
~25 shipped candidates.

---

## 4. Delivery

Mirror the ruleset exactly (`RulesetStore`): **bundle a default `alternatives.json`
+ background-refresh** from the worker, strictly-newer wins, offline = keep the
bundled copy.

- New `AlternativesStore` (parallels `RulesetStore`): bundled default, detached
  background refresh, `current` accessor, never on the scan path.
- New worker route `GET /alternatives` (behind `X-Sage-Key`, edge-cached) +
  `GET /alternatives/version`, served from a KV/asset copy — same shape as
  `/ruleset`. The file is data, so no Worker logic beyond serving it.

---

## 5. Behavior rules & empty states

- **Show suggestions:** a "Better options" **horizontal rail** under the
  score card (same shape as the Home "Top picks" rail — Scout-style), max 3
  compact cards (photo with the score ring in the corner · brand + name (2
  lines) · **one reason** "Less sugar"), each tappable → its own ResultView;
  "See all" in the header → `TopRatedListView` for shelves in
  `topRatedBrowse` — when `Alternatives.suggest` returns `.suggestions([...])`.
- **Show already-top line:** when the outcome is `.alreadyTopOfShelf` (shelf
  peers exist, but `baseline + MARGIN > max(live peer scores)`), render one
  positive line — seal icon + "Among the best <shelf> we've scored", tappable
  into the ranking when one exists. No empty suggestion cards.
- Selection runs in `.task` off the main thread (≈50 re-scores per shelf).
- **Hide entirely when:** `.noShelf` · `.unscored` · `.noBetterPeers` (shelf has
  peers but none clear the margin for a reason other than "already top").
- **Fire after** the result screen renders; never block score/scan.
- **One heading, "Better options"** — a margin-only pick in a junk shelf is still
  genuinely better than what they scanned, so no separate "less bad" copy in v1.
- **Margin/floor tunable** in the ruleset-adjacent config so they can move
  without an app release.

---

## 6. Offline generation pipeline

Implemented in `TopRatedBuilder/`:

1. **`generate_candidates.py`** — per shelf, pulls OFF products matching
   `SHELF_TAGS` + `countries_tags` for each market (US only since 2026-08-22;
   Top Rated and Better Options are US-only and the UK/CA rows were never
   surfaced), applies shelf hygiene (`SHELF_EXCLUDE` / `SHELF_NAME_EXCLUDE`),
   keeps `allergens_tags` / `ingredients_analysis_tags` / `countries_tags` /
   `unique_scans_n`, stamps `countries`, merges duplicate barcodes, emits
   `candidates.json`.
2. **`TopRatedBuilder`** — scores with the real engine + bundled ruleset,
   drops rows that fail the evidence gate (mirror of `TopRated.isEligible`)
   or lack US barcode evidence (mirror of `Alternatives.hasUSMarketEvidence`),
   keeps top **80 per shelf**, stamps `ruleset_version`, writes
   `alternatives.json`. Build it with `swiftc` for now (README: the Xcode
   target links PIL dylibs from `.imgenv` and won't launch).
3. **Regenerate on:** every ruleset version bump (enforced by
   `AlternativesSyncTests`) **and** a periodic OFF-freshness cadence (~monthly).
   See `TopRatedBuilder/README.md` for the two-country command.

---

## 7. Decisions & remaining edges

**Decided:**
- **Junk-shelf floor** — `GOOD_FLOOR` is a per-scan preference with a margin-only
  fallback (§3.5), so guilty-pleasure shelves still surface a less-bad pick.
- **Compare axis** — **Your Score** when `personalizeScoring` is on, Overall
  otherwise (v2, shipped 2026-08-22). Top Rated stays on Overall.
- **Empty-reason contract** — `Alternatives.suggest` returns
  `AlternativesOutcome`:
  - `.suggestions` — up to 3 peers clearing the +10 margin (US-market only).
  - `.alreadyTopOfShelf` — live peers exist, but none are ≥ `baseline + 10`
    *and* `baseline + 10 > max(peer scores)` (product is at/near the top).
  - `.noBetterPeers` — shelf exists / has candidates, but nothing clears the
    margin for other reasons (e.g. empty scored pool after gates).
  - `.noShelf` — `SageCategory.shelf(for:)` is nil (coffee excluded; water /
    alcohol / unknown categories).
  - `.unscored` — no Overall baseline (water/alcohol unsupported, table
    sweeteners).
  The older §5 gate ("already Good **and** shelf top-3") is **not** implemented;
  already-top is purely the margin vs max-peer comparison above.
- **Multi-country** — candidates carry `countries: ["us"]` / `["br"]` (or both).
  Selection is **US-only** (same as Top Rated): Brazilian-only peers are never
  suggested, even when they outscore US peers or the scan is a Brazilian EAN.
- **No-alternative categories** — coffee (shelf-excluded), water/alcohol
  (unsupported), table sweeteners (unscored) correctly hide the row via
  `.noShelf` / `.unscored`.

**Coverage beyond the curated shelves:**
Additional shelves (`nutButtersAndSpreads`, `snackBars`, `milks`, `fatsAndOils`,
`instantNoodles`) ship alongside the original twelve. Further growth can still
use on-demand OFF-tag anchoring + backend cache (see prior plan) for the long
tail.

**Remaining edge:**
- **Dedup strength** — OFF has many size/region SKUs of one product; reuse
  `TopRatedBuilder.dedupe`, and also exclude near-duplicates of the *scanned*
  item (same brand + normalized name) so we never recommend "the same thing".

---

## 8. Phasing

- **v1 (this spec):** curated precomputed shelves (US+BR), on-device re-score on
  **Overall**, margin gate with preferred floor, shared-tag preference,
  **US-only** suggestions, bundle+refresh delivery. Instrument scan→shelf hit-rate.
- **v1.5 (coverage):** on-demand OFF-tag anchoring + backend cache for scans
  outside curated shelves — coverage grows to real demand.
- **v2 (shipped 2026-08-22):** `yourScore` axis · evidence / market / safety /
  form gates · brand diversity · per-row reasons · "See all" hand-off.
- **v2.5 (next):** regenerate the dataset with the builder-side gates (US cap
  80, `allergens_tags` / `ingredients_analysis_tags` / `countries_tags` /
  `unique_scans_n` in the candidate schema) · per-form quotas at build time
  so every form has peers · more shelves (crackers, yogurt drinks, sauces,
  deli meat) · an engine-side confidence haircut so a thin record cannot
  score 100 in the first place.
- **v3:** embeddings (Cloudflare Vectorize) for cross-category swaps.

---

## 9. Test plan

- **Unit:** `SageCategory.shelf(for:)` routing (incl. new shelves + no-match) ·
  `anchorTag` precision · `Alternatives.select` margin/floor/region/top-3 ·
  `AlternativesOutcome` empty reasons — hand-built fixtures.
- **Sync:** `Sage/Alternatives.json` ≡ `backend/src/alternatives.json`;
  `ruleset_version` matches bundled ruleset.
- **Golden:** a fixed `alternatives.json` fixture → assert exact suggestions for
  a few scans (grape juice → better grape/fruit juices; a good yogurt →
  already-top or empty).
- **Version-consistency:** candidates carrying an older `ruleset_version` still
  compare correctly because they're re-scored under `RulesetStore.current`.
