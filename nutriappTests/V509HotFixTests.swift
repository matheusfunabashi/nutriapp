import Testing
import Foundation
@testable import Sage

/// V5.0.9 — ice_cream ingredient integrity, UPF band display cap, sweetener surfacing.
struct V509HotfixTests {

    private let rs = RulesetV4.bundledV509

    private func product(
        id: String = "T",
        kcal: Double? = nil, protein: Double? = nil, fiber: Double? = nil,
        sugar: Double? = nil, satFat: Double? = nil, sodium: Double? = nil,
        calcium: Double? = nil, fvn: Double? = nil,
        nova: Int = 0, name: String = "T",
        nutriGrade: String = "?",
        ingredientsText: String? = nil,
        additives: [ProductAdditive] = [],
        categories: [String]? = nil
    ) -> Product {
        Product(
            id: id, name: name, brand: "B", size: "", glyph: "🛒",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: nutriGrade, novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                 fiber_g: fiber, protein_g: protein, calcium_mg: calcium,
                                 kcal: kcal, fvn: fvn),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            labels: nil, packagingMaterials: nil, origins: nil,
            ingredientShares: nil, categories: categories
        )
    }

    private func profile(
        restrictions: [String] = [],
        avoid: [String] = [],
        objective: String = "eat healthier",
        goals: [String]? = ["Blood sugar"],
        preferences: [String] = ["Organic", "High protein", "Minimally processed"]
    ) -> UserProfile {
        var u = MockData.user
        u.personalizeScoring = true
        u.autoFlagRestrictions = true
        u.objective = objective
        u.healthGoals = goals
        u.restrictions = restrictions
        u.avoidList = avoid
        u.preferences = preferences
        return u
    }

    /// Protein Pints Cookie Dough — production fixture A.
    private var proteinPints: Product {
        product(
            id: "0850067366010",
            kcal: 177.78, protein: 11.11, fiber: nil,
            sugar: 5.56, satFat: 5.56, sodium: 211.11, fvn: 1.94,
            nova: 4, name: "Cookie Dough",
            ingredientsText: "Whole milk, allulose, cream, whey protein isolate, butter, tapioca syrup, almond flour, egg yolk, powdered sugar, cane sugar, coconut oil, water, cocoa powder (processed with alkali), molasses, vanilla extract, tapioca starch, salt, skim milk, guar gum, monk fruit, sunflower lecithin",
            additives: [
                ProductAdditive(name: "Lecithins", risk: .low, code: "e322", tier: .soft),
                ProductAdditive(name: "Guar gum", risk: .low, code: "e412", tier: .soft),
            ],
            categories: ["desserts", "frozen-foods", "frozen-desserts",
                         "ice-creams-and-sorbets", "ice-creams"]
        )
    }

    /// Ice Cream for Bears Honey Honey — production fixture B.
    private var bearsHoney: Product {
        product(
            id: "0198168739242",
            kcal: 250, protein: 4.84, fiber: nil,
            sugar: 22.58, satFat: 8.06, sodium: 72.58, fvn: 0,
            nova: 3, name: "Honey Honey Honey Swirl French Ice Cream",
            ingredientsText: "Milk, cream, raw honey, skim milk, egg yolk",
            categories: ["desserts", "frozen-foods", "frozen-desserts",
                         "ice-creams-and-sorbets", "ice-creams"]
        )
    }

    @Test func rulesetIsV509() {
        #expect(rs.version == "2026.07-v5.0.9")
        let ice = try! #require(rs.profiles["ice_cream"])
        let sum = ice.reduce(0.0) { $0 + $1.w }
        #expect(abs(sum - 100) < 0.01)
        #expect(ice.contains { $0.rule == "S14" && $0.w == 4 })
        #expect(ice.contains { $0.rule == "S2" && $0.w == 22 })
        #expect(ice.contains { $0.rule == "S3" && $0.w == 20 })
    }

    @Test func bearsRanksAboveProteinPintsOnOverall() throws {
        #expect(ScoringEngineV4.route(bearsHoney) == "ice_cream")
        #expect(ScoringEngineV4.route(proteinPints) == "ice_cream")

        let b = try #require(ScoringEngineV4.score(bearsHoney, ruleset: rs))
        let a = try #require(ScoringEngineV4.score(proteinPints, ruleset: rs))

        #expect(b.base >= 59 && b.base <= 64)
        #expect(rs.bandLabel(b.base) == "Good")

        #expect(a.base >= 52 && a.base <= 58)
        #expect(b.base > a.base)

        guard case .scored(let scoredA) =
                ScoringEngineV4.scoreProduct(proteinPints, for: profile(), ruleset: rs)
        else {
            Issue.record("expected scored Protein Pints")
            return
        }
        #expect(scoredA.overallScore == a.base)
        #expect(scoredA.overallBandCap == nil)
        let display = ScoringEngineV4.displayBandLabel(
            score: scoredA.overallScore ?? 0, product: scoredA, ruleset: rs)
        #expect(display == rs.bandLabel(scoredA.overallScore ?? 0))
    }

    @Test func lowSugarPersonalizationUnchangedOrder() throws {
        let lowSugar = profile(restrictions: ["low-sugar diet"])
        guard case .scored(let a) =
                ScoringEngineV4.scoreProduct(proteinPints, for: lowSugar, ruleset: rs),
              case .scored(let b) =
                ScoringEngineV4.scoreProduct(bearsHoney, for: lowSugar, ruleset: rs)
        else {
            Issue.record("expected both scored")
            return
        }
        // Reweight raises S2 (m≈2 for minimally-processed prefs), so A's Your Score
        // sits below the old ~66 zone — ranking vs diet-capped B must stay A > B.
        #expect((a.yourScore ?? 0) >= 50)
        #expect(b.bindingCap?.kind == "dietConflict" || (b.yourScore ?? 100) <= 39)
        #expect((a.yourScore ?? 0) > (b.yourScore ?? 0))
    }

    @Test func sweetenerSystemSurfacing() {
        let a = IngredientIntegrity.sweetenerSystemMatches(
            ingredientsText: proteinPints.ingredientsText)
        let b = IngredientIntegrity.sweetenerSystemMatches(
            ingredientsText: bearsHoney.ingredientsText)
        #expect(a.count >= 2)
        #expect(a.contains(where: { $0.contains("allulose") || $0 == "allulose" }))
        #expect(a.contains(where: { $0.contains("monk") }))
        #expect(b.isEmpty)
    }

    @Test func s14FactorsSplitFixtures() {
        let a = IngredientIntegrity.evaluate(ingredientsText: proteinPints.ingredientsText)
        let b = IngredientIntegrity.evaluate(ingredientsText: bearsHoney.ingredientsText)
        #expect(a.hadData && b.hadData)
        #expect(b.fraction >= 0.90)
        #expect(a.fraction <= 0.35)
        #expect(a.ingredientCount >= 15)
        #expect(b.ingredientCount <= 7)
    }

    @Test func s12IsolateDiscountLogged() {
        let debug = ScoringEngineV4.debugText(proteinPints, for: profile(), ruleset: rs)
        #expect(debug.contains("S12 isolate discount ×0.5"))
        #expect(!debug.contains("upfBandCap"))
        #expect(!debug.contains("display band:"))
    }

    @Test func confidenceBelow100WhenFiberMissing() throws {
        let scored = try #require(ScoringEngineV4.score(bearsHoney, ruleset: rs))
        #expect(scored.confidence < 1.0)
        #expect(scored.confidence >= 0.60)
        let a = try #require(ScoringEngineV4.score(proteinPints, ruleset: rs))
        #expect(a.confidence < 1.0)
    }

    @Test func missingIngredientsRedistributesS14() throws {
        var p = bearsHoney
        p = product(
            id: p.id, kcal: 250, protein: 4.84, sugar: 22.58, satFat: 8.06,
            sodium: 72.58, fvn: 0, nova: 3, name: p.name,
            ingredientsText: nil,
            categories: p.categories
        )
        let scored = try #require(ScoringEngineV4.score(p, ruleset: rs))
        #expect(scored.rules.contains { $0.rule == "S14" && !$0.hadData })
        // Still produces a score — S14 weight dropped from Σw.
        #expect(scored.base >= 10)
        #expect(scored.confidence < 1.0)
        let debug = ScoringEngineV4.debugText(p, for: profile(), ruleset: rs)
        #expect(debug.contains("redistributed") || debug.contains("unknown-tier"))
    }

    @Test func overviewValidatorRejectsFaultyCookieDoughCopy() throws {
        guard case .scored(let scored) =
                ScoringEngineV4.scoreProduct(proteinPints, for: profile(), ruleset: rs),
              let ctx = ScoringEngineV4.overviewContext(for: scored, profile: profile(), ruleset: rs)
        else {
            Issue.record("expected overview context")
            return
        }
        let faulty = "Protein Pints Cookie Dough received a good score primarily due to moderate sugar content and beneficial additives like lecithins and guar gum. However, it is highly processed and has lower protein and fiber levels, along with high saturated fat content."
        #expect(OverviewValidator.isValid(faulty, ctx: ctx) == false)

        let template = OverviewTemplate.generate(ctx)
        #expect(OverviewValidator.isValid(template, ctx: ctx))
    }
}
