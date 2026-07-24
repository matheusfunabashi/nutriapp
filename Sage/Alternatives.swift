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

    enum CodingKeys: String, CodingKey {
        case barcode, name, brand, nutriments
        case imageURL = "image_url"
        case precomputedScore = "precomputed_score"
        case categoriesTags = "categories_tags"
        case ingredientsText = "ingredients_text"
        case additivesTags = "additives_tags"
        case novaGroup = "nova_group"
        case nutriscoreGrade = "nutriscore_grade"
        case labelsTags = "labels_tags"
    }
}

/// The versioned, per-shelf, per-country file the app ships + background-refreshes.
struct AlternativesFile: Decodable {
    let version: Int
    let rulesetVersion: String?
    let generatedAt: String?
    let country: String?
    /// shelf id (`SageCategory.rawValue`) → ranked candidates.
    let shelves: [String: [AlternativeCandidate]]

    enum CodingKeys: String, CodingKey {
        case version, country, shelves
        case rulesetVersion = "ruleset_version"
        case generatedAt = "generated_at"
    }

    static let empty = AlternativesFile(version: 0, rulesetVersion: nil,
                                        generatedAt: nil, country: nil, shelves: [:])
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
    var id: String { product.id }
}

/// The two fields the pure selection step needs — lets `select` be unit-tested
/// with lightweight mocks, decoupled from the scoring engine.
protocol RankableAlternative {
    var score: Int { get }
    var sharedTag: Bool { get }
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

    /// Convenience entry point for the UI (reads the shared stores on the main actor).
    @MainActor
    static func suggest(for scanned: Product, profile: UserProfile) -> [Alternative] {
        guard let shelf = SageCategory.shelf(for: scanned) else { return [] }
        return rank(scanned: scanned,
                    candidates: AlternativesStore.candidates(for: shelf),
                    anchorTag: shelf.anchorTag(for: scanned),
                    profile: profile,
                    ruleset: RulesetStore.current)
    }

    /// Pure core (no global state) — the §3 algorithm. Testable in isolation.
    static func rank(scanned: Product,
                     candidates: [AlternativeCandidate],
                     anchorTag: String?,
                     profile: UserProfile,
                     ruleset: RulesetV4) -> [Alternative] {
        // Unscored scans (water/alcohol/sweeteners) have no baseline to beat.
        guard let baseline = scanned.overallScore else { return [] }
        let scannedKey = dedupeKey(brand: scanned.brand, name: scanned.name)

        var pool: [Alternative] = []
        for cand in candidates {
            if cand.barcode == scanned.id { continue }          // exact same product
            guard let (p, score) = scored(cand, profile: profile, ruleset: ruleset) else { continue }
            // Never recommend a different SKU of the scanned product itself.
            if dedupeKey(brand: p.brand, name: p.name) == scannedKey { continue }
            let shared = anchorTag.map { p.categories?.contains($0) ?? false } ?? false
            pool.append(Alternative(product: p, score: score, sharedTag: shared))
        }
        return select(baseline: baseline, from: pool)
    }

    /// Map a precomputed candidate to a scored (product, Overall) pair under the
    /// given ruleset, or nil when it doesn't score. Shared by Alternatives and
    /// Top Rated so both re-score candidates identically (version-consistent).
    static func scored(_ c: AlternativeCandidate, profile: UserProfile,
                       ruleset: RulesetV4) -> (product: Product, score: Int)? {
        let raw = OpenFoodFactsService.mapCandidate(
            barcode: c.barcode, name: c.name, brands: c.brand,
            ingredientsText: c.ingredientsText, additivesTags: c.additivesTags,
            nutriments: c.nutriments, nutriscoreGrade: c.nutriscoreGrade,
            novaGroup: c.novaGroup, imageURL: BackendService.productImageURL(barcode: c.barcode),
            categoriesTags: c.categoriesTags, labelsTags: c.labelsTags)
        guard case .scored(let p) = ScoringEngineV4.scoreProduct(raw, for: profile, ruleset: ruleset),
              let score = p.overallScore else { return nil }
        return (p, score)
    }

    /// Pure selection over already-scored candidates (§3.5–3.6): margin gate,
    /// "Good" preference with a margin-only fallback, same-subtype first, top N.
    /// Generic over `RankableAlternative` so it unit-tests without the engine.
    static func select<T: RankableAlternative>(baseline: Int, from pool: [T]) -> [T] {
        let overMargin = pool.filter { $0.score >= baseline + margin }
        let good = overMargin.filter { $0.score >= goodFloor }
        let ranked = (good.isEmpty ? overMargin : good).sorted {
            $0.sharedTag != $1.sharedTag ? $0.sharedTag       // same-subtype first
                                         : $0.score > $1.score // then best score
        }
        return Array(ranked.prefix(maxResults))
    }

    /// Brand + name, alphanumerics only — collapses size/region SKUs of one product.
    private static func dedupeKey(brand: String, name: String) -> String {
        let s = (brand + name).lowercased()
        return String(s.unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }
}

// MARK: - Top Rated (TOPRATED_SPEC.md)
//
// The best-scoring products per category, ranked by Overall (same for every
// user). Reuses the Alternatives dataset + scoring — no new data or pipeline;
// candidates are re-scored on-device so the list matches the detail screen and
// the current ruleset.

enum TopRated {
    static let maxItems = 20

    /// Top-N products in a category, re-scored on-device (Overall), best first.
    @MainActor
    static func items(for shelf: SageCategory, profile: UserProfile) -> [Alternative] {
        items(from: AlternativesStore.candidates(for: shelf),
              profile: profile, ruleset: RulesetStore.current)
    }

    /// Pure core (no global state) — testable in isolation.
    static func items(from candidates: [AlternativeCandidate],
                      profile: UserProfile, ruleset: RulesetV4) -> [Alternative] {
        candidates
            .compactMap { c -> Alternative? in
                guard let (p, s) = Alternatives.scored(c, profile: profile, ruleset: ruleset)
                else { return nil }
                return Alternative(product: p, score: s, sharedTag: false)
            }
            .sorted { $0.score > $1.score }
            .prefix(maxItems)
            .map { $0 }
    }
}
