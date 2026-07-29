# Sage — "Better Alternatives" feature spec

**Status: DRAFT for build.** After every scan, show up to three products of the
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

- **Show suggestions:** a "Better options" row under the score card, max 3 cards
  (image · name · brand · score pill), each tappable → its own ResultView —
  when `Alternatives.suggest` returns `.suggestions([...])`.
- **Show already-top chip:** when the outcome is `.alreadyTopOfShelf` (shelf
  peers exist, but `baseline + MARGIN > max(live peer scores)`), render a single
  positive line — checkmark + "Among the best in its category" — styled like the
  Organic ✓ chip. No empty suggestion cards.
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
   `SHELF_TAGS` + `countries_tags` for each market (`us`, `br` by default),
   stamps `countries`, merges duplicate barcodes, emits `candidates.json`.
2. **`TopRatedBuilder`** — scores with the real engine + bundled ruleset, keeps
   top **25 per shelf per country**, merges by barcode, stamps
   `ruleset_version`, writes `alternatives.json`.
3. **Regenerate on:** every ruleset version bump (enforced by
   `AlternativesSyncTests`) **and** a periodic OFF-freshness cadence (~monthly).
   See `TopRatedBuilder/README.md` for the two-country command.

---

## 7. Decisions & remaining edges

**Decided:**
- **Junk-shelf floor** — `GOOD_FLOOR` is a per-scan preference with a margin-only
  fallback (§3.5), so guilty-pleasure shelves still surface a less-bad pick.
- **Compare axis** — Overall for v1 (`yourScore` is v2).
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
- **v2:** `yourScore` personalization · finer within-shelf sub-tag clustering ·
  more countries.
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
