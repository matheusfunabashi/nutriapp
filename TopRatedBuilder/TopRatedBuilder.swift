import Foundation

// MARK: - Input

private struct CandidatesFile: Decodable {
    let categories: [String: [CandidateEntry]]
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

    enum CodingKeys: String, CodingKey {
        case barcode
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

private struct AltFile: Encodable {
    let version: Int
    let rulesetVersion: String
    let generatedAt: String
    let country: String
    let shelves: [String: [AltCandidate]]

    enum CodingKeys: String, CodingKey {
        case version, country, shelves
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
                        labelsTags: entry.labelsTags
                    )

                    switch ScoringEngineV4.scoreProduct(raw, for: profile, ruleset: ruleset) {
                    case .scored(let product):
                        // Neutral ranking profile ⇒ Your == Overall; both are optional
                        // in V5, so fall back defensively.
                        scored.append(ScoredCandidate(entry: entry, product: product,
                                                      score: product.overallScore ?? product.yourScore ?? 0))
                    case .unsupported:
                        stats.skippedUnsupported += 1
                    case .insufficientData:
                        stats.skippedInsufficient += 1
                    case .unscored:
                        // V5 withholds a score (e.g. table sweeteners) — not shelf-able.
                        stats.skippedInsufficient += 1
                    }
                }

                let beforeDedupe = scored.count
                scored = dedupe(scored, stats: &stats)
                stats.scored = scored.count

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
                    country: "us",
                    rankedCount: stats.scored,
                    products: products
                ))

                // Alternatives keeps a deeper cut (top ~25) with scoring inputs, so
                // the app's "better than scanned" filter has headroom (SPEC §2.1).
                altShelves[categoryId] = ranked.prefix(25).map(altCandidate(from:))

                printCategorySummary(
                    categoryId: categoryId,
                    inputCount: entries.count,
                    beforeDedupe: beforeDedupe,
                    stats: stats,
                    top: top
                )
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
                country: "us",
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
            nutriments: item.entry.nutriments)
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
