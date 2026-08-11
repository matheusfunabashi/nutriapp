import Testing
import Foundation
@testable import Sage

/// Live-pipeline diagnosis only — does NOT assert golden ranges.
/// Loads captured OFF JSON and prints fixture-vs-live diffs for Coca-Cola / Red Bull.
@Suite(.serialized)
struct DrinksLivePipelineDiagnosisTests {

    private func fixturesDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }

    private func loadOFF(_ code: String) throws -> Product {
        let url = fixturesDir().appendingPathComponent("off_\(code).json")
        let data = try Data(contentsOf: url)
        return try OpenFoodFactsService.makeProduct(from: data, barcode: code)
    }

    private func score(_ p: Product) -> (Int, String, DrinksScoreBreakdown) {
        let r = ScoringEngineV4.score(p)!
        return (r.base, r.profileId, r.drinksBreakdown!)
    }

    /// Golden Coca-Cola fixture (can, 355 ml) — same as DrinksScoringGoldenTests.
    private var fixtureCoca: Product {
        var p = Product(
            id: "fixture-coca", name: "Coca-Cola", brand: "T", size: "355 ml", glyph: "🥤",
            overallScore: 0, yourScore: 0, overview: nil, nutriGrade: "?", novaGroup: 4,
            nutrients: Nutrients(
                sugar_g: 10.986, sodium_mg: 4, satFat_g: 0, fiber_g: 0, protein_g: 0,
                kcal: 42, fvn: nil, addedSugar_g: nil
            ),
            bonuses: [], transFats: false, caffeine_mg: 9.58, sweeteners: [], seedOils: false,
            additives: [
                .init(name: "e150d", risk: .moderate, code: "e150d", tier: .moderate),
                .init(name: "e338", risk: .moderate, code: "e338", tier: .mild),
            ],
            restrictions: [], dietFlags: nil, allergenTags: nil,
            ingredientsText: "carbonated water, sugar, caramel color, phosphoric acid, natural flavors, caffeine",
            imageURL: nil, labels: nil, packagingMaterials: ["aluminium"], origins: nil,
            ingredientShares: nil, categories: ["beverages", "sodas", "colas"]
        )
        return p
    }

    private var fixtureRedBull: Product {
        Product(
            id: "fixture-rb", name: "Red Bull", brand: "T", size: "250 ml", glyph: "🥤",
            overallScore: 0, yourScore: 0, overview: nil, nutriGrade: "?", novaGroup: 4,
            nutrients: Nutrients(
                sugar_g: 10.8, sodium_mg: 40, satFat_g: 0, fiber_g: 0, protein_g: 0,
                kcal: 45, fvn: nil, addedSugar_g: nil
            ),
            bonuses: [], transFats: false, caffeine_mg: 32, sweeteners: [], seedOils: false,
            additives: [], restrictions: [], dietFlags: nil, allergenTags: nil,
            ingredientsText: "water, sucrose, glucose, taurine, caffeine, B-vitamins",
            imageURL: nil, labels: nil, packagingMaterials: ["aluminium"], origins: nil,
            ingredientShares: nil, categories: ["beverages", "energy-drinks"]
        )
    }

    private func dumpDiff(label: String, fixture: Product, live: Product) {
        let (fs, fp, fbd) = score(fixture)
        let (ls, lp, lbd) = score(live)
        let esF = DrinksScoring.effectiveServing(for: fixture)
        let esL = DrinksScoring.effectiveServing(for: live)
        print("======== DIFF \(label) ========")
        print("field                        | FIXTURE                | LIVE")
        func row(_ k: String, _ a: String, _ b: String) {
            let mark = a == b ? "  " : "≠ "
            let left = (mark + k).padding(toLength: 28, withPad: " ", startingAt: 0)
            let mid = a.padding(toLength: 22, withPad: " ", startingAt: 0)
            print("\(left) | \(mid) | \(b)")
        }
        row("barcode/name", fixture.name, "\(live.id) \(live.name)")
        row("quantity (size)", fixture.size, live.size)
        row("serving_size", fixture.servingSize ?? "nil", live.servingSize ?? "nil")
        row("sugar_g (per 100)", fmt(fixture.nutrients.sugar_g), fmt(live.nutrients.sugar_g))
        row("addedSugar_g (per 100)", fmt(fixture.nutrients.addedSugar_g), fmt(live.nutrients.addedSugar_g))
        row("caffeine_mg (per 100)", fmt(fixture.caffeine_mg), fmt(live.caffeine_mg))
        row("effectiveServingMl", String(format: "%.1f", esF.ml), String(format: "%.1f", esL.ml))
        row("usedWholeContainer", String(esF.usedWholeContainer), String(esL.usedWholeContainer))
        row("estimatedServing", String(esF.estimatedServing), String(esL.estimatedServing))
        row("sugarPerServingG", fmt(fbd.sugarPerServingG), fmt(lbd.sugarPerServingG))
        row("caffeinePerServingMg", fmt(fbd.caffeinePerServingMg), fmt(lbd.caffeinePerServingMg))
        row("profile", fp, lp)
        row("sugarCap", "\(fbd.sugarCap)", "\(lbd.sugarCap)")
        row("caffeineCap", "\(fbd.caffeineCap)", "\(lbd.caffeineCap)")
        row("sweetenerCap", "\(fbd.sweetenerCap)", "\(lbd.sweetenerCap)")
        row("bindingCapId", fbd.bindingCapId ?? "-", lbd.bindingCapId ?? "-")
        row("weightedScore", "\(fbd.weightedScore)", "\(lbd.weightedScore)")
        row("stackingDrag", "\(fbd.stackingDrag)", "\(lbd.stackingDrag)")
        row("finalScore", "\(fs)", "\(ls)")
        for rule in ["S1", "S3", "S8", "S6", "S4", "S7"] {
            let fr = fbd.rules.first { $0.rule == rule }
            let lr = lbd.rules.first { $0.rule == rule }
            row("\(rule).fraction",
                fr.map { String(format: "%.3f", $0.fraction) } ?? "-",
                lr.map { String(format: "%.3f", $0.fraction) } ?? "-")
        }
        print("==============================")
    }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "nil" }
        return String(format: "%.3f", v)
    }

    @Test func diagnoseCocaColaLiveVsFixture() throws {
        // Live capture: EU 1.5L bottle, nutrition panel serving 100 ml.
        // After Fix 1+2: panel discarded → 355 ml dose, total sugars only → score 20.
        let live = try loadOFF("5449000000439")
        dumpDiff(label: "Coca-Cola", fixture: fixtureCoca, live: live)
        let (_, _, bd) = score(live)
        #expect(DrinksScoring.effectiveServing(for: live).ml == 355)
        #expect(bd.sugarCap == 20)
        #expect(bd.bindingCapId == "sugarCap")
        #expect(bd.finalScore == 20)
    }

    @Test func diagnoseCocaColaUSCanMultipackIsOK() throws {
        // Control: US 12-pack entry with serving "355ml" still binds at 20.
        let live = try loadOFF("049000028904")
        dumpDiff(label: "Coca-Cola US multipack control", fixture: fixtureCoca, live: live)
        let (s, _, bd) = score(live)
        #expect(DrinksScoring.effectiveServing(for: live).ml == 355)
        #expect(bd.sugarCap == 20)
        #expect(s == 20)
    }

    @Test func diagnoseRedBullLiveVsFixture() throws {
        // Fix 2 on raw OFF: total sugars only (27.5 g), not added 11.4 / 25.42.
        let clean = try loadOFF("9002490100070")
        dumpDiff(label: "Red Bull clean can", fixture: fixtureRedBull, live: clean)
        let inflated = try loadOFF("9002490205973")
        dumpDiff(label: "Red Bull inflated added-sugars", fixture: fixtureRedBull, live: inflated)

        let (_, _, cleanBd) = score(clean)
        let (_, _, infBd) = score(inflated)
        #expect(abs((cleanBd.sugarPerServingG ?? 0) - 27.5) < 0.2)
        #expect(abs((infBd.sugarPerServingG ?? 0) - 27.5) < 0.2)
    }

    @Test func diagnoseLaCroixRoutesUnsupportedWater() throws {
        let live = try loadOFF("0012993101619")
        let profile = ScoringEngineV4.route(live, ruleset: RulesetV4.bundled)
        let outcome = ScoringEngineV4.scoreProduct(live, for: MockData.user, ruleset: RulesetV4.bundled)
        print("LaCroix barcode=\(live.id) name=\(live.name)")
        print("categories=\(live.categories ?? [])")
        print("routedProfile=\(profile)")
        print("outcome=\(String(describing: outcome))")
        // Fix 3: flavored-waters wins over waters → drinks (scored).
        #expect(profile == "drinks")
        if case .unsupported = outcome {
            Issue.record("expected scored drinks for LaCroix with flavored-waters tags")
        }
    }
}
