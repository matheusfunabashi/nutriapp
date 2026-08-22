import Foundation

// MARK: - "Better Alternatives" (ALTERNATIVES_SPEC.md)
//
// After a scan, surface up to three same-shelf products that score genuinely
// better. The candidate lists are precomputed offline (TopRatedBuilder) and
// carry their scoring inputs, so each is *re-scored on-device* under the
// current ruleset — the comparison is always version-consistent with the scan,
// and the comparison axis is the user's own score (§3.5 v2).
//
// Everything here is pure + synchronous; it runs after the result screen
// renders and never touches the network on the scan path.
//
// What a suggestion must clear (v2, 2026-08-22 audit — see ALTERNATIVES_SPEC
// §3.5 for the why behind each gate):
//   1. Evidence: `TopRated.isEligible` — ingredients, known NOVA, a real
//      nutrition table, rule confidence ≥ 0.80. A thin OFF record scores high
//      *because* information is missing (a Diet Mountain Dew with an OCR
//      ingredient list and no NOVA re-scored 100); it is never a recommendation.
//   2. Market: sold in the US. OFF's community country tags leak Hungarian
//      Coke and Polish tomato juice into the US pull, so a candidate also
//      needs barcode evidence (UPC / UPC-E, a US store-brand prefix, or an
//      Asian import prefix on the instant-noodle shelf).
//   3. Safety: no conflict with the user's restrictions, allergens or
//      avoid-list — a nut-allergic shopper is never handed almond butter.
//   4. Fit: same shelf, swap-compatible form (`SageCategory.isSwapCompatible`
//      — a loaf is not a tortilla, cheddar is not cottage cheese, cow's milk
//      is not oat milk), not the scanned product or a size/region SKU of it.
//   5. Better: beats the scan's score on the comparison axis by `margin`,
//      preferring picks that reach the "Good" band.
//   6. Useful: at most one product per brand, near-duplicate names collapsed,
//      same sub-type (anchor tag) first, then form, then score.

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
    /// Markets this candidate was pulled for (`us` / `uk` / `ca` / `br`).
    /// Dual-listed products keep both tags after barcode merge.
    let countries: [String]?
    /// Offline verdict on the photo the app will display (`good` / `low` /
    /// `missing`, annotate_image_quality.py). Nil on pre-annotation datasets.
    let imageQuality: String?
    /// V5.5 — OFF `serving_size` ("1 bar (60 g)"); protein-bar S12 scores
    /// protein per serving. Nil on pre-v5.5 datasets (engine assumes 50 g).
    let servingSize: String?
    /// OFF `allergens_tags` / `ingredients_analysis_tags` — lets the safety
    /// filter (allergens, vegan/vegetarian restrictions) see structured data
    /// instead of only ingredient keywords. Nil on older datasets.
    let allergensTags: [String]?
    let ingredientsAnalysisTags: [String]?

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
        case servingSize = "serving_size"
        case allergensTags = "allergens_tags"
        case ingredientsAnalysisTags = "ingredients_analysis_tags"
    }
}

/// The versioned, per-shelf, multi-country file the app ships + background-refreshes.
struct AlternativesFile: Decodable {
    let version: Int
    let rulesetVersion: String?
    let generatedAt: String?
    /// Legacy single-market stamp; prefer `countries` when present.
    let country: String?
    /// Markets represented in this file (e.g. `["us","uk","ca"]`).
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
    /// The score this list ranks and displays. Top Rated: Overall (universal).
    /// Better Options: the user's own score when personalization is on
    /// (Overall otherwise) — the same axis the product page emphasizes.
    let score: Int
    /// Candidate shares the scanned product's most-specific OFF tag (grape→grape).
    let sharedTag: Bool
    /// Markets this candidate belongs to (`us` / `uk` / `ca` / `br`).
    let countries: [String]
    /// Better Options only: how much the pick beats the scanned product by, on
    /// the same axis as `score`.
    var delta: Int = 0
    /// Better Options only: 0–2 short, label-derived reasons it is better
    /// ("Less sugar", "No additives"…). See `AlternativeReasons`.
    var reasons: [String] = []
    /// Better Options only: 2 = same sub-type (anchor tag), 1 = same form,
    /// 0 = same shelf. Higher sorts first.
    var similarity: Int = 0
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

/// GS1 prefix helpers. Used both for the (legacy) coarse region and for the
/// US-market evidence gate.
enum AlternativesRegion: String, Equatable {
    case us, br

    /// 789/790 → Brazil; everything else defaults to US for v1.
    static func from(barcode: String) -> AlternativesRegion {
        guard let prefix = gs1Prefix(barcode) else { return .us }
        if (789...790).contains(prefix) { return .br }
        return .us
    }

    /// The three-digit GS1 company prefix of a 13-digit-normalized code.
    /// UPC-A (12 digits) normalizes to a leading 0; GTIN-14 drops its leading
    /// 0; EAN-8 has no country prefix (returns nil).
    static func gs1Prefix(_ barcode: String) -> Int? {
        let digits = barcode.filter(\.isNumber)
        let padded: String
        switch digits.count {
        case 12: padded = "0" + digits
        case 13: padded = digits
        case 14 where digits.hasPrefix("0"): padded = String(digits.dropFirst())
        default: return nil
        }
        return Int(padded.prefix(3))
    }

    /// GS1 prefixes 000–139 are issued by GS1 US (UPC). Canada shares the
    /// UPC space for most of its brands (754–755 is rare), so this reads
    /// "North American barcode" — the evidence Better Options wants.
    /// 8-digit codes starting with 0 are UPC-E (Trader Joe's, Kroger, Mountain
    /// Dew cans); other 8-digit codes are EAN-8 (UK/EU) and carry no prefix.
    static func isUPC(_ barcode: String) -> Bool {
        let digits = barcode.filter(\.isNumber)
        if digits.count == 8 { return digits.hasPrefix("0") }
        guard let p = gs1Prefix(barcode) else { return false }
        return (0...139).contains(p)
    }

    /// US store brands that carry a non-US GS1 company prefix: ALDI US
    /// (Simply Nature, Friendly Farms, Millville, Happy Farms, little Journey,
    /// Goldhen…) issues 4099100 / 4061462 / 4061464; Lidl US private label
    /// uses 4056489. Real US-shelf products, just not UPC-coded.
    static let usStoreBrandPrefixes: [String] = ["4099100", "4061462", "4061464", "4056489"]

    static func isUSStoreBrand(_ barcode: String) -> Bool {
        let digits = barcode.filter(\.isNumber)
        return usStoreBrandPrefixes.contains { digits.hasPrefix($0) }
    }

    /// GS1 prefixes of the Asian markets whose imports *are* the US instant-
    /// noodle aisle (Nongshim / Ottogi / Samyang 880, Thai 885, Singapore 888,
    /// Indonesia 899, Malaysia 955, Vietnam 893, Japan 45/49, Taiwan 471,
    /// HK 489, China 690–699, India 890). Allowed for that shelf only.
    static func isAsianImport(_ barcode: String) -> Bool {
        guard let p = gs1Prefix(barcode) else { return false }
        return (450...459).contains(p) || (490...499).contains(p) || p == 471 || p == 489
            || (690...699).contains(p) || p == 880 || p == 885 || p == 888 || p == 890
            || p == 893 || p == 899 || p == 955
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
    /// At most one pick per brand — three RXBAR flavours is one suggestion.
    static let maxPerBrand = 1

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

    /// US-market evidence beyond OFF's community `countries` tag, which leaks
    /// Hungarian Coke and Polish tomato juice into a US pull: a North American
    /// barcode (UPC / UPC-E), a known US store-brand prefix (ALDI / Lidl US),
    /// or — on the instant-noodle shelf only — an Asian import prefix, because
    /// Korean / Thai / Japanese imports *are* that aisle in US stores.
    /// (Declared added sugars was tried as a US-label signal and rejected:
    /// OFF carries community-typed zeros on EU records.)
    static func hasUSMarketEvidence(barcode: String, shelf: SageCategory? = nil) -> Bool {
        // Shorter than EAN-8 ⇒ not a GS1 code (test fixtures, internal ids):
        // nothing to judge, so the `countries` tag stands alone.
        guard barcode.filter(\.isNumber).count >= 8 else { return true }
        if AlternativesRegion.isUPC(barcode) || AlternativesRegion.isUSStoreBrand(barcode) { return true }
        if shelf == .instantNoodles, AlternativesRegion.isAsianImport(barcode) { return true }
        return false
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
                           shelf: shelf,
                           profile: profile,
                           ruleset: ruleset)
    }

    /// Pure core (no global state) — the §3 algorithm + empty-reason (§7).
    static func rank(scanned: Product,
                     candidates: [AlternativeCandidate],
                     shelf: SageCategory? = nil,
                     profile: UserProfile,
                     ruleset: RulesetV4) -> [Alternative] {
        switch rankOutcome(scanned: scanned, candidates: candidates, shelf: shelf,
                           profile: profile, ruleset: ruleset) {
        case .suggestions(let list): return list
        default: return []
        }
    }

    /// The score a product is compared on: the user's own score when
    /// personalization is on (what the product page emphasizes), else Overall.
    static func axisScore(_ p: Product, profile: UserProfile) -> Int? {
        profile.personalizeScoring ? (p.yourScore ?? p.overallScore) : p.overallScore
    }

    static func rankOutcome(scanned: Product,
                            candidates: [AlternativeCandidate],
                            shelf: SageCategory? = nil,
                            profile: UserProfile,
                            ruleset: RulesetV4) -> AlternativesOutcome {
        guard scanned.overallScore != nil,
              let baseline = axisScore(scanned, profile: profile) else { return .unscored }
        let shelf = shelf ?? SageCategory.shelf(for: scanned)
        let anchorTag = shelf?.anchorTag(for: scanned)
        let scannedForm = shelf?.form(of: scanned)
        let scannedKey = TopRated.listKey(brand: scanned.brand, name: scanned.name)

        var pool: [Alternative] = []
        for cand in candidates {
            // 2. Market.
            guard isAllowedMarket(cand.countries),
                  hasUSMarketEvidence(barcode: cand.barcode, shelf: shelf)
            else { continue }
            if cand.barcode == scanned.id { continue }
            guard let (p, _) = scored(cand, profile: profile, ruleset: ruleset),
                  let axis = axisScore(p, profile: profile) else { continue }
            // 4. Fit: not the same product, and a swap-compatible form.
            if TopRated.listKey(brand: p.brand, name: p.name) == scannedKey { continue }
            let candidateForm = shelf?.form(of: p)
            if shelf != nil,
               !SageCategory.isSwapCompatible(scannedForm: scannedForm, candidateForm: candidateForm) { continue }
            // 1. Evidence.
            guard TopRated.isEligible(p, ruleset: ruleset) else { continue }
            // 3. Safety.
            guard isSafe(p, profile: profile, ruleset: ruleset) else { continue }

            let shared = anchorTag.map { (p.categories ?? []).contains($0) } ?? false
            let similarity: Int = {
                if shared { return 2 }
                if let sf = scannedForm, let cf = candidateForm, sf.id == cf.id { return 1 }
                return 0
            }()
            pool.append(Alternative(product: p, score: axis, sharedTag: shared,
                                    countries: cand.countries ?? [],
                                    delta: axis - baseline,
                                    reasons: AlternativeReasons.reasons(scanned: scanned, alternative: p),
                                    similarity: similarity))
        }

        let picks = select(baseline: baseline, from: pool)
        if !picks.isEmpty { return .suggestions(picks) }

        guard let maxPeer = pool.map(\.score).max() else { return .noBetterPeers }
        if baseline + margin > maxPeer { return .alreadyTopOfShelf }
        return .noBetterPeers
    }

    /// A candidate that conflicts with what the user told Sage to watch for is
    /// never a "better option" — whatever its number. Restriction conflicts
    /// (vegan, low-sugar, …) are already stamped by the engine under this
    /// profile; allergens and the avoid-list are checked here.
    static func isSafe(_ p: Product, profile: UserProfile, ruleset: RulesetV4) -> Bool {
        if !p.restrictions.isEmpty { return false }
        if !AllergenMatcher.warnings(product: p, allergies: profile.allergies ?? []).isEmpty { return false }
        if !ScoringEngineV4.avoidListHits(p, profile: profile, rs: ruleset).isEmpty { return false }
        return true
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
            categoriesTags: c.categoriesTags, labelsTags: c.labelsTags,
            servingSize: c.servingSize,
            allergensTags: c.allergensTags,
            ingredientsAnalysisTags: c.ingredientsAnalysisTags)
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

    private static func selectMargin<T: RankableAlternative>(baseline: Int, from pool: [T]) -> [T] {
        let overMargin = pool.filter { $0.score >= baseline + margin }
        let good = overMargin.filter { $0.score >= goodFloor }
        let ranked = (good.isEmpty ? overMargin : good).sorted {
            let ls = similarity($0), rs = similarity($1)
            if ls != rs { return ls > rs }
            if $0.score != $1.score { return $0.score > $1.score }
            return stableId($0) < stableId($1)
        }
        // 6. Useful: one per brand, no near-duplicate names.
        var out: [T] = []
        var seenNames = Set<String>()
        var seenBrands = Set<String>()
        for item in ranked where out.count < maxResults {
            guard let alt = item as? Alternative else { out.append(item); continue }
            let nameKey = TopRated.listKey(brand: alt.product.brand, name: alt.product.name)
            guard seenNames.insert(nameKey).inserted else { continue }
            let brandKey = TopRated.listKey(brand: alt.product.brand, name: "")
            if !brandKey.isEmpty {
                if seenBrands.contains(where: { $0.hasPrefix(brandKey) || brandKey.hasPrefix($0) }) { continue }
                seenBrands.insert(brandKey)
            }
            out.append(item)
        }
        return out
    }

    private static func similarity<T: RankableAlternative>(_ t: T) -> Int {
        if let a = t as? Alternative { return a.similarity }
        return t.sharedTag ? 2 : 0
    }

    private static func stableId<T: RankableAlternative>(_ t: T) -> String {
        (t as? Alternative)?.id ?? ""
    }
}

// MARK: - Why it's better
//
// Short, label-derived reasons a pick beats the scanned product. Only facts
// the engine itself scores on (sugar, processing, additives, sweeteners,
// sodium, saturated fat, protein, fiber), with thresholds big enough to be a
// real difference per 100 g/ml — never a marketing adjective. Max two, in
// the order a dietitian would mention them.

enum AlternativeReasons {
    static let maxReasons = 2

    static func reasons(scanned s: Product, alternative a: Product) -> [String] {
        var out: [String] = []
        let sn = s.nutrients, an = a.nutrients

        // Free/total sugar — the single most consistent "better" signal.
        if let ss = sn.sugar_g, let asug = an.sugar_g, lower(asug, than: ss, byFraction: 0.30, minAbs: 2.0) {
            out.append(asug <= 0.5 ? "No sugar" : "Less sugar")
        }
        // Processing level (NOVA), only when both are known.
        if s.hasKnownNova, a.hasKnownNova, a.novaGroup < s.novaGroup {
            out.append(a.novaGroup <= 2 ? "Minimally processed" : "Less processed")
        }
        // Additives: count and risk.
        let sRisky = s.additives.filter { $0.risk == .high || $0.risk == .moderate }.count
        let aRisky = a.additives.filter { $0.risk == .high || $0.risk == .moderate }.count
        if a.additives.isEmpty, !s.additives.isEmpty {
            out.append("No additives")
        } else if aRisky < sRisky || a.additives.count + 2 <= s.additives.count {
            out.append("Fewer additives")
        }
        // Artificial sweeteners.
        if !s.sweeteners.isEmpty, a.sweeteners.isEmpty {
            out.append("No artificial sweeteners")
        }
        if let ss = sn.sodium_mg, let asod = an.sodium_mg, lower(asod, than: ss, byFraction: 0.30, minAbs: 100) {
            out.append("Less sodium")
        }
        if let sf = sn.satFat_g, let af = an.satFat_g, lower(af, than: sf, byFraction: 0.30, minAbs: 1.0) {
            out.append("Less saturated fat")
        }
        if let sp = sn.protein_g, let ap = an.protein_g, lower(sp, than: ap, byFraction: 0.30, minAbs: 2.0) {
            out.append("More protein")
        }
        if let sfi = sn.fiber_g, let afi = an.fiber_g, lower(sfi, than: afi, byFraction: 0.30, minAbs: 1.5) {
            out.append("More fiber")
        }
        if let st = sn.transFat_g, st > 0, (an.transFat_g ?? 0) == 0 {
            out.insert("No trans fat", at: 0)
        }
        return Array(out.prefix(maxReasons))
    }

    /// `a` is meaningfully lower than `b`: at least `fraction` lower *and* at
    /// least `minAbs` lower (so 0.2 g vs 0.1 g never reads as "less sugar").
    static func lower(_ a: Double, than b: Double, byFraction fraction: Double, minAbs: Double) -> Bool {
        guard b > 0 else { return false }
        return (b - a) >= minAbs && a <= b * (1 - fraction)
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
              markets: allowedMarkets(for: shelf), shelf: shelf)
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
                      markets: Set<String> = Alternatives.allowedMarkets,
                      shelf: SageCategory? = nil) -> [Alternative] {
        let pool = candidates
            .filter { !markets.isDisjoint(with: $0.countries ?? []) }
            .filter {
                // Same market-evidence gate as Better Options: a Hungarian
                // Coke stamped `us` by OFF's community tags is not a US pick.
                !markets.contains("us")
                    || Alternatives.hasUSMarketEvidence(barcode: $0.barcode, shelf: shelf)
            }
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
