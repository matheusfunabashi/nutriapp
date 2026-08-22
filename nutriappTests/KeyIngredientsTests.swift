import Testing
import Foundation
@testable import Sage

/// Key ingredients (product page): label-derived per-ingredient verdicts.
/// The classifier must agree with the engine's tables and never guess:
/// additives carry their risk tier, the curated KB wins over the whole-food
/// whitelist for sugars ("honey" is whole food to S14 but 'Limit' here), and
/// unknown tokens stay 'Fine'.
struct KeyIngredientsTests {

    private func product(_ ingredients: String?,
                         additives: [ProductAdditive] = [],
                         shares: [IngredientShare]? = nil) -> Product {
        Product(
            id: "t", name: "Test", brand: "Brand", size: "", glyph: "🍫",
            overallScore: 50, yourScore: 50, overview: nil,
            nutriGrade: "?", novaGroup: 4,
            nutrients: Nutrients(sugar_g: 10, sodium_mg: 100, satFat_g: 2,
                                 fiber_g: 1, protein_g: 2, calcium_mg: nil),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredients, imageURL: nil,
            labels: nil, packagingMaterials: nil, origins: nil,
            ingredientShares: shares, categories: nil
        )
    }

    private func verdict(_ a: KeyIngredients.Analysis?, _ token: String) -> KeyIngredients.Verdict? {
        a?.items.first { $0.token == token }?.verdict
    }

    @Test func nutellaLikeListSplitsGoodAndLimit() {
        let text = "Sugar, palm oil, hazelnuts (13%), skimmed milk powder, fat-reduced cocoa, emulsifier: lecithins (soya), vanillin"
        let a = KeyIngredients.analyze(product(text))
        #expect(a != nil)
        #expect(verdict(a, "sugar") == .limit)
        #expect(verdict(a, "palm oil") == .limit)
        #expect(verdict(a, "hazelnuts") == .good)
        #expect(verdict(a, "skimmed milk powder") == .neutral)
        #expect(verdict(a, "fat-reduced cocoa") == .good)
        #expect(verdict(a, "vanillin") == .neutral)
        // Sorted avoid → limit → good → fine, recipe order within.
        let order = a!.items.map(\.verdict)
        #expect(order == order.sorted())
        #expect(a!.items.first?.token == "sugar")
        #expect(a!.goodCount == 2)
        #expect(a!.watchCount == 2)
    }

    @Test func detectedAdditiveCarriesItsRisk() {
        let caramel = ProductAdditive(name: "Caramel colour IV (E150D)", risk: .moderate, code: "e150d")
        let aspartame = ProductAdditive(name: "Aspartame (E951)", risk: .high, code: "e951")
        let a = KeyIngredients.analyze(product(
            "Carbonated water, caramel color, phosphoric acid, aspartame, natural flavors",
            additives: [caramel, aspartame]))
        #expect(verdict(a, "caramel color") == .limit)          // class stem match: "caramel colour iv" → "caramel color"
        #expect(a?.items.first { $0.token == "caramel color" }?.additive?.code == "e150d")
        #expect(verdict(a, "aspartame") == .avoid)
        #expect(verdict(a, "carbonated water") == .neutral)
        #expect(verdict(a, "natural flavors") == .neutral)
        #expect(a?.hasAvoid == true)
        // Additive rows show the curated name, not the label token.
        #expect(a?.items.first { $0.token == "aspartame" }?.name == "Aspartame")
    }

    @Test func qualifiersAndSpecificityResolveToTheRightEntry() {
        let a = KeyIngredients.analyze(product(
            "Organic whole wheat flour, unbleached enriched wheat flour, organic cane sugar, extra virgin olive oil, soybean oil, partially hydrogenated soybean oil, honey, sea salt"))
        #expect(verdict(a, "organic whole wheat flour") == .good)
        #expect(verdict(a, "unbleached enriched wheat flour") == .neutral)
        #expect(verdict(a, "organic cane sugar") == .limit)
        #expect(verdict(a, "extra virgin olive oil") == .good)
        #expect(verdict(a, "soybean oil") == .limit)
        #expect(verdict(a, "partially hydrogenated soybean oil") == .avoid)
        #expect(verdict(a, "honey") == .limit)                 // KB beats the S14 whitelist
        #expect(verdict(a, "sea salt") == .neutral)
    }

    @Test func engineTablesCoverWhatTheKBDoesNot() {
        let a = KeyIngredients.analyze(product("Blueberries, water, erythritol, whey protein isolate, xyzzy extract"))
        #expect(verdict(a, "blueberries") == .good)             // whitelist
        #expect(verdict(a, "water") == .neutral)                // water token
        #expect(verdict(a, "erythritol") == .limit)             // sweetener system
        #expect(verdict(a, "whey protein isolate") == .neutral) // KB protein isolate — never docked
        #expect(verdict(a, "xyzzy extract") == .neutral)        // unknown stays neutral, never guessed
    }

    @Test func noListMeansNoAnalysis() {
        #expect(KeyIngredients.analyze(product(nil)) == nil)
        #expect(KeyIngredients.analyze(product("")) == nil)
        // Marketing prose in the ingredients field is not a list.
        #expect(KeyIngredients.analyze(product("Delicious and healthy snack for the whole family to enjoy every day")) == nil)
    }

    @Test func duplicatesCollapseAndSharesJoin() {
        let a = KeyIngredients.analyze(product(
            "Whole grain oats, salt, almonds, salt",
            shares: [IngredientShare(name: "whole-grain-oats", percent: 62, percentEstimate: nil),
                     IngredientShare(name: "almonds", percent: nil, percentEstimate: 12)]))
        #expect(a?.items.filter { $0.token == "salt" }.count == 1)
        #expect(a?.total == 4)
        let oats = a?.items.first { $0.token == "whole grain oats" }
        #expect(oats?.share == 62)
        #expect(oats?.shareIsDeclared == true)
        let almonds = a?.items.first { $0.token == "almonds" }
        #expect(almonds?.share == 12)
        #expect(almonds?.shareIsDeclared == false)
    }

    @Test func knowledgeBaseLoadsAndMatchTermsAreUnique() {
        let entries = IngredientKnowledgeBase.entries
        #expect(entries.count >= 50)
        var seen = Set<String>()
        for e in entries {
            #expect(KeyIngredients.Verdict(key: e.verdict) != nil, "unknown verdict \(e.verdict) on \(e.id)")
            for m in e.match {
                #expect(!seen.contains(m), "duplicate match term \(m)")
                seen.insert(m)
            }
        }
        #expect(IngredientKnowledgeBase.entry(matching: "whole wheat flour")?.id == "whole-wheat")
        #expect(IngredientKnowledgeBase.entry(matching: "wheat flour")?.id == "wheat-flour")
    }
}
