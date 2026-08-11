import Testing
import Foundation
@testable import Sage

/// Spot checks for drinks scoring v2 (caps, effective serving, S6 tiers).
/// Full ranges live in `DrinksScoringGoldenTests`.
struct DrinksOasisScoringTests {

    private let rs = RulesetV4.bundled

    private func product(
        kcal: Double? = nil, protein: Double? = nil, fiber: Double? = nil,
        sugar: Double? = nil, addedSugar: Double? = nil, satFat: Double? = nil,
        sodium: Double? = nil, fvn: Double? = nil, nova: Int = 0,
        name: String = "T", size: String = "",
        ingredientsText: String? = "some ingredients",
        additives: [ProductAdditive] = [],
        categories: [String]? = nil,
        packaging: [String]? = nil,
        servingSize: String? = nil,
        caffeinePer100ml: Double? = nil
    ) -> Product {
        var p = Product(
            id: "x", name: name, brand: "B", size: size, glyph: "🛒",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                 fiber_g: fiber, protein_g: protein,
                                 kcal: kcal, fvn: fvn, addedSugar_g: addedSugar),
            bonuses: [], transFats: false, caffeine_mg: caffeinePer100ml,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            labels: nil, packagingMaterials: packaging, origins: nil,
            ingredientShares: nil,
            categories: categories
        )
        p.servingSize = servingSize
        return p
    }

    // MARK: Effective serving

    @Test func effectiveServingWholeContainerUnder600() {
        let p = product(sugar: 10, size: "500 ml", categories: ["beverages", "sodas"],
                        servingSize: "250 ml")
        let s = DrinksScoring.effectiveServing(for: p)
        #expect(s.ml == 500)
        #expect(s.usedWholeContainer)
        #expect(!s.estimatedServing)
    }

    @Test func effectiveServingFallback355() {
        let p = product(sugar: 10, categories: ["beverages", "sodas"])
        let s = DrinksScoring.effectiveServing(for: p)
        #expect(s.ml == 355)
        #expect(s.estimatedServing)
    }

    @Test func parseVolumeFlOz() {
        let ml = DrinksScoring.parseVolumeMilliliters("12 fl oz")
        #expect(abs((ml ?? 0) - 354.882) < 0.01)
    }

    // MARK: Profile shape

    @Test func drinksProfileHasV2Rules() throws {
        let rules = try #require(rs.profiles["drinks"])
        let byRule = Dictionary(uniqueKeysWithValues: rules.map { ($0.rule, $0) })
        #expect(byRule["S1"]?.w == 23)
        #expect(byRule["S3"]?.w == 43)
        #expect(byRule["S3"]?.variant == "drinksServing")
        #expect(byRule["S8"]?.w == 15)
        #expect(byRule["S6"]?.w == 13)
        #expect(byRule["S4"]?.w == 6)
        // F1: packaging is a sustainability badge, not a scored health rule.
        #expect(byRule["S7"] == nil)
        #expect(byRule["S2"] == nil)
        #expect(byRule["S5"] == nil)
        #expect(rules.reduce(0) { $0 + $1.w } == 100)
        #expect(rs.s3Thresholds["drinksServing"] == [2, 8, 16, 30])
        #expect(rs.ruleMeta?["S8"]?.displayName == "caffeine")
    }

    // MARK: Caps

    @Test func sugarCapCurve() {
        #expect(DrinksScoring.sugarCap(gramsPerServing: 10) == 100)
        #expect(DrinksScoring.sugarCap(gramsPerServing: 16) == 100)
        #expect(DrinksScoring.sugarCap(gramsPerServing: 30) == 20)
        #expect(DrinksScoring.sugarCap(gramsPerServing: 40) == 20)
        let mid = DrinksScoring.sugarCap(gramsPerServing: 23)
        #expect(mid > 20 && mid < 55)
    }

    /// Track 2 (3c): cap starts biting at 60 mg and lands on 25 at 300 mg.
    @Test func caffeineCapCurve() {
        #expect(DrinksScoring.caffeineCap(mgPerServing: 50) == 100)
        #expect(DrinksScoring.caffeineCap(mgPerServing: 60) == 100)
        #expect(DrinksScoring.caffeineCap(mgPerServing: 160) == 52)
        #expect(DrinksScoring.caffeineCap(mgPerServing: 200) == 40)
        #expect(DrinksScoring.caffeineCap(mgPerServing: 300) == 25)
    }

    @Test func sweetenerCapTier1() {
        #expect(DrinksScoring.sweetenerCap(hasTier1: true) == 55)
        #expect(DrinksScoring.sweetenerCap(hasTier1: false) == 100)
    }

    // MARK: S3 / S6 / S7

    @Test func cokeSugarCapBinds() throws {
        let coke = product(
            kcal: 42, sugar: 10.6, sodium: 10, nova: 4, size: "355 ml",
            ingredientsText: "carbonated water, sugar, caramel color, phosphoric acid",
            additives: [
                ProductAdditive(name: "Caramel", risk: .moderate, code: "e150d", tier: .moderate),
            ],
            categories: ["beverages", "sodas"],
            packaging: ["aluminium"]
        )
        let r = try #require(ScoringEngineV4.score(coke))
        #expect(r.profileId == "drinks")
        let bd = try #require(r.drinksBreakdown)
        #expect((bd.sugarPerServingG ?? 0) >= 30)
        #expect(bd.sugarCap == 20)
        #expect(r.base <= 20)
        #expect(r.base >= 10)
    }

    @Test func dietCokeTier1S6AndCap() throws {
        let diet = product(
            kcal: 1, sugar: 0, sodium: 10, nova: 4, name: "Diet Coke", size: "355 ml",
            ingredientsText: "carbonated water, caramel color, aspartame, phosphoric acid, caffeine",
            additives: [
                ProductAdditive(name: "Aspartame", risk: .moderate, code: "e951", tier: .moderate),
                ProductAdditive(name: "Caramel", risk: .moderate, code: "e150d", tier: .moderate),
            ],
            categories: ["beverages", "sodas", "diet-sodas"],
            packaging: ["aluminium"],
            caffeinePer100ml: 12.96
        )
        let r = try #require(ScoringEngineV4.score(diet))
        let s6 = try #require(r.rules.first { $0.rule == "S6" })
        #expect(abs(s6.fraction - 0.10) < 0.001)
        #expect(r.drinksBreakdown?.sweetenerCap == 55)
        #expect(r.base <= 55)
        #expect(r.base >= 40)
        // Cap should rarely bind after stacking — prefer merit score.
        #expect(r.drinksBreakdown?.bindingCapId != "sweetenerCap")
    }

    @Test func steviaIsTier3NotTier1() throws {
        let stevia = product(
            kcal: 1, sugar: 0, sodium: 5, nova: 4, name: "Stevia Cola", size: "355 ml",
            ingredientsText: "carbonated water, stevia leaf extract, natural flavor",
            additives: [
                ProductAdditive(name: "Stevia", risk: .low, code: "e960", tier: .mild),
            ],
            categories: ["beverages", "sodas"],
            packaging: ["aluminium"]
        )
        let r = try #require(ScoringEngineV4.score(stevia))
        let s6 = try #require(r.rules.first { $0.rule == "S6" })
        // Track 2 (3b): one Tier-3 sweetener lands on 0.70, not the old ~0.90.
        #expect(abs(s6.fraction - 0.70) < 0.001)
        #expect(r.drinksBreakdown?.sweetenerCap == 100)
    }

    @Test func packagingIsABadgeNotAScore() throws {
        let base = { (pack: [String]) in
            product(kcal: 1, sugar: 0, sodium: 5, nova: 1, size: "355 ml",
                    ingredientsText: "carbonated water, natural lemon flavor",
                    categories: ["beverages", "sodas"],
                    packaging: pack)
        }
        let glass = try #require(ScoringEngineV4.score(base(["glass"])))
        let pet = try #require(ScoringEngineV4.score(base(["pet"])))
        // F1: packaging still resolves, as a sustainability badge…
        #expect(glass.drinksBreakdown?.packagingCredit == 1.0)
        #expect(pet.drinksBreakdown?.packagingCredit == 0.25)
        #expect(glass.drinksBreakdown?.packagingHadData == true)
        // …but it must no longer move the health score, and must not appear
        // among the weighted rules.
        #expect(glass.base == pet.base)
        #expect(!glass.rules.contains { $0.rule == "S7" })
    }

    @Test func missingPackagingGetsMidCredit() throws {
        let p = product(kcal: 1, sugar: 0, sodium: 5, nova: 1, size: "355 ml",
                        ingredientsText: "carbonated water, natural lemon flavor",
                        categories: ["beverages", "sodas"])
        let r = try #require(ScoringEngineV4.score(p))
        #expect(r.drinksBreakdown?.packagingCredit == 0.40)
        #expect(r.drinksBreakdown?.packagingHadData == false)
        #expect(!r.rules.contains { $0.rule == "S7" })
        #expect(r.drinksBreakdown?.lowDataConfidence != true
                || r.drinksBreakdown?.estimatedServing == false)
    }

    @Test func unsweetenedSparklingScoresExcellent() throws {
        let flavored = product(
            kcal: 1, sugar: 0, sodium: 5, nova: 1,
            name: "sparkling lemon", size: "355 ml",
            ingredientsText: "carbonated water, natural lemon flavor",
            categories: ["beverages", "carbonated-drinks", "sodas"],
            packaging: ["glass"]
        )
        let r = try #require(ScoringEngineV4.score(flavored))
        #expect(r.profileId == "drinks")
        #expect(r.base >= 75)
    }

    @Test func orangeJuiceRoutesToJuice100() throws {
        let oj = product(
            kcal: 45, protein: 0.7, sugar: 9.33, sodium: 1, fvn: 100, nova: 1,
            name: "orange juice", size: "300 ml",
            ingredientsText: "orange juice",
            categories: ["beverages", "juices", "orange-juices"],
            packaging: ["carton"]
        )
        let r = try #require(ScoringEngineV4.score(oj))
        #expect(r.profileId == "juice_100")
        let bd = try #require(r.drinksBreakdown)
        #expect(abs((bd.sugarPerServingG ?? 0) - 28.0) < 0.2)
        #expect(bd.micronutrientBoost == 3)
        #expect(bd.sugarCap < 100) // 28g → between 20 and 40
    }
}
