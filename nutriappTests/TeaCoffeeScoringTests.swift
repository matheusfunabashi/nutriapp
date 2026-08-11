import Testing
import Foundation
@testable import Sage

/// Task 3 golden set: tea & coffee across both paths — the dry-goods
/// `tea_coffee` profile (M1, M5) and RTD coffee/tea on `drinks` (M2–M4).
/// Ranges per docs/TEA_COFFEE_FIXTURES_PROPOSAL.md.
@Suite(.serialized)
struct TeaCoffeeScoringTests {

    private func mk(name: String, size: String, sugar: Double,
                    addedSugar: Double? = nil, satFat: Double = 0,
                    kcal: Double = 50, nova: Int, caffeine: Double?,
                    categories: [String], ingredients: String,
                    additives: [ProductAdditive] = [],
                    packaging: [String]? = ["carton"]) -> Product {
        Product(
            id: name, name: name, brand: "T", size: size, glyph: "☕️",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: 5, satFat_g: satFat,
                                 fiber_g: 0, protein_g: 0, kcal: kcal, fvn: nil,
                                 addedSugar_g: addedSugar),
            bonuses: [], transFats: false, caffeine_mg: caffeine,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredients, imageURL: nil,
            labels: nil, packagingMaterials: packaging, origins: nil,
            ingredientShares: nil, categories: categories
        )
    }

    // MARK: Dry-goods fixtures (tea_coffee profile)

    /// D1 — plain roasted ground coffee, NOVA 1.
    private var groundCoffee: Product {
        mk(name: "Ground Coffee", size: "500 g", sugar: 0, kcal: 2, nova: 1, caffeine: nil,
           categories: ["beverages", "coffees", "ground-coffees", "roasted-coffees"],
           ingredients: "roasted ground coffee")
    }

    /// D2 — loose-leaf green tea, NOVA 1.
    private var looseGreenTea: Product {
        mk(name: "Green Tea Loose", size: "100 g", sugar: 0, kcal: 1, nova: 1, caffeine: nil,
           categories: ["beverages", "teas", "green-teas"],
           ingredients: "green tea leaves")
    }

    /// D3 — plain instant coffee (spray-dried), NOVA 4 per OFF tagging.
    private var instantCoffee: Product {
        mk(name: "Instant Coffee", size: "100 g", sugar: 0, kcal: 2, nova: 4, caffeine: nil,
           categories: ["beverages", "coffees", "instant-coffees"],
           ingredients: "instant coffee")
    }

    /// D4 — roasted chicory coffee substitute, NOVA 3.
    private var chicorySubstitute: Product {
        mk(name: "Chicory Drink Mix", size: "200 g", sugar: 2, nova: 3, caffeine: nil,
           categories: ["beverages", "instant-chicory", "coffee-substitutes", "coffees"],
           ingredients: "roasted chicory root")
    }

    /// D5 — 3-in-1 sweetened instant mix: 60 g sugar per 100 g of *powder*.
    /// The M1 liquid gate keeps it on the dry profile.
    private var threeInOneMix: Product {
        mk(name: "3-in-1 Instant Coffee", size: "200 g", sugar: 60, kcal: 450, nova: 4,
           caffeine: nil,
           categories: ["beverages", "coffees", "instant-coffees"],
           ingredients: "sugar, instant coffee, coconut oil creamer, emulsifier e471",
           additives: [.init(name: "e471", risk: .low, code: "e471", tier: .mild)])
    }

    // MARK: RTD fixtures (drinks profile)

    /// R1 — unsweetened black cold brew, 149 mg caffeine per can.
    private var coldBrewBlack: Product {
        mk(name: "Cold Brew Black", size: "355 ml", sugar: 0, kcal: 5, nova: 1, caffeine: 42,
           categories: ["beverages", "iced-coffees", "coffee-drinks"],
           ingredients: "water, coffee")
    }

    /// R2 — unsweetened caffè latte: all sugar is milk lactose (M2).
    private var unsweetenedLatte: Product {
        mk(name: "Caffe Latte Unsweetened", size: "330 ml", sugar: 4.8, satFat: 1.1,
           kcal: 45, nova: 3, caffeine: 25,
           categories: ["beverages", "iced-coffees", "coffee-drinks"],
           ingredients: "milk, coffee")
    }

    /// R3 — lightly sweetened matcha latte: ~4.5 g/100 ml lactose + ~3 g/100 ml added.
    private var matchaLatte: Product {
        mk(name: "Matcha Latte", size: "330 ml", sugar: 7.5, satFat: 1.5,
           kcal: 60, nova: 4, caffeine: 18,
           categories: ["beverages", "iced-teas", "tea-based-drinks"],
           ingredients: "milk, water, sugar, matcha green tea, gellan gum",
           additives: [.init(name: "e418", risk: .low, code: "e418", tier: .mild)])
    }

    /// R4 — Frappuccino-class: heavy added sugar plus cream (M3).
    private var frappuccino: Product {
        mk(name: "Frappuccino", size: "405 ml", sugar: 11, satFat: 2.5,
           kcal: 80, nova: 4, caffeine: 16,
           categories: ["beverages", "iced-coffees", "coffee-drinks"],
           ingredients: "milk, coffee, sugar, cream")
    }

    /// R5 — sweetened RTD wearing dry-tea tags: must rerail to drinks (M1 keeps
    /// the envelope for genuine liquids).
    private var mislabeledSweetTea: Product {
        mk(name: "Sweet Tea Drink", size: "500 ml", sugar: 8, kcal: 35, nova: 4, caffeine: 10,
           categories: ["beverages", "teas", "black-teas"],
           ingredients: "water, sugar, black tea extract")
    }

    /// Oat-milk latte control: plant milk must NOT get the lactose allowance (M2).
    private var oatMilkLatte: Product {
        mk(name: "Oat Latte", size: "330 ml", sugar: 4.8, satFat: 0.3,
           kcal: 45, nova: 4, caffeine: 25,
           categories: ["beverages", "iced-coffees", "coffee-drinks"],
           ingredients: "oat milk, coffee")
    }

    // MARK: Helpers

    private func score(_ p: Product, expectProfile: String? = nil) -> Int {
        let r = ScoringEngineV4.score(p)!
        if let expectProfile {
            #expect(r.profileId == expectProfile, "\(p.name) profile \(r.profileId)")
        }
        return r.base
    }

    private func expectRange(_ p: Product, _ lo: Int, _ hi: Int, profile: String) {
        let r = ScoringEngineV4.score(p)!
        #expect(r.profileId == profile, "\(p.name) profile \(r.profileId)")
        if r.base < lo || r.base > hi, let bd = r.drinksBreakdown {
            print("FAIL \(p.name) score=\(r.base) weighted=\(bd.weightedScore) "
                  + "caps s=\(bd.sugarCap) c=\(bd.caffeineCap) w=\(bd.sweetenerCap) f=\(bd.satFatCap) "
                  + "bind=\(bd.bindingCapId ?? "nil") sugarG=\(bd.sugarPerServingG ?? -1) "
                  + "cafMg=\(bd.caffeinePerServingMg ?? -1)")
            for rule in bd.rules {
                print("  \(rule.rule) w=\(rule.weight) f=\(String(format: "%.3f", rule.fraction))")
            }
        }
        #expect((lo...hi).contains(r.base), "\(p.name) → \(r.base) not in \(lo)...\(hi)")
    }

    // MARK: Golden ranges — dry goods

    @Test func goldenGroundCoffee() { expectRange(groundCoffee, 78, 92, profile: "tea_coffee") }
    @Test func goldenLooseGreenTea() { expectRange(looseGreenTea, 85, 95, profile: "tea_coffee") }
    @Test func goldenInstantCoffee() { expectRange(instantCoffee, 50, 68, profile: "tea_coffee") }
    @Test func goldenChicorySubstitute() { expectRange(chicorySubstitute, 60, 75, profile: "tea_coffee") }

    /// D5 — the powder bug: must stay on the dry profile (M1), never be handed
    /// a fictional liquid serving, and land in the Bad/low-OK band its sugar
    /// density deserves.
    @Test func goldenThreeInOneMix() {
        let r = ScoringEngineV4.score(threeInOneMix)!
        #expect(r.profileId == "tea_coffee", "3-in-1 must not reroute to drinks")
        #expect(r.drinksBreakdown == nil, "3-in-1 must not get a liquid serving")
        #expect((25...40).contains(r.base), "3-in-1 → \(r.base) not in 25...40")
    }

    // MARK: Golden ranges — RTD

    @Test func goldenColdBrewBlack() { expectRange(coldBrewBlack, 88, 96, profile: "drinks") }
    @Test func goldenUnsweetenedLatte() { expectRange(unsweetenedLatte, 78, 90, profile: "drinks") }
    @Test func goldenMatchaLatte() { expectRange(matchaLatte, 58, 74, profile: "drinks") }
    @Test func goldenFrappuccino() { expectRange(frappuccino, 25, 35, profile: "drinks") }

    /// R5 — liquid with dry-tea tags still rerails through the envelope.
    @Test func goldenMislabeledSweetTea() {
        #expect(ScoringEngineV4.firstTagProfile(mislabeledSweetTea) == "tea_coffee")
        expectRange(mislabeledSweetTea, 15, 22, profile: "drinks")
    }

    // MARK: Invariants

    /// I24 — an unsweetened, non-energy coffee/tea RTD (≤200 mg caffeine per
    /// serving) beats every diet soda by ≥30 points.
    @Test func invariantI24_BlackCoffeeBeatsDietSodas() {
        let coffee = score(coldBrewBlack, expectProfile: "drinks")
        let dietCoke = mk(name: "Diet Coke", size: "355 ml", sugar: 0, kcal: 1, nova: 4,
                          caffeine: 12.96,
                          categories: ["beverages", "sodas", "diet-sodas", "colas"],
                          ingredients: "carbonated water, caramel color, aspartame, phosphoric acid, caffeine",
                          additives: [
                            .init(name: "aspartame", risk: .moderate, code: "e951", tier: .moderate),
                            .init(name: "e150d", risk: .moderate, code: "e150d", tier: .moderate),
                          ])
        let diet = score(dietCoke, expectProfile: "drinks")
        #expect(coffee - diet >= 30, "cold brew \(coffee) vs diet \(diet)")
    }

    /// I25 — lactose-only latte beats Frappuccino-class by ≥30; lightly
    /// sweetened matcha sits strictly between them.
    @Test func invariantI25_LatteLadder() {
        let latte = score(unsweetenedLatte)
        let matcha = score(matchaLatte)
        let frap = score(frappuccino)
        #expect(latte - frap >= 30, "latte \(latte) vs frap \(frap)")
        #expect(latte > matcha && matcha > frap,
                "ladder \(latte) > \(matcha) > \(frap) violated")
    }

    /// I26 — a product whose size does not parse as a liquid volume never gets
    /// a drinks breakdown with a liquid effective serving (kills the powder
    /// bug class permanently).
    @Test func invariantI26_NoFictionalLiquidServings() {
        for p in [groundCoffee, looseGreenTea, instantCoffee, chicorySubstitute, threeInOneMix] {
            let r = ScoringEngineV4.score(p)!
            #expect(r.drinksBreakdown == nil,
                    "\(p.name) (dry) got a liquid breakdown: \(r.profileId)")
        }
    }

    /// I27 — energyDrinkEvidence outranks the gentle coffee curve: Red Bull
    /// wearing tea tags stays within 3 points of canonical Red Bull.
    @Test func invariantI27_EnergyEvidenceOutranksGentleCurve() {
        let canonical = mk(name: "Red Bull", size: "250 ml", sugar: 10.8, kcal: 45, nova: 4,
                           caffeine: 32,
                           categories: ["beverages", "energy-drinks"],
                           ingredients: "water, sucrose, glucose, taurine, caffeine, B-vitamins")
        let teaTagged = mk(name: "Red Bull tea tags", size: "250 ml", sugar: 10.8, kcal: 45,
                           nova: 4, caffeine: 32,
                           categories: ["beverages", "teas", "black-teas"],
                           ingredients: "water, sucrose, glucose, taurine, caffeine, B-vitamins")
        #expect(DrinksScoring.isEnergyDrink(teaTagged), "evidence gate must fire")
        #expect(!DrinksScoring.isNonEnergyTeaCoffeeRTD(teaTagged),
                "gentle curve must refuse energy-evidence products")
        let a = score(canonical, expectProfile: "drinks")
        let b = score(teaTagged, expectProfile: "drinks")
        #expect(abs(a - b) <= 3, "tag variance \(a) vs \(b)")
    }

    /// I28 — M2 is a no-op for non-dairy drinks: the lactose allowance never
    /// fires without dairy evidence, and plant milks are excluded.
    @Test func invariantI28_LactoseAllowanceNoLeak() {
        #expect(!DrinksScoring.hasDairyIngredientEvidence(oatMilkLatte),
                "oat milk must not count as dairy")
        #expect(DrinksScoring.hasDairyIngredientEvidence(unsweetenedLatte))
        // Same numbers as the latte but plant-based: no exemption, lower score.
        let dairy = score(unsweetenedLatte)
        let oat = score(oatMilkLatte)
        #expect(oat < dairy, "oat latte \(oat) must score below dairy latte \(dairy) (no lactose exemption)")
        // And for a non-dairy drink, per-serving sugar equals the raw total.
        let serving = DrinksScoring.effectiveServing(for: oatMilkLatte)
        let g = DrinksScoring.sugarGramsPerServing(oatMilkLatte, serving: serving)
        let raw = DrinksScoring.sugarGramsPerServingRaw(oatMilkLatte, serving: serving)
        #expect(g == raw, "non-dairy sugar must be untouched by M2")
    }

    /// Gentle-cap continuity guard (mirrors I20 for the coffee/tea cap).
    @Test func invariantCoffeeTeaCapMonotonic() {
        var previous = DrinksScoring.coffeeTeaCaffeineCap(mgPerServing: 0)
        for mg in stride(from: 0.0, through: 450.0, by: 0.5) {
            let cap = DrinksScoring.coffeeTeaCaffeineCap(mgPerServing: mg)
            #expect(cap <= previous, "gentle cap rose at \(mg) mg")
            previous = cap
        }
    }

    // MARK: Summary table

    @Test func printTeaCoffeeSummary() {
        let rows: [(String, Product, String)] = [
            ("D1 ground coffee", groundCoffee, "78-92"),
            ("D2 loose green tea", looseGreenTea, "85-95"),
            ("D3 instant coffee", instantCoffee, "50-68"),
            ("D4 chicory", chicorySubstitute, "60-75"),
            ("D5 3-in-1 mix", threeInOneMix, "25-40"),
            ("R1 cold brew", coldBrewBlack, "88-96"),
            ("R2 latte", unsweetenedLatte, "78-90"),
            ("R3 matcha latte", matchaLatte, "58-74"),
            ("R4 frappuccino", frappuccino, "25-35"),
            ("R5 mislabeled tea", mislabeledSweetTea, "15-22"),
            ("ctrl oat latte", oatMilkLatte, "< latte"),
        ]
        var lines = ["=== TEA/COFFEE GOLDEN (Task 3) ==="]
        for (label, p, expected) in rows {
            guard let r = ScoringEngineV4.score(p) else {
                lines.append("\(label)\tnil\t\(expected)"); continue
            }
            let bind = r.drinksBreakdown?.bindingCapId ?? "-"
            lines.append("\(label)\t\(r.base)\t\(r.profileId)\t\(bind)\t\(expected)")
        }
        print(lines.joined(separator: "\n"))
    }
}
