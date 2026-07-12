import Testing
import Foundation
@testable import Sage

// Scoring-v4 Phase A: widened OFF field mapping, the minimum-data
// requirement, and the provisional Data Confidence checklist.
struct DataFoundationTests {

    // MARK: Widened field mapping

    @Test func v4FieldsMapFromLookup() throws {
        let body = """
        {
          "source": "off",
          "product": {
            "product_name": "Oat drink",
            "nova_group": 4,
            "nutriments": {
              "energy-kcal_100g": 45, "sugars_100g": 4, "added-sugars_100g": 3.2,
              "proteins_100g": 1, "fiber_100g": 0.8
            },
            "labels_tags": ["en:organic", "en:eu-organic"],
            "packagings": [{ "material": "en:tetra-pak" }],
            "packaging_materials_tags": ["en:cardboard"],
            "origins_tags": ["en:sweden"],
            "ingredients": [
              { "id": "en:water", "percent_estimate": 88.5 },
              { "id": "en:oats", "percent": "10", "percent_estimate": 10.2 }
            ],
            "ecoscore_grade": "b",
            "completeness": 0.85,
            "last_modified_t": 1780000000,
            "serving_size": "250 ml",
            "countries_tags": ["en:united-kingdom", "en:sweden"]
          }
        }
        """.data(using: .utf8)!

        let p = try OpenFoodFactsService.makeProduct(from: body, barcode: "1")
        #expect(p.labels == ["organic", "eu-organic"])
        #expect(p.packagingMaterials == ["tetra-pak", "cardboard"])
        #expect(p.origins == ["sweden"])
        #expect(p.ecoGrade == "b")
        #expect(p.servingSize == "250 ml")
        #expect(p.completeness == 0.85)
        #expect(p.countries == ["united-kingdom", "sweden"])
        #expect(p.nutrients.addedSugar_g == 3.2)
        #expect(p.lastModified == Date(timeIntervalSince1970: 1_780_000_000))

        let oats = p.ingredientShares?.first { $0.name == "oats" }
        #expect(oats?.percent == 10)          // string "10" decoded leniently
        #expect(oats?.percentEstimate == 10.2)
    }

    @Test func absentV4FieldsStayNil() throws {
        let body = #"{"source":"off","product":{"product_name":"Bare","nutriments":{"sugars_100g":5}}}"#
            .data(using: .utf8)!
        let p = try OpenFoodFactsService.makeProduct(from: body, barcode: "2")
        #expect(p.labels == nil)
        #expect(p.packagingMaterials == nil)
        #expect(p.ingredientShares == nil)
        #expect(p.ecoGrade == nil)
        #expect(p.completeness == nil)
    }

    @Test func nonGradeEcoValuesAreNoData() throws {
        let body = #"{"source":"off","product":{"product_name":"X","nutriments":{},"ingredients_text":"water","ecoscore_grade":"not-applicable"}}"#
            .data(using: .utf8)!
        let p = try OpenFoodFactsService.makeProduct(from: body, barcode: "3")
        #expect(p.ecoGrade == nil)
    }

    // MARK: Minimum data requirement (§3.3)

    private func bareProduct(ingredientsText: String? = nil,
                             kcal: Double? = nil,
                             nova: Int = 0,
                             additives: [ProductAdditive] = [],
                             shares: [IngredientShare]? = nil) -> Product {
        Product(
            id: "x", name: "T", brand: "B", size: "", glyph: "🛒",
            overallScore: 0, yourScore: 0, deltaReason: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: nil, sodium_mg: nil, satFat_g: nil,
                                 fiber_g: nil, protein_g: nil, calcium_mg: nil,
                                 kcal: kcal),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            ingredientShares: shares
        )
    }

    @Test func minimumDataRequirement() {
        #expect(!bareProduct().hasMinimumData)                       // nothing → gate
        #expect(!bareProduct(ingredientsText: "water, oats").hasMinimumData) // text alone
        #expect(!bareProduct(kcal: 45).hasMinimumData)               // one macro ≠ table
        #expect(bareProduct(ingredientsText: "water", nova: 1).hasMinimumData) // known NOVA
        #expect(bareProduct(ingredientsText: "water",
                            additives: [ProductAdditive(name: "Aspartame", risk: .moderate,
                                                         code: "e951")]).hasMinimumData)
        let proteinOnly = Product(
            id: "p", name: "Hydro", brand: "", size: "", glyph: "🛒",
            overallScore: 0, yourScore: 0, deltaReason: nil,
            nutriGrade: "?", novaGroup: 0,
            nutrients: Nutrients(sugar_g: nil, sodium_mg: nil, satFat_g: nil,
                                 fiber_g: nil, protein_g: 80, calcium_mg: nil, kcal: nil),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: [], restrictions: [],
            dietFlags: nil, allergenTags: nil, ingredientsText: nil, imageURL: nil
        )
        #expect(!proteinOnly.hasMinimumData)
        let nutritionTable = Product(
            id: "n", name: "N", brand: "", size: "", glyph: "🛒",
            overallScore: 0, yourScore: 0, deltaReason: nil,
            nutriGrade: "?", novaGroup: 0,
            nutrients: Nutrients(sugar_g: 4, sodium_mg: 40, satFat_g: nil,
                                 fiber_g: nil, protein_g: 1, calcium_mg: nil, kcal: 45),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: [], restrictions: [],
            dietFlags: nil, allergenTags: nil, ingredientsText: nil, imageURL: nil
        )
        #expect(nutritionTable.hasMinimumData)                       // 3+ core fields
        #expect(!bareProduct(shares: [IngredientShare(name: "water", percent: nil,
                                                     percentEstimate: 90)]).hasMinimumData)
        #expect(!bareProduct(ingredientsText: "").hasMinimumData)    // empty ≠ present

        // Prata Água Mineral pattern: one-line ingredients, no nutrition, unknown NOVA.
        let prata = bareProduct(ingredientsText: "água mineral natural")
        #expect(!prata.hasMinimumData)
        #expect(!prata.hasScoreableIngredientSignal)
    }

    // MARK: Data confidence (§3.2, provisional Phase-A checklist)

    @Test func confidenceLevels() {
        // Rich record: ingredients + full nutrition + NOVA + packaging → high.
        var rich = bareProduct(ingredientsText: "water, oats")
        rich = Product(
            id: rich.id, name: rich.name, brand: rich.brand, size: rich.size,
            glyph: rich.glyph, overallScore: 0, yourScore: 0, deltaReason: nil,
            nutriGrade: "?", novaGroup: 4,
            nutrients: Nutrients(sugar_g: 4, sodium_mg: 40, satFat_g: 0.5,
                                 fiber_g: 0.8, protein_g: 1, calcium_mg: nil,
                                 kcal: 45),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: [], restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: "water, oats", imageURL: nil,
            packagingMaterials: ["tetra-pak"]
        )
        #expect(rich.dataConfidence == .high)

        // Nothing at all → low.
        #expect(bareProduct().dataConfidence == .low)

        // Ingredients + NOVA + partial nutrition, no packaging → medium
        // (0.30 + 0.15 + 3/6·0.30 = 0.60).
        let mid = Product(
            id: "m", name: "M", brand: "", size: "", glyph: "🛒",
            overallScore: 0, yourScore: 0, deltaReason: nil,
            nutriGrade: "?", novaGroup: 4,
            nutrients: Nutrients(sugar_g: 4, sodium_mg: nil, satFat_g: nil,
                                 fiber_g: nil, protein_g: 1, calcium_mg: nil,
                                 kcal: 45),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: [], restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: "water, oats", imageURL: nil
        )
        #expect(mid.dataConfidence == .medium)
    }
}
