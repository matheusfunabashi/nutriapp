import Foundation

// MARK: - "Better Alternatives" (ALTERNATIVES_SPEC.md)
//
// After a scan, surface up to three same-shelf products that score genuinely
// better. The candidate lists are precomputed offline (TopRatedBuilder) and
// carry their scoring inputs, so each is *re-scored on-device* under the
// current ruleset — the comparison is always version-consistent with the scan,
// and personalization is a v2 flip from Overall to Your Score (§3).
//
// Everything here is pure + synchronous; it runs after the result screen
// renders and never touches the network on the scan path.

// MARK: Precomputed candidate schema (alternatives.json)

/// One precomputed candidate. Fields mirror `OpenFoodFactsService.mapCandidate`
/// so a candidate can be turned into a scorable `Product` on-device.
struct AlternativeCandidate: Decodable {
    let barcode: String
    let name: String
    let brand: String?
    let imageURL: String?
    /// Overall under `rulesetVersion` — an offline ordering hint only; the live
    /// comparison always re-scores under the current ruleset.
    let precomputedScore: Int?
    let categoriesTags: [String]?
    let ingredientsText: String?
    let additivesTags: [String]?
    let novaGroup: Int?
    let nutriscoreGrade: String?
    let labelsTags: [String]?
    let nutriments: OFFNutriments?
    /// Markets this candidate was pulled for (`us` / `br`). Dual-listed products
    /// keep both tags after barcode merge.
    let countries: [String]?
    /// Offline verdict on the photo the app will display (`good` / `low` /
    /// `missing`, annotate_image_quality.py). Nil on pre-annotation datasets.
    let imageQuality: String?

    enum CodingKeys: String, CodingKey {
        case barcode, name, brand, nutriments, countries
        case imageURL = "image_url"
        case precomputedScore = "precomputed_score"
        case categoriesTags = "categories_tags"
        case ingredientsText = "ingredients_text"
        case additivesTags = "additives_tags"
        case novaGroup = "nova_group"
        case nutriscoreGrade = "nutriscore_grade"
        case labelsTags = "labels_tags"
        case imageQuality = "image_quality"
    }
}

/// The versioned, per-shelf, multi-country file the app ships + background-refreshes.
struct AlternativesFile: Decodable {
    let version: Int
    let rulesetVersion: String?
    let generatedAt: String?
    /// Legacy single-market stamp; prefer `countries` when present.
    let country: String?
    /// Markets represented in this file (e.g. `["us","br"]`).
    let countries: [String]?
    /// shelf id (`SageCategory.rawValue`) → ranked candidates.
    let shelves: [String: [AlternativeCandidate]]

    enum CodingKeys: String, CodingKey {
        case version, country, countries, shelves
        case rulesetVersion = "ruleset_version"
        case generatedAt = "generated_at"
    }

    static let empty = AlternativesFile(version: 0, rulesetVersion: nil,
                                        generatedAt: nil, country: nil,
                                        countries: nil, shelves: [:])
}

// MARK: Store (bundled default + background refresh — mirrors RulesetStore)

/// Where the last downloaded alternatives dataset is persisted between launches.
private func alternativesFileURL() -> URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                       in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("Alternatives.json")
}

@MainActor
enum AlternativesStore {
    private final class BundleToken {}

    private static func bundledFile() -> AlternativesFile {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "Alternatives", withExtension: "json")
                ?? Bundle.main.url(forResource: "Alternatives", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(AlternativesFile.self, from: data)
        else { return .empty }
        return file
    }

    /// Active dataset: the last downloaded copy when it's strictly newer than the
    /// bundled default, else the bundled default. Missing/corrupt ⇒ empty (the
    /// feature simply shows nothing), never a crash.
    private(set) static var current: AlternativesFile = {
        let bundled = bundledFile()
        if let data = try? Data(contentsOf: alternativesFileURL()),
           let file = try? JSONDecoder().decode(AlternativesFile.self, from: data),
           (file.generatedAt ?? "") > (bundled.generatedAt ?? "") {
            return file
        }
        return bundled
    }()

    static func candidates(for shelf: SageCategory) -> [AlternativeCandidate] {
        current.shelves[shelf.rawValue] ?? []
    }

    /// Detached background refresh (mirrors RulesetStore, never on the scan path):
    /// a cheap generated_at probe, then a full download only when the server's
    /// dataset is strictly newer. ISO-8601 timestamps sort chronologically, so a
    /// server briefly behind the bundle can never downgrade the app.
    static func refreshInBackground(backend: BackendService) {
        let localGeneratedAt = current.generatedAt ?? ""
        Task.detached(priority: .utility) {
            guard let remote = await backend.alternativesVersion(),
                  remote > localGeneratedAt,
                  let (data, file) = await backend.fetchAlternatives()
            else { return }
            try? data.write(to: alternativesFileURL(), options: .atomic)
            await MainActor.run { current = file }
        }
    }
}

// MARK: Runtime result

struct Alternative: Identifiable, Hashable {
    let product: Product
    /// Re-scored Overall under the current ruleset (v2: Your Score).
    let score: Int
    /// Candidate shares the scanned product's most-specific OFF tag (grape→grape).
    let sharedTag: Bool
    /// Markets this candidate belongs to (`us` / `br`).
    let countries: [String]
    var id: String { product.id }
}

/// Outcome of `Alternatives.suggest` — list plus empty-reason for the UI.
enum AlternativesOutcome: Equatable {
    case suggestions([Alternative])
    /// Scanned product already beats (or nearly matches) the best live peers.
    case alreadyTopOfShelf
    /// Shelf exists and has peers, but none clear the +10 margin.
    case noBetterPeers
    case noShelf
    case unscored
}

/// Market region helper (GS1 → coarse region). Kept for barcode diagnostics /
/// tests; suggestion selection is US-only and no longer prefers by scan region.
enum AlternativesRegion: String, Equatable {
    case us, br

    /// 789/790 → Brazil; everything else defaults to US for v1.
    static func from(barcode: String) -> AlternativesRegion {
        let digits = barcode.filter(\.isNumber)
        let padded: String
        if digits.count == 12 {
            padded = "0" + digits
        } else if digits.count == 14, digits.hasPrefix("0") {
            padded = String(digits.dropFirst())
        } else {
            padded = digits.count >= 13 ? String(digits.suffix(13)) : digits.padLeft(to: 13, with: "0")
        }
        guard padded.count >= 3, let prefix = Int(padded.prefix(3)) else { return .us }
        if (789...790).contains(prefix) { return .br }
        return .us
    }
}

private extension String {
    func padLeft(to length: Int, with char: Character) -> String {
        if count >= length { return self }
        return String(repeating: String(char), count: length - count) + self
    }
}

/// The fields the pure selection step needs — lets `select` be unit-tested
/// with lightweight mocks, decoupled from the scoring engine.
protocol RankableAlternative {
    var score: Int { get }
    var sharedTag: Bool { get }
    var countries: [String] { get }
}

extension Alternative: RankableAlternative {}

// MARK: Selection

enum Alternatives {
    /// A candidate must beat the scan by at least this much to be "better".
    static let margin = 10
    /// Preferred lower bound ("Good"). Applied as a per-scan preference, not a
    /// hard gate: junk shelves fall back to margin-only (§3.5, §7).
    static let goodFloor = 55
    static let maxResults = 3

    /// Markets Sage surfaces in Better Options — **US-only** (ALTERNATIVES_SPEC
    /// §8), matching Top Rated. The dataset also carries `uk`/`ca`/`br`
    /// candidates; they're filtered out here so only American products are
    /// suggested. (OFF records for foreign SKUs are often thin — missing
    /// additives/ingredients — which inflates their re-scored value, so a
    /// sparse UK energy drink could otherwise out-rank real US options.)
    static let allowedMarkets: Set<String> = ["us"]
    static func isAllowedMarket(_ countries: [String]?) -> Bool {
        !allowedMarkets.isDisjoint(with: countries ?? [])
    }

    /// Convenience entry point for the UI (reads the shared stores on the main actor).
    @MainActor
    static func suggest(for scanned: Product, profile: UserProfile) -> AlternativesOutcome {
        suggest(for: scanned,
                candidates: { shelf in AlternativesStore.candidates(for: shelf) },
                profile: profile,
                ruleset: RulesetStore.current)
    }

    /// Testable entry — inject candidates by shelf.
    static func suggest(for scanned: Product,
                        candidates: (SageCategory) -> [AlternativeCandidate],
                        profile: UserProfile,
                        ruleset: RulesetV4) -> AlternativesOutcome {
        guard scanned.overallScore != nil else { return .unscored }
        guard let shelf = SageCategory.shelf(for: scanned) else { return .noShelf }
        return rankOutcome(scanned: scanned,
                           candidates: candidates(shelf),
                           anchorTag: shelf.anchorTag(for: scanned),
                           profile: profile,
                           ruleset: ruleset)
    }

    /// Pure core (no global state) — the §3 algorithm + empty-reason (§7).
    static func rank(scanned: Product,
                     candidates: [AlternativeCandidate],
                     anchorTag: String?,
                     profile: UserProfile,
                     ruleset: RulesetV4) -> [Alternative] {
        switch rankOutcome(scanned: scanned, candidates: candidates,
                           anchorTag: anchorTag, profile: profile, ruleset: ruleset) {
        case .suggestions(let list): return list
        default: return []
        }
    }

    static func rankOutcome(scanned: Product,
                            candidates: [AlternativeCandidate],
                            anchorTag: String?,
                            profile: UserProfile,
                            ruleset: RulesetV4) -> AlternativesOutcome {
        guard let baseline = scanned.overallScore else { return .unscored }
        let scannedKey = dedupeKey(brand: scanned.brand, name: scanned.name)

        // Market-filtered (US-only): the dataset may carry other markets, but
        // suggestions (and empty-reason peers) stay US-market — same as Top Rated.
        var pool: [Alternative] = []
        for cand in candidates {
            guard isAllowedMarket(cand.countries) else { continue }
            if cand.barcode == scanned.id { continue }
            guard let (p, score) = scored(cand, profile: profile, ruleset: ruleset) else { continue }
            if dedupeKey(brand: p.brand, name: p.name) == scannedKey { continue }
            let shared = anchorTag.map { p.categories?.contains($0) ?? false } ?? false
            let countries = cand.countries ?? []
            pool.append(Alternative(product: p, score: score, sharedTag: shared,
                                    countries: countries))
        }

        let picks = select(baseline: baseline, from: pool)
        if !picks.isEmpty { return .suggestions(picks) }

        guard let maxPeer = pool.map(\.score).max() else { return .noBetterPeers }
        if baseline + margin > maxPeer { return .alreadyTopOfShelf }
        return .noBetterPeers
    }

    /// Map a precomputed candidate to a scored (product, Overall) pair under the
    /// given ruleset, or nil when it doesn't score. Shared by Alternatives and
    /// Top Rated so both re-score candidates identically (version-consistent).
    static func scored(_ c: AlternativeCandidate, profile: UserProfile,
                       ruleset: RulesetV4) -> (product: Product, score: Int)? {
        let primaryImageURL = Self.imageURL(for: c)
        let raw = OpenFoodFactsService.mapCandidate(
            barcode: c.barcode, name: c.name, brands: c.brand,
            ingredientsText: c.ingredientsText, additivesTags: c.additivesTags,
            nutriments: c.nutriments, nutriscoreGrade: c.nutriscoreGrade,
            novaGroup: c.novaGroup, imageURL: primaryImageURL,
            categoriesTags: c.categoriesTags, labelsTags: c.labelsTags)
        guard case .scored(var p) = ScoringEngineV4.scoreProduct(raw, for: profile, ruleset: ruleset),
              let score = p.overallScore else { return nil }
        // The backend slot can 404 (never-resolved barcode); keep the dataset's
        // own OFF photo as a fallback so the row degrades to a real photo.
        if let offURL = OFFImageResolver.upgradeToDisplaySize(c.imageURL), offURL != primaryImageURL {
            p.imageFallbackURL = offURL
        }
        return (p, score)
    }

    /// US products resolve to the good backend pack shot (`/images/…`,
    /// Kroger → OFF), the same source the scan detail uses — so Top Rated and
    /// Alternatives match it. Non-US products (e.g. Brazilian EANs) blank on the
    /// backend (Kroger skips them, lazy-resolve finds no OFF product), so they
    /// keep the perfectly good OFF url from `alternatives.json`.
    static func imageURL(for c: AlternativeCandidate) -> String {
        // US resolves on the backend; non-US markets blank there, so keep their
        // OFF url. (Non-US candidates are market-filtered out of display, so this
        // only guards stray callers.)
        if !isAllowedMarket(c.countries),
           let url = c.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            return url
        }
        return BackendService.productImageURL(barcode: c.barcode)
    }

    /// Pure selection over already-scored candidates (§3.5–3.6): margin gate,
    /// "Good" preference with a margin-only fallback, same-subtype first, top N.
    /// Market-filtered (US-only) — non-US peers are never suggested.
    static func select<T: RankableAlternative>(baseline: Int, from pool: [T]) -> [T] {
        let inMarket = pool.filter { isAllowedMarket($0.countries) }
        return selectMargin(baseline: baseline, from: inMarket)
    }

    /// Brand + name, alphanumerics only — collapses size/region SKUs of one product.
    private static func dedupeKey(brand: String, name: String) -> String {
        let s = (brand + name).lowercased()
        return String(s.unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    private static func selectMargin<T: RankableAlternative>(baseline: Int, from pool: [T]) -> [T] {
        let overMargin = pool.filter { $0.score >= baseline + margin }
        let good = overMargin.filter { $0.score >= goodFloor }
        let ranked = (good.isEmpty ? overMargin : good).sorted {
            $0.sharedTag != $1.sharedTag ? $0.sharedTag
                                         : $0.score > $1.score
        }
        return Array(ranked.prefix(maxResults))
    }
}

// MARK: - Top Rated (TOPRATED_SPEC.md)
//
// The best-scoring products per category, ranked by Overall (same for every
// user). Reuses the Alternatives dataset + scoring — no new data or pipeline;
// candidates are re-scored on-device so the list matches the detail screen and
// the current ruleset.
//
// Spec §8: US-only. The alternatives dataset is multi-market (`us` + `br`) so
// we must filter here — ranking every candidate would surface Brazilian
// products (often the top of a shelf) in a US-facing browse tab.

enum TopRated {
    /// A short list is the product: ten defensible picks per shelf, not a
    /// leaderboard that trails off into 40-point sodas.
    static let maxItems = 10

    /// Eligibility floor (stricter than "scoreable"): a Top Rated placement is
    /// an endorsement, so the score must rest on evidence, not on defaults.
    /// Confidence is the engine's weight-backed measure; `maxUnknownRuleWeight`
    /// tolerates systemic mid-weight unknowns (e.g. `dairyProcessing`, which no
    /// label can evidence) but never an unknown core driver (S1/S12-class).
    static let minConfidence = 0.80
    static let maxUnknownRuleWeight = 20.0

    /// Markets shown in Top Rated. US-only (TOPRATED_SPEC §8) — the dataset
    /// still carries UK/CA/BR candidates, but foreign SKUs on a US browse tab
    /// read as broken, and their barcodes never resolve to a clean backend
    /// pack shot (Kroger is US-only). Better Options is US-only too.
    static func allowedMarkets(for shelf: SageCategory) -> Set<String> {
        ["us"]
    }

    /// A candidate may appear in Top Rated only when its label data is complete
    /// enough to defend the ranking: ingredients, known NOVA, a real nutrition
    /// table, and rule evidence above the confidence floor. Products that score
    /// high *because* information is missing never clear this.
    static func isEligible(_ product: Product, ruleset: RulesetV4) -> Bool {
        guard product.hasIngredientData,
              product.hasKnownNova,
              product.hasNutritionData,
              let evidence = ScoringEngineV4.evidenceSummary(product, ruleset: ruleset)
        else { return false }
        return evidence.confidence >= minConfidence
            && evidence.maxUnknownWeight < maxUnknownRuleWeight
    }

    /// Top-N products in a category, re-scored on-device (Overall), best first.
    @MainActor
    static func items(for shelf: SageCategory, profile: UserProfile) -> [Alternative] {
        items(from: AlternativesStore.candidates(for: shelf),
              profile: profile, ruleset: RulesetStore.current,
              markets: allowedMarkets(for: shelf))
    }

    /// At most this many list slots per brand — a top list that is one third
    /// Häagen-Dazs SKUs reads as broken even when the scores are right.
    static let maxPerBrand = 2

    /// Pure core (no global state) — testable in isolation.
    ///
    /// Slots fill from candidates with a pack-shot-quality photo first (this
    /// is a visual browse surface; a kitchen-counter phone photo at #1 reads
    /// as broken), then top up from the rest so a shelf never goes empty over
    /// image quality alone. Un-annotated datasets (nil) count as good.
    static func items(from candidates: [AlternativeCandidate],
                      profile: UserProfile, ruleset: RulesetV4,
                      markets: Set<String> = Alternatives.allowedMarkets) -> [Alternative] {
        let pool = candidates
            .filter { !markets.isDisjoint(with: $0.countries ?? []) }
            .compactMap { c -> (alt: Alternative, goodImage: Bool)? in
                guard let (p, s) = Alternatives.scored(c, profile: profile, ruleset: ruleset),
                      isEligible(p, ruleset: ruleset)
                else { return nil }
                let alt = Alternative(product: p, score: s, sharedTag: false,
                                      countries: c.countries ?? [])
                return (alt, c.imageQuality.map { $0 == "good" } ?? true)
            }
            .sorted {
                if $0.alt.score != $1.alt.score { return $0.alt.score > $1.alt.score }
                // Score ties: US variant first (its barcode resolves to a real
                // pack shot), then stable by id.
                let lus = $0.alt.countries.contains("us"), rus = $1.alt.countries.contains("us")
                if lus != rus { return lus }
                return $0.alt.id < $1.alt.id
            }

        var seenProducts = Set<String>()
        var perBrand: [String: Int] = [:]
        var out: [Alternative] = []

        func fill(goodImage: Bool) {
            for (alt, good) in pool where good == goodImage && out.count < maxItems {
                let product = listKey(brand: alt.product.brand, name: alt.product.name)
                guard seenProducts.insert(product).inserted else { continue }
                let brand = listKey(brand: alt.product.brand, name: "")
                if !brand.isEmpty {
                    // Brand aliases share a bucket by prefix ("Quaker" and
                    // "Quaker Oats" are one brand); sorted scan keeps it
                    // deterministic.
                    let bucket = perBrand.keys.sorted().first {
                        $0.hasPrefix(brand) || brand.hasPrefix($0)
                    } ?? brand
                    guard perBrand[bucket, default: 0] < maxPerBrand else { continue }
                    perBrand[bucket, default: 0] += 1
                }
                out.append(alt)
            }
        }
        fill(goodImage: true)
        fill(goodImage: false)
        return out
    }

    /// Dedupe/brand key: diacritic-folded, unit/size tokens stripped,
    /// alphanumerics only — so "Flocons d'avoine complète 500 g" and
    /// "Flocons d'avoine complete" collide, and "Häagen-Dazs" == "Haagen-Dazs".
    static func listKey(brand: String?, name: String) -> String {
        let joined = ((brand ?? "") + " " + name)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
        let unitPattern = #"\b(\d+([.,]\d+)?\s*(fl\s*oz|fluid\s+ounces?|oz|ml|l|g|kg|lbs?|ct|pk)|pack|count|each)\b"#
        let stripped = joined.replacingOccurrences(of: unitPattern, with: " ",
                                                   options: .regularExpression)
        return String(stripped.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
