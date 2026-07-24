import Testing
import Foundation
@testable import Sage

/// V5.0.4: router hygiene, preference multipliers, overview exclusivity, organic chip.
struct V504HotfixTests {

    private let rs = RulesetV4.bundled

    private func product(
        kcal: Double? = nil, protein: Double? = nil, fiber: Double? = nil,
        sugar: Double? = nil, satFat: Double? = nil, sodium: Double? = nil,
        calcium: Double? = nil, fvn: Double? = nil, nova: Int = 0,
        name: String = "T",
        ingredientsText: String? = nil,
        additives: [ProductAdditive] = [],
        categories: [String]? = nil,
        labels: [String]? = nil
    ) -> Product {
        Product(
            id: name, name: name, brand: "B", size: "", glyph: "🛒",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                 fiber_g: fiber, protein_g: protein, calcium_mg: calcium,
                                 kcal: kcal, fvn: fvn),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            labels: labels, packagingMaterials: nil, origins: nil,
            ingredientShares: nil, categories: categories
        )
    }

    private func profile(
        objective: String = "eat healthier",
        preferences: [String] = [],
        personalize: Bool = true
    ) -> UserProfile {
        var u = MockData.user
        u.objective = objective
        u.preferences = preferences
        u.personalizeScoring = personalize
        u.healthGoals = nil
        u.sliderCleanIngredients = 1
        u.sliderNutrition = 1
        return u
    }

    // MARK: 1 — Router hygiene

    @Test func jifWithNutsAncestorRoutesGeneral() {
        let jif = product(
            kcal: 594, protein: 22, fiber: 6, sugar: 9, satFat: 10, sodium: 420, nova: 4,
            name: "Jif",
            ingredientsText: "roasted peanuts, sugar, salt",
            categories: ["spreads", "peanut-butters", "nuts", "nuts-and-their-products"]
        )
        #expect(ScoringEngineV4.route(jif, ruleset: rs) == "general")
        let scored = ScoringEngineV4.score(jif, ruleset: rs)
        #expect(scored?.profileId == "general")
        #expect(scored?.rules.contains { $0.rule == "S5" } == true)
    }

    @Test func plainAlmondsRouteWholeFoods() {
        let almonds = product(
            kcal: 600, protein: 20, fiber: 8, sugar: 4, satFat: 5, sodium: 5, fvn: 100,
            nova: 1, name: "almonds",
            ingredientsText: "almonds",
            categories: ["nuts", "almonds"]
        )
        #expect(ScoringEngineV4.route(almonds, ruleset: rs) == "whole_foods")
    }

    @Test func maruchanPastasPlusInstantNoodlesRoutesSnacks() {
        let maruchan = product(
            kcal: 440, protein: 10, sugar: 2, satFat: 8, sodium: 1600, nova: 4,
            name: "Maruchan",
            categories: ["pastas", "instant-noodles", "noodles", "meals"]
        )
        #expect(ScoringEngineV4.route(maruchan, ruleset: rs) == "snacks")
        let scored = ScoringEngineV4.score(maruchan, ruleset: rs)
        #expect(scored?.rules.contains { $0.rule == "wholeGrain" } != true)
    }

    @Test func plainPastaRoutesBreads() {
        let pasta = product(
            kcal: 350, protein: 12, fiber: 3, sugar: 2, satFat: 0.5, sodium: 5, nova: 1,
            name: "spaghetti",
            ingredientsText: "durum wheat semolina",
            categories: ["pastas"]
        )
        #expect(ScoringEngineV4.route(pasta, ruleset: rs) == "breads")
    }

    @Test func wholeFoodsRouterHasNoUmbrellaProductsTags() {
        let umbrella = rs.router.filter {
            $0.profile == "whole_foods" && $0.match.contains("and-their-products")
        }
        #expect(umbrella.isEmpty)
        let noodleIdx = rs.router.firstIndex { $0.match == "instant-noodles" }!
        let pastaIdx = rs.router.firstIndex { $0.match == "pastas" }!
        #expect(noodleIdx < pastaIdx)
    }

    // MARK: 2 — Preference multipliers

    @Test func preferenceMultipliersComposeWithObjective() {
        let u = profile(preferences: ["High protein", "Minimally processed"])
        let detail = ScoringEngineV4.ruleMultiplierBreakdown(u, rs: rs)
        #expect(abs((detail["S12"]?.product ?? 0) - 1.5) < 0.001)   // 1.2 × 1.25
        #expect(abs((detail["S2"]?.product ?? 0) - 1.875) < 0.001)  // 1.5 × 1.25
        #expect(detail["S12"]?.factors.contains { $0.source == "objective" } == true)
        #expect(detail["S12"]?.factors.contains { $0.source == "preference" } == true)
        #expect(detail["S2"]?.factors.contains { $0.source == "preference" } == true)
    }

    @Test func preferenceMultiplierClampsAtTwo() {
        // lose weight S3 ×2.0 × low sugar ×1.3 → 2.6 → clamp 2.0
        let u = profile(objective: "lose weight", preferences: ["Low sugar"])
        let detail = ScoringEngineV4.ruleMultiplierBreakdown(u, rs: rs)
        #expect(detail["S3"]?.product == 2.0)
        let raw = detail["S3"]!.factors.reduce(1.0) { $0 * $1.factor }
        #expect(raw > 2.0)
    }

    @Test func organicPreferenceProducesNoMultipliers() {
        let u = profile(preferences: ["Organic"])
        let detail = ScoringEngineV4.ruleMultiplierBreakdown(u, rs: rs)
        #expect(detail.values.allSatisfy { d in
            !d.factors.contains { $0.source == "preference" }
        })
        #expect(rs.multipliers?.preference?["organic"] == nil)
    }

    @Test func organicChipOnlyWhenPreferenceAndLabelMatch() {
        let labeled = product(name: "oats", categories: ["cereals"], labels: ["organic", "eu-organic"])
        let plain = product(name: "oats", categories: ["cereals"], labels: nil)
        let withPref = profile(preferences: ["Organic"])
        let noPref = profile(preferences: [])
        #expect(ScoringEngineV4.showsOrganicChip(product: labeled, profile: withPref))
        #expect(!ScoringEngineV4.showsOrganicChip(product: labeled, profile: noPref))
        #expect(!ScoringEngineV4.showsOrganicChip(product: plain, profile: withPref))
        #expect(!ScoringEngineV4.showsOrganicChip(product: plain, profile: noPref))
    }

    @Test func organicPreferenceDoesNotChangeScores() {
        let p = product(
            kcal: 594, protein: 22, fiber: 6, sugar: 9, satFat: 10, sodium: 420, nova: 4,
            name: "Jif", categories: ["spreads", "peanut-butters"],
            labels: ["organic"]
        )
        let base = profile(preferences: [])
        let org = profile(preferences: ["Organic"])
        guard case .scored(let a) = ScoringEngineV4.scoreProduct(p, for: base, ruleset: rs),
              case .scored(let b) = ScoringEngineV4.scoreProduct(p, for: org, ruleset: rs)
        else {
            Issue.record("expected scored")
            return
        }
        #expect(a.overallScore == b.overallScore)
        #expect(a.yourScore == b.yourScore)
    }

    @Test func debugListsPreferenceSources() {
        let p = product(
            kcal: 367, protein: 12, fiber: 10, sugar: 4.5, satFat: 0.8, sodium: 470, nova: 4,
            name: "Cheerios",
            ingredientsText: "whole grain oats, corn starch, sugar, salt",
            categories: ["breakfast-cereals", "cereals"]
        )
        let u = profile(preferences: ["High protein"])
        let text = ScoringEngineV4.debugText(p, for: u, ruleset: rs)
        #expect(text.contains("(objective)"))
        #expect(text.contains("(preference)"))
        #expect(text.contains("S12:"))
    }

    @Test func overviewPayloadCarriesMultiplierSources() throws {
        let p = product(
            kcal: 367, protein: 12, fiber: 10, sugar: 4.5, satFat: 0.8, sodium: 470, nova: 4,
            name: "Cheerios",
            ingredientsText: "whole grain oats",
            categories: ["breakfast-cereals", "cereals"]
        )
        var scored = p
        scored.overallScore = 58
        scored.yourScore = 62
        // Neutral objective so preference is the sole S12 multiplier source.
        let u = profile(objective: "maintain", preferences: ["High protein"])
        let ctx = try #require(
            ScoringEngineV4.overviewContext(for: scored, profile: u, ruleset: rs)
        )
        let s12 = try #require(ctx.rules.first { $0.rule == "S12" })
        #expect(s12.multiplierSources?.map(\.source) == ["preference"])
        #expect(abs((s12.multiplier ?? 0) - 1.25) < 0.001)
        #expect(ctx.deltaDrivers.contains {
            $0.topic.localizedCaseInsensitiveContains("high-protein preference")
        })
    }

    // MARK: 3 — Overview exclusivity

    @Test func cheeriosAdditivesAppearOnExactlyOneSide() throws {
        let cheerios = product(
            kcal: 367, protein: 12, fiber: 10, sugar: 4.5, satFat: 0.8, sodium: 470, nova: 4,
            name: "Cheerios",
            ingredientsText: "whole grain oats, corn starch, sugar, salt, tripotassium phosphate",
            additives: [.init(name: "e340", risk: .moderate, code: "e340", tier: .mild)],
            categories: ["breakfast-cereals", "cereals"]
        )
        var scored = cheerios
        scored.overallScore = 58
        scored.yourScore = 58
        let ctx = try #require(
            ScoringEngineV4.overviewContext(for: scored, profile: profile(), ruleset: rs)
        )
        let pos = ctx.topPositive.filter { $0.topic == "additives" }.count
        let neg = ctx.topNegative.filter { $0.topic == "additives" }.count
        #expect(pos + neg == 1, "S1/additives must appear on exactly one side (pos=\(pos) neg=\(neg))")
        #expect(ctx.rules.contains { $0.rule == "S1" })
    }

    // MARK: 5 — Delta sentence

    @Test func personalSentenceDoesNotRepeatGapParenthetical() {
        let ctx = ScoringEngineV4.OverviewContext(
            profileId: "general",
            productName: "Product",
            objective: "eat healthier",
            overall: 50,
            your: 46,
            band: "OK",
            confidence: 1.0,
            hasScoreableIngredientSignal: true,
            hasNutritionData: true,
            hasIngredientData: true,
            rules: [
                .init(rule: "S2", topic: "degree of processing", weight: 26, fraction: 0.2,
                      contribution: 5.2, multiplier: 1.5, evidenceTier: "data",
                      driverKind: "merit"),
            ],
            topPositive: [],
            topNegative: [.init(topic: "degree of processing", contribution: 5.2,
                                evidenceTier: "data", potentialLoss: 20.8)],
            nutrientLevels: [],
            deltaValue: -4,
            deltaDrivers: [.init(topic: "degree of processing", direction: "down")],
            avoidMatches: [],
            detectedAdditives: [],
            novaGroup: 4,
            hardGate: nil,
            bindingCap: nil,
            firedCaps: [],
            overallBindingCap: nil,
            overallFiredCaps: [],
            knownRuleIds: rs.allRuleIds,
            nutrientNudge: nil,
            nutrientNudgeDriver: nil
        )
        let text = OverviewTemplate.personalSentence(ctx)
        #expect(text.contains("4 points"))
        #expect(!text.contains("gap)"))
        #expect(!text.contains("points gap"))
    }

    @Test func rulesetVersionIsV504() {
        #expect(rs.version == "2026.07-v5.0.8")
        #expect(rs.multipliers?.preference?["high protein"]?["S12"] == 1.25)
    }
}
