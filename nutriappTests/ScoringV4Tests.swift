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
        sodium: Double? = nil, calcium: Double? = nil, fvn: Double? = nil, nova: Int = 0,
        iron: Double? = nil, potassium: Double? = nil, magnesium: Double? = nil,
        zinc: Double? = nil, vitaminC: Double? = nil,
        name: String = "T",
        ingredientsText: String? = "some ingredients",
        additives: [ProductAdditive] = [],
        shares: [IngredientShare]? = nil,
        categories: [String]? = nil,
        packaging: [String]? = nil,
        labels: [String]? = nil,
        origins: [String]? = nil
    ) -> Product {
        Product(
            id: "x", name: name, brand: "B", size: "", glyph: "🛒",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                 fiber_g: fiber, protein_g: protein, calcium_mg: calcium,
                                 kcal: kcal, fvn: fvn, addedSugar_g: addedSugar,
                                 iron_mg: iron, potassium_mg: potassium, magnesium_mg: magnesium,
                                 zinc_mg: zinc, vitaminC_mg: vitaminC),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            labels: labels, packagingMaterials: packaging, origins: origins,
            ingredientShares: shares,
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
    private var mineralWater: Product {
        product(kcal: 0, sugar: 0, sodium: 2, calcium: 80, nova: 1,
                name: "natural mineral water", ingredientsText: "natural mineral water",
                categories: ["beverages", "waters", "mineral-waters"], packaging: ["glass"])
    }
    private var oatMilk: Product {   // the SCORING_V4.md §8 worked example
        product(kcal: 45, protein: 1, fiber: 0.8, sugar: 4, nova: 4, name: "oat drink",
                ingredientsText: "water, oats, canola oil, dipotassium phosphate, gellan gum, salt",
                additives: [ProductAdditive(name: "e340", risk: .moderate, code: "e340"),
                            ProductAdditive(name: "e418", risk: .low, code: "e418")],
                shares: [IngredientShare(name: "water", percent: nil, percentEstimate: 88),
                         IngredientShare(name: "oats", percent: 10, percentEstimate: 10)],
                categories: ["beverages", "plant-based-milk-alternatives"],
                packaging: ["tetra-pak"])
    }

    // Category-profile anchors (ruleset 2026.08-e1 — §12.9 activation calibration
    // over 11,057 EN-market OFF products). Values below are the engine's exact
    // base scores, verified in the macOS calibration harness.
    private var wholeMilk: Product {
        product(kcal: 64, protein: 3.3, fiber: 0, sugar: 4.8, satFat: 1.9, sodium: 44,
                calcium: 120, nova: 1, name: "whole milk", ingredientsText: "milk",
                categories: ["dairies", "milks"])
    }
    private var greekYogurt: Product {
        product(kcal: 59, protein: 10, fiber: 0, sugar: 3.6, satFat: 0.4, sodium: 36,
                calcium: 110, nova: 1, name: "plain greek yogurt",
                ingredientsText: "milk, live active cultures",
                categories: ["dairies", "yogurts", "greek-yogurts"])
    }
    private var cheddar: Product {
        product(kcal: 402, protein: 25, fiber: 0, sugar: 0.5, satFat: 21, sodium: 621,
                calcium: 721, nova: 1, name: "cheddar cheese",
                ingredientsText: "milk, salt, cultures, enzymes",
                categories: ["dairies", "cheeses", "cheddar-cheese"])
    }
    private var whiteBread: Product {
        product(kcal: 265, protein: 9, fiber: 2.7, sugar: 5, satFat: 0.9, sodium: 490,
                nova: 4, name: "white bread",
                ingredientsText: "wheat flour, water, yeast, salt, emulsifier",
                additives: [ProductAdditive(name: "e471", risk: .low, code: "e471", tier: .mild)],
                categories: ["breads", "white-breads"])
    }
    private var wholeGrainBread: Product {
        product(kcal: 247, protein: 13, fiber: 7, sugar: 4, satFat: 0.9, sodium: 450,
                nova: 3, name: "whole grain bread",
                ingredientsText: "whole wheat flour, water, yeast, salt",
                categories: ["breads", "whole-wheat-breads"])
    }
    private var blackTea: Product {
        product(kcal: 1, sugar: 0, nova: 1, name: "black tea", ingredientsText: "black tea",
                categories: ["teas", "black-teas"])
    }
    private var honey: Product {
        product(kcal: 304, sugar: 82, nova: 1, name: "raw honey",
                ingredientsText: "honey", categories: ["sweeteners", "honeys"])
    }
    private var bacon: Product {
        product(kcal: 400, protein: 14, sugar: 0, satFat: 12, sodium: 1300, nova: 4,
                name: "bacon", ingredientsText: "pork, salt, sodium nitrite",
                additives: [ProductAdditive(name: "e250", risk: .high, code: "e250", tier: .major)],
                categories: ["meats", "prepared-meats", "bacons"])
    }
    private var meatChicken: Product {
        product(kcal: 165, protein: 31, fiber: 0, sugar: 0, satFat: 1, sodium: 74,
                nova: 1, iron: 1, potassium: 256, zinc: 1, name: "chicken breast",
                ingredientsText: "chicken breast", categories: ["meats"])
    }

    // MARK: Ruleset + router

    @Test func bundledRulesetLoads() {
        let rs = RulesetV4.bundled
        #expect(rs.version == "2026.07-v5.0.7")
        #expect(rs.bands.excellent == 75)
        #expect(rs.bands.good == 55)
        #expect(rs.bands.ok == 35)
        #expect(rs.profiles.count == 12)
        #expect(rs.bandLabel(80) == "Excellent")
        #expect(rs.bandLabel(55) == "Good")
        #expect(rs.bandLabel(35) == "OK")
        #expect(rs.bandLabel(12) == "Bad")
    }

    // Ruleset e1 (§12.9): the eight category profiles are activated. Water +
    // alcohol stay unsupported; ready-to-drink beverages still beat dry
    // tea/coffee; every other category routes to its own calibrated profile.
    @Test func routerActivatesCategoryProfiles() {
        #expect(ScoringEngineV4.route(coke) == "drinks")
        #expect(ScoringEngineV4.route(cheetos) == "snacks")
        #expect(ScoringEngineV4.route(chicken) == "general")   // no categories → fallback
        #expect(ScoringEngineV4.route(mineralWater) == "unsupported")
        #expect(ScoringEngineV4.route(product(categories: ["beverages", "beers"])) == "unsupported")
        // Activated categories route to their own profiles.
        #expect(ScoringEngineV4.route(oatMilk) == "plant_milk")
        #expect(ScoringEngineV4.route(wholeMilk) == "dairy_milk")
        #expect(ScoringEngineV4.route(greekYogurt) == "yogurt_cheese")
        #expect(ScoringEngineV4.route(blackTea) == "tea_coffee")
        #expect(ScoringEngineV4.route(honey) == "unscored_sweetener")
        #expect(ScoringEngineV4.route(whiteBread) == "breads")
        #expect(ScoringEngineV4.route(bacon) == "meat")
        #expect(ScoringEngineV4.route(product(categories: ["frozen-desserts", "ice-creams"])) == "ice_cream")
        // Plant "milk-substitutes" beat dairy; bottled iced tea beats dry tea.
        #expect(ScoringEngineV4.route(product(categories: ["milk-substitutes"])) == "plant_milk")
        #expect(ScoringEngineV4.route(product(categories: ["beverages", "teas", "iced-teas"])) == "drinks")
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
        let p = product(kcal: 100, sugar: 0, sodium: 0, nova: 4,
                        ingredientsText: "corn, high fructose corn syrup, salt")
        let s1 = ScoringEngineV4.score(p)!.rules.first { $0.rule == "S1" }!
        #expect(abs(s1.fraction - 0.82) < 0.001)   // HFCS = Tier B −0.18
    }

    @Test func s3FvnDiscountsFruitSugarOnSolids() {
        // Solid-food variant keeps the full FVN discount; drinks cap it at 30%.
        let fruitBar = product(kcal: 50, sugar: 12, satFat: 0, sodium: 0, fvn: 100,
                               categories: ["snacks"])
        let candy = product(kcal: 50, sugar: 12, satFat: 0, sodium: 0, fvn: 0,
                            categories: ["snacks"])
        let s3 = { (p: Product) in
            ScoringEngineV4.score(p)!.rules.first { $0.rule == "S3" }!.fraction
        }
        #expect(s3(fruitBar) == 1.0)
        #expect(s3(candy) < s3(fruitBar))
        #expect(s3(candy) < 0.65)   // continuous stepped ≈ 0.63 at 12 g foods
    }

    @Test func s3DrinksCapsFvnDiscount() {
        let juice = product(kcal: 45, sugar: 8.4, fvn: 100, nova: 1,
                            categories: ["beverages", "juices"])
        let s3 = ScoringEngineV4.score(juice)!.rules.first { $0.rule == "S3" }!
        #expect(s3.fraction < 1.0)
    }

    // MARK: S13 — micronutrient credit

    @Test func s13RewardsMicronutrientDensity() {
        // Iron 9mg (0.5 cap of 18 DV) + potassium 400 (0.085) + zinc 3 (0.273)
        // → capped sum 0.858 / target 1.2 = 0.715.
        let rich = product(kcal: 350, protein: 10, sugar: 5, sodium: 100,
                           iron: 9, potassium: 400, zinc: 3)
        let s13 = ScoringEngineV4.score(rich)!.rules.first { $0.rule == "S13" }!
        #expect(abs(s13.fraction - 0.715) < 0.01)
        #expect(s13.hadData)
    }

    @Test func s13NeutralWhenNoMicrosReported() {
        // No micronutrients → neutral unknown credit, flagged as not data-backed.
        let plain = product(kcal: 200, protein: 5, sugar: 5, sodium: 100)
        let s13 = ScoringEngineV4.score(plain)!.rules.first { $0.rule == "S13" }!
        #expect(s13.fraction == 0.35)
        #expect(!s13.hadData)
    }

    @Test func s13CapsSingleMegadose() {
        // 500mg vitamin C is 5.5× DV but one nutrient can't exceed the 0.5 cap.
        let single = product(kcal: 100, sugar: 5, sodium: 50, vitaminC: 500)
        let s13 = ScoringEngineV4.score(single)!.rules.first { $0.rule == "S13" }!
        #expect(abs(s13.fraction - (0.5 / 1.2)) < 0.01)   // 0.417
        #expect(s13.hadData)
    }

    // MARK: Minimum data + confidence

    @Test func engineRefusesInsufficientData() {
        let empty = product(kcal: nil, ingredientsText: nil)
        #expect(ScoringEngineV4.score(empty) == nil)
        let textOnly = product(kcal: nil, nova: 0, ingredientsText: "água mineral natural")
        #expect(ScoringEngineV4.score(textOnly) == nil)
    }

    @Test func confidenceIsWeightBacked() {
        // General profile Σw=100. Chicken has data on all rules except S13
        // (no micros → unknownCredit, hadData false, w=5) → confidence 0.95.
        let r = ScoringEngineV4.score(chicken)!
        #expect(abs(r.confidence - 0.95) < 0.001)
    }

    // MARK: Anchor products (V5 — soft bands; exact numbers live in V5CalibrationTests)

    @Test func anchorsWholeFoodsScoreExcellent() {
        let c = ScoringEngineV4.score(chicken)!
        let a = ScoringEngineV4.score(apple)!
        #expect(c.base >= 75)
        #expect(a.base >= 75)
        #expect(RulesetV4.bundled.bandLabel(c.base) == "Excellent")
        #expect(RulesetV4.bundled.bandLabel(a.base) == "Excellent")
    }

    @Test func anchorCokeIsBad() {
        let r = ScoringEngineV4.score(coke)!
        #expect(r.profileId == "drinks")
        #expect(r.base <= 30)
        #expect(RulesetV4.bundled.bandLabel(r.base) == "Bad")
    }

    @Test func anchorDairyProfiles() {
        let milk = ScoringEngineV4.score(wholeMilk)!
        #expect(milk.profileId == "dairy_milk")
        #expect(milk.base >= 55)
        let yog = ScoringEngineV4.score(greekYogurt)!
        #expect(yog.profileId == "yogurt_cheese")
        #expect(yog.base >= 55)
        #expect(ScoringEngineV4.score(cheddar)!.base < yog.base)
    }

    @Test func anchorBreadsProfile() {
        let white = ScoringEngineV4.score(whiteBread)!
        #expect(white.profileId == "breads")
        #expect(RulesetV4.bundled.bandLabel(white.base) == "OK"
                || RulesetV4.bundled.bandLabel(white.base) == "Bad"
                || RulesetV4.bundled.bandLabel(white.base) == "Good")
        #expect(ScoringEngineV4.score(wholeGrainBread)!.base > white.base)
    }

    @Test func anchorTeaCoffeeAndSweeteners() {
        let tea = ScoringEngineV4.score(blackTea)!
        #expect(tea.profileId == "tea_coffee")
        #expect(tea.base >= 70)
        #expect(ScoringEngineV4.route(honey) == "unscored_sweetener")
        #expect(ScoringEngineV4.score(honey) == nil)
        guard case .unscored(let h, let key) =
                ScoringEngineV4.scoreProduct(honey, for: MockData.user, ruleset: RulesetV4.bundled)
        else {
            Issue.record("expected unscored honey")
            return
        }
        #expect(key == "sweetener")
        #expect(h.overallScore == nil)
    }

    @Test func anchorMeatProfile() {
        let b = ScoringEngineV4.score(bacon)!
        #expect(b.profileId == "meat")
        #expect(b.base <= 45)
        let c = ScoringEngineV4.score(meatChicken)!
        #expect(c.profileId == "meat")
        #expect(c.base >= 70)
    }

    // MARK: Phase D routing (water/alcohol unsupported; categories → general)

    @Test func waterAndAlcoholAreUnsupported() {
        // Base score() has no profile for "unsupported" → nil; the app-facing
        // scoreProduct returns .unsupported (verified in the macOS harness).
        #expect(ScoringEngineV4.route(mineralWater) == "unsupported")
        #expect(ScoringEngineV4.score(mineralWater) == nil)
        let beer = product(nova: 3, name: "lager", ingredientsText: "water, barley",
                           categories: ["beverages", "beers"])
        #expect(ScoringEngineV4.route(beer) == "unsupported")
    }

    @Test func activatedCategoriesScoreViaOwnProfile() {
        #expect(ScoringEngineV4.score(wholeMilk)!.profileId == "dairy_milk")
        #expect(ScoringEngineV4.score(oatMilk)!.profileId == "plant_milk")
        #expect(ScoringEngineV4.score(greekYogurt)!.base >= 10)
    }

    @Test func anchorOrderingHolds() {
        let scores = [chicken, apple, coke, cheetos]
            .map { ScoringEngineV4.score($0)!.base }
        #expect(scores[0] > scores[2])   // chicken > coke
        #expect(scores[1] > scores[3])   // apple > cheetos
    }

    @Test func cheetosLandsBottomHalf() {
        let r = ScoringEngineV4.score(cheetos)!
        #expect(r.profileId == "snacks")
        #expect(r.base < 55)
    }
}
