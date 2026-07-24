import Testing
import Foundation
@testable import Sage

/// V5.0.7 — pure sweeteners become unscored (no dials / caps / overview).
struct V507HotfixTests {

    private let rs = RulesetV4.bundled

    private func product(
        kcal: Double? = nil, protein: Double? = nil, fiber: Double? = nil,
        sugar: Double? = nil, satFat: Double? = nil, sodium: Double? = nil,
        calcium: Double? = nil, fvn: Double? = nil, transFat: Double? = nil,
        nova: Int = 0, name: String = "T",
        ingredientsText: String? = nil,
        additives: [ProductAdditive] = [],
        categories: [String]? = nil,
        labels: [String]? = nil,
        ingredientShares: [IngredientShare]? = nil
    ) -> Product {
        Product(
            id: name, name: name, brand: "B", size: "", glyph: "🛒",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                 fiber_g: fiber, protein_g: protein, calcium_mg: calcium,
                                 kcal: kcal, fvn: fvn, transFat_g: transFat),
            bonuses: [], transFats: (transFat ?? 0) > 0, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            labels: labels, packagingMaterials: nil, origins: nil,
            ingredientShares: ingredientShares, categories: categories
        )
    }

    private func profile(restrictions: [String] = [], avoid: [String] = []) -> UserProfile {
        var u = MockData.user
        u.personalizeScoring = true
        u.autoFlagRestrictions = true
        u.objective = "eat healthier"
        u.restrictions = restrictions
        u.avoidList = avoid
        return u
    }

    @Test func rulesetIsV507() {
        #expect(rs.version == "2026.07-v5.0.8")
        #expect(rs.profiles["sweeteners"] == nil)
        #expect(rs.profiles.count == 12)
        #expect(rs.sweetenerType != nil)
        #expect(rs.authenticityBad != nil)
    }

    @Test func honeySugarSteviaErythritolAreUnscored() throws {
        let honey = product(kcal: 304, sugar: 82, nova: 1, name: "raw honey",
                            ingredientsText: "honey", categories: ["sweeteners", "honeys"])
        let sugar = product(kcal: 387, sugar: 100, nova: 2, name: "white sugar",
                            ingredientsText: "sugar", categories: ["sweeteners", "sugars"])
        let stevia = product(kcal: 0, sugar: 0, nova: 4, name: "stevia tablets",
                             ingredientsText: "stevia leaf extract, erythritol",
                             categories: ["sweeteners", "tabletop-sweeteners"], labels: ["stevia"])
        let erythritol = product(kcal: 20, sugar: 2, nova: 4, name: "erythritol blend",
                                 ingredientsText: "erythritol, steviol glycosides",
                                 categories: ["sweeteners", "tabletop-sweeteners"])

        for p in [honey, sugar, stevia, erythritol] {
            #expect(ScoringEngineV4.route(p) == "unscored_sweetener")
            #expect(ScoringEngineV4.score(p) == nil)
            guard case .unscored(let out, let key) =
                    ScoringEngineV4.scoreProduct(p, for: profile(), ruleset: rs)
            else {
                Issue.record("expected unscored for \(p.name)")
                continue
            }
            #expect(key == "sweetener")
            #expect(out.isUnscored)
            #expect(out.overallScore == nil)
            #expect(out.yourScore == nil)
            #expect(out.bindingCap == nil)
            #expect(out.overallBindingCap == nil)
            #expect(out.firedCaps == nil)
            #expect(out.overallFiredCaps == nil)
            #expect(out.overview == nil)
            #expect(out.overviewStale == false)
            #expect(out.bonuses.isEmpty)
            #expect(ScoringEngineV4.overviewContext(for: out, profile: profile(), ruleset: rs) == nil)
            let debug = ScoringEngineV4.debugText(out, for: profile(), ruleset: rs)
            #expect(debug.contains("outcome: unscored_sweetener"))
        }
    }

    @Test func honeyLowSugarConflictWithoutCapLanguage() throws {
        let honey = product(kcal: 304, sugar: 82, nova: 1, name: "raw honey",
                            ingredientsText: "honey", categories: ["sweeteners", "honeys"])
        guard case .unscored(let out, _) =
                ScoringEngineV4.scoreProduct(honey, for: profile(restrictions: ["low-sugar diet"]),
                                             ruleset: rs)
        else {
            Issue.record("expected unscored honey")
            return
        }
        #expect(out.restrictions.contains { $0.type == "low-sugar diet" })
        #expect(out.bindingCap == nil)
        let headline = String(format: String(localized: "Conflicts with your %@."),
                              "low-sugar diet")
        #expect(headline == "Conflicts with your low-sugar diet.")
        #expect(!headline.lowercased().contains("cap"))
    }

    @Test func candyStillScoredWithFreeSugarCeiling() throws {
        let candy = product(kcal: 400, sugar: 55, fvn: 0, nova: 4, name: "candy",
                            ingredientsText: "sugar, corn syrup",
                            categories: ["snacks", "sweet-snacks", "candies"])
        #expect(ScoringEngineV4.route(candy) == "snacks")
        let scored = try #require(ScoringEngineV4.score(candy))
        #expect(scored.base <= 35)
        #expect(ScoringEngineV4.applyBaseCaps(base: 80, product: candy, rs: rs)
            .fired.contains(where: { $0.kind == "freeSugar" }))
        guard case .scored(let p) = ScoringEngineV4.scoreProduct(candy, for: profile(), ruleset: rs)
        else {
            Issue.record("expected scored candy")
            return
        }
        #expect(p.overallScore != nil)
        #expect(!p.isUnscored)
    }

    @Test func amongSweetenersNotesForHoneyRefinedAndBlend() {
        let rawHoney = product(kcal: 304, sugar: 82, nova: 1, name: "raw honey",
                               ingredientsText: "raw honey",
                               categories: ["sweeteners", "honeys"],
                               ingredientShares: [
                                   .init(name: "honey", percent: 100, percentEstimate: nil)
                               ])
        let white = product(kcal: 387, sugar: 100, nova: 2, name: "white sugar",
                            ingredientsText: "sugar", categories: ["sweeteners", "sugars"],
                            ingredientShares: [
                                .init(name: "sugar", percent: 100, percentEstimate: nil)
                            ])
        let blend = product(kcal: 20, sugar: 2, nova: 4, name: "stevia blend",
                            ingredientsText: "erythritol, stevia leaf extract, maltodextrin",
                            categories: ["sweeteners", "tabletop-sweeteners"],
                            ingredientShares: [
                                .init(name: "erythritol", percent: 60, percentEstimate: nil),
                                .init(name: "stevia", percent: 40, percentEstimate: nil),
                            ])

        let honeyNotes = ScoringEngineV4.sweetenerQualityNotes(rawHoney, ruleset: rs)
        #expect(!honeyNotes.isEmpty)
        #expect(honeyNotes.contains { $0.lowercased().contains("honey")
            || $0.lowercased().contains("minimally")
            || $0.lowercased().contains("single") })

        let whiteNotes = ScoringEngineV4.sweetenerQualityNotes(white, ruleset: rs)
        #expect(whiteNotes.contains { $0 == "Refined" || $0.lowercased().contains("refined") }
                || whiteNotes.contains { $0.lowercased().contains("single") })

        let blendNotes = ScoringEngineV4.sweetenerQualityNotes(blend, ruleset: rs)
        #expect(blendNotes.contains("Blend")
                || blendNotes.contains { $0.lowercased().contains("stevia") })
    }

    @Test func rescoreClearsLegacySweetenerScoresAndOverview() throws {
        var legacy = product(kcal: 304, sugar: 82, nova: 1, name: "raw honey",
                             ingredientsText: "honey", categories: ["sweeteners", "honeys"])
        legacy.overallScore = 35
        legacy.yourScore = 35
        legacy.scoreState = .scored
        legacy.overview = ProductOverview(tone: .negative, text: "Capped at 35.")
        legacy.overviewStale = false
        legacy.overallBindingCap = ScoreCap(
            id: "freeSugarCeiling", value: 35, shortLabel: "free sugar",
            kind: "freeSugar", intensity: "full", detail: nil
        )

        guard case .unscored(let migrated, _) =
                ScoringEngineV4.scoreProduct(legacy, for: profile(), ruleset: rs)
        else {
            Issue.record("expected unscored after rescore")
            return
        }
        #expect(migrated.overallScore == nil)
        #expect(migrated.yourScore == nil)
        #expect(migrated.overview == nil)
        #expect(migrated.overallBindingCap == nil)
        #expect(migrated.isUnscored)
    }

    @Test func compareHoneyVsYogurtHasNoScoreDelta() throws {
        let honey = product(kcal: 304, sugar: 82, nova: 1, name: "raw honey",
                            ingredientsText: "honey", categories: ["sweeteners", "honeys"])
        let yogurt = product(kcal: 59, protein: 10, sugar: 3.6, satFat: 0.4, sodium: 36,
                             calcium: 110, nova: 1, name: "yogurt",
                             ingredientsText: "milk, cultures",
                             categories: ["dairies", "yogurts"])
        guard case .unscored(let h, _) =
                ScoringEngineV4.scoreProduct(honey, for: profile(), ruleset: rs),
              case .scored(let y) =
                ScoringEngineV4.scoreProduct(yogurt, for: profile(), ruleset: rs)
        else {
            Issue.record("expected unscored honey + scored yogurt")
            return
        }
        #expect(h.yourScore == nil)
        #expect(y.yourScore != nil)
        let bothScored = !h.isUnscored && !y.isUnscored
            && h.yourScore != nil && y.yourScore != nil
        #expect(!bothScored)
    }

    @Test func legacyDecodeWithoutScoreStateIsNotUnscored() throws {
        let json = """
        {
          "id":"1","name":"apple","brand":"B","size":"","glyph":"🍎",
          "overallScore":85,"yourScore":85,"nutriGrade":"A","novaGroup":1,
          "nutrients":{"kcal":52,"sugar_g":10},"bonuses":[],"transFats":false,
          "caffeine_mg":null,"sweeteners":[],"seedOils":false,"additives":[],
          "restrictions":[]
        }
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(Product.self, from: json)
        #expect(p.scoreState == nil)
        #expect(!p.isUnscored)
        #expect(p.overallScore == 85)
        #expect(p.yourScore == 85)
    }

    @Test func rulesetsStayByteIdentical() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let root = thisFile.deletingLastPathComponent().deletingLastPathComponent()
        let a = try Data(contentsOf: root.appendingPathComponent("Sage/RulesetV5.json"))
        let b = try Data(contentsOf: root.appendingPathComponent("backend/src/ruleset.json"))
        #expect(a == b)
        let version = try JSONDecoder().decode(RulesetV4.self, from: a).version
        #expect(version == "2026.07-v5.0.8")
    }
}
