import Testing
import Foundation
@testable import Sage

struct AvoidListMatcherTests {

    @Test func jifStyleHydrogenatedSeedOilsFlagged() {
        let text = "Fully hydrogenated vegetable oils (rapeseed and soybean), sugar, molasses"
        #expect(AvoidListMatcher.containsSeedOils(ingredientsText: text))

        var profile = MockData.user
        profile.avoidList = ["Seed oils"]
        let product = fixture(
            ingredients: text,
            seedOils: AvoidListMatcher.containsSeedOils(ingredientsText: text)
        )
        let hit = ScoringEngineV4.avoidListHit(product, profile: profile, rs: .bundled)
        #expect(hit == "Seed oils")
    }

    @Test func oliveOilAloneDoesNotFlag() {
        let text = "Roasted peanuts, sugar, salt, olive oil"
        #expect(!AvoidListMatcher.containsSeedOils(ingredientsText: text))

        var profile = MockData.user
        profile.avoidList = ["Seed oils"]
        let product = fixture(ingredients: text, seedOils: false)
        let hit = ScoringEngineV4.avoidListHit(product, profile: profile, rs: .bundled)
        #expect(hit == nil)
    }

    @Test func cornSyrupWithOliveOilDoesNotFlag() {
        // Regression: bare "corn" must not fire just because the word "oil" appears.
        let text = "Water, corn syrup, olive oil, salt"
        #expect(!AvoidListMatcher.containsSeedOils(ingredientsText: text))
    }

    @Test func classicSoybeanOilFlags() {
        #expect(AvoidListMatcher.containsSeedOils(ingredientsText: "soybean oil, salt"))
    }

    private func fixture(ingredients: String, seedOils: Bool) -> Product {
        Product(
            id: "0051500255162",
            name: "Creamy Peanut Butter",
            brand: "Jif",
            size: "454 g",
            glyph: "🥜",
            overallScore: 40,
            yourScore: 39,
            overview: nil,
            nutriGrade: "D",
            novaGroup: 4,
            nutrients: Nutrients(sugar_g: 9, sodium_mg: 350, satFat_g: 3.5,
                                 fiber_g: 6, protein_g: 22, kcal: 590),
            bonuses: [],
            transFats: false,
            caffeine_mg: nil,
            sweeteners: [],
            seedOils: seedOils,
            additives: [],
            restrictions: [],
            ingredientsText: ingredients,
            categories: ["spreads", "nut-butters"]
        )
    }
}
