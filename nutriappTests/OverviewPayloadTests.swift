import Testing
import Foundation
@testable import Sage

struct OverviewPayloadTests {

    @Test func payloadIncludesEvidenceTierForEveryRule() throws {
        var p = fixtureYogurt()
        p.overallScore = 59
        p.yourScore = 57

        let ctx = try #require(
            ScoringEngineV4.overviewContext(for: p, profile: profile(), ruleset: RulesetV4.bundled)
        )
        #expect(!ctx.rules.isEmpty)
        for rule in ctx.rules {
            #expect(rule.evidenceTier == "data" || rule.evidenceTier == "unknown-tier")
            #expect(!rule.topic.isEmpty)
            #expect(rule.driverKind == "merit" || rule.driverKind == "hygiene")
        }
        #expect(ctx.rules.contains { $0.rule == "S1" && $0.evidenceTier == "unknown-tier" })
        #expect(!ctx.knownRuleIds.isEmpty)
    }

    @Test func cerealPayloadIncludesWholeGrainDisplayName() throws {
        let p = fixtureCereal()
        let ctx = try #require(
            ScoringEngineV4.overviewContext(for: p, profile: profile(), ruleset: RulesetV4.bundled)
        )
        let wg = try #require(ctx.rules.first { $0.rule == "wholeGrain" })
        #expect(wg.topic == "whole grain content")
        #expect(wg.driverKind == "merit")
        // Hygiene rules must not appear as positives even at full score.
        #expect(!ctx.topPositive.contains { $0.topic == "flour treatment agents" })
        if let flour = ctx.rules.first(where: { $0.rule == "flourOxidizers" }) {
            #expect(flour.topic == "flour treatment agents")
            #expect(flour.driverKind == "hygiene")
        }
    }

    @Test func validatorRejectsInternalRuleIdsAndCamelCase() {
        let ctx = baseCtx(confidence: 1.0, signal: true, delta: -1, allData: true)
        #expect(OverviewValidator.forbiddenPhrase(
            in: "It scores well on flourOxidizers.", ctx: ctx) == "flourOxidizers")
        #expect(OverviewValidator.forbiddenPhrase(
            in: "Boosted by wholeGrain content.", ctx: ctx) == "wholeGrain"
            || OverviewValidator.forbiddenPhrase(
                in: "Boosted by wholeGrain content.", ctx: ctx) == "wholeGrain")
    }

    @Test func negativesRankedByPotentialLoss() throws {
        var p = fixtureYogurt()
        p.overallScore = 59
        p.yourScore = 57
        let ctx = try #require(
            ScoringEngineV4.overviewContext(for: p, profile: profile(), ruleset: RulesetV4.bundled)
        )
        #expect(!ctx.topNegative.isEmpty)
        #expect(ctx.topNegative.contains { $0.topic == "additives" })
    }

    @Test func validatorRejectsAdditivePresenceClaims() {
        let ctx = baseCtx(confidence: 0.64, signal: false, delta: -2)
        let bad = "While this yogurt has good nutrition, the presence of riskier additives lowers its fit."
        #expect(!OverviewValidator.isValid(bad, ctx: ctx))
        #expect(OverviewValidator.forbiddenPhrase(in: bad, ctx: ctx) != nil)
    }

    @Test func validatorRejectsThinDataWhenConfident() {
        let ctx = baseCtx(confidence: 1.0, signal: true, delta: -1, allData: true)
        let bad = "Your score is 1 point below because processing weighs more, especially where data is thin."
        #expect(OverviewValidator.forbiddenPhrase(in: bad, ctx: ctx) == "where data is thin"
                || OverviewValidator.forbiddenPhrase(in: bad, ctx: ctx) == "data is thin")
    }

    @Test func validatorRejectsEmAndEnDashes() {
        let ctx = baseCtx(confidence: 1.0, signal: true, delta: -1, allData: true)
        #expect(OverviewValidator.forbiddenPhrase(in: "Held back by processing — ultra-processed.", ctx: ctx) == "em dash")
        #expect(OverviewValidator.forbiddenPhrase(in: "Held back by processing – ultra-processed.", ctx: ctx) == "en dash")
    }

    @Test func validatorRejectsPluralPointsForDeltaOne() {
        let ctx = baseCtx(confidence: 1.0, signal: true, delta: -1, allData: true)
        let bad = "Your score is 1 points below the overall because of processing."
        #expect(OverviewValidator.forbiddenPhrase(in: bad, ctx: ctx) == "1 points")
    }

    @Test func templateFallbackForNoIngredientProduct() {
        let ctx = ScoringEngineV4.OverviewContext(
            profileId: "yogurt_cheese",
            productName: "Yogurt",
            objective: "eat healthier",
            overall: 43,
            your: 41,
            band: "OK",
            confidence: 0.64,
            hasScoreableIngredientSignal: false,
            hasNutritionData: true,
            hasIngredientData: false,
            rules: [
                .init(rule: "S1", topic: "additives", weight: 30, fraction: 0.2,
                      contribution: 6, multiplier: 1.3, evidenceTier: "unknown-tier",
                      driverKind: "merit"),
                .init(rule: "S3", topic: "sugar", weight: 15, fraction: 1.0,
                      contribution: 15, multiplier: nil, evidenceTier: "data",
                      driverKind: "merit"),
            ],
            topPositive: [.init(topic: "sugar", contribution: 15, evidenceTier: "data")],
            topNegative: [.init(topic: "additives", contribution: 6,
                                evidenceTier: "unknown-tier", potentialLoss: 24)],
            nutrientLevels: ["sugar: low (2g)"],
            deltaValue: -2,
            deltaDrivers: [.init(topic: "additives", direction: "down")],
            avoidMatches: [],
            detectedAdditives: [],
            novaGroup: nil,
            hardGate: nil,
            bindingCap: nil,
            firedCaps: [],
            overallBindingCap: nil,
            overallFiredCaps: [],
            knownRuleIds: RulesetV4.bundled.allRuleIds,
            nutrientNudge: nil,
            nutrientNudgeDriver: nil
        )
        let text = OverviewTemplate.generate(ctx)
        #expect(text.localizedCaseInsensitiveContains("missing ingredient"))
        #expect(!text.localizedCaseInsensitiveContains("presence of"))
        #expect(text.localizedCaseInsensitiveContains("2 points"))
        #expect(!text.contains("\u{2014}"))
        #expect(!text.contains("\u{2013}"))
        #expect(OverviewValidator.isValid(text, ctx: ctx))
    }

    @Test func natureValleyDietConflictDeltaIsHardGateNotMultipliers() throws {
        // Investigation D: overall ~44 → your 20 with Low-sugar diet is dietConflictCap,
        // not multiplier-only reweighting. Overview must name the gate.
        var u = profile()
        u.restrictions = ["Low-sugar diet"]
        u.autoFlagRestrictions = true
        u.personalizeScoring = true
        u.avoidList = nil

        guard case .scored(let scored) = ScoringEngineV4.scoreProduct(fixtureGranola(), for: u) else {
            Issue.record("expected scored granola")
            return
        }
        #expect((scored.overallScore ?? 0) >= 30)
        #expect(scored.yourScore == 20)
        let delta = (scored.yourScore ?? 0) - (scored.overallScore ?? 0)
        #expect(delta <= -15) // large delta is correct when dietConflictCap fires

        let ctx = try #require(
            ScoringEngineV4.overviewContext(for: scored, profile: u, ruleset: .bundled)
        )
        #expect(ctx.hardGate?.kind == "dietConflict")
        #expect(ctx.hardGate?.cappedTo == 20)
        #expect(ctx.hardGate?.intensity == "full")
        #expect(ctx.bindingCap?.id == "dietConflictCap")
        #expect(scored.bindingCap?.shortLabel == "low-sugar diet")
        let text = OverviewTemplate.generate(ctx)
        #expect(text.localizedCaseInsensitiveContains("low-sugar")
                || text.localizedCaseInsensitiveContains("caps")
                || text.localizedCaseInsensitiveContains("limits"))
        #expect(!text.contains("flourOxidizers"))
        #expect(!text.contains("wholeGrain"))
        #expect(OverviewValidator.isValid(text, ctx: ctx))
    }

    @Test func provisionalBannerUsesEngineNotUndercount() {
        #expect(ScoringEngineV4.isProvisionalScore(fixtureYogurt(), ruleset: .bundled))
    }

    @Test func transFatFlagRequiresStrictlyPositiveGrams() {
        var zero = fixtureYogurt()
        zero = withTransFat(zero, grams: 0, flag: false)
        #expect(!zero.showsTransFatFlag)
        #expect(!TransFatAttribution.isHeaviestPenalty(in: zero))

        var nilFat = fixtureYogurt()
        nilFat = withTransFat(nilFat, grams: nil, flag: false)
        #expect(!nilFat.showsTransFatFlag)

        var positive = fixtureYogurt()
        positive = withTransFat(positive, grams: 0.5, flag: true)
        #expect(positive.showsTransFatFlag)
        // v4 attributes no trans-fat penalty → never claim "most heavily penalized".
        #expect(!TransFatAttribution.isHeaviestPenalty(in: positive))
    }

    private func profile() -> UserProfile {
        var u = MockData.user
        u.objective = "eat healthier"
        u.personalizeScoring = true
        return u
    }

    private func baseCtx(confidence: Double, signal: Bool, delta: Int,
                         allData: Bool = false) -> ScoringEngineV4.OverviewContext {
        ScoringEngineV4.OverviewContext(
            profileId: "general",
            productName: "Product",
            objective: "eat healthier",
            overall: 40,
            your: 40 + delta,
            band: "OK",
            confidence: confidence,
            hasScoreableIngredientSignal: signal,
            hasNutritionData: true,
            hasIngredientData: signal,
            rules: [
                .init(rule: "S1", topic: "additives", weight: 20, fraction: 0.9,
                      contribution: 18, multiplier: 1.3,
                      evidenceTier: allData ? "data" : (signal ? "data" : "unknown-tier"),
                      driverKind: "merit"),
                .init(rule: "S2", topic: "degree of processing", weight: 26, fraction: 0,
                      contribution: 0, multiplier: 1.5, evidenceTier: "data",
                      driverKind: "merit"),
            ],
            topPositive: [],
            topNegative: [.init(topic: "degree of processing", contribution: 0,
                                evidenceTier: "data", potentialLoss: 26)],
            nutrientLevels: [],
            deltaValue: delta,
            deltaDrivers: [.init(topic: "degree of processing", direction: "down")],
            avoidMatches: [],
            detectedAdditives: [],
            novaGroup: 4,
            hardGate: nil,
            bindingCap: nil,
            firedCaps: [],
            overallBindingCap: nil,
            overallFiredCaps: [],
            knownRuleIds: RulesetV4.bundled.allRuleIds,
            nutrientNudge: nil,
            nutrientNudgeDriver: nil
        )
    }

    private func fixtureYogurt() -> Product {
        Product(
            id: "7898571520514",
            name: "Yogurte Natural Desnatado",
            brand: "Yorgus",
            size: "170 g",
            glyph: "🥛",
            overallScore: 59,
            yourScore: 57,
            overview: nil,
            nutriGrade: "A",
            novaGroup: 0,
            nutrients: Nutrients(
                sugar_g: 2, sodium_mg: 40, satFat_g: 0,
                fiber_g: 0, protein_g: 11.5, calcium_mg: 95, kcal: 54
            ),
            bonuses: [],
            transFats: false,
            caffeine_mg: nil,
            sweeteners: [],
            seedOils: false,
            additives: [],
            restrictions: [],
            categories: ["yogurts", "dairies"]
        )
    }

    private func fixtureCereal() -> Product {
        Product(
            id: "016000275287",
            name: "Cheerios",
            brand: "General Mills",
            size: "340 g",
            glyph: "🥣",
            overallScore: 55,
            yourScore: 54,
            overview: nil,
            nutriGrade: "B",
            novaGroup: 3,
            nutrients: Nutrients(
                sugar_g: 4, sodium_mg: 190, satFat_g: 0.5,
                fiber_g: 10, protein_g: 12, calcium_mg: 130, kcal: 140,
                transFat_g: 0, iron_mg: 8
            ),
            bonuses: [],
            transFats: false,
            caffeine_mg: nil,
            sweeteners: [],
            seedOils: false,
            additives: [],
            restrictions: [],
            ingredientsText: "whole grain oats, corn starch, sugar, salt, tripotassium phosphate",
            categories: ["breakfast-cereals", "cereals"]
        )
    }

    private func fixtureGranola() -> Product {
        Product(
            id: "016000487529",
            name: "Nature Valley Oats 'N Honey",
            brand: "Nature Valley",
            size: "210 g",
            glyph: "granola",
            overallScore: 0,
            yourScore: 0,
            overview: nil,
            nutriGrade: "D",
            novaGroup: 4,
            nutrients: Nutrients(
                sugar_g: 26, sodium_mg: 180, satFat_g: 1.5,
                fiber_g: 4, protein_g: 7, kcal: 190,
                addedSugar_g: 11, transFat_g: 0
            ),
            bonuses: [],
            transFats: false,
            caffeine_mg: nil,
            sweeteners: [],
            seedOils: true,
            additives: [],
            restrictions: [],
            ingredientsText: "whole grain oats, sugar, canola oil, honey, brown sugar syrup, salt, baking soda, soy lecithin, natural flavor",
            categories: ["cereals", "granola-bars", "snacks"]
        )
    }

    private func withTransFat(_ p: Product, grams: Double?, flag: Bool) -> Product {
        var n = p.nutrients
        n.transFat_g = grams
        return Product(
            id: p.id, name: p.name, brand: p.brand, size: p.size, glyph: p.glyph,
            overallScore: p.overallScore, yourScore: p.yourScore, overview: p.overview,
            nutriGrade: p.nutriGrade, novaGroup: p.novaGroup, nutrients: n,
            bonuses: p.bonuses, transFats: flag, caffeine_mg: p.caffeine_mg,
            sweeteners: p.sweeteners, seedOils: p.seedOils, additives: p.additives,
            restrictions: p.restrictions, categories: p.categories
        )
    }
}
