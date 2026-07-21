import Testing
import Foundation
@testable import Sage

/// Prints / asserts the V5.0.7 calibration snapshot used in SCORING_V5.md.
/// Baseline is V5.0.6; only white sugar / raw honey / stevia change (→ unscored).
struct V5CalibrationSnapshotTests {

    private let rs = RulesetV4.bundled
    /// Baselines from V5.0.6 snapshot (SCORING_V5.md).
    private let v506: [String: Int] = [
        "apple": 86, "banana": 87, "chicken breast (no text)": 88,
        "chicken breast (with text)": 88, "plain green tea": 79,
        "OJ": 48, "Coke": 24, "Diet Coke": 34, "cheddar": 64,
        "extra-virgin olive oil": 84, "unsalted butter": 44,
        "salted butter": 38, "margarine": 35, "coconut oil": 37,
        "fresh coconut": 82, "whole milk": 70, "dates": 86,
        "salted nuts": 87, "unsalted nuts": 91, "ramen": 28,
        "Jif": 48, "Cheerios": 58, "Nature Valley": 48, "Yorgus": 59,
    ]
    private let unscoredNames: Set<String> = ["white sugar", "raw honey", "stevia tablets"]

    private func product(
        kcal: Double? = nil, protein: Double? = nil, fiber: Double? = nil,
        sugar: Double? = nil, satFat: Double? = nil, sodium: Double? = nil,
        calcium: Double? = nil, fvn: Double? = nil, transFat: Double? = nil,
        nova: Int = 0, name: String = "T",
        ingredientsText: String? = nil,
        additives: [ProductAdditive] = [],
        categories: [String]? = nil,
        labels: [String]? = nil
    ) -> Product {
        Product(
            id: name, name: name, brand: "B", size: "", glyph: "🛒",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                 fiber_g: fiber, protein_g: protein, calcium_mg: calcium,
                                 kcal: kcal, fvn: fvn, transFat_g: transFat),
            bonuses: [], transFats: (transFat ?? 0) > 0, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            labels: labels, packagingMaterials: nil, origins: nil,
            ingredientShares: nil, categories: categories
        )
    }

    private func row(_ p: Product) -> String {
        if unscoredNames.contains(p.name) {
            #expect(ScoringEngineV4.route(p) == "unscored_sweetener")
            #expect(ScoringEngineV4.score(p) == nil)
            return "| \(p.name) | unscored | — | — | — |"
        }
        guard let raw = ScoringEngineV4.score(p) else {
            return "| \(p.name) | — | — | — | unsupported/insufficient |"
        }
        let gate = ScoringEngineV4.applyBaseCaps(base: 100, product: p, rs: rs)
        let fired = gate.fired.isEmpty ? "—" : gate.fired.map { "\($0.id):\($0.value)" }.joined(separator: ", ")
        let deltaText: String
        if let previous = v506[p.name] {
            let delta = raw.base - previous
            deltaText = delta > 0 ? "+\(delta)" : "\(delta)"
        } else {
            deltaText = "new"
        }
        return "| \(p.name) | \(raw.base) | \(deltaText) | \(rs.bandLabel(raw.base)) | \(fired) |"
    }

    @Test func printCalibrationSnapshot() {
        let fixtures: [Product] = [
            product(kcal: 52, protein: 0.3, fiber: 2.4, sugar: 10.4, satFat: 0.1, sodium: 1, nova: 1,
                    name: "apple", ingredientsText: nil, categories: ["fruits", "fresh-fruits"]),
            product(kcal: 89, protein: 1.1, fiber: 2.6, sugar: 12.2, satFat: 0.3, sodium: 1, nova: 1,
                    name: "banana", ingredientsText: nil, categories: ["fruits", "bananas"]),
            product(kcal: 165, protein: 31, sugar: 0, satFat: 1, sodium: 74, nova: 1,
                    name: "chicken breast (no text)", ingredientsText: nil, categories: ["meats"]),
            product(kcal: 165, protein: 31, sugar: 0, satFat: 1, sodium: 74, nova: 1,
                    name: "chicken breast (with text)", ingredientsText: "chicken", categories: ["meats"]),
            product(kcal: 1, sugar: 0, nova: 1, name: "plain green tea",
                    ingredientsText: "green tea", categories: ["teas", "green-teas"]),
            product(kcal: 45, protein: 0.7, sugar: 8.4, sodium: 1, fvn: 100, nova: 1,
                    name: "OJ", ingredientsText: "orange juice",
                    categories: ["beverages", "juices", "orange-juices"]),
            product(kcal: 42, sugar: 10.6, sodium: 10, nova: 4, name: "Coke",
                    ingredientsText: "carbonated water, sugar, caramel color, phosphoric acid",
                    additives: [
                        .init(name: "e150d", risk: .moderate, code: "e150d", tier: .moderate),
                        .init(name: "e338", risk: .moderate, code: "e338", tier: .mild),
                    ],
                    categories: ["beverages", "sodas"]),
            product(kcal: 1, sugar: 0, sodium: 10, nova: 4, name: "Diet Coke",
                    ingredientsText: "carbonated water, caramel color, aspartame, phosphoric acid",
                    additives: [
                        .init(name: "e951", risk: .moderate, code: "e951", tier: .moderate),
                        .init(name: "e150d", risk: .moderate, code: "e150d", tier: .moderate),
                    ],
                    categories: ["beverages", "sodas", "diet-sodas"]),
            product(kcal: 387, sugar: 100, nova: 2, name: "white sugar",
                    ingredientsText: "sugar", categories: ["sweeteners", "sugars"]),
            product(kcal: 304, sugar: 82, nova: 1, name: "raw honey",
                    ingredientsText: "honey", categories: ["sweeteners", "honeys"]),
            product(kcal: 0, sugar: 0, nova: 4, name: "stevia tablets",
                    ingredientsText: "stevia leaf extract, erythritol",
                    categories: ["sweeteners", "tabletop-sweeteners"], labels: ["stevia"]),
            product(kcal: 402, protein: 25, sugar: 0.5, satFat: 21, sodium: 621, calcium: 721,
                    transFat: 0.8, nova: 3, name: "cheddar",
                    ingredientsText: "milk, salt, cultures, enzymes",
                    categories: ["dairies", "cheeses", "cheddar-cheese"]),
            product(kcal: 884, sugar: 0, satFat: 14, sodium: 0, nova: 1,
                    name: "extra-virgin olive oil", ingredientsText: "extra virgin olive oil",
                    categories: ["vegetable-oils", "olive-oils"]),
            product(kcal: 717, sugar: 0.1, satFat: 51, sodium: 11, transFat: 3.0, nova: 2,
                    name: "unsalted butter", ingredientsText: "cream",
                    categories: ["dairies", "butters"]),
            product(kcal: 717, sugar: 0.1, satFat: 51, sodium: 650, transFat: 3.0, nova: 2,
                    name: "salted butter", ingredientsText: "cream, salt",
                    categories: ["dairies", "butters"]),
            product(kcal: 700, sugar: 0, satFat: 15, sodium: 700, transFat: 1.5, nova: 4,
                    name: "margarine",
                    ingredientsText: "partially hydrogenated soybean oil, water, salt",
                    categories: ["margarines"]),
            product(kcal: 892, sugar: 0, satFat: 87, sodium: 0, nova: 2,
                    name: "coconut oil", ingredientsText: "coconut oil",
                    categories: ["vegetable-oils", "coconut-oils"]),
            product(kcal: 354, protein: 3.3, fiber: 9, sugar: 6.2, satFat: 33, sodium: 20,
                    nova: 1, name: "fresh coconut", ingredientsText: "coconut",
                    categories: ["fruits", "nuts", "coconuts"]),
            product(kcal: 64, protein: 3.3, sugar: 4.8, satFat: 1.9, sodium: 44, calcium: 120,
                    nova: 1, name: "whole milk", ingredientsText: "milk",
                    categories: ["dairies", "milks"]),
            product(kcal: 282, fiber: 8, sugar: 66, satFat: 0.2, nova: 1, name: "dates",
                    ingredientsText: "dates", categories: ["fruits", "dried-fruits", "dates"]),
            product(kcal: 600, protein: 20, fiber: 8, sugar: 4, satFat: 5, sodium: 500,
                    nova: 1, name: "salted nuts", ingredientsText: "almonds, salt",
                    categories: ["nuts", "almonds"]),
            product(kcal: 600, protein: 20, fiber: 8, sugar: 4, satFat: 5, sodium: 5,
                    nova: 1, name: "unsalted nuts", ingredientsText: "almonds",
                    categories: ["nuts", "almonds"]),
            product(kcal: 440, protein: 10, sugar: 2, satFat: 8, sodium: 1600, nova: 4,
                    name: "ramen",
                    ingredientsText: """
                    wheat flour, palm oil, salt, monosodium glutamate, disodium inosinate,
                    disodium guanylate, natural flavor, caramel color, TBHQ
                    """,
                    additives: [
                        .init(name: "e621", risk: .moderate, code: "e621", tier: .moderate),
                        .init(name: "e627", risk: .low, code: "e627", tier: .mild),
                        .init(name: "e631", risk: .low, code: "e631", tier: .mild),
                        .init(name: "e319", risk: .high, code: "e319", tier: .major),
                    ],
                    categories: ["meals", "dried-products", "noodles"]),
            product(kcal: 594, protein: 22, fiber: 6, sugar: 9, satFat: 10, sodium: 420, nova: 4,
                    name: "Jif",
                    ingredientsText: "roasted peanuts, sugar, molasses, fully hydrogenated vegetable oils (rapeseed and soybean), salt",
                    additives: [.init(name: "e471", risk: .low, code: "e471", tier: .mild)],
                    categories: ["spreads", "peanut-butters", "nuts", "nuts-and-their-products"]),
            product(kcal: 367, protein: 12, fiber: 10, sugar: 4.5, satFat: 0.8, sodium: 470, nova: 4,
                    name: "Cheerios",
                    ingredientsText: "whole grain oats, corn starch, sugar, salt",
                    additives: [.init(name: "e340", risk: .moderate, code: "e340", tier: .mild)],
                    categories: ["breakfast-cereals", "cereals"]),
            product(kcal: 471, protein: 8, fiber: 6, sugar: 26, satFat: 2, sodium: 350, nova: 4,
                    name: "Nature Valley",
                    ingredientsText: "whole grain oats, sugar, canola oil, honey, soy lecithin, salt",
                    additives: [.init(name: "e322", risk: .low, code: "e322", tier: .mild)],
                    categories: ["snacks", "cereal-bars"]),
            product(kcal: 54, protein: 11.5, sugar: 2, satFat: 0, sodium: 40, calcium: 95, nova: 0,
                    name: "Yorgus", ingredientsText: nil,
                    categories: ["dairies", "yogurts"]),
        ]

        var lines = [
            "| Product | Overall | Δ vs v5.0.6 | Band | Fired caps |",
            "|---|---:|---:|---|---|",
        ]
        for p in fixtures {
            lines.append(row(p))
        }
        let table = lines.joined(separator: "\n")
        print("\n=== CALIBRATION SNAPSHOT V5.0.7 ===\n\(table)\n")

        let scores = Dictionary(uniqueKeysWithValues: fixtures.compactMap { p -> (String, Int)? in
            guard !unscoredNames.contains(p.name) else { return nil }
            return ScoringEngineV4.score(p).map { (p.name, $0.base) }
        })

        // Exactly three movers: the sweetener rows become unscored.
        for name in unscoredNames {
            let p = fixtures.first { $0.name == name }!
            #expect(ScoringEngineV4.route(p) == "unscored_sweetener")
            #expect(ScoringEngineV4.score(p) == nil)
            #expect(scores[name] == nil)
        }

        // All other rows Δ0 vs V5.0.6.
        for (name, previous) in v506 {
            #expect(scores[name] == previous,
                    "snapshot drifted: \(name) was \(previous) now \(scores[name] as Any)")
        }

        #expect(ScoringEngineV4.route(fixtures.first { $0.name == "Jif" }!) == "general")
        #expect(ScoringEngineV4.route(fixtures.first { $0.name == "fresh coconut" }!) == "whole_foods")
        #expect(lines.count == fixtures.count + 2)
        #expect(rs.version == "2026.07-v5.0.7")
        #expect(rs.profiles["sweeteners"] == nil)
    }
}
