# Sage — Project Handoff / Context

> Context doc for picking up work across sessions. Updated after backend + business-model planning.

## What this is
**Sage** — a SwiftUI iOS app (target iOS 18.2) that scans food barcodes, looks them
up in Open Food Facts, and shows a universal **Overall Score** plus a personalized
**Your Score** with explanations, additive risk, and allergen warnings. A single
`AppStore` (`@EnvironmentObject`) backs the UI; custom overlay-stack navigation lives
in `ContentView`.

## Business model (decided)
- **Free tier:** 1 scan/day, **Open Food Facts only** (never triggers paid APIs).
- **Premium tier:** unlimited scans; **OFF first, Go-UPC as fallback** when OFF lacks
  the product. Premium billed via StoreKit (Apple ID).

## Branch / commit state (nothing merged to `main` yet)
Each branch builds on the previous; all pushed to `origin`.

| Branch | Commit | Contents |
|---|---|---|
| `phase-1` | `2792f8f` | SwiftData persistence |
| `phase-2` | `de2e219` | Open Food Facts + barcode scanning |
| `phase-3` | `092532c` | Scoring engine |
| `phase-4-allergens` | `935bec5` (+`3c54f1d` roadmap) | Allergen profiles + warnings ("Phase 4a") |

> Uncommitted: a `DEVELOPMENT_TEAM` signing ID in `project.pbxproj` (local Xcode setting).

## Phase status

| Phase | Status | Notes |
|---|---|---|
| **1 — Local persistence (SwiftData)** | ✅ Done | `@Model` records in `Persistence.swift`. |
| **2 — Open Food Facts + barcode** | ✅ Done | `OpenFoodFactsService`, `Additives.json`. Mapper tests passed. ⚠️ Barcode only testable on a real device. |
| **3 — Scoring engine** | ✅ Done | `ScoringEngine.swift`. Tests written, run not yet confirmed. |
| **4a — Allergens** | ✅ Done | Deterministic (no LLM). Tests written, run not yet confirmed. |
| **3.5 — Scoring engine v2 (composite model)** | ⏳ **Planned — do next** | Richer Penalty/Quality/Driver model using kcal + fruit/veg estimate. Do **before 4b** so the LLM explanation reflects the final scoring. See "Scoring engine v2" section. |
| **4b — LLM explanations + backend** | ⏳ **Not started** | Backend proxy decided; hosting platform still open. See Backend section. |
| **5 — Search** | ⏳ Not started | Connect Search tab to OFF search endpoint. |
| **6 — Edge cases/cleanup** | ⏳ Not started | Offline handling, dup-scan prevention, delete/clear history. |
| **Later** | ⏳ | Frontend polish → Onboarding → Paywall (placeholders exist). |

---

> **⚠️ Scoring v4 is specced:** see [SCORING_V4.md](SCORING_V4.md) — a
> category-aware rule system (router + weighted fractional rules + Data
> Confidence + JSON rulesets) that will replace v3 below once the team signs
> off. v3 remains the shipped engine until Phase B of that plan completes.

## Scoring engine v3 — anchored modifier model (CURRENT, replaces v2)

Anchored scale: **100 perfect · 70 good · 50 neutral · 30 bad · 10 shouldn't eat
it** — scores are floored at 10, never 0. Same per-100g building blocks as v2,
restructured:

- **Overall (goal-neutral):** `clamp(50 + quality − penalty, 10, 100)` where
  quality = `14·protDens + 12·fiber + 14·fvn + 10·(1−procPen)` (max +50) and
  penalty = `12·sugarPen + 8·satPen + 8·sodiumPen + 6·upfPen + 4·additivesPen
  + 6·transPen`. New signals vs v2: **additive risk** (risk-weighted load from
  the Additives catalog) and **trans fats** (heaviest flat penalty) now enter
  the score; `upfPen` only punishes NOVA 4 (unknown NOVA is neutral).
- **Your Score = Overall + signed adjustments (capped ±20):** personalization
  *tunes* the universal number instead of recomputing it, so junk that floors
  both scores still shows a delta (fixes the "0 vs 0 → no explanation" hole).
  Goal drivers: muscle → protein density (centered, so low-protein foods dip);
  lose weight → calorie lightness **gated by sugar** (sugary drinks get no
  "light" bonus; zero-cal soda rises a bit) + satiety (protein/fiber) − sugar;
  eat healthier → fvn + fiber + processing (NOVA 4 dips) − additives.
  **Preferences now adjust too** (±4-level nudges: low sugar/sodium/fat, high
  protein/fiber, minimally processed; "Organic" has no data signal → inert).
- The adjustment list is the single source for the rule-based deltaReason AND
  the signed `/explain` factors, so the LLM only ever sees factors the score
  used. UI tiers rebanded: 80+ Excellent · 60+ Good · 40+ OK · else Bad.
- Validation (Overall/muscle/lose/healthy): chicken 73/85/82/78 · apple
  78/74/86/93 · Cheetos 34/32/31/30 · Coke Zero ~42, +7 for lose weight.
- Known limitation: plain water lands ~60 (no positive drivers) — revisit with
  a beverage-specific rule if it bothers users.

## Scoring engine v2 — composite model (SUPERSEDED by v3 above)

Team-proposed upgrade for better accuracy, **refined to cover all 4 goals**. Key rule:
**the goal/class only changes Score 2 (Your Score); Score 1 (Overall) is goal-neutral and
identical for everyone.** Pure on-device logic, no backend dependency. **Sequence before
Phase 4b** so the LLM explanation describes the final model.

**Base decision:** per-100g canonical (already used), plus ratio features (protein/kcal,
kcal/100g). Score the *food*, not the portion eaten — "how much you ate" is a separate
future logging layer.

**New OFF fields required (mapper fetches neither today):** `energy-kcal_100g` and
`fruits-vegetables-nuts-estimate-from-ingredients_100g` ("fvn" — discounts natural
fruit/veg sugar so an apple isn't penalized; also drives the "eat healthier" goal).

**Building blocks (each normalized 0–1):**
- `protDensScore = min(1, (protein / (kcal/100)) / 15)`  — protein per 100 kcal
- `lowEnergy = clamp((500 − kcal)/450, 0, 1)`
- `fiberScore = min(1, fiber/8)`
- `fvnScore = min(1, fvn/100)`  — fraction fruit/veg/nuts (whole-food signal)
- `sugarPen = min(1, sugars·(1 − fvn/100) / 25)`
- `satPen = min(1, satfat/10)`
- `sodiumPen = clamp((sodium_mg − 100)/700, 0, 1)`
- `procPen` (NOVA): 1→0, 2→0.2, 3→0.5, 4→1.0
- Guard: if `kcal < 5` → `protDensScore = 0`, `lowEnergy = 1`

**Composites (both goal-independent):**
- Penalty `P = 0.35·procPen + 0.25·sugarPen + 0.20·satPen + 0.20·sodiumPen`
- Quality `Q = 0.40·protDensScore + 0.35·fiberScore + 0.25·(1 − procPen)`

**Score 1 (Overall) — goal-neutral, same for everyone (LOCKED):**
`Score1 = clamp(round(100·(Q − 0.5·P)), 0, 100)`  (the no-driver baseline; equals the
"maintain" case below by construction). This composite **replaces** the current
Nutri-Score-anchored Overall.

**Score 2 (Your Score) — goal-dependent (the ONLY place the class matters):**
`Score2 = clamp(round(100·(w_d·D_goal + w_q·Q − w_p·P)), 0, 100)`

| Goal (app id) | Driver `D_goal` | w_d | w_q | w_p |
|---|---|---|---|---|
| `build muscle` | `protDensScore` | 0.55 | 0.45 | 0.45 |
| `lose weight` | `0.5·protDensScore + 0.3·lowEnergy + 0.2·fiberScore` | 0.50 | 0.50 | 0.55 |
| `maintain` | `Q`  (→ Score2 == Score1) | 0.50 | 0.50 | 0.50 |
| `eat healthier` | `0.40·fiberScore + 0.35·(1 − procPen) + 0.25·fvnScore` | 0.50 | 0.50 | 0.60 |

Notes: `lose weight` uses the fat-loss driver. `maintain` is goal-neutral, so its Score 2
equals Score 1. `eat healthier` (the new 4th goal) rewards whole-food signals (fiber, fvn,
low processing) and weighs Penalty highest (0.60) so ultra-processed / additive-heavy
items sink hardest.

**Validation (apple vs Cheetos vs chicken)** — the goal-tie is broken; apple beats Cheetos
even for muscle (Cheetos' NOVA4 + sodium + satfat penalty sinks its protein driver). The
`eat healthier` column is hand-estimated — confirm during calibration.

| | Muscle | Lose weight | Maintain | Eat healthier* | Overall (Score 1) |
|---|---|---|---|---|---|
| Chicken | 83 | 68 | 64 | ~49 | 64 |
| Apple | 19 | 37 | 37 | ~55 | 37 |
| Cheetos | 0 | 0 | 0 | 0 | 0 |

\*approximate

**Follow-ups after locking weights:** (1) calibrate against a reference food set (min-max
or smooth curve) — outputs cluster low/mid, under-using 0–100; (2) tune weights against
20–30 known foods until the ranking matches intuition.

**Decided (no open scope questions remain for this model):** Score 1 adopts the composite
`Q − 0.5·P` and **replaces** the Nutri-Score-anchored Overall; goal/class affects **only
Score 2**; all 4 goals have drivers.

**Integration impact:** rewrites `ScoringEngine.computeOverall` (→ composite Score 1) and
`computePersonal` (→ per-goal Score 2); LLM explanation factors come from these composites;
bump the explanation cache `version` when the model changes; carry over the restriction
hard-cap (≤20) + nutrient bonuses. Remaining tuning is calibration + weight-fitting only.

---

## Backend architecture (Phase 4b — decided to build a proxy)

A single backend service (the **proxy**) holds all API keys and fans out to **OFF,
Go-UPC, and the LLM**. It owns the shared cache (a database) and a thin admin surface
for the image backfill. Hosting platform is still open: **Cloudflare Workers + KV**
(cheap, global, scale-to-zero) vs **Railway/Render + Redis** (simpler, always-on).

### Database tables
| Table | Key | Holds |
|---|---|---|
| **`product`** | `barcode` | Cached product data (OFF *or* Go-UPC via `source`), `off_image_url`, `go_upc_image_url`, `image_source`, `has_off_image`, `quality_flag`, `go_upc_fetched`, `scan_count` |
| **`explanation_cache`** | `version + barcode + classHash` | LLM explanation text, `created_at` (the bucketed cache) |
| **`fetch_log`** | append-only | One row per *paid* call (`api` = go_upc/llm, `reason`, `ts`) — cost tracking + image-backfill counters |
| **`usage`** | `deviceId + day` | Free-tier daily scan count |

Notes: there is **no per-user scan table** — personal history lives on-device
(SwiftData). The explanation is **not** a column on `product` (one product has many
explanations, one per class). Go-UPC products are **not** a separate table — just
`product` rows with `source = go_upc`.

### Two-layer cache
- **L1 — on-device** (SwiftData): caches product, image, and the explanation **for the
  user's current class** (store `classHash`; profile change → mismatch → refetch).
  Re-scans are instant + offline.
- **L2 — backend shared** (`product` + `explanation_cache`): cross-user reuse.

### Cache key / bucketing — `ScoreClass`
Hash of the **score-relevant profile projection**: `objective` + sorted `preferences`
+ sorted scoring-`restrictions` + toggles. Cache key = `version:barcode:classHash`.
**Allergies are excluded** (deterministic, on-device) → keeps cardinality low.
Bump `version` to invalidate. `ScoreClass` is **designed but not yet in the repo.**

### Request flow (one scan)
```
1. App checks L1 (device): product + explanation for my class? hit → show instantly.
2. Miss → app calls proxy { barcode, classHash, isPremium, deviceToken }.
3. Proxy:
   a. Enforce free limit (usage table via DeviceCheck/App Attest identity).
   b. PRODUCT: check `product`. miss → OFF. If OFF miss AND premium → Go-UPC (log).
      Free + OFF miss → "not found / manual entry". Cache result.
   c. scan_count++ (popularity → image backfill).
   d. EXPLANATION: check `explanation_cache`. miss → if score delta meaningful →
      LLM (log), store, return. else rule-based template.
   e. IMAGE: OFF image if present, else placeholder. (Go-UPC image only if backfilled.)
4. Return { product, explanation, image }; app writes to L1 + local history.
```

### LLM provider
- **GPT-4o-mini** (chosen over Claude Haiku: same quality for a one-liner, ~7× cheaper).
- Behind a provider-agnostic **`ExplanationProvider`** interface; **version-pinned model**;
  **`max_tokens` capped**. Fires only on meaningful score delta + cache miss; rule-based
  templates are the offline/fallback path. **Async** — never blocks the result render.

### Identity / free-tier enforcement
- **DeviceCheck / App Attest** for device identity (iOS 11+/14+ — universal on iOS 18.2,
  no hardware gate). **No sign-in required.** Server-side `usage` table does the counting.
  ⚠️ Device-only (no Simulator); needs a DeviceCheck key from the Apple Developer portal.
- **Premium** via StoreKit (Apple ID) + App Store receipt / Server API validation in the
  proxy. Sign in with Apple now **optional** (only for cross-device sync/backup).

---

## Image strategy (decided)
- App shows **OFF image with a designed glyph placeholder fallback** ("no image" is a
  first-class state, not an error). Quality-gate OFF images by resolution; never promote
  a thumbnail to hero. Cache the image decision per barcode.
- **Don't auto-judge aesthetic quality** (unmeasurable). **Machine handles only the
  objective case (missing image)**; **humans flag low-quality** in an admin view.
- **Go-UPC image backfill** (premium-funded, popularity-ranked, manual-trigger):
  - Auto-eligible: top-N by `scan_count` with `has_off_image = false`.
  - Human-eligible: team flags `quality_flag = low_quality`.
  - Combined monthly cap; **you trigger runs manually**; cap enforced server-side via
    `fetch_log` counts. Idempotent (`go_upc_fetched`).
- **Launch plan:** do **not** fetch images at launch (no volume/data). **Instrument
  `scan_count` + `has_off_image` from day 1**, keep the Go-UPC fetch behind a flag, and
  **activate ~month 2** once data shows the gaps. Quota does **not** roll over month to
  month — pace by real bottleneck (human review), or burst-then-pause.

## Go-UPC notes
- Pricing: $74.95/5k, $245/45k, $795/450k requests/mo. Used **only on cache miss**, so
  cost ≈ unique *new* missed barcodes (not total scans).
- **Verify via trial key before committing:** (1) images are actually returned,
  (2) ToS permits **storing/caching** results (the whole cost model depends on it),
  (3) rollover/overage terms.
- Commercial alternatives if needed: Nutritionix, FatSecret (intl), Syndigo/1WorldSync
  (enterprise, best images).

---

## Open decisions
1. **Backend hosting:** Cloudflare Workers + KV vs Railway/Render + Redis.
2. **Age in scoring:** keep goal-only (current) vs add light capped age nudges
   (sodium/protein/sat-fat) — "Option B".
3. **Go-UPC vs alternatives** for the premium data fallback (pending trial evaluation).
4. **Sign in with Apple:** keep optional (DeviceCheck covers the free limit) vs adopt
   for sync/backup.

## What's missing inside the phase plan
- **Phase 4b** (LLM + backend proxy + 2-layer cache + `ScoreClass` + async wiring).
- **Product images** on the result page (add image field to OFF fetch + async load + gate + fallback).
- **Phase 5 (Search)**, **Phase 6 (edge cases)**.
- Confirm test runs for Phase 3 + 4a (only Phase 2 mapper tests confirmed green).

## Pre-deployment checklist (OUTSIDE the phase roadmap)
These are needed to actually ship but aren't part of the feature phases:
- **Paywall + StoreKit**: real `PaywallView` (currently a stub), StoreKit 2 purchase +
  restore, subscription products in App Store Connect, server-side receipt validation,
  **premium entitlement gating** (lock >1 scan/day, lock Go-UPC fallback behind premium).
- **Onboarding**: real flow (currently a stub) — welcome, profile setup (goal, dietary,
  allergens), DeviceCheck registration.
- **Backend deploy/ops**: pick host, CI/CD, secrets, monitoring, **cost alerts** for
  LLM + Go-UPC, rate limiting, DeviceCheck key setup.
- **App Store submission**: app icon, screenshots, listing, App Privacy details,
  age rating, export compliance.
- **Legal/compliance**: Privacy Policy + Terms (required w/ subscriptions), health/allergen
  disclaimer review (liability), OFF **ODbL attribution** + image (CC-BY-SA) attribution,
  Go-UPC ToS, GDPR/CCPA for backend-stored data.
- **Quality/observability**: crash reporting (Sentry/Crashlytics), analytics, accessibility
  (Dynamic Type, contrast, VoiceOver), TestFlight beta, real-device QA (camera + DeviceCheck).

## How to run the tests
```bash
cd /Users/felipeassis/Desktop/Sage
xcodebuild test -project Sage.xcodeproj -scheme Sage \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:nutriappTests
```
Or run via Xcode `⌘U`. Test files: `OpenFoodFactsMappingTests` (passed),
`ScoringEngineTests`, `AllergenMatcherTests` (run pending). App builds cleanly on all branches.

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
- `ScoreClass` — **designed, NOT in repo yet** (cache-bucket logic for 4b)
- **Backend / proxy — NOT in repo yet** (separate service: tables, cache, API fan-out)
