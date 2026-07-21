import Testing
import Foundation
@testable import Sage

/// V5.0.6 acceptance: overall-cap overview attribution, list-claim hygiene,
/// badge/materiality truthfulness, fats/whole_foods touch-ups, FVN annotation.
struct V506HotfixTests {

    private let rs = RulesetV4.bundled

    private func product(
        kcal: Double? = nil, protein: Double? = nil, fiber: Double? = nil,
        sugar: Double? = nil, satFat: Double? = nil, sodium: Double? = nil,
        calcium: Double? = nil, fvn: Double? = nil, transFat: Double? = nil,
        nova: Int = 0, name: String = "T",
        ingredientsText: String? = nil,
        additives: [ProductAdditive] = [],
        categories: [String]? = nil
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
            labels: nil, packagingMaterials: nil, origins: nil,
            ingredientShares: nil, categories: categories
        )
    }

    private func profile(
        objective: String = "eat healthier",
        personalize: Bool = true
    ) -> UserProfile {
        var u = MockData.user
        u.objective = objective
        u.personalizeScoring = personalize
        u.autoFlagRestrictions = false
        u.avoidList = []
        u.restrictions = []
        return u
    }

    @Test func rulesetIsV506() throws {
        // Structural weight asserts still hold under V5.0.7; version bumped.
        #expect(rs.version == "2026.07-v5.0.7")
        let wf = try #require(rs.profiles["whole_foods"])
        #expect(wf.contains { $0.rule == "S5" && $0.w == 10 })
        #expect(wf.first { $0.rule == "S2" }?.w == 24)
        #expect(wf.first { $0.rule == "S12" }?.w == 24)
        let fats = try #require(rs.profiles["fats"])
        #expect(fats.first { $0.rule == "S5" }?.w == 54)
        #expect(fats.first { $0.rule == "S13" }?.w == 8)
    }

    @Test func honeyOverallCapAttributedInOverview() throws {
        // V5.0.7: honey is unscored — no overview / free-sugar dial attribution.
        var honey = product(
            kcal: 304, sugar: 82, nova: 1, name: "raw honey",
            ingredientsText: "honey", categories: ["sweeteners", "honeys"]
        )
        guard case .unscored(let scored, _) = ScoringEngineV4.scoreProduct(honey, for: profile(), ruleset: rs)
        else {
            Issue.record("expected unscored honey")
            return
        }
        honey = scored
        #expect(honey.overallScore == nil)
        #expect(honey.overallBindingCap == nil)
        #expect(ScoringEngineV4.overviewContext(for: honey, profile: profile(), ruleset: rs) == nil)
    }

    @Test func validatorRejectsFalseListClaimForFreeSugar() {
        let ctx = ScoringEngineV4.OverviewContext(
            profileId: "snacks",
            productName: "honey",
            objective: "eat healthier",
            overall: 35,
            your: 35,
            band: "OK",
            confidence: 1.0,
            hasScoreableIngredientSignal: true,
            hasNutritionData: true,
            hasIngredientData: true,
            rules: [],
            topPositive: [],
            topNegative: [],
            nutrientLevels: ["sugar: high (82g)"],
            deltaValue: 0,
            deltaDrivers: [],
            avoidMatches: [],
            detectedAdditives: [],
            novaGroup: 1,
            hardGate: nil,
            bindingCap: nil,
            firedCaps: [],
            overallBindingCap: .init(
                id: "freeSugarCeiling", value: 35, shortLabel: "free sugar",
                kind: "freeSugar", intensity: "full"
            ),
            overallFiredCaps: [],
            knownRuleIds: ["S1", "S3"],
            nutrientNudge: nil,
            nutrientNudgeDriver: nil
        )
        let bad = "It scores well on processing (also on your list: free sugar)."
        #expect(OverviewValidator.forbiddenPhrase(in: bad, ctx: ctx)?
            .contains("false list claim") == true)
        let good = "As a concentrated sugar, its score is capped at 35."
        #expect(OverviewValidator.isValid(good, ctx: ctx))
    }

    @Test func validatorRejectsMeasuredDeficiencyForUnknownTier() {
        let ctx = ScoringEngineV4.OverviewContext(
            profileId: "fats",
            productName: "oil",
            objective: "eat healthier",
            overall: 70,
            your: 70,
            band: "Good",
            confidence: 0.9,
            hasScoreableIngredientSignal: true,
            hasNutritionData: true,
            hasIngredientData: true,
            rules: [
                .init(rule: "S13", topic: "micronutrients", weight: 8, fraction: 0.5,
                      contribution: 4, multiplier: nil, evidenceTier: "unknown-tier",
                      driverKind: "merit"),
            ],
            topPositive: [],
            topNegative: [
                .init(topic: "micronutrients", contribution: 4,
                      evidenceTier: "unknown-tier", potentialLoss: 4),
            ],
            nutrientLevels: [],
            deltaValue: 0,
            deltaDrivers: [],
            avoidMatches: [],
            detectedAdditives: [],
            novaGroup: 1,
            hardGate: nil,
            bindingCap: nil,
            firedCaps: [],
            overallBindingCap: nil,
            overallFiredCaps: [],
            knownRuleIds: ["S13"],
            nutrientNudge: nil,
            nutrientNudgeDriver: nil
        )
        #expect(OverviewValidator.forbiddenPhrase(
            in: "Held back by micronutrients.", ctx: ctx) == "micronutrients")
        #expect(OverviewValidator.isValid(
            "Micronutrient data is missing, so the score assumes uncertainty.", ctx: ctx))
    }

    @Test func eggsDoNotCiteSodiumAsNegative() throws {
        let eggs = product(
            kcal: 143, protein: 13, sugar: 0.4, satFat: 3.1, sodium: 142,
            nova: 1, name: "eggs", ingredientsText: "eggs",
            categories: ["eggs"]
        )
        guard case .scored(let scored) = ScoringEngineV4.scoreProduct(eggs, for: profile(), ruleset: rs)
        else {
            Issue.record("expected scored eggs")
            return
        }
        let ctx = try #require(
            ScoringEngineV4.overviewContext(for: scored, profile: profile(), ruleset: rs)
        )
        #expect(!ctx.topNegative.contains { $0.topic.lowercased().contains("sodium") })
        #expect(ScoringEngineV4.route(scored, ruleset: rs) == "whole_foods")
    }

    @Test func evooNotProvisionalAndAtLeastSeventy() throws {
        var evoo = product(
            kcal: 884, sugar: 0, satFat: 14, sodium: 0, nova: 1,
            name: "extra-virgin olive oil", ingredientsText: "extra virgin olive oil",
            categories: ["vegetable-oils", "olive-oils"]
        )
        let result = try #require(ScoringEngineV4.score(evoo, ruleset: rs))
        #expect(result.base >= 70)
        guard case .scored(let scored) = ScoringEngineV4.scoreProduct(evoo, for: profile(), ruleset: rs)
        else {
            Issue.record("expected scored EVOO")
            return
        }
        evoo = scored
        #expect(!ScoringEngineV4.isProvisionalScore(evoo, ruleset: rs))
    }

    @Test func unsaltedNutsAtLeastEightyFive() throws {
        let nuts = product(
            kcal: 600, protein: 20, fiber: 8, sugar: 4, satFat: 5, sodium: 5,
            nova: 1, name: "unsalted nuts", ingredientsText: "almonds",
            categories: ["nuts", "almonds"]
        )
        let score = try #require(ScoringEngineV4.score(nuts, ruleset: rs))
        #expect(score.base >= 85)
        #expect(ScoringEngineV4.route(nuts, ruleset: rs) == "whole_foods")
    }

    @Test func butterShiftWithinTwoPointsOfPrior() throws {
        let unsalted = product(
            kcal: 717, sugar: 0.1, satFat: 51, sodium: 11, transFat: 3.0, nova: 2,
            name: "unsalted butter", ingredientsText: "cream",
            categories: ["dairies", "butters"]
        )
        let salted = product(
            kcal: 717, sugar: 0.1, satFat: 51, sodium: 650, transFat: 3.0, nova: 2,
            name: "salted butter", ingredientsText: "cream, salt",
            categories: ["dairies", "butters"]
        )
        let u = try #require(ScoringEngineV4.score(unsalted, ruleset: rs)).base
        let s = try #require(ScoringEngineV4.score(salted, ruleset: rs)).base
        #expect(abs(u - 45) <= 2)
        #expect(abs(s - 39) <= 2)
    }

    @Test func coconutOilRestoredSatFatEightySeven() throws {
        let oil = product(
            kcal: 892, sugar: 0, satFat: 87, sodium: 0, nova: 2,
            name: "coconut oil", ingredientsText: "coconut oil",
            categories: ["vegetable-oils", "coconut-oils"]
        )
        let butter = product(
            kcal: 717, sugar: 0.1, satFat: 51, sodium: 11, transFat: 3.0, nova: 2,
            name: "unsalted butter", ingredientsText: "cream",
            categories: ["dairies", "butters"]
        )
        let oilScore = try #require(ScoringEngineV4.score(oil, ruleset: rs)).base
        let butterScore = try #require(ScoringEngineV4.score(butter, ruleset: rs)).base
        #expect(ScoringEngineV4.route(oil, ruleset: rs) == "fats")
        #expect(oilScore <= 42)
        #expect(oilScore < butterScore)
        #expect((35...39).contains(oilScore)) // ≈37 after fats S5/S13 touch-up
    }

    /// Fresh coconut (whole_foods) — satFat 33 is the intended C1 fixture.
    /// Original ≤75 target was recalibrated deliberately in v5.0.6 (S5 raised
    /// only to 10; a whole food with satFat 33 still lands ~81–82). Do not
    /// silently edit this assertion again.
    @Test func freshCoconutWholeFoodsAtMostEightyTwo() throws {
        let fresh = product(
            kcal: 354, protein: 3.3, fiber: 9, sugar: 6.2, satFat: 33, sodium: 20,
            nova: 1, name: "fresh coconut", ingredientsText: "coconut",
            categories: ["fruits", "nuts", "coconuts"]
        )
        let unsaltedNuts = product(
            kcal: 600, protein: 20, fiber: 8, sugar: 4, satFat: 5, sodium: 5,
            nova: 1, name: "unsalted nuts", ingredientsText: "almonds",
            categories: ["nuts", "almonds"]
        )
        let freshScore = try #require(ScoringEngineV4.score(fresh, ruleset: rs)).base
        let nutsScore = try #require(ScoringEngineV4.score(unsaltedNuts, ruleset: rs)).base
        #expect(ScoringEngineV4.route(fresh, ruleset: rs) == "whole_foods")
        #expect(freshScore <= 82)
        #expect(freshScore < nutsScore)
    }

    @Test func measuredFVNAnnotationIsBareInDebug() throws {
        let banana = product(
            kcal: 89, protein: 1.1, fiber: 2.6, sugar: 12.2, sodium: 1, fvn: 100,
            nova: 1, name: "measured banana",
            categories: ["fruits", "bananas"]
        )
        let debug = ScoringEngineV4.debugText(banana, for: profile(), ruleset: rs)
        #expect(debug.contains("fvn: 100") || debug.contains("fvn: 100.00"))
        #expect(!debug.contains("inferred:"))
        // Inferred path still annotated.
        let bare = product(
            kcal: 89, protein: 1.1, fiber: 2.6, sugar: 12.2, sodium: 1,
            nova: 1, name: "inferred banana",
            categories: ["fruits", "bananas"]
        )
        let inferredDebug = ScoringEngineV4.debugText(bare, for: profile(), ruleset: rs)
        #expect(inferredDebug.contains("inferred:"))
    }

    @Test func bananaStaysNearEightyFive() throws {
        let banana = product(
            kcal: 89, protein: 1.1, fiber: 2.6, sugar: 12.2, satFat: 0.3, sodium: 1, nova: 1,
            name: "banana", categories: ["fruits", "bananas"]
        )
        let score = try #require(ScoringEngineV4.score(banana, ruleset: rs)).base
        #expect((83...87).contains(score))
    }

    @Test func eatHealthierBoostsS3S4S5() {
        let detail = ScoringEngineV4.ruleMultiplierBreakdown(
            profile(objective: "eat healthier"), rs: rs
        )
        #expect((detail["S3"]?.product ?? 1) >= 1.2)
        #expect((detail["S4"]?.product ?? 1) >= 1.2)
        #expect((detail["S5"]?.product ?? 1) >= 1.2)
        #expect(detail["S3"]?.factors.contains {
            $0.source == "objective" && $0.selection == "eat healthier"
        } == true)
    }
}
