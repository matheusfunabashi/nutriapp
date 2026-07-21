import Testing
import Foundation
@testable import Sage

struct OpenFoodFactsMappingTests {

    // A representative OFF v2 response (soda-like product).
    private let colaJSON = """
    {
      "product": {
        "product_name": "Test Cola",
        "brands": "TestBrand, Other Co",
        "quantity": "330 ml",
        "nutriscore_grade": "e",
        "nova_group": 4,
        "additives_tags": ["en:e150d", "en:e338", "en:e999"],
        "ingredients_text": "Water, sugar, sunflower oil, caffeine",
        "categories_tags": ["en:beverages", "en:sodas"],
        "nutriments": {
          "sugars_100g": 10.6,
          "salt_100g": 0.05,
          "saturated-fat_100g": 0.0,
          "proteins_100g": 0.0,
          "trans-fat_100g": 0.0,
          "caffeine_100g": 0.012
        }
      }
    }
    """

    @Test func mapsCoreFields() throws {
        let p = try OpenFoodFactsService.makeProduct(from: Data(colaJSON.utf8), barcode: "123")
        #expect(p.id == "123")
        #expect(p.name == "Test Cola")
        #expect(p.brand == "TestBrand")          // first brand only
        #expect(p.size == "330 ml")
        #expect(p.novaGroup == 4)
        #expect(p.nutriGrade == "E")             // uppercased
        #expect(p.glyph == "🥤")                  // beverage category
    }

    @Test func derivesKcalFromKilojoulesWhenKcalMissing() throws {
        // Many EU products report only kJ; scoring needs kcal for protein density.
        let json = """
        { "product": { "product_name": "EU Snack", "nova_group": 1,
          "nutriments": { "energy-kj_100g": 1000, "proteins_100g": 8 } } }
        """
        let p = try OpenFoodFactsService.makeProduct(from: Data(json.utf8), barcode: "eu1")
        #expect(p.nutrients.kcal != nil)                         // 1000 kJ ÷ 4.184 ≈ 239
        #expect(abs((p.nutrients.kcal ?? 0) - 239.0) < 1.0)
    }

    @Test func placeholderScoreFromGrade() throws {
        let p = try OpenFoodFactsService.makeProduct(from: Data(colaJSON.utf8), barcode: "123")
        #expect(p.overallScore == 16)            // grade E placeholder
        #expect(p.yourScore == 16)               // not personalized yet
    }

    @Test func derivesSodiumFromSalt() throws {
        let p = try OpenFoodFactsService.makeProduct(from: Data(colaJSON.utf8), barcode: "123")
        // salt 0.05 g → sodium 0.05/2.5*1000 = 20 mg
        #expect(p.nutrients.sodium_mg == 20)
        #expect(p.nutrients.sugar_g == 10.6)
        #expect(p.caffeine_mg == 12)  // OFF stores grams; map ×1000 → mg
    }

    @Test func mapsAdditivesWithRiskAndUnratedFallback() throws {
        let p = try OpenFoodFactsService.makeProduct(from: Data(colaJSON.utf8), barcode: "123")
        #expect(p.additives.count == 3)

        let caramel = p.additives.first { $0.name.contains("Caramel") }
        #expect(caramel?.risk == .moderate)

        // Unknown additive → unrated, code shown uppercased.
        let unknown = p.additives.first { $0.name == "E999" }
        #expect(unknown?.risk == .unrated)
        #expect(unknown?.note == nil)
    }

    @Test func detectsSeedOils() throws {
        let p = try OpenFoodFactsService.makeProduct(from: Data(colaJSON.utf8), barcode: "123")
        #expect(p.seedOils == true)              // "sunflower oil" in ingredients
    }

    @Test func detectsSweetenersAndHighRiskNote() throws {
        let json = """
        {
          "product": {
            "product_name": "Diet Drink",
            "brands": "Zero",
            "nutriscore_grade": "c",
            "nova_group": 4,
            "additives_tags": ["en:e951", "en:e955"],
            "nutriments": { "sugars_100g": 0 }
          }
        }
        """
        let p = try OpenFoodFactsService.makeProduct(from: Data(json.utf8), barcode: "555")
        #expect(p.sweeteners.contains("aspartame"))
        #expect(p.sweeteners.contains("sucralose"))

        let aspartame = p.additives.first {
            $0.code == "e951" || $0.name.localizedCaseInsensitiveContains("aspartame")
        }
        #expect(aspartame?.risk == .moderate)    // KB tier for E951
        #expect(aspartame?.tier == .moderate)
        #expect(aspartame?.note != nil)
        #expect(p.overallScore == 54)            // grade C placeholder
    }

    @Test func missingProductThrowsNotFound() {
        let json = "{ }"
        #expect(throws: OpenFoodFactsService.LookupError.notFound) {
            try OpenFoodFactsService.makeProduct(from: Data(json.utf8), barcode: "000")
        }
    }

    @Test func emptyProductThrowsNotFound() {
        let json = "{ \"product\": {} }"
        #expect(throws: OpenFoodFactsService.LookupError.notFound) {
            try OpenFoodFactsService.makeProduct(from: Data(json.utf8), barcode: "000")
        }
    }

    @Test func novaFallbackScoreWhenNoGrade() throws {
        let json = """
        { "product": { "product_name": "Whole Oats", "nova_group": 1,
          "nutriments": { "fiber_100g": 10 } } }
        """
        let p = try OpenFoodFactsService.makeProduct(from: Data(json.utf8), barcode: "777")
        #expect(p.nutriGrade == "?")             // no grade
        #expect(p.overallScore == 80)            // NOVA 1 fallback
        #expect(p.nutrients.fiber_g == 10)
    }
}
