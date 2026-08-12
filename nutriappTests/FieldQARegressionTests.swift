import Testing
import Foundation
@testable import Sage

/// Regressions found by scanning real products in the app (field QA).
/// Each fixture is the exact live OFF payload the user scanned.
@Suite(.serialized)
struct FieldQARegressionTests {

    private func loadBulk(_ code: String) throws -> Product {
        let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        // Bulk corpus first, then the original top-level captures.
        let candidates = [base.appendingPathComponent("Bulk/off_\(code).json"),
                          base.appendingPathComponent("off_\(code).json")]
        let url = candidates.first { FileManager.default.fileExists(atPath: $0.path) }
            ?? candidates[0]
        return try OpenFoodFactsService.makeProduct(from: Data(contentsOf: url),
                                                    barcode: code)
    }

    /// I29 — plain water stays unscored no matter what tags it wears.
    /// Live bug: US S.Pellegrino carried Spanish category tags ("Aguas",
    /// "Bebidas") that matched no router entry and scored 77 in-app.
    @Test func invariantI29_PlainWaterEvidenceBeatsTags() throws {
        let pellegrino = try loadBulk("0041508800082")
        #expect(ScoringEngineV4.isPlainWaterByEvidence(pellegrino))
        #expect(ScoringEngineV4.route(pellegrino) == "unsupported")
        #expect(ScoringEngineV4.score(pellegrino) == nil)
    }

    /// The water gate must NOT catch flavored waters (they stay scoreable) —
    /// the flavor vocabulary is the boundary.
    @Test func waterGateSparesFlavoredWater() throws {
        let lacroix = try loadBulk("0012993441128")
        #expect(!ScoringEngineV4.isPlainWaterByEvidence(lacroix))
        #expect(ScoringEngineV4.route(lacroix) == "drinks")
    }

    /// I30 — a multi-serve bottle cannot score better than the same liquid in
    /// a can by declaring a small serving. Live find: 1 L Coca-Cola with a
    /// declared 250 ml serving scored 29 vs 20 for the 355 ml can.
    @Test func invariantI30_MultiServeServingParity() throws {
        let liter = try loadBulk("5449000054227")   // 1 L, declared 250 ml
        let can = try loadBulk("5449000000439")     // canonical can payload
        let rLiter = try #require(ScoringEngineV4.score(liter))
        let rCan = try #require(ScoringEngineV4.score(can))
        #expect(abs(rLiter.base - rCan.base) <= 3,
                "same liquid \(rLiter.base) vs \(rCan.base)")
        // The declared 250 ml was floored to the cola-typical 355 ml dose.
        let bd = try #require(rLiter.drinksBreakdown)
        #expect(bd.effectiveServingMl >= 355)
        #expect(bd.estimatedServing)
    }

    /// Serving floor never touches honest declarations: a 1 L juice carton
    /// declaring a 200 ml glass (= the category dose) keeps it, unflagged.
    @Test func servingFloorSparesHonestDeclarations() {
        var oj = Product(
            id: "oj", name: "OJ 1L carton", brand: "T", size: "1 L", glyph: "🧃",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: 1,
            nutrients: Nutrients(sugar_g: 9.5, sodium_mg: 1, satFat_g: 0,
                                 fiber_g: 0, protein_g: 0, kcal: 45, fvn: 100,
                                 addedSugar_g: nil),
            bonuses: [], transFats: false, caffeine_mg: 0,
            sweeteners: [], seedOils: false, additives: [], restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: "orange juice", imageURL: nil,
            labels: nil, packagingMaterials: ["carton"], origins: nil,
            ingredientShares: nil,
            categories: ["beverages", "juices", "fruit-juices", "orange-juices"]
        )
        oj.servingSize = "200 ml"
        let s = DrinksScoring.effectiveServing(for: oj)
        #expect(s.ml == 200)
        #expect(!s.estimatedServing)
    }
}
