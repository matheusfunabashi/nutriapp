import Testing
import Foundation
@testable import Sage

// Covers the two client-side halves of the backend integration:
// decoding the Worker's /lookup envelope with the existing OFF mapper,
// and the signed factor strings sent to /explain.
struct BackendIntegrationTests {

    // MARK: /lookup envelope → existing mapper

    @Test func lookupEnvelopeDecodesViaOFFMapper() throws {
        // The Worker wraps the raw OFF product as {source, product}; the OFF
        // decoder only reads `product`, so the body must decode unchanged.
        let body = """
        {
          "source": "cache",
          "product": {
            "product_name": "Coca-Cola",
            "brands": "Coca-Cola",
            "nutriscore_grade": "e",
            "nova_group": 4,
            "nutriments": { "sugars_100g": 10.6, "energy-kcal_100g": 42 }
          }
        }
        """.data(using: .utf8)!

        let p = try OpenFoodFactsService.makeProduct(from: body, barcode: "5449000000996")
        #expect(p.id == "5449000000996")
        #expect(p.name == "Coca-Cola")
        #expect(p.novaGroup == 4)
        #expect(p.nutrients.kcal == 42)
    }

    @Test func lookupNotFoundEnvelopeThrows() {
        let body = #"{"error":"not_found"}"#.data(using: .utf8)!
        #expect(throws: OpenFoodFactsService.LookupError.notFound) {
            _ = try OpenFoodFactsService.makeProduct(from: body, barcode: "000")
        }
    }

    // MARK: Product images

    @Test func imageURLMappedFromLookup() throws {
        let body = """
        {
          "source": "off",
          "product": {
            "product_name": "Pictured product",
            "nutriments": {},
            "image_front_url": "https://images.openfoodfacts.org/x/front.jpg"
          }
        }
        """.data(using: .utf8)!
        let p = try OpenFoodFactsService.makeProduct(from: body, barcode: "1")
        #expect(p.imageURL == "https://images.openfoodfacts.org/x/front.jpg")
    }

    @Test func missingImageIsNilNotError() throws {
        // "No image" is a first-class state — the glyph placeholder renders.
        let body = #"{"source":"off","product":{"product_name":"Bare","nutriments":{}}}"#
            .data(using: .utf8)!
        let p = try OpenFoodFactsService.makeProduct(from: body, barcode: "2")
        #expect(p.imageURL == nil)
    }

    @Test func imageURLSanitizing() {
        #expect(OpenFoodFactsService.sanitizedImageURL(nil) == nil)
        #expect(OpenFoodFactsService.sanitizedImageURL("") == nil)
        #expect(OpenFoodFactsService.sanitizedImageURL("   ") == nil)
        // Plain http would be blocked by ATS — treated as no image.
        #expect(OpenFoodFactsService.sanitizedImageURL("http://img.example/a.jpg") == nil)
        #expect(OpenFoodFactsService.sanitizedImageURL("https://img.example/a.jpg")
                == "https://img.example/a.jpg")
    }

    // MARK: signedFactors

    private func product(
        kcal: Double?, protein: Double? = nil, fiber: Double? = nil,
        sugar: Double? = nil, satFat: Double? = nil, sodium: Double? = nil,
        fvn: Double? = nil, nova: Int = 0
    ) -> Product {
        Product(
            id: "x", name: "T", brand: "B", size: "100 g", glyph: "🛒",
            overallScore: 0, yourScore: 0, deltaReason: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                 fiber_g: fiber, protein_g: protein, calcium_mg: nil,
                                 kcal: kcal, fvn: fvn),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: [], restrictions: [],
            dietFlags: [], allergenTags: nil, ingredientsText: nil
        )
    }

    private func profile(_ objective: String) -> UserProfile {
        var u = MockData.user
        u.objective = objective
        return u
    }

    private var chicken: Product { product(kcal: 165, protein: 31, fiber: 0, sugar: 0, satFat: 1, sodium: 74, fvn: 0, nova: 1) }
    private var cheetos: Product { product(kcal: 570, protein: 6, fiber: 1, sugar: 3, satFat: 4, sodium: 800, fvn: 0, nova: 4) }
    private var apple: Product   { product(kcal: 52, protein: 0.3, fiber: 2.4, sugar: 10.4, satFat: 0, sodium: 1, fvn: 100, nova: 1) }

    @Test func everyFactorIsSigned() {
        for p in [chicken, cheetos, apple] {
            for obj in ["build muscle", "lose weight", "eat healthier", "maintain"] {
                for f in ScoringEngine.signedFactors(p, profile: profile(obj)) {
                    #expect(f.hasPrefix("+ ") || f.hasPrefix("- "),
                            "unsigned factor '\(f)' for \(obj)")
                }
            }
        }
    }

    @Test func chickenRaisesMuscleScore() {
        let f = ScoringEngine.signedFactors(chicken, profile: profile("build muscle"))
        #expect(f.contains("+ high protein per calorie"))
        #expect(!f.contains { $0.hasPrefix("- ") })
    }

    @Test func cheetosHeldBackForMuscle() {
        // Factors describe the personalization delta: low protein density and
        // the profile's low-sodium preference (MockData) both pull it down.
        let f = ScoringEngine.signedFactors(cheetos, profile: profile("build muscle"))
        #expect(f.contains("- low protein per calorie for a muscle goal"))
        #expect(f.contains("- high sodium (you prefer low sodium)"))
    }

    @Test func appleRaisesEatHealthier() {
        let f = ScoringEngine.signedFactors(apple, profile: profile("eat healthier"))
        #expect(f.contains("+ mostly whole fruits, vegetables, or nuts"))
        #expect(f.contains("+ minimally processed"))
    }

    @Test func unknownNovaIsNotAssertedAsProcessed() {
        // When NOVA is unknown the prompt must not claim a processing level
        // as fact — no "processed"-related factor may appear.
        let unknown = product(kcal: 100, protein: 5, nova: 0)
        for obj in ["build muscle", "lose weight", "eat healthier", "maintain"] {
            let f = ScoringEngine.signedFactors(unknown, profile: profile(obj))
            #expect(!f.contains { $0.lowercased().contains("processed") })
        }
    }

    @Test func factorsAreCapped() {
        for p in [chicken, cheetos, apple] {
            for obj in ["build muscle", "lose weight", "eat healthier", "maintain"] {
                #expect(ScoringEngine.signedFactors(p, profile: profile(obj)).count <= 5)
            }
        }
    }

    @Test func restrictionConflictLeadsFactors() {
        // Hard-capped scans get an explanation too — the conflict must be the
        // first thing the LLM sees.
        var u = profile("eat healthier")
        u.restrictions = ["Low-sugar diet"]
        u.autoFlagRestrictions = true
        let candy = product(kcal: 400, sugar: 60, satFat: 5, sodium: 50, nova: 4)
        let scored = ScoringEngine.score(candy, for: u)
        let f = ScoringEngine.signedFactors(scored, profile: u)
        #expect(f.first == "- conflicts with your low-sugar diet restriction (high sugar)")
    }

    @Test func personalizationOffUsesOverallDriversOnly() {
        var u = profile("build muscle")
        u.personalizeScoring = false
        let f = ScoringEngine.signedFactors(cheetos, profile: u)
        #expect(!f.contains("- low protein per calorie for a muscle goal"))
        #expect(f.contains("- ultra-processed (NOVA 4)"))
    }
}
