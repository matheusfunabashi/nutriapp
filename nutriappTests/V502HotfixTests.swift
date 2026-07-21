import Testing
import Foundation
@testable import Sage

struct V502HotfixTests {
    private let rs = RulesetV4.bundled

    private func product(
        kcal: Double? = nil, protein: Double? = nil, fiber: Double? = nil,
        sugar: Double? = nil, satFat: Double? = nil, sodium: Double? = nil,
        fvn: Double? = nil, transFat: Double? = nil, nova: Int = 0,
        name: String, ingredientsText: String?,
        additives: [ProductAdditive] = [],
        categories: [String]
    ) -> Product {
        Product(
            id: name, name: name, brand: "B", size: "", glyph: "🛒",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(
                sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                fiber_g: fiber, protein_g: protein, calcium_mg: nil,
                kcal: kcal, fvn: fvn, transFat_g: transFat
            ),
            bonuses: [], transFats: (transFat ?? 0) > 0, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            labels: nil, packagingMaterials: nil, origins: nil,
            ingredientShares: nil, categories: categories
        )
    }

    @Test func snacksWeightsAndRamenBound() throws {
        let expected: [String: Double] = [
            "S1": 26, "S2": 28, "S3": 12, "S4": 16,
            "S5": 10, "S12": 5, "S13": 3,
        ]
        let snacks = try #require(rs.profiles["snacks"])
        #expect(snacks.reduce(0) { $0 + $1.w } == 100)
        for rule in snacks {
            #expect(expected[rule.rule] == rule.w)
        }

        let ramen = product(
            kcal: 440, protein: 10, fiber: 2, sugar: 2, satFat: 8, sodium: 1600,
            nova: 4, name: "ramen",
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
            categories: ["meals", "dried-products", "noodles"]
        )
        let score = try #require(ScoringEngineV4.score(ramen))
        #expect(score.profileId == "snacks")
        #expect(score.base <= 35)
        #expect(rs.bandLabel(score.base) == "Bad")
    }

    @Test func natureValleyStaysAtMost50AndCheeriosUnchanged() throws {
        let natureValley = product(
            kcal: 471, protein: 8, fiber: 6, sugar: 26, satFat: 2, sodium: 350,
            nova: 4, name: "Nature Valley",
            ingredientsText: "whole grain oats, sugar, canola oil, honey, soy lecithin, salt",
            additives: [.init(name: "e322", risk: .low, code: "e322", tier: .mild)],
            categories: ["snacks", "cereal-bars"]
        )
        let cheerios = product(
            kcal: 367, protein: 12, fiber: 10, sugar: 4.5, satFat: 0.8, sodium: 470,
            nova: 4, name: "Cheerios",
            ingredientsText: "whole grain oats, corn starch, sugar, salt",
            additives: [.init(name: "e340", risk: .moderate, code: "e340", tier: .mild)],
            categories: ["breakfast-cereals", "cereals"]
        )
        let nv = try #require(ScoringEngineV4.score(natureValley))
        let ch = try #require(ScoringEngineV4.score(cheerios))
        #expect(nv.base <= 50)
        #expect(ch.base == 58)
        #expect(ch.profileId == "breads")
    }

    @Test func fatsProfileRoutingAndCalibration() throws {
        let expected: [(String, Double, String?)] = [
            ("S5", 54, "fats"), ("S2", 16, nil), ("S1", 12, nil),
            ("S4", 10, nil), ("S13", 8, nil),
        ]
        let profile = try #require(rs.profiles["fats"])
        #expect(profile.count == expected.count)
        for (actual, expected) in zip(profile, expected) {
            #expect(actual.rule == expected.0)
            #expect(actual.w == expected.1)
            #expect(actual.variant == expected.2)
        }
        #expect(rs.s5Thresholds["fats"] == [8, 20, 40])
        #expect(!profile.contains(where: { $0.rule == "S12" }))

        let oliveOil = product(
            kcal: 884, sugar: 0, satFat: 14, sodium: 0, nova: 1,
            name: "extra-virgin olive oil", ingredientsText: "extra virgin olive oil",
            categories: ["vegetable-oils", "olive-oils"]
        )
        let unsaltedButter = product(
            kcal: 717, sugar: 0.1, satFat: 51, sodium: 11, transFat: 3, nova: 2,
            name: "unsalted butter", ingredientsText: "cream",
            categories: ["dairies", "butters"]
        )
        let saltedButter = product(
            kcal: 717, sugar: 0.1, satFat: 51, sodium: 650, transFat: 3, nova: 2,
            name: "salted butter", ingredientsText: "cream, salt",
            categories: ["dairies", "butters"]
        )
        let margarine = product(
            kcal: 700, sugar: 0, satFat: 15, sodium: 700, transFat: 1.5, nova: 4,
            name: "margarine",
            ingredientsText: "partially hydrogenated soybean oil, water, salt",
            categories: ["margarines"]
        )
        let coconutOil = product(
            kcal: 892, sugar: 0, satFat: 87, sodium: 0, nova: 2,
            name: "coconut oil", ingredientsText: "coconut oil",
            categories: ["vegetable-oils", "coconut-oils"]
        )

        for p in [oliveOil, unsaltedButter, saltedButter, margarine, coconutOil] {
            #expect(ScoringEngineV4.route(p) == "fats")
        }
        let olive = try #require(ScoringEngineV4.score(oliveOil))
        let butterScore = try #require(ScoringEngineV4.score(unsaltedButter))
        let saltedButterScore = try #require(ScoringEngineV4.score(saltedButter))
        let margarineScore = try #require(ScoringEngineV4.score(margarine))
        let coconut = try #require(ScoringEngineV4.score(coconutOil))
        #expect(olive.base >= 70)
        #expect(abs(butterScore.base - 45) <= 2)
        let butterDelta = butterScore.base - saltedButterScore.base
        #expect((4...8).contains(butterDelta))
        #expect(margarineScore.base <= 35)
        #expect(ScoringEngineV4.applyBaseCaps(base: 100, product: margarine, rs: rs)
            .fired.contains(where: { $0.kind == "transFat" }))
        #expect(coconut.base <= 42)
        #expect(coconut.base < butterScore.base)
        #expect(olive.base > butterScore.base)
        #expect(butterScore.base > coconut.base)
        #expect(coconut.base > margarineScore.base)
    }

    @Test func nnsTableProductCeiling() throws {
        let stevia = product(
            kcal: 0, sugar: 0, nova: 4, name: "stevia tablets",
            ingredientsText: "stevia leaf extract, erythritol",
            categories: ["sweeteners", "tabletop-sweeteners"]
        )
        let erythritol = product(
            kcal: 20, sugar: 2, nova: 4, name: "erythritol blend",
            ingredientsText: "erythritol, steviol glycosides",
            additives: [.init(name: "e960", risk: .low, code: "e960", tier: .mild)],
            categories: ["sweeteners", "tabletop-sweeteners"]
        )
        let honey = product(
            kcal: 304, sugar: 82, nova: 1, name: "raw honey",
            ingredientsText: "honey", categories: ["sweeteners", "honeys"]
        )
        // V5.0.7: table NNS + caloric sweeteners are unscored (nnsCeiling moot).
        for p in [stevia, erythritol, honey] {
            #expect(ScoringEngineV4.route(p) == "unscored_sweetener")
            #expect(ScoringEngineV4.score(p) == nil)
        }
        #expect(rs.additiveTiers["e960"] == "C")
    }
}
