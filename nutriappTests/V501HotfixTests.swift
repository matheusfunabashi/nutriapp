import Testing
import Foundation
@testable import Sage

/// V5.0.1 calibration hotfixes.
struct V501HotfixTests {

    private let rs = RulesetV4.bundled

    private func product(
        kcal: Double? = nil, protein: Double? = nil, fiber: Double? = nil,
        sugar: Double? = nil, addedSugar: Double? = nil, satFat: Double? = nil,
        sodium: Double? = nil, calcium: Double? = nil, fvn: Double? = nil,
        transFat: Double? = nil, nova: Int = 0,
        name: String = "T",
        ingredientsText: String? = "some ingredients",
        additives: [ProductAdditive] = [],
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
                                 transFat_g: transFat),
            bonuses: [], transFats: (transFat ?? 0) > 0, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            labels: labels, packagingMaterials: nil, origins: nil,
            ingredientShares: nil,
            categories: categories
        )
    }

    // MARK: 1 — Industrial TFA gate

    @Test func cheddarRuminantTransFatDoesNotCap() {
        let cheddar = product(kcal: 402, protein: 25, sugar: 0.5, satFat: 21, sodium: 621,
                              calcium: 721, transFat: 0.8, nova: 3, name: "cheddar",
                              ingredientsText: "milk, salt, cultures, enzymes",
                              categories: ["dairies", "cheeses", "cheddar-cheese"])
        let gate = ScoringEngineV4.applyBaseCaps(base: 80, product: cheddar, rs: rs)
        #expect(!gate.fired.contains(where: { $0.kind == "transFat" }))
    }

    @Test func margarinePartiallyHydrogenatedCapsAt35() throws {
        let marg = product(kcal: 700, sugar: 0, satFat: 15, sodium: 700, transFat: 1.5, nova: 4,
                           name: "margarine",
                           ingredientsText: "partially hydrogenated soybean oil, water, salt",
                           categories: ["fats", "margarines"])
        let r = try #require(ScoringEngineV4.score(marg))
        #expect(r.base <= 35)
        let gate = ScoringEngineV4.applyBaseCaps(base: 80, product: marg, rs: rs)
        #expect(gate.fired.contains(where: { $0.kind == "transFat" && $0.value == 35 }))
    }

    @Test func fullyHydrogenatedOilsDoNotCap() {
        let jifLike = product(kcal: 594, protein: 22, fiber: 6, sugar: 9, satFat: 10, sodium: 420,
                              transFat: 0, nova: 4, name: "peanut butter",
                              ingredientsText: "roasted peanuts, sugar, fully hydrogenated vegetable oils (rapeseed and soybean), salt",
                              categories: ["spreads", "peanut-butters"])
        let gate = ScoringEngineV4.applyBaseCaps(base: 80, product: jifLike, rs: rs)
        #expect(!gate.fired.contains(where: { $0.kind == "transFat" }))
    }

    // MARK: 2 — Drinks NNS floor; S6 gone

    @Test func dietCokeNNSFloorBand() throws {
        let diet = product(kcal: 1, sugar: 0, sodium: 10, nova: 4, name: "Diet Coke",
                           ingredientsText: "carbonated water, caramel color, aspartame, phosphoric acid",
                           additives: [
                            ProductAdditive(name: "Aspartame", risk: .moderate, code: "e951", tier: .moderate),
                            ProductAdditive(name: "Caramel", risk: .moderate, code: "e150d", tier: .moderate),
                           ],
                           categories: ["beverages", "sodas", "diet-sodas"])
        let r = try #require(ScoringEngineV4.score(diet))
        #expect(r.profileId == "drinks")
        #expect((30...38).contains(r.base))
        let band = rs.bandLabel(r.base)
        #expect(band == "Bad" || band == "OK")
        // S3 fraction capped by NNS floor
        let s3 = r.rules.first { $0.rule == "S3" }!
        #expect(s3.fraction <= 0.30 + 0.001)
    }

    @Test func regularCokeAtMost30() throws {
        let coke = product(kcal: 42, sugar: 10.6, sodium: 10, nova: 4,
                           ingredientsText: "carbonated water, sugar, caramel color, phosphoric acid",
                           additives: [
                            ProductAdditive(name: "Caramel", risk: .moderate, code: "e150d", tier: .moderate),
                            ProductAdditive(name: "Phosphoric", risk: .moderate, code: "e338", tier: .mild),
                           ],
                           categories: ["beverages", "sodas"])
        let r = try #require(ScoringEngineV4.score(coke))
        #expect(r.base <= 30)
    }

    @Test func orangeJuiceIn45to55() throws {
        let oj = product(kcal: 45, protein: 0.7, sugar: 8.4, sodium: 1, fvn: 100, nova: 1,
                         name: "orange juice", ingredientsText: "orange juice",
                         categories: ["beverages", "juices", "orange-juices"])
        let r = try #require(ScoringEngineV4.score(oj))
        #expect((45...55).contains(r.base))
    }

    @Test func unsweetenedSparklingHigh() throws {
        let sparkling = product(kcal: 0, sugar: 0, sodium: 5, nova: 1,
                                name: "sparkling water",
                                ingredientsText: "carbonated water, natural flavor",
                                categories: ["beverages", "waters", "carbonated-waters"])
        // waters → unsupported; use flavored sparkling soda without sugar/NNS
        let flavored = product(kcal: 1, sugar: 0, sodium: 5, nova: 1,
                               name: "sparkling lemon",
                               ingredientsText: "carbonated water, natural lemon flavor",
                               categories: ["beverages", "carbonated-drinks", "sodas"])
        #expect(ScoringEngineV4.route(sparkling) == "unsupported")
        let r = try #require(ScoringEngineV4.score(flavored))
        #expect(r.profileId == "drinks")
        #expect(r.base >= 70)
        _ = sparkling
    }

    @Test func s6RemovedFromRulesetAndEngine() {
        #expect(rs.ruleMeta?["S6"] == nil)
        #expect(rs.multipliers?.objective["lose weight"]?["S6"] == nil)
        #expect(rs.multipliers?.goal["gut health"]?["S6"] == nil)
        for (_, rules) in rs.profiles {
            #expect(!rules.contains(where: { $0.rule == "S6" }))
        }
    }

    // MARK: 3 — freeSugarCeiling fruit exempt

    @Test func datesExemptFromSugarCeiling() {
        let dates = product(kcal: 282, fiber: 8, sugar: 66, fvn: 100, nova: 1,
                            name: "dates", ingredientsText: "dates",
                            categories: ["fruits", "dried-fruits", "dates"])
        let gate = ScoringEngineV4.applyBaseCaps(base: 80, product: dates, rs: rs)
        #expect(!gate.fired.contains(where: { $0.kind == "freeSugar" }))
    }

    @Test func honeyAndCandyHitCeiling() throws {
        let honey = product(kcal: 304, sugar: 82, nova: 1, name: "honey",
                            ingredientsText: "honey", categories: ["sweeteners", "honeys"])
        let candy = product(kcal: 400, sugar: 55, fvn: 0, nova: 4, name: "candy",
                            ingredientsText: "sugar, corn syrup",
                            categories: ["sweets", "candies"])
        // V5.0.7: pure honey is unscored; freeSugar still applies to food candy.
        #expect(ScoringEngineV4.route(honey) == "unscored_sweetener")
        #expect(ScoringEngineV4.score(honey) == nil)
        let c = try #require(ScoringEngineV4.score(candy))
        #expect(c.base <= 35)
        #expect(ScoringEngineV4.applyBaseCaps(base: 80, product: candy, rs: rs)
            .fired.contains(where: { $0.kind == "freeSugar" }))
    }

    // MARK: 4 — Router

    @Test func driedLentilsWholeFoodsRamenSnacks() {
        let lentils = product(kcal: 116, protein: 9, fiber: 8, sugar: 2, sodium: 5, fvn: 100,
                              nova: 1, name: "dried lentils", ingredientsText: "lentils",
                              categories: ["legumes", "dried-products", "lentils"])
        let ramen = product(kcal: 440, protein: 10, sugar: 2, satFat: 8, sodium: 1600, nova: 4,
                            name: "ramen",
                            ingredientsText: "wheat flour, palm oil, salt",
                            categories: ["meals", "dried-products", "noodles"])
        #expect(ScoringEngineV4.route(lentils) == "whole_foods")
        #expect(ScoringEngineV4.route(ramen) == "snacks")

        // V5.0.4: noodles sit above pastas (breads). Other snack tags may follow
        // whole_foods; NOVA gate (not order) keeps processed nuts out of whole_foods.
        let noodleIdx = rs.router.firstIndex { $0.match == "noodles" }!
        let pastaIdx = rs.router.firstIndex { $0.match == "pastas" }!
        #expect(noodleIdx < pastaIdx)
        #expect(!rs.router.contains(where: { $0.match == "dried-products" }))
    }

    // MARK: 5 — whole_foods sodium

    @Test func saltedNutsScoreBelowUnsalted() throws {
        let unsalted = product(kcal: 600, protein: 20, fiber: 8, sugar: 4, satFat: 5, sodium: 5,
                               fvn: 100, nova: 1, name: "almonds",
                               ingredientsText: "almonds",
                               categories: ["nuts", "almonds"])
        let salted = product(kcal: 600, protein: 20, fiber: 8, sugar: 4, satFat: 5, sodium: 500,
                             fvn: 100, nova: 1, name: "salted almonds",
                             ingredientsText: "almonds, salt",
                             categories: ["nuts", "almonds"])
        let u = try #require(ScoringEngineV4.score(unsalted))
        let s = try #require(ScoringEngineV4.score(salted))
        #expect(ScoringEngineV4.route(unsalted) == "whole_foods")
        let delta = u.base - s.base
        #expect(delta >= 3 && delta <= 8)
    }

    @Test func plainAppleUnchangedAroundExcellent() throws {
        let apple = product(kcal: 52, protein: 0.3, fiber: 2.4, sugar: 10.4, sodium: 1,
                            fvn: 100, nova: 1, name: "apple", ingredientsText: nil,
                            categories: ["fruits", "fresh-fruits"])
        let r = try #require(ScoringEngineV4.score(apple))
        #expect(r.base >= 75)
        // Prior V5 snapshot was Excellent; allow ±2 around a high Excellent floor.
        #expect(r.base >= 73)
    }
}
