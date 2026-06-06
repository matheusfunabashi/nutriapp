import Testing
import Foundation
@testable import nutriapp

struct ScoringEngineTests {

    // MARK: Builders

    private func product(
        grade: String = "?",
        nova: Int = 0,
        sugar: Double? = nil,
        sodium: Double? = nil,
        satFat: Double? = nil,
        fiber: Double? = nil,
        protein: Double? = nil,
        calcium: Double? = nil,
        transFats: Bool = false,
        additives: [Additive] = [],
        dietFlags: [String] = []
    ) -> Product {
        Product(
            id: "x", name: "Test", brand: "Brand", size: "100 g", glyph: "🛒",
            overallScore: 0, yourScore: 0, deltaReason: nil,
            nutriGrade: grade, novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                 fiber_g: fiber, protein_g: protein, calcium_mg: calcium),
            bonuses: [], transFats: transFats, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives,
            restrictions: [], dietFlags: dietFlags
        )
    }

    private func profile(
        objective: String = "maintain",
        restrictions: [String] = [],
        preferences: [String] = [],
        personalize: Bool = true,
        autoFlag: Bool = true
    ) -> UserProfile {
        var u = MockData.user
        u.objective = objective
        u.restrictions = restrictions
        u.preferences = preferences
        u.personalizeScoring = personalize
        u.autoFlagRestrictions = autoFlag
        return u
    }

    // MARK: Overall

    @Test func overallAnchoredOnGrade() {
        #expect(ScoringEngine.computeOverall(product(grade: "A")) == 90)
        #expect(ScoringEngine.computeOverall(product(grade: "E")) == 22)
    }

    @Test func overallPenalizesProcessingAndTransFats() {
        let junk = product(grade: "E", nova: 4, transFats: true,
                           additives: [Additive(name: "X", risk: .high)])
        // 22 (E) - 8 (NOVA4) - 15 (trans) - 6 (high additive) = -7 → clamped to 0
        #expect(ScoringEngine.computeOverall(junk) == 0)
    }

    @Test func overallRewardsCleanWholeFood() {
        let oats = product(grade: "A", nova: 1, fiber: 10, protein: 13)
        // 90 + 5 (NOVA1) = 95
        #expect(ScoringEngine.computeOverall(oats) == 95)
    }

    @Test func overallFallsBackToNutrientsWithoutGrade() {
        let p = product(grade: "?", nova: 1, fiber: 8, protein: 13)
        // nutrientBase: 60 + 8 (fiber) + 8 (protein) = 76, + 5 (NOVA1) = 81
        #expect(ScoringEngine.computeOverall(p) == 81)
    }

    // MARK: Personalization

    @Test func proteinRichBoostsMuscleGoal() {
        let bar = product(grade: "C", nova: 4, sugar: 14, protein: 20)
        let base = ScoringEngine.computeOverall(bar)
        let scored = ScoringEngine.score(bar, for: profile(objective: "build muscle"))
        #expect(scored.yourScore > base)               // protein pushes Your Score up
        #expect(scored.bonuses.contains("protein"))
    }

    @Test func sameFoodDiffersByGoal() {
        let bar = product(grade: "C", nova: 4, sugar: 16, protein: 20)
        let muscle = ScoringEngine.score(bar, for: profile(objective: "build muscle")).yourScore
        let lose = ScoringEngine.score(bar, for: profile(objective: "lose weight")).yourScore
        #expect(muscle > lose)                          // protein helps one, sugar hurts the other
    }

    @Test func swingIsCappedAt35() {
        // Pile on many positive signals; ensure Your Score can't exceed Overall+35.
        let p = product(grade: "C", nova: 1, sugar: 2, sodium: 50, satFat: 0.5,
                        fiber: 12, protein: 25)
        let overall = ScoringEngine.computeOverall(p)
        let scored = ScoringEngine.score(p, for: profile(
            objective: "build muscle",
            preferences: ["High protein", "High fiber", "Low sugar", "Low sodium",
                          "Low fat", "Minimally processed"]))
        #expect(scored.yourScore - overall <= 35)
    }

    // MARK: Restrictions

    @Test func lowSugarRestrictionHardCaps() {
        let candy = product(grade: "E", sugar: 50)
        let scored = ScoringEngine.score(candy, for: profile(restrictions: ["Low-sugar diet"]))
        #expect(scored.yourScore <= ScoringEngine.restrictionCap)
        #expect(scored.restrictions.contains { $0.type == "low-sugar diet" })
        #expect(scored.deltaReason?.tone == .negative)
    }

    @Test func veganConflictHardCaps() {
        let cheese = product(grade: "C", protein: 20, dietFlags: ["non-vegan"])
        let scored = ScoringEngine.score(cheese, for: profile(restrictions: ["Vegan"]))
        #expect(scored.yourScore <= ScoringEngine.restrictionCap)
        #expect(scored.restrictions.contains { $0.type == "vegan" })
    }

    @Test func noConflictWhenProductCompliant() {
        let tofu = product(grade: "B", protein: 15, dietFlags: ["vegan"])
        let scored = ScoringEngine.score(tofu, for: profile(restrictions: ["Vegan"]))
        #expect(scored.restrictions.isEmpty)
        #expect(scored.yourScore > ScoringEngine.restrictionCap)
    }

    @Test func autoFlagOffSkipsRestrictions() {
        let candy = product(grade: "E", sugar: 50)
        let scored = ScoringEngine.score(candy, for: profile(restrictions: ["Low-sugar diet"], autoFlag: false))
        #expect(scored.restrictions.isEmpty)
    }

    // MARK: Toggle off

    @Test func personalizeOffMirrorsOverall() {
        let bar = product(grade: "C", sugar: 14, protein: 20)
        let overall = ScoringEngine.computeOverall(bar)
        let scored = ScoringEngine.score(bar, for: profile(objective: "build muscle", personalize: false))
        #expect(scored.yourScore == overall)
        #expect(scored.deltaReason == nil)
    }
}
