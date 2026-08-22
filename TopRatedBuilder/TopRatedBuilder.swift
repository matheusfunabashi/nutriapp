import Foundation

// MARK: - Input

private struct CandidatesFile: Decodable {
    let categories: [String: [CandidateEntry]]
    let countries: [String]?
}

private struct CandidateEntry: Decodable {
    let barcode: String
    let offName: String?
    let offBrands: String?
    let ingredientsText: String?
    let additivesTags: [String]?
    let nutriments: OFFNutriments?
    let nutriscoreGrade: String?
    let novaGroup: Int?
    let imageURL: String?
    let categoriesTags: [String]?
    let labelsTags: [String]?
    let dataProblems: [String]?
    /// Markets this row was pulled for (`us` / `br`).
    let countries: [String]?
    /// V5.5 — OFF `serving_size`; protein-bar S12 scores protein per serving.
    let servingSize: String?
    /// Better Options safety filter inputs + market-audit fields (2026-08-22).
    let allergensTags: [String]?
    let ingredientsAnalysisTags: [String]?
    let countriesTags: [String]?
    let uniqueScansN: Int?

    enum CodingKeys: String, CodingKey {
        case barcode, countries
        case servingSize = "serving_size"
        case allergensTags = "allergens_tags"
        case ingredientsAnalysisTags = "ingredients_analysis_tags"
        case countriesTags = "countries_tags"
        case uniqueScansN = "unique_scans_n"
        case offName = "off_name"
        case offBrands = "off_brands"
        case ingredientsText = "ingredients_text"
        case additivesTags = "additives_tags"
        case nutriments
        case nutriscoreGrade = "nutriscore_grade"
        case novaGroup = "nova_group"
        case imageURL = "image_url"
        case categoriesTags = "categories_tags"
        case labelsTags = "labels_tags"
        case dataProblems = "data_problems"
    }

    func withCountries(_ countries: [String]) -> CandidateEntry {
        CandidateEntry(
            barcode: barcode, offName: offName, offBrands: offBrands,
            ingredientsText: ingredientsText, additivesTags: additivesTags,
            nutriments: nutriments, nutriscoreGrade: nutriscoreGrade,
            novaGroup: novaGroup, imageURL: imageURL,
            categoriesTags: categoriesTags, labelsTags: labelsTags,
            dataProblems: dataProblems, countries: countries,
            servingSize: servingSize,
            allergensTags: allergensTags,
            ingredientsAnalysisTags: ingredientsAnalysisTags,
            countriesTags: countriesTags,
            uniqueScansN: uniqueScansN)
    }
}

// MARK: - Output

private struct TopRatedFile: Encodable {
    let version: Int
    let generatedAt: String
    let categories: [TopRatedCategory]

    enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case categories
    }
}

private struct TopRatedCategory: Encodable {
    let id: String
    let displayName: String
    let country: String
    let rankedCount: Int
    let products: [TopRatedProduct]

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case country
        case rankedCount = "ranked_count"
        case products
    }
}

private struct TopRatedProduct: Encodable {
    let rank: Int
    let barcode: String
    let name: String
    let brand: String
    let score: Int
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case rank, barcode, name, brand, score
        case imageURL = "image_url"
    }
}

// Alternatives output (ALTERNATIVES_SPEC.md §2.1): richer than TopRatedProduct —
// each candidate carries its scoring inputs so the app can re-score on-device
// under the current ruleset. Shape round-trips into the app's AlternativeCandidate.
private struct AltCandidate: Encodable {
    let barcode: String
    let name: String
    let brand: String?
    let imageURL: String?
    let precomputedScore: Int?
    let categoriesTags: [String]?
    let ingredientsText: String?
    let additivesTags: [String]?
    let novaGroup: Int?
    let nutriscoreGrade: String?
    let labelsTags: [String]?
    let nutriments: OFFNutriments?
    let countries: [String]?
    let servingSize: String?
    let allergensTags: [String]?
    let ingredientsAnalysisTags: [String]?

    enum CodingKeys: String, CodingKey {
        case barcode, name, brand, nutriments, countries
        case servingSize = "serving_size"
        case allergensTags = "allergens_tags"
        case ingredientsAnalysisTags = "ingredients_analysis_tags"
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

private struct AltFile: Encodable {
    let version: Int
    let rulesetVersion: String
    let generatedAt: String
    /// Legacy single-market field; multi-market files also set `countries`.
    let country: String
    let countries: [String]
    let shelves: [String: [AltCandidate]]

    enum CodingKeys: String, CodingKey {
        case version, country, countries, shelves
        case rulesetVersion = "ruleset_version"
        case generatedAt = "generated_at"
    }
}

// MARK: - Processing

private struct ScoredCandidate {
    let entry: CandidateEntry
    let product: Product
    let score: Int
}

private enum SkipReason: String {
    case dataProblems = "data_problems"
    case coffeeCategory = "coffee category"
    case unsupported = "unsupported category"
    case insufficientData = "insufficient data"
}

private struct CategoryStats {
    var skippedDataProblems = 0
    var skippedUnsupported = 0
    var skippedInsufficient = 0
    var skippedMarket = 0
    var deduped = 0
    var scored = 0
}

@main
enum TopRatedBuilder {
    static func main() {
        guard CommandLine.arguments.count >= 2 else {
            fputs("Usage: TopRatedBuilder <path/to/candidates.json>\n", stderr)
            exit(1)
        }

        let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent("top-rated.json")

        do {
            let data = try Data(contentsOf: inputURL)
            let candidates = try JSONDecoder().decode(CandidatesFile.self, from: data)
            let ruleset = RulesetV4.bundled
            let profile = rankingProfile()
            let marketCodes = candidates.countries?.isEmpty == false
                ? (candidates.countries ?? ["us"])
                : ["us"]

            var outputCategories: [TopRatedCategory] = []
            var altShelves: [String: [AltCandidate]] = [:]
            let sortedKeys = candidates.categories.keys.sorted()

            for categoryId in sortedKeys {
                if categoryId.lowercased() == "coffee" {
                    let entries = candidates.categories[categoryId] ?? []
                    print("\(categoryId): skipped entire category (\(entries.count) entries)")
                    continue
                }

                let entries = candidates.categories[categoryId] ?? []
                var stats = CategoryStats()
                var scored: [ScoredCandidate] = []

                for entry in entries {
                    if shouldSkipForDataProblems(entry.dataProblems) {
                        stats.skippedDataProblems += 1
                        continue
                    }
                    if !hasUsableName(entry) {
                        stats.skippedInsufficient += 1
                        continue
                    }

                    let raw = OpenFoodFactsService.mapCandidate(
                        barcode: entry.barcode,
                        name: entry.offName,
                        brands: entry.offBrands,
                        ingredientsText: entry.ingredientsText,
                        additivesTags: entry.additivesTags,
                        nutriments: entry.nutriments,
                        nutriscoreGrade: entry.nutriscoreGrade,
                        novaGroup: entry.novaGroup,
                        imageURL: entry.imageURL,
                        categoriesTags: entry.categoriesTags,
                        labelsTags: entry.labelsTags,
                        servingSize: entry.servingSize,
                        allergensTags: entry.allergensTags,
                        ingredientsAnalysisTags: entry.ingredientsAnalysisTags
                    )

                    switch ScoringEngineV4.scoreProduct(raw, for: profile, ruleset: ruleset) {
                    case .scored(let product):
                        // Ship only what the app could ever show: the Top
                        // Rated / Better Options evidence gate (ingredients,
                        // NOVA, nutrition table, confidence) and, for the US
                        // market, barcode evidence that it is a US-shelf
                        // product. Mirrors Alternatives.swift (not in this
                        // target) — keep the two in step.
                        guard isEligible(product, ruleset: ruleset) else {
                            stats.skippedInsufficient += 1
                            continue
                        }
                        guard hasMarketEvidence(entry, shelf: categoryId) else {
                            stats.skippedMarket += 1
                            continue
                        }
                        scored.append(ScoredCandidate(entry: entry, product: product,
                                                      score: product.overallScore ?? product.yourScore ?? 0))
                    case .unsupported:
                        stats.skippedUnsupported += 1
                    case .insufficientData:
                        stats.skippedInsufficient += 1
                    case .unscored:
                        stats.skippedInsufficient += 1
                    }
                }

                let beforeDedupe = scored.count
                scored = dedupe(scored, stats: &stats)
                stats.scored = scored.count

                // Top N per market, then merge by barcode (union countries).
                let altMerged = topPerCountry(scored, markets: marketCodes,
                                              limit: marketCap)
                altShelves[categoryId] = altMerged.map(altCandidate(from:))

                let ranked = scored.sorted { $0.score > $1.score }
                let top = Array(ranked.prefix(10))
                let products: [TopRatedProduct] = top.enumerated().map { idx, item in
                    TopRatedProduct(
                        rank: idx + 1,
                        barcode: item.entry.barcode,
                        name: item.product.name,
                        brand: item.product.brand,
                        score: item.score,
                        imageURL: item.entry.imageURL
                    )
                }

                outputCategories.append(TopRatedCategory(
                    id: categoryId,
                    displayName: displayName(for: categoryId),
                    country: marketCodes.joined(separator: "+"),
                    rankedCount: stats.scored,
                    products: products
                ))

                printCategorySummary(
                    categoryId: categoryId,
                    inputCount: entries.count,
                    beforeDedupe: beforeDedupe,
                    stats: stats,
                    top: top
                )
                for market in marketCodes {
                    let n = altMerged.filter {
                        ($0.entry.countries ?? []).contains(market)
                    }.count
                    print("  alt \(market): \(n) (cap \(marketCap(market)))")
                }
            }

            let output = TopRatedFile(
                version: 1,
                generatedAt: ISO8601DateFormatter().string(from: Date()),
                categories: outputCategories
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(output).write(to: outputURL, options: .atomic)
            print("\nWrote \(outputURL.path)")

            let altOut = AltFile(
                version: 1,
                rulesetVersion: ruleset.version,
                generatedAt: ISO8601DateFormatter().string(from: Date()),
                country: marketCodes.count == 1 ? marketCodes[0] : "multi",
                countries: marketCodes,
                shelves: altShelves
            )
            let altURL = inputURL.deletingLastPathComponent().appendingPathComponent("alternatives.json")
            try encoder.encode(altOut).write(to: altURL, options: .atomic)
            print("Wrote \(altURL.path)")
        } catch {
            fputs("TopRatedBuilder failed: \(error)\n", stderr)
            exit(1)
        }
    }

    /// Per-market candidate cap. US carries double headroom: the app's Top
    /// Rated eligibility gate (ingredients + NOVA + nutrition + evidence)
    /// prunes the pool at runtime, and the browse tab is US-only.
    private static func marketCap(_ market: String) -> Int {
        market == "us" ? 80 : 25
    }

    // MARK: Gates (mirror Alternatives.swift / TopRated.isEligible)

    static let minConfidence = 0.80
    static let maxUnknownRuleWeight = 20.0

    /// Ingredients + known NOVA + a real nutrition table + rule evidence above
    /// the confidence floor. A record that scores high *because* data is
    /// missing (a NOVA-less diet soda re-scored 100) never ships.
    private static func isEligible(_ product: Product, ruleset: RulesetV4) -> Bool {
        guard product.hasIngredientData, product.hasKnownNova, product.hasNutritionData,
              let evidence = ScoringEngineV4.evidenceSummary(product, ruleset: ruleset)
        else { return false }
        return evidence.confidence >= minConfidence
            && evidence.maxUnknownWeight < maxUnknownRuleWeight
    }

    private static func gs1Prefix(_ barcode: String) -> Int? {
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

    /// UPC / UPC-E, ALDI-US / Lidl-US store-brand prefixes, or (instant
    /// noodles only) an Asian import prefix — OFF's community `countries`
    /// tag alone let Hungarian Coke and Polish tomato juice into the US pull.
    private static func hasUSBarcodeEvidence(_ barcode: String, shelf: String) -> Bool {
        let digits = barcode.filter(\.isNumber)
        if digits.count == 8 { return digits.hasPrefix("0") }
        if ["4099100", "4061462", "4061464", "4056489"].contains(where: { digits.hasPrefix($0) }) { return true }
        guard let p = gs1Prefix(barcode) else { return false }
        if (0...139).contains(p) { return true }
        if shelf == "instantNoodles" {
            return (450...459).contains(p) || (490...499).contains(p) || p == 471 || p == 489
                || (690...699).contains(p) || p == 880 || p == 885 || p == 888 || p == 890
                || p == 893 || p == 899 || p == 955
        }
        return false
    }

    /// Rows pulled for the US market must carry US barcode evidence; other
    /// markets keep OFF's country tag as-is (they are not surfaced today).
    private static func hasMarketEvidence(_ entry: CandidateEntry, shelf: String) -> Bool {
        let markets = entry.countries ?? []
        guard markets.contains("us") else { return true }
        return hasUSBarcodeEvidence(entry.barcode, shelf: shelf)
    }

    /// Keep top `limit(market)` per market code, then merge duplicate barcodes.
    private static func topPerCountry(_ scored: [ScoredCandidate],
                                      markets: [String],
                                      limit: (String) -> Int) -> [ScoredCandidate] {
        var byBarcode: [String: ScoredCandidate] = [:]
        for market in markets {
            let inMarket = scored.filter {
                let cs = $0.entry.countries ?? []
                return cs.isEmpty || cs.contains(market)
            }
            .sorted { $0.score > $1.score }
            for item in inMarket.prefix(limit(market)) {
                if let existing = byBarcode[item.entry.barcode] {
                    let union = sortedUnion(existing.entry.countries, item.entry.countries)
                    byBarcode[item.entry.barcode] = ScoredCandidate(
                        entry: existing.entry.withCountries(union),
                        product: existing.score >= item.score ? existing.product : item.product,
                        score: max(existing.score, item.score)
                    )
                } else {
                    byBarcode[item.entry.barcode] = item
                }
            }
        }
        return Array(byBarcode.values).sorted { $0.score > $1.score }
    }

    private static func sortedUnion(_ a: [String]?, _ b: [String]?) -> [String] {
        Array(Set(a ?? []).union(b ?? [])).sorted()
    }

    /// Goal-neutral profile so shelf rankings match Overall (Your == Overall).
    private static func rankingProfile() -> UserProfile {
        var profile = MockData.user
        profile.objective = "maintain"
        profile.personalizeScoring = false
        profile.restrictions = []
        profile.preferences = []
        profile.healthGoals = nil
        profile.dietPattern = nil
        profile.avoidList = nil
        profile.sliderCleanIngredients = nil
        profile.sliderNutrition = nil
        profile.sliderEnvironment = nil
        profile.sliderAnimalWelfare = nil
        return profile
    }

    /// A product that cannot be named cannot be recommended: reject empty
    /// names, OFF's "Unknown product" placeholder, and barcode-as-name rows.
    private static func hasUsableName(_ entry: CandidateEntry) -> Bool {
        let name = (entry.offName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if name.lowercased() == "unknown product" { return false }
        if name.filter(\.isNumber) == entry.barcode.filter(\.isNumber),
           !name.contains(where: \.isLetter) { return false }
        return true
    }

    /// Keep entries whose only problem is a missing image; skip all others.
    private static func shouldSkipForDataProblems(_ problems: [String]?) -> Bool {
        guard let problems, !problems.isEmpty else { return false }
        let normalized = Set(problems.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
        return normalized != ["no image"]
    }

    private static func displayName(for categoryId: String) -> String {
        if let cat = SageCategory(rawValue: categoryId) {
            return cat.displayName
        }
        return categoryId
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Maps a scored+deduped candidate into an alternatives record, carrying the
    /// entry's scoring inputs forward for on-device re-scoring.
    private static func altCandidate(from item: ScoredCandidate) -> AltCandidate {
        AltCandidate(
            barcode: item.entry.barcode,
            name: item.product.name,
            brand: item.product.brand,
            imageURL: item.entry.imageURL,
            precomputedScore: item.score,
            categoriesTags: item.entry.categoriesTags,
            ingredientsText: item.entry.ingredientsText,
            additivesTags: item.entry.additivesTags,
            novaGroup: item.entry.novaGroup,
            nutriscoreGrade: item.entry.nutriscoreGrade,
            labelsTags: item.entry.labelsTags,
            nutriments: item.entry.nutriments,
            countries: item.entry.countries,
            servingSize: item.entry.servingSize,
            allergensTags: item.entry.allergensTags,
            ingredientsAnalysisTags: item.entry.ingredientsAnalysisTags)
    }

    private static func dedupe(_ items: [ScoredCandidate], stats: inout CategoryStats) -> [ScoredCandidate] {
        var best: [String: ScoredCandidate] = [:]
        for item in items {
            let key = dedupeKey(brand: item.product.brand, name: item.product.name)
            if let existing = best[key] {
                stats.deduped += 1
                if completeness(item.entry) > completeness(existing.entry) {
                    best[key] = item
                }
            } else {
                best[key] = item
            }
        }
        return Array(best.values)
    }

    private static func dedupeKey(brand: String, name: String) -> String {
        normalizeForDedupe(brand) + "|" + normalizeForDedupe(name)
    }

    private static func normalizeForDedupe(_ text: String) -> String {
        var s = text.lowercased()
        let units = [
            "\\bfl\\.?\\s*oz\\b", "\\bfluid\\s+ounces?\\b", "\\boz\\b", "\\bml\\b", "\\bl\\b",
            "\\bg\\b", "\\bkg\\b", "\\blb\\b", "\\blbs\\b", "\\bpack\\b", "\\bct\\b", "\\bcount\\b",
            "\\bpk\\b", "\\beach\\b"
        ]
        for pattern in units {
            s = s.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        let stripped = s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        return String(String.UnicodeScalarView(stripped))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func completeness(_ entry: CandidateEntry) -> Int {
        var score = 0
        if entry.offName?.isEmpty == false { score += 2 }
        if entry.offBrands?.isEmpty == false { score += 1 }
        if entry.ingredientsText?.isEmpty == false { score += 3 }
        if let tags = entry.additivesTags, !tags.isEmpty { score += 1 }
        if entry.nutriments != nil { score += 4 }
        if entry.novaGroup != nil { score += 1 }
        if entry.imageURL?.isEmpty == false { score += 1 }
        if let tags = entry.categoriesTags, !tags.isEmpty { score += 1 }
        if let tags = entry.labelsTags, !tags.isEmpty { score += 1 }
        return score
    }

    private static func printCategorySummary(
        categoryId: String,
        inputCount: Int,
        beforeDedupe: Int,
        stats: CategoryStats,
        top: [ScoredCandidate]
    ) {
        print("\n\(categoryId):")
        print("  input: \(inputCount)")
        print("  scored: \(stats.scored) (before dedupe: \(beforeDedupe))")
        if stats.skippedDataProblems > 0 {
            print("  skipped data_problems: \(stats.skippedDataProblems)")
        }
        if stats.skippedUnsupported > 0 {
            print("  skipped unsupported: \(stats.skippedUnsupported)")
        }
        if stats.skippedInsufficient > 0 {
            print("  skipped insufficient data: \(stats.skippedInsufficient)")
            print("  skipped no US barcode evidence: \(stats.skippedMarket)")
        }
        if stats.deduped > 0 {
            print("  deduped collisions: \(stats.deduped)")
        }
        if top.isEmpty {
            print("  top 10 score range: —")
        } else {
            let scores = top.map(\.score)
            print("  top 10 score range: \(scores.min()!)–\(scores.max()!)")
        }
    }
}
