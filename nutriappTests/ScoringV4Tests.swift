import Testing
import Foundation
@testable import Sage

// Scoring v4 Phase B: bundled ruleset, category router, rule fractions, and
// anchor-product expectations (SCORING_V4.md §5, §6, §12). The v4 engine is
// not UI-wired yet — these tests ARE the reference implementation gate.
struct ScoringV4Tests {

    // MARK: Fixtures

    private func product(
        kcal: Double? = nil, protein: Double? = nil, fiber: Double? = nil,
        sugar: Double? = nil, addedSugar: Double? = nil, satFat: Double? = nil,
        sodium: Double? = nil, fvn: Double? = nil, nova: Int = 0,
        ingredientsText: String? = "some ingredients",
        additives: [ProductAdditive] = [],
        categories: [String]? = nil,
        packaging: [String]? = nil,
        labels: [String]? = nil
    ) -> Product {
        Product(
            id: "x", name: "T", brand: "B", size: "", glyph: "🛒",
            overallScore: 0, yourScore: 0, deltaReason: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                 fiber_g: fiber, protein_g: protein, calcium_mg: nil,
                                 kcal: kcal, fvn: fvn, addedSugar_g: addedSugar),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            labels: labels, packagingMaterials: packaging,
            categories: categories
        )
    }

    private var chicken: Product {
        product(kcal: 165, protein: 31, fiber: 0, sugar: 0, satFat: 1, sodium: 74,
                nova: 1, ingredientsText: "chicken breast")
    }
    private var apple: Product {
        product(kcal: 52, protein: 0.3, fiber: 2.4, sugar: 10.4, satFat: 0, sodium: 1,
                fvn: 100, nova: 1, ingredientsText: "apples")
    }
    private var coke: Product {
        product(kcal: 42, protein: 0, sugar: 10.6, sodium: 10, nova: 4,
                ingredientsText: "carbonated water, sugar, caramel color, phosphoric acid",
                additives: [ProductAdditive(name: "Caramel IV", risk: .moderate, code: "e150d"),
                            ProductAdditive(name: "Phosphoric acid", risk: .moderate, code: "e338")],
                categories: ["beverages", "carbonated-drinks", "sodas"])
    }
    private var cheetos: Product {
        product(kcal: 570, protein: 6, fiber: 1, sugar: 3, satFat: 4, sodium: 800,
                nova: 4, ingredientsText: "cornmeal, oil, cheese seasoning",
                categories: ["snacks", "salty-snacks"])
    }
    private var water: Product {
        product(kcal: 0.3, sugar: 0, sodium: 2, nova: 1, ingredientsText: "water",
                categories: ["beverages", "waters"])
    }

    // MARK: Ruleset + router

    @Test func bundledRulesetLoads() {
        let rs = RulesetV4.bundled
        #expect(rs.version == "2026.07-b2")   // b2 = post-calibration weights
        #expect(rs.bands.excellent == 75)
        #expect(rs.profiles.count == 3)
        #expect(rs.bandLabel(80) == "Excellent")
        #expect(rs.bandLabel(50) == "Good")
        #expect(rs.bandLabel(30) == "Mediocre")
        #expect(rs.bandLabel(12) == "Bad")
    }

    @Test func routerPicksMostSpecificFirst() {
        #expect(ScoringEngineV4.route(coke) == "drinks")
        #expect(ScoringEngineV4.route(cheetos) == "snacks")
        #expect(ScoringEngineV4.route(chicken) == "general")   // no categories → fallback
        // Milk is tagged as a beverage too — the milks entry must win.
        let milk = product(kcal: 64, protein: 3.3, sugar: 4.8,
                           categories: ["beverages", "dairies", "milks"])
        #expect(ScoringEngineV4.route(milk) == "general")
    }

    // MARK: Rule mechanics

    @Test func s1DampeningAfterThirdHit() {
        // Five Tier-C additives (−0.09): three full + two at 50% → −0.36.
        let codes = ["e466", "e471", "e338", "e339", "e340"]
        let p = product(kcal: 100,
                        additives: codes.map { ProductAdditive(name: $0, risk: .moderate, code: $0) })
        let r = ScoringEngineV4.score(p)!
        let s1 = r.rules.first { $0.rule == "S1" }!
        #expect(abs(s1.fraction - 0.64) < 0.001)
    }

    @Test func s1GumCapCountsOnlyTwo() {
        let gums = ["e410", "e412", "e415"]   // three gums, Tier D −0.045 each
        let p = product(kcal: 100,
                        additives: gums.map { ProductAdditive(name: $0, risk: .low, code: $0) })
        let s1 = ScoringEngineV4.score(p)!.rules.first { $0.rule == "S1" }!
        #expect(abs(s1.fraction - 0.91) < 0.001)   // only two counted
    }

    @Test func s1TextSignalsDetected() {
        let p = product(kcal: 100, ingredientsText: "corn, high fructose corn syrup, salt")
        let s1 = ScoringEngineV4.score(p)!.rules.first { $0.rule == "S1" }!
        #expect(abs(s1.fraction - 0.82) < 0.001)   // HFCS = Tier B −0.18
    }

    @Test func s3FvnDiscountsFruitSugar() {
        // Same total sugar; whole-fruit smoothie keeps full credit, soda gets zero.
        let smoothie = product(kcal: 50, sugar: 12, fvn: 100,
                               categories: ["beverages", "smoothies"])
        let soda = product(kcal: 50, sugar: 12, fvn: 0,
                           categories: ["beverages", "sodas"])
        let s3 = { (p: Product) in
            ScoringEngineV4.score(p)!.rules.first { $0.rule == "S3" }!.fraction
        }
        #expect(s3(smoothie) == 1.0)
        #expect(s3(soda) == 0.0)
    }

    @Test func s6ArtificialSweetenerSteps() {
        let one = product(kcal: 1, sugar: 0, nova: 4,
                          additives: [ProductAdditive(name: "Sucralose", risk: .moderate, code: "e955")],
                          categories: ["beverages"])
        let two = product(kcal: 1, sugar: 0, nova: 4,
                          additives: [ProductAdditive(name: "Sucralose", risk: .moderate, code: "e955"),
                                      ProductAdditive(name: "Ace-K", risk: .moderate, code: "e950")],
                          categories: ["beverages"])
        let s6 = { (p: Product) in
            ScoringEngineV4.score(p)!.rules.first { $0.rule == "S6" }!.fraction
        }
        #expect(abs(s6(one) - 0.60) < 0.001)
        #expect(abs(s6(two) - 0.20) < 0.001)
    }

    @Test func s7WorstMaterialWins() {
        let mixed = product(kcal: 100, packaging: ["cardboard", "pet"])
        let s7 = ScoringEngineV4.score(mixed)!.rules.first { $0.rule == "S7" }!
        #expect(s7.fraction == 0.25)   // PET beats cardboard downward
        #expect(s7.hadData)
    }

    @Test func s8CertificationBinary() {
        let organic = product(kcal: 100, labels: ["organic", "vegan"])
        let none = product(kcal: 100, labels: ["vegan"])
        let s8 = { (p: Product) in
            ScoringEngineV4.score(p)!.rules.first { $0.rule == "S8" }!
        }
        #expect(s8(organic).fraction == 1.0)
        #expect(s8(none).fraction == 0.0)
        #expect(s8(none).hadData)   // Tier-1: absence is information, not a gap
    }

    // MARK: Minimum data + confidence

    @Test func engineRefusesInsufficientData() {
        let empty = product(kcal: nil, ingredientsText: nil)
        #expect(ScoringEngineV4.score(empty) == nil)
    }

    @Test func confidenceIsWeightBacked() {
        // Chicken: every rule has data except packaging (w 5 of Σ104).
        let r = ScoringEngineV4.score(chicken)!
        #expect(abs(r.confidence - 99.0 / 104.0) < 0.001)
    }

    // MARK: Anchor products (ruleset 2026.07-b2 — weights locked by the
    // §12 calibration run over 7,250 EN-market OFF products, 2026-07-11)

    @Test func anchorsWholeFoodsScoreExcellent() {
        let c = ScoringEngineV4.score(chicken)!
        let a = ScoringEngineV4.score(apple)!
        #expect(c.base == 83)
        #expect(a.base == 83)
        #expect(RulesetV4.bundled.bandLabel(c.base) == "Excellent")
        #expect(RulesetV4.bundled.bandLabel(a.base) == "Excellent")
    }

    @Test func anchorCokeIsMediocre() {
        let r = ScoringEngineV4.score(coke)!
        #expect(r.profileId == "drinks")
        #expect((33...34).contains(r.base))   // raw is exactly 33.5 — rounding-sensitive
        #expect(RulesetV4.bundled.bandLabel(r.base) == "Mediocre")
    }

    @Test func anchorWaterScoresHigh() {
        #expect(ScoringEngineV4.score(water)!.base >= 80)   // 85 under b2
    }

    @Test func anchorOrderingHolds() {
        let scores = [chicken, apple, water, coke, cheetos]
            .map { ScoringEngineV4.score($0)!.base }
        #expect(scores[0] > scores[3])   // chicken > coke
        #expect(scores[1] > scores[4])   // apple > cheetos
        #expect(scores[2] > scores[3])   // water > coke
    }

    /// The former "calibration gap": before the §12 run, an additive-clean
    /// NOVA-4 snack scored 64 ("Good"). The b2 weights (NOVA promoted to the
    /// second-biggest rule) put it in the bottom half — the harsh-scale
    /// target the team chose with interpretation 1 (bands, no caps).
    @Test func cheetosLandsBottomHalf() {
        let r = ScoringEngineV4.score(cheetos)!
        #expect(r.profileId == "snacks")
        #expect(r.base == 47)
        #expect(RulesetV4.bundled.bandLabel(r.base) == "Mediocre")
    }
}
