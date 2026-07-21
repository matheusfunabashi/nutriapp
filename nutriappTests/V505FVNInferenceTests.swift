import Testing
import Foundation
@testable import Sage

struct V505FVNInferenceTests {
    private let rs = RulesetV4.bundled

    private func product(
        name: String,
        kcal: Double = 90,
        sugar: Double = 12,
        fiber: Double = 2.6,
        protein: Double = 1.1,
        nova: Int,
        categories: [String],
        fvn: Double? = nil
    ) -> Product {
        Product(
            id: name, name: name, brand: "", size: "", glyph: "🍌",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(
                sugar_g: sugar, sodium_mg: 1, satFat_g: 0.3,
                fiber_g: fiber, protein_g: protein, kcal: kcal, fvn: fvn
            ),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: [], restrictions: [],
            categories: categories
        )
    }

    private func profile() -> UserProfile {
        var user = MockData.user
        user.objective = "eat healthier"
        user.personalizeScoring = true
        return user
    }

    @Test func bananaInfersFVNAndScoresExcellent() throws {
        var banana = product(
            name: "banana", nova: 1, categories: ["fruits", "bananas"]
        )
        let resolution = ScoringEngineV4.resolvedFVN(banana)
        #expect(resolution.value == 100)
        #expect(resolution.inferredFrom == "fruits")

        let result = try #require(ScoringEngineV4.score(banana, ruleset: rs))
        #expect(result.base >= 80)
        #expect(result.rules.first { $0.rule == "S12" }?.hadData == true)

        banana.overallScore = result.base
        banana.yourScore = result.base
        let ctx = try #require(
            ScoringEngineV4.overviewContext(for: banana, profile: profile(), ruleset: rs)
        )
        #expect(!ctx.topNegative.contains { $0.topic == "sugar" })

        let debug = ScoringEngineV4.debugText(banana, for: profile(), ruleset: rs)
        #expect(debug.contains("fvn: 100 (inferred: fruits)"))

        guard case .scored(let stored) = ScoringEngineV4.scoreProduct(
            banana, for: profile(), ruleset: rs
        ) else {
            Issue.record("expected scored banana")
            return
        }
        #expect(stored.nutrients.fvn == nil)
        #expect(ScoringEngineV4.debugText(stored, for: profile(), ruleset: rs)
            .contains("fvn: 100 (inferred: fruits)"))
    }

    @Test func fruitFlavoredCandyDoesNotInferFVN() throws {
        let candy = product(
            name: "fruit candy", kcal: 390, sugar: 70, fiber: 0, protein: 0,
            nova: 4, categories: ["sweet-snacks", "candies"]
        )
        #expect(ScoringEngineV4.resolvedFVN(candy).value == nil)
        let result = try #require(ScoringEngineV4.score(candy, ruleset: rs))
        let s3 = try #require(result.rules.first { $0.rule == "S3" })
        #expect(s3.fraction == 0)
    }

    @Test func cannedFruitNovaThreeDoesNotInferFVN() throws {
        let canned = product(
            name: "peaches in syrup", kcal: 95, sugar: 22, fiber: 1, protein: 0.5,
            nova: 3, categories: ["fruits", "canned-fruits"]
        )
        #expect(ScoringEngineV4.resolvedFVN(canned).value == nil)
        let result = try #require(ScoringEngineV4.score(canned, ruleset: rs))
        let s12 = try #require(result.rules.first { $0.rule == "S12" })
        #expect(s12.fraction < 0.5)
    }

    @Test func inferenceAppliesOutsideWholeFoodsProfile() throws {
        let fruit = product(
            name: "mis-tagged fruit", nova: 1,
            categories: ["breakfast-cereals", "fruits"]
        )
        #expect(ScoringEngineV4.resolvedFVN(fruit).value == 100)
        // Router remains first-match; inference is independent of profile.
        #expect(ScoringEngineV4.route(fruit, ruleset: rs) == "breads")
        let result = try #require(ScoringEngineV4.score(fruit, ruleset: rs))
        #expect(result.rules.first { $0.rule == "S12" }?.hadData == true)
    }

    @Test func measuredFVNAlwaysWins() {
        let measured = product(
            name: "measured banana", nova: 1,
            categories: ["fruits", "bananas"], fvn: 63
        )
        #expect(ScoringEngineV4.resolvedFVN(measured) == .init(value: 63, inferredFrom: nil))
    }

    @Test func rulesetVersionIsV505() {
        #expect(rs.version == "2026.07-v5.0.7")
    }
}
