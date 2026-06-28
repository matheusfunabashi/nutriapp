import Testing
import Foundation
@testable import Sage

struct AllergenMatcherTests {

    private func product(allergenTags: [String] = [], ingredients: String? = nil) -> Product {
        Product(
            id: "x", name: "Test", brand: "B", size: "", glyph: "🛒",
            overallScore: 50, yourScore: 50, deltaReason: nil,
            nutriGrade: "C", novaGroup: 4,
            nutrients: Nutrients(sugar_g: nil, sodium_mg: nil, satFat_g: nil,
                                 fiber_g: nil, protein_g: nil, calcium_mg: nil),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: [], restrictions: [],
            dietFlags: nil, allergenTags: allergenTags, ingredientsText: ingredients
        )
    }

    @Test func structuredTagMatchIsHighConfidence() {
        let p = product(allergenTags: ["milk"])
        let w = AllergenMatcher.warnings(product: p, allergies: ["Milk"])
        #expect(w.count == 1)
        #expect(w.first?.fromTag == true)
    }

    @Test func ingredientKeywordMatchIsLowerConfidence() {
        let p = product(ingredients: "Sugar, roasted peanuts, salt")
        let w = AllergenMatcher.warnings(product: p, allergies: ["Peanuts"])
        #expect(w.count == 1)
        #expect(w.first?.fromTag == false)
    }

    @Test func noMatchProducesNoWarning() {
        let p = product(allergenTags: ["milk"], ingredients: "Water, sugar")
        let w = AllergenMatcher.warnings(product: p, allergies: ["Soy"])
        #expect(w.isEmpty)
    }

    @Test func freeTextAllergyMatchesIngredients() {
        let p = product(ingredients: "Flour, sesame seeds, oil")
        let w = AllergenMatcher.warnings(product: p, allergies: ["sesame"])
        #expect(w.count == 1)
    }

    @Test func shellfishMapsToCrustaceansOrMolluscs() {
        let p = product(allergenTags: ["molluscs"])
        let w = AllergenMatcher.warnings(product: p, allergies: ["Shellfish"])
        #expect(w.first?.fromTag == true)
    }

    @Test func emptyAllergiesProducesNothing() {
        let p = product(allergenTags: ["milk", "eggs"])
        #expect(AllergenMatcher.warnings(product: p, allergies: []).isEmpty)
    }

    @Test func shortFreeTextIsIgnored() {
        // 2-char free-text shouldn't trigger noisy substring matches.
        let p = product(ingredients: "Contains a bit of everything")
        let w = AllergenMatcher.warnings(product: p, allergies: ["ab"])
        #expect(w.isEmpty)
    }
}
