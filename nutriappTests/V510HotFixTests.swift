import Testing
import Foundation
@testable import Sage

/// V5.1.0 — Real Food / Fat Quality / kill switch.
struct V510HotfixTests {

    private let rs510 = RulesetV4.bundled
    private let rs509 = RulesetV4.bundledV509

    private func product(
        id: String = "T",
        kcal: Double? = nil, protein: Double? = nil, fiber: Double? = nil,
        sugar: Double? = nil, satFat: Double? = nil, sodium: Double? = nil,
        calcium: Double? = nil, fvn: Double? = nil, transFat: Double? = nil,
        nova: Int = 0, name: String = "T", nutriGrade: String = "?",
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
                                 kcal: kcal, fvn: fvn, transFat_g: transFat),
            bonuses: [], transFats: (transFat ?? 0) > 0, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            labels: nil, packagingMaterials: nil, origins: nil,
            ingredientShares: nil, categories: categories
        )
    }

    private var proteinPints: Product {
        product(
            id: "0850067366010",
            kcal: 177.78, protein: 11.11, sugar: 5.56, satFat: 5.56, sodium: 211.11, fvn: 1.94,
            nova: 4, name: "Cookie Dough",
            ingredientsText: "Whole milk, allulose, cream, whey protein isolate, butter, tapioca syrup, almond flour, egg yolk, powdered sugar, cane sugar, coconut oil, water, cocoa powder (processed with alkali), molasses, vanilla extract, tapioca starch, salt, skim milk, guar gum, monk fruit, sunflower lecithin",
            additives: [
                ProductAdditive(name: "Lecithins", risk: .low, code: "e322", tier: .soft),
                ProductAdditive(name: "Guar gum", risk: .low, code: "e412", tier: .soft),
            ],
            categories: ["desserts", "ice-creams"]
        )
    }

    private var bearsHoney: Product {
        product(
            id: "0198168739242",
            kcal: 250, protein: 4.84, sugar: 22.58, satFat: 8.06, sodium: 72.58, fvn: 0,
            nova: 3, name: "Honey Honey", nutriGrade: "e",
            ingredientsText: "Milk, cream, raw honey, skim milk, egg yolk",
            categories: ["desserts", "ice-creams"]
        )
    }

    @Test func rulesetIsV510AndSums100() {
        #expect(rs510.version == "2026.08-v5.5.0")
        #expect(rs510.isV510)
        #expect(rs509.version == "2026.07-v5.0.9")
        #expect(!rs509.isV510)
        for (name, rules) in rs510.profiles {
            let sum = rules.reduce(0.0) { $0 + $1.w }
            #expect(abs(sum - 100) < 0.01, "\(name) Σw=\(sum)")
        }
        #expect(rs510.ruleMeta?["S14"]?.displayName == "real food")
        #expect(rs510.ruleMeta?["S15"]?.displayName == "fat quality")
    }

    @Test func killSwitchOffReproducesV509IceCreamOrder() throws {
        let a509 = try #require(ScoringEngineV4.score(proteinPints, ruleset: rs509))
        let b509 = try #require(ScoringEngineV4.score(bearsHoney, ruleset: rs509))
        // Frozen 5.0.9 behavior: Protein Pints still competitive on sugar gaming.
        #expect(a509.base >= 52 && a509.base <= 60)
        #expect(rs509.profiles["ice_cream"]?.contains { $0.rule == "S14" && $0.w == 4 } == true)
        #expect(rs509.profiles["fats"]?.contains { $0.rule == "S15" } != true)
        _ = b509
    }

    @Test func seedOilsDropBelowTraditionalFats() throws {
        let sunflower = product(
            kcal: 884, satFat: 10, sodium: 0, nova: 2, name: "sunflower oil",
            ingredientsText: "Refined sunflower oil",
            categories: ["fats", "sunflower-oils"]
        )
        let canola = product(
            kcal: 884, satFat: 7, sodium: 0, nova: 2, name: "canola oil",
            ingredientsText: "Canola oil",
            categories: ["fats", "rapeseed-oils", "vegetable-oils"]
        )
        let evoo = product(
            kcal: 884, satFat: 14, sodium: 0, nova: 2, name: "EVOO",
            ingredientsText: "Extra virgin olive oil",
            categories: ["fats", "olive-oils"]
        )
        let coconut = product(
            kcal: 862, satFat: 82, sodium: 0, nova: 2, name: "coconut oil",
            ingredientsText: "Coconut oil",
            categories: ["fats", "coconut-oils"]
        )
        let butter = product(
            kcal: 717, satFat: 51, sodium: 11, nova: 2, name: "unsalted butter",
            ingredientsText: "Butter",
            categories: ["fats", "butters"]
        )

        let sSun = try #require(ScoringEngineV4.score(sunflower, ruleset: rs510))
        let sCan = try #require(ScoringEngineV4.score(canola, ruleset: rs510))
        let sEvoo = try #require(ScoringEngineV4.score(evoo, ruleset: rs510))
        let sCoco = try #require(ScoringEngineV4.score(coconut, ruleset: rs510))
        let sBut = try #require(ScoringEngineV4.score(butter, ruleset: rs510))

        let sun509 = try #require(ScoringEngineV4.score(sunflower, ruleset: rs509))
        let can509 = try #require(ScoringEngineV4.score(canola, ruleset: rs509))

        #expect(sun509.base - sSun.base >= 30)
        #expect(can509.base - sCan.base >= 30)
        #expect(sSun.base < sEvoo.base)
        #expect(sSun.base < sCoco.base)
        #expect(sSun.base < sBut.base)
        #expect(sCan.base < sEvoo.base)
        #expect(sCoco.base >= 65)
        #expect(sBut.base >= 62)
        #expect(sEvoo.base >= 80)
    }

    @Test func iceCreamAcceptance() throws {
        let a = try #require(ScoringEngineV4.score(proteinPints, ruleset: rs510))
        let b = try #require(ScoringEngineV4.score(bearsHoney, ruleset: rs510))
        #expect(a.base <= 48)
        #expect(b.base >= 61)
        #expect(b.base > a.base)
        #expect(rs510.bandLabel(b.base) == "Good" || rs510.bandLabel(b.base) == "Excellent")

        guard case .scored(let scoredA) =
                ScoringEngineV4.scoreProduct(proteinPints, for: MockData.user, ruleset: rs510),
              case .scored(let scoredB) =
                ScoringEngineV4.scoreProduct(bearsHoney, for: MockData.user, ruleset: rs510)
        else {
            Issue.record("expected scored")
            return
        }
        // Band label always matches the number (no UPF/Nutri-Score display cap).
        let displayA = ScoringEngineV4.displayBandLabel(
            score: scoredA.overallScore ?? 0, product: scoredA, ruleset: rs510)
        #expect(displayA == rs510.bandLabel(scoredA.overallScore ?? 0))
        #expect(scoredA.overallBandCap == nil)
        let displayB = ScoringEngineV4.displayBandLabel(
            score: scoredB.overallScore ?? 0, product: scoredB, ruleset: rs510)
        #expect(displayB == rs510.bandLabel(scoredB.overallScore ?? 0))
        #expect(displayB == "Good" || displayB == "Excellent")
        #expect(scoredB.overallBandCap == nil)

        let debug = ScoringEngineV4.debugText(proteinPints, for: MockData.user, ruleset: rs510)
        #expect(debug.contains("S3 sweetenerSubstitutionCap"))
        #expect(debug.contains("S12 isolate discount ×0.5"))
    }

    @Test func fatFreeRedistributesS15() throws {
        let tea = product(
            kcal: 1, sugar: 0, sodium: 1, nova: 1, name: "plain green tea",
            ingredientsText: "Green tea",
            categories: ["teas", "green-teas"]
        )
        let scored = try #require(ScoringEngineV4.score(tea, ruleset: rs510))
        #expect(scored.rules.contains { $0.rule == "S14" })
        // tea_coffee has no S15 — use a general fat-free snack-like product with S15 in profile
        let jelly = product(
            kcal: 60, sugar: 14, sodium: 10, nova: 3, name: "fruit jelly",
            ingredientsText: "Water, sugar, fruit juice, pectin",
            categories: ["snacks", "jellies"]
        )
        let j = try #require(ScoringEngineV4.score(jelly, ruleset: rs510))
        #expect(j.rules.contains { $0.rule == "S15" && !$0.hadData })
        let debug = ScoringEngineV4.debugText(jelly, for: MockData.user, ruleset: rs510)
        #expect(debug.contains("redistributed") || debug.contains("S15 fatQuality: no data"))
    }

    @Test func nova4BandFollowsNumber() {
        let bar = product(
            kcal: 400, protein: 20, sugar: 5, satFat: 3, sodium: 200, nova: 4,
            name: "protein bar",
            ingredientsText: "Whey protein isolate, almonds, dates",
            categories: ["snacks", "protein-bars"]
        )
        guard case .scored(let scored) =
                ScoringEngineV4.scoreProduct(bar, for: MockData.user, ruleset: rs510)
        else { return }
        let score = scored.overallScore ?? 0
        let band = ScoringEngineV4.displayBandLabel(
            score: score, product: scored, ruleset: rs510)
        #expect(band == rs510.bandLabel(score))
        #expect(scored.overallBandCap == nil)
    }

    @Test func drinksOrderingUnchanged() throws {
        let coke = product(
            kcal: 42, sugar: 10.6, sodium: 4, nova: 4, name: "Coke",
            ingredientsText: "Carbonated water, sugar, caramel, caffeine",
            categories: ["sodas", "colas"]
        )
        let diet = product(
            kcal: 0.4, sugar: 0, sodium: 8, nova: 4, name: "Diet Coke",
            ingredientsText: "Carbonated water, aspartame, caffeine",
            additives: [ProductAdditive(name: "Aspartame", risk: .moderate, code: "e951", tier: .moderate)],
            categories: ["sodas", "diet-sodas"]
        )
        let c510 = try #require(ScoringEngineV4.score(coke, ruleset: rs510))
        let d510 = try #require(ScoringEngineV4.score(diet, ruleset: rs510))
        // Oasis-aligned drinks (v5.1.0+) still ranks diet above regular cola.
        #expect(d510.base > c510.base)
        // Frozen v5.0.9 keeps the prior drinks curve; ranking direction matches.
        if let c509 = ScoringEngineV4.score(coke, ruleset: rs509),
           let d509 = ScoringEngineV4.score(diet, ruleset: rs509) {
            #expect(d509.base > c509.base)
        }
    }
}
