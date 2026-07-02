import Testing
import Foundation
@testable import Sage

struct ScoringEngineTests {

    // MARK: Builders

    private func product(
        kcal: Double?,
        protein: Double? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        satFat: Double? = nil,
        sodium: Double? = nil,
        calcium: Double? = nil,
        fvn: Double? = nil,
        nova: Int = 0,
        dietFlags: [String] = []
    ) -> Product {
        Product(
            id: "x", name: "T", brand: "B", size: "100 g", glyph: "🛒",
            overallScore: 0, yourScore: 0, deltaReason: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                 fiber_g: fiber, protein_g: protein, calcium_mg: calcium,
                                 kcal: kcal, fvn: fvn),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: [], restrictions: [],
            dietFlags: dietFlags, allergenTags: nil, ingredientsText: nil
        )
    }

    private func profile(
        objective: String = "maintain",
        restrictions: [String] = [],
        personalize: Bool = true,
        autoFlag: Bool = true
    ) -> UserProfile {
        var u = MockData.user
        u.objective = objective
        u.restrictions = restrictions
        u.preferences = []
        u.personalizeScoring = personalize
        u.autoFlagRestrictions = autoFlag
        return u
    }

    // Canonical reference foods (per 100g) used in the v3 validation table.
    // Anchors: 100 perfect · 70 good · 50 neutral · 30 bad · 10 avoid.
    private var chicken: Product { product(kcal: 165, protein: 31, fiber: 0, sugar: 0, satFat: 1, sodium: 74, fvn: 0, nova: 1) }
    private var apple: Product   { product(kcal: 52, protein: 0.3, fiber: 2.4, sugar: 10.4, satFat: 0, sodium: 1, fvn: 100, nova: 1) }
    private var cheetos: Product { product(kcal: 570, protein: 6, fiber: 1, sugar: 3, satFat: 4, sodium: 800, fvn: 0, nova: 4) }

    private func your(_ p: Product, _ objective: String) -> Int {
        ScoringEngine.score(p, for: profile(objective: objective)).yourScore
    }

    // MARK: Overall (Score 1, goal-neutral)

    @Test func overallMatchesValidation() {
        #expect(ScoringEngine.computeOverall(chicken) == 73)   // good food
        #expect(ScoringEngine.computeOverall(apple) == 78)     // good food
        #expect(ScoringEngine.computeOverall(cheetos) == 34)   // bad, but never 0
    }

    // MARK: Score 2 per goal — the validation table

    @Test func buildMuscleColumn() {
        #expect(your(chicken, "build muscle") == 85)
        #expect(your(apple, "build muscle") == 74)
        #expect(your(cheetos, "build muscle") == 32)
    }

    @Test func loseWeightColumn() {
        #expect(your(chicken, "lose weight") == 82)
        #expect(your(apple, "lose weight") == 86)
        #expect(your(cheetos, "lose weight") == 31)
    }

    @Test func eatHealthierColumn() {
        #expect(your(apple, "eat healthier") == 93)
        #expect(your(chicken, "eat healthier") == 78)
        #expect(your(cheetos, "eat healthier") == 30)
    }

    // MARK: Anchored scale invariants

    @Test func scoresNeverHitZero() {
        // Max out every penalty: sugary, fatty, salty, ultra-processed junk.
        let worst = product(kcal: 600, fiber: 0, sugar: 80, satFat: 30, sodium: 2000, fvn: 0, nova: 4)
        #expect(ScoringEngine.computeOverall(worst) >= ScoringEngine.floorScore)
        for goal in ["build muscle", "lose weight", "eat healthier", "maintain"] {
            #expect(your(worst, goal) >= ScoringEngine.floorScore)
        }
    }

    @Test func personalizationTunesRatherThanReplaces() {
        // Your Score stays within the ±20 adjustment band around Overall.
        for p in [chicken, apple, cheetos] {
            let overall = ScoringEngine.computeOverall(p)
            for goal in ["build muscle", "lose weight", "eat healthier"] {
                #expect(abs(your(p, goal) - overall) <= Int(ScoringEngine.maxAdjustment))
            }
        }
    }

    @Test func zeroCalorieSodaRisesForWeightLoss() {
        // The Coke Zero case: low overall, but nudged up when losing weight.
        let dietSoda = product(kcal: 0.3, sugar: 0, sodium: 15, fvn: 0, nova: 4)
        let overall = ScoringEngine.computeOverall(dietSoda)
        #expect(your(dietSoda, "lose weight") > overall)
        #expect(your(dietSoda, "eat healthier") < overall)   // …but not "healthier"
    }

    @Test func sugaryDrinkGetsNoLightnessBonus() {
        // Regular soda is low-kcal per 100ml but must not collect the
        // low-calorie-density bonus — the sugar gate blocks it.
        let soda = product(kcal: 42, sugar: 10.6, fvn: 0, nova: 4)
        #expect(your(soda, "lose weight") <= ScoringEngine.computeOverall(soda))
    }

    // MARK: Preferences tune the score too

    @Test func preferencesAdjustScore() {
        var lowSodiumFan = profile(objective: "maintain")
        lowSodiumFan.preferences = ["Low sodium"]
        let scored = ScoringEngine.score(cheetos, for: lowSodiumFan)
        #expect(scored.yourScore < scored.overallScore)   // 800mg sodium

        var proteinFan = profile(objective: "maintain")
        proteinFan.preferences = ["High protein"]
        let chick = ScoringEngine.score(chicken, for: proteinFan)
        #expect(chick.yourScore > chick.overallScore)
    }

    @Test func maintainEqualsOverall() {
        let s = ScoringEngine.score(chicken, for: profile(objective: "maintain"))
        #expect(s.yourScore == s.overallScore)   // maintain is goal-neutral
    }

    @Test func appleBeatsCheetosForMuscle() {
        // The whole point: even for muscle, the apple outranks Cheetos despite
        // Cheetos' higher protein/kcal, because its penalty sinks the driver.
        #expect(your(apple, "build muscle") > your(cheetos, "build muscle"))
    }

    // MARK: fvn discounts natural fruit sugar

    @Test func fruitSugarIsNotPenalizedViaFvn() {
        // Same sugar, but fvn=100 (whole fruit) vs fvn=0 (added sugar drink).
        let fruit = product(kcal: 52, sugar: 12, fvn: 100, nova: 1)
        let soda  = product(kcal: 52, sugar: 12, fvn: 0, nova: 4)
        #expect(ScoringEngine.computeOverall(fruit) > ScoringEngine.computeOverall(soda))
    }

    // MARK: Guards / robustness

    @Test func lowEnergyGuardDoesNotCrash() {
        let dietSoda = product(kcal: 0.4, protein: 0, sugar: 0, sodium: 10, fvn: 0, nova: 4)
        #expect(ScoringEngine.computeOverall(dietSoda) >= ScoringEngine.floorScore)
    }

    @Test func missingKcalStillScores() {
        let p = product(kcal: nil, protein: 10, fiber: 5, sugar: 3, nova: 1)
        #expect(ScoringEngine.computeOverall(p) >= ScoringEngine.floorScore)
    }

    // MARK: Restrictions

    @Test func lowSugarRestrictionHardCaps() {
        let candy = product(kcal: 400, sugar: 60, satFat: 5, sodium: 50, fvn: 0, nova: 4)
        let scored = ScoringEngine.score(candy, for: profile(restrictions: ["Low-sugar diet"]))
        #expect(scored.yourScore <= ScoringEngine.restrictionCap)
        #expect(scored.restrictions.contains { $0.type == "low-sugar diet" })
        #expect(scored.deltaReason?.tone == .negative)
    }

    @Test func veganConflictHardCaps() {
        let cheese = product(kcal: 400, protein: 25, satFat: 20, sodium: 600, fvn: 0, nova: 3,
                             dietFlags: ["non-vegan"])
        let scored = ScoringEngine.score(cheese, for: profile(restrictions: ["Vegan"]))
        #expect(scored.yourScore <= ScoringEngine.restrictionCap)
        #expect(scored.restrictions.contains { $0.type == "vegan" })
    }

    @Test func autoFlagOffSkipsRestrictions() {
        let candy = product(kcal: 400, sugar: 60, nova: 4)
        let scored = ScoringEngine.score(candy, for: profile(restrictions: ["Low-sugar diet"], autoFlag: false))
        #expect(scored.restrictions.isEmpty)
    }

    // MARK: Toggles + bonuses

    @Test func personalizeOffMirrorsOverall() {
        let s = ScoringEngine.score(chicken, for: profile(objective: "build muscle", personalize: false))
        #expect(s.yourScore == s.overallScore)
        #expect(s.deltaReason == nil)
    }

    @Test func proteinBonusPill() {
        let s = ScoringEngine.score(chicken, for: profile())
        #expect(s.bonuses.contains("protein"))
    }
}
