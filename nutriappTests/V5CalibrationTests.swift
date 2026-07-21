import Testing
import Foundation
@testable import Sage

/// V5 calibration gate (SCORING_V5 §11). Ordering + structural assertions.
struct V5CalibrationTests {

    private let rs = RulesetV4.bundled
    private let tol = 3

    // MARK: Fixtures

    private func product(
        kcal: Double? = nil, protein: Double? = nil, fiber: Double? = nil,
        sugar: Double? = nil, addedSugar: Double? = nil, satFat: Double? = nil,
        sodium: Double? = nil, calcium: Double? = nil, fvn: Double? = nil,
        transFat: Double? = nil, nova: Int = 0,
        iron: Double? = nil, potassium: Double? = nil, magnesium: Double? = nil,
        zinc: Double? = nil, vitaminC: Double? = nil,
        name: String = "T",
        ingredientsText: String? = "some ingredients",
        additives: [ProductAdditive] = [],
        shares: [IngredientShare]? = nil,
        categories: [String]? = nil,
        labels: [String]? = nil
    ) -> Product {
        Product(
            id: "x", name: name, brand: "B", size: "", glyph: "🛒",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                 fiber_g: fiber, protein_g: protein, calcium_mg: calcium,
                                 kcal: kcal, fvn: fvn, addedSugar_g: addedSugar,
                                 transFat_g: transFat,
                                 iron_mg: iron, potassium_mg: potassium, magnesium_mg: magnesium,
                                 zinc_mg: zinc, vitaminC_mg: vitaminC),
            bonuses: [], transFats: (transFat ?? 0) > 0, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            labels: labels, packagingMaterials: nil, origins: nil,
            ingredientShares: shares,
            categories: categories
        )
    }

    private var rawApple: Product {
        product(kcal: 52, protein: 0.3, fiber: 2.4, sugar: 10.4, satFat: 0, sodium: 1,
                fvn: 100, nova: 1, name: "apple",
                ingredientsText: nil,
                categories: ["fruits", "fresh-fruits"])
    }

    private var cheeriosLike: Product {
        product(kcal: 367, protein: 12, fiber: 10, sugar: 4.5, satFat: 0.8, sodium: 470,
                nova: 4, name: "Cheerios-like cereal",
                ingredientsText: "whole grain oats, corn starch, sugar, salt, tripottassium phosphate",
                additives: [ProductAdditive(name: "e340", risk: .moderate, code: "e340", tier: .mild)],
                categories: ["breakfast-cereals", "cereals"])
    }

    private var chickenNoText: Product {
        product(kcal: 165, protein: 31, fiber: 0, sugar: 0, satFat: 1, sodium: 74,
                nova: 1, name: "chicken breast", ingredientsText: nil,
                categories: ["meats"])
    }

    private var chickenWithText: Product {
        product(kcal: 165, protein: 31, fiber: 0, sugar: 0, satFat: 1, sodium: 74,
                nova: 1, name: "chicken breast", ingredientsText: "chicken",
                categories: ["meats"])
    }

    private var greenTea: Product {
        product(kcal: 1, sugar: 0, nova: 1, name: "green tea",
                ingredientsText: "green tea",
                categories: ["teas", "green-teas"])
    }

    private var orangeJuice: Product {
        product(kcal: 45, protein: 0.7, sugar: 8.4, sodium: 1, fvn: 100, nova: 1,
                name: "100% orange juice",
                ingredientsText: "orange juice",
                categories: ["beverages", "juices", "fruit-juices", "orange-juices"])
    }

    private var cokeLike: Product {
        product(kcal: 42, protein: 0, sugar: 10.6, sodium: 10, nova: 4,
                ingredientsText: "carbonated water, sugar, caramel color, phosphoric acid",
                additives: [ProductAdditive(name: "Caramel IV", risk: .moderate, code: "e150d", tier: .moderate),
                            ProductAdditive(name: "Phosphoric acid", risk: .moderate, code: "e338", tier: .mild)],
                categories: ["beverages", "carbonated-drinks", "sodas"])
    }

    private var whiteSugar: Product {
        product(kcal: 387, sugar: 100, nova: 2, name: "white sugar",
                ingredientsText: "sugar", categories: ["sweeteners", "sugars"])
    }

    private var rawHoney: Product {
        product(kcal: 304, sugar: 82, nova: 1, name: "raw honey",
                ingredientsText: "honey", categories: ["sweeteners", "honeys"])
    }

    private var steviaTablets: Product {
        product(kcal: 0, sugar: 0, nova: 4, name: "stevia tablets",
                ingredientsText: "stevia leaf extract, erythritol",
                categories: ["sweeteners", "tabletop-sweeteners"],
                labels: ["stevia"])
    }

    private var transFatBomb: Product {
        product(kcal: 500, protein: 5, fiber: 2, sugar: 5, satFat: 8, sodium: 200,
                transFat: 1.5, nova: 4, name: "trans-fat snack",
                ingredientsText: "flour, partially hydrogenated oil",
                categories: ["snacks"])
    }

    private var brieLike: Product {
        product(kcal: 334, protein: 21, fiber: 0, sugar: 0.5, satFat: 17, sodium: 630,
                calcium: 180, nova: 3, name: "brie",
                ingredientsText: "milk, salt, cultures, enzymes",
                categories: ["dairies", "cheeses", "soft-cheeses"])
    }

    private var plainYogurt: Product {
        product(kcal: 59, protein: 10, fiber: 0, sugar: 3.6, satFat: 0.4, sodium: 36,
                calcium: 110, nova: 1, name: "plain yogurt",
                ingredientsText: "milk, live active cultures",
                categories: ["dairies", "yogurts"])
    }

    private var ramen: Product {
        product(kcal: 440, protein: 10, fiber: 2, sugar: 2, satFat: 8, sodium: 1600,
                nova: 4, name: "instant ramen",
                ingredientsText: """
                wheat flour, palm oil, salt, monosodium glutamate, disodium inosinate,
                disodium guanylate, natural flavor, caramel color, TBHQ
                """,
                additives: [
                    ProductAdditive(name: "e621", risk: .moderate, code: "e621", tier: .moderate),
                    ProductAdditive(name: "e627", risk: .low, code: "e627", tier: .mild),
                    ProductAdditive(name: "e631", risk: .low, code: "e631", tier: .mild),
                    ProductAdditive(name: "e319", risk: .high, code: "e319", tier: .major),
                ],
                categories: ["meals", "dried-products", "noodles"])
    }

    private var jif: Product {
        product(kcal: 594, protein: 22, fiber: 6, sugar: 9, satFat: 10, sodium: 420,
                nova: 4, name: "peanut butter",
                ingredientsText: "roasted peanuts, sugar, molasses, fully hydrogenated vegetable oils (rapeseed and soybean), mono and diglycerides, salt",
                additives: [ProductAdditive(name: "e471", risk: .low, code: "e471", tier: .mild)],
                categories: ["spreads", "nut-butters", "peanut-butters"])
    }

    private var yorgus: Product {
        // Sparse ingredients → provisional; yogurt_cheese profile.
        product(kcal: 97, protein: 4.5, fiber: 0, sugar: 12, satFat: 2.5, sodium: 50,
                calcium: 120, nova: 4, name: "Yorgus",
                ingredientsText: nil,
                categories: ["dairies", "yogurts", "fruit-yogurts"])
    }

    // MARK: Structural

    @Test func rulesetVersionAndBands() {
        #expect(rs.version == "2026.07-v5.0.7")
        #expect(ScoringEngineV4.engineVersion == "v5")
        #expect(rs.bands.excellent == 75)
        #expect(rs.bands.good == 55)
        #expect(rs.bands.ok == 35)
        #expect(rs.bandLabel(75) == "Excellent")
        #expect(rs.bandLabel(55) == "Good")
        #expect(rs.bandLabel(35) == "OK")
        #expect(rs.bandLabel(34) == "Bad")
        #expect(scoreLabel(75) == "Excellent")
        #expect(scoreLabel(55) == "Good")
        #expect(scoreLabel(35) == "OK")
    }

    @Test func everyProfileSumsTo100() {
        for (id, rules) in rs.profiles {
            let sum = rules.reduce(0.0) { $0 + $1.w }
            #expect(sum == 100, "profile \(id) Σw=\(sum)")
        }
    }

    @Test func waterProfileRemoved() {
        #expect(rs.profiles["water"] == nil)
        #expect(ScoringEngineV4.route(product(categories: ["waters", "mineral-waters"])) == "unsupported")
    }

    // MARK: Ordering

    @Test func rawAppleRoutesWholeFoodsAndBeatsCereal() throws {
        #expect(ScoringEngineV4.route(rawApple) == "whole_foods")
        let apple = try #require(ScoringEngineV4.score(rawApple))
        let cereal = try #require(ScoringEngineV4.score(cheeriosLike))
        #expect(apple.base >= 75)
        #expect(apple.base > cereal.base)
    }

    @Test func chickenIngredientBypassDeltaWithin3() throws {
        let a = try #require(ScoringEngineV4.score(chickenNoText))
        let b = try #require(ScoringEngineV4.score(chickenWithText))
        #expect(abs(a.base - b.base) <= 3)
    }

    @Test func plainGreenTeaAtLeast70() throws {
        let r = try #require(ScoringEngineV4.score(greenTea))
        #expect(r.base >= 70)
    }

    @Test func cokeLikeAtMost30() throws {
        let r = try #require(ScoringEngineV4.score(cokeLike))
        #expect(r.base <= 30)
    }

    @Test func orangeJuiceFreeSugarFix() throws {
        let r = try #require(ScoringEngineV4.score(orangeJuice))
        #expect(r.base <= 55)
        #expect(r.base >= 45)
        let (f, _) = ScoringEngineV4.stepped(8.4 * 0.70, thresholds: rs.s3Thresholds["drinks"]!,
                                             unknownCredit: 0.25)
        #expect(f < 1.0)
    }

    @Test func caloricSweetenersCeiling() throws {
        // V5.0.7: pure sweeteners are unscored; freeSugar still does not fire on NNS.
        #expect(ScoringEngineV4.score(whiteSugar) == nil)
        #expect(ScoringEngineV4.score(rawHoney) == nil)
        #expect(ScoringEngineV4.score(steviaTablets) == nil)
        let base = ScoringEngineV4.applyBaseCaps(base: 80, product: steviaTablets, rs: rs)
        #expect(!base.fired.contains(where: { $0.kind == "freeSugar" }))
    }

    @Test func transFatCapsOverallAt35() throws {
        let r = try #require(ScoringEngineV4.score(transFatBomb))
        #expect(r.base <= 35)
    }

    @Test func brieScoresBelowPlainYogurt() throws {
        let brie = try #require(ScoringEngineV4.score(brieLike))
        let yogurt = try #require(ScoringEngineV4.score(plainYogurt))
        #expect(brie.base < yogurt.base)
    }

    @Test func ramenIsBadAtMost35() throws {
        // Instant noodles: NOVA-4 + extreme sodium → Bad.
        let r = try #require(ScoringEngineV4.score(ramen))
        #expect(r.base <= 35)
        #expect(rs.bandLabel(r.base) == "Bad")
    }

    @Test func jifInOKBandRange() throws {
        let r = try #require(ScoringEngineV4.score(jif))
        #expect(r.base >= 35 - tol && r.base <= 50 + tol)
    }

    @Test func yorgusProvisionalAndBandOKOrGood() throws {
        #expect(ScoringEngineV4.isProvisionalScore(yorgus, ruleset: rs))
        let r = try #require(ScoringEngineV4.score(yorgus))
        let band = rs.bandLabel(r.base)
        #expect(band == "OK" || band == "Good")
    }

    @Test func steppedIsContinuousForSmallDeltas() {
        let sugarT = rs.s3Thresholds["foods"]!
        let sodiumT = rs.s4Thresholds
        for base in stride(from: 0.0, through: 30.0, by: 0.5) {
            let (a, _) = ScoringEngineV4.stepped(base, thresholds: sugarT, unknownCredit: 0.25)
            let (b, _) = ScoringEngineV4.stepped(base + 0.1, thresholds: sugarT, unknownCredit: 0.25)
            // Fraction delta × max weight (~30) → points; allow ≤2 final-point cliffs.
            #expect(abs(a - b) * 30 <= 2.0 + 0.01)
        }
        for base in stride(from: 0.0, through: 900.0, by: 20.0) {
            let (a, _) = ScoringEngineV4.stepped(base, thresholds: sodiumT, unknownCredit: 0.30)
            let (b, _) = ScoringEngineV4.stepped(base + 10, thresholds: sodiumT, unknownCredit: 0.30)
            #expect(abs(a - b) * 14 <= 2.0 + 0.01)
        }
    }

    @Test func additiveTierABNeverShowAsLowWithoutKB() {
        // A→High, B→Moderate; C/D→Low. Detector-only path (no KB) must agree.
        let major = AdditiveCatalog.risk(for: .major)
        let moderate = AdditiveCatalog.risk(for: .moderate)
        #expect(major == .high)
        #expect(moderate == .moderate)
        #expect(major != .low)
        #expect(moderate != .low)

        // e960/e961/e962/e969 are explicitly tier C in the ruleset (not fallback).
        #expect(rs.additiveTiers["e960"] == "C")
        #expect(rs.additiveTiers["e961"] == "C")
        #expect(rs.additiveTiers["e962"] == "C")
        #expect(rs.additiveTiers["e969"] == "C")
    }

    @Test func dairyProcessingDefaultIsUnknownTier() {
        let milk = product(kcal: 64, protein: 3.3, sugar: 4.8, satFat: 1.9, sodium: 44,
                           calcium: 120, nova: 1, ingredientsText: "milk",
                           categories: ["dairies", "milks"])
        let r = ScoringEngineV4.score(milk)!
        let dp = r.rules.first { $0.rule == "dairyProcessing" }
        #expect(dp?.hadData == false)
    }
}
