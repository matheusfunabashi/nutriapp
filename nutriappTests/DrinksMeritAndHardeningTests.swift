import Testing
import Foundation
@testable import Sage

/// Merit layer, erythritol dock, and F3 continuity (continuous drag/undercut).
@Suite(.serialized)
struct DrinksMeritAndHardeningTests {

    private func mk(name: String, size: String, sugar: Double, satFat: Double = 0,
                    protein: Double = 0, kcal: Double = 50, fvn: Double? = nil,
                    nova: Int,
                    caffeine: Double?, categories: [String], ingredients: String,
                    additives: [ProductAdditive] = []) -> Product {
        Product(
            id: name, name: name, brand: "T", size: size, glyph: "🥛",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: 5, satFat_g: satFat,
                                 fiber_g: 0, protein_g: protein, kcal: kcal, fvn: fvn,
                                 addedSugar_g: nil),
            bonuses: [], transFats: false, caffeine_mg: caffeine,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredients, imageURL: nil,
            labels: nil, packagingMaterials: ["carton"], origins: nil,
            ingredientShares: nil, categories: categories
        )
    }

    // MARK: Merit layer

    /// Skim-milk latte: earns BOTH merits (unsweetened brew + dairy nutrition)
    /// and, uncapped, lands at the top of the scale.
    @Test func meritSkimLatteEarnsBoth() throws {
        let skim = mk(name: "Skim Latte", size: "330 ml", sugar: 4.9, satFat: 0.1,
                      protein: 3.4, kcal: 35, nova: 3, caffeine: 25,
                      categories: ["beverages", "iced-coffees", "coffee-drinks"],
                      ingredients: "skimmed milk, coffee")
        let r = try #require(ScoringEngineV4.score(skim))
        let bd = try #require(r.drinksBreakdown)
        #expect(bd.meritBoost == DrinksScoring.brewPolyphenolMerit
                + DrinksScoring.dairyNutritionMerit)
        #expect(bd.satFatCap == 100)
        #expect((95...100).contains(r.base), "skim latte → \(r.base)")
    }

    /// Merit never lets a capped product climb: the whole-milk latte earns
    /// brew merit but stays pinned at its satfat cap.
    @Test func meritNeverOverridesCaps() throws {
        let latte = mk(name: "Whole Latte", size: "330 ml", sugar: 4.8, satFat: 1.1,
                       protein: 3.2, kcal: 60, nova: 3, caffeine: 25,
                       categories: ["beverages", "iced-coffees", "coffee-drinks"],
                       ingredients: "milk, coffee")
        let r = try #require(ScoringEngineV4.score(latte))
        let bd = try #require(r.drinksBreakdown)
        #expect(bd.meritBoost > 0)
        #expect(bd.bindingCapId == "satFatCap")
        #expect(r.base == bd.satFatCap, "merit must not lift past the cap")
    }

    /// Kombucha earns no merit: fermentation-benefit trial evidence is too
    /// weak to score, and its residual sugar disqualifies the brew credit.
    @Test func meritKombuchaUncredited() throws {
        let kombucha = mk(name: "Kombucha", size: "355 ml", sugar: 1.7, kcal: 20,
                          nova: 3, caffeine: 2,
                          categories: ["beverages", "kombucha"],
                          ingredients: "kombucha culture, tea, sugar, ginger")
        let r = try #require(ScoringEngineV4.score(kombucha))
        #expect(r.drinksBreakdown?.meritBoost == 0)
    }

    /// Sweetened tea drinks earn no brew merit — the credit is for
    /// unsweetened brews only.
    @Test func meritRequiresUnsweetened() throws {
        let sweetTea = mk(name: "Sweet Iced Tea", size: "500 ml", sugar: 6, kcal: 28,
                          nova: 4, caffeine: 8,
                          categories: ["beverages", "iced-teas"],
                          ingredients: "water, sugar, black tea")
        let r = try #require(ScoringEngineV4.score(sweetTea))
        #expect(r.drinksBreakdown?.meritBoost == 0)
    }

    // MARK: F4b — erythritol

    /// Erythritol docks harder than an otherwise-identical polyol drink.
    @Test func erythritolDocksBelowOtherPolyols() throws {
        let base = { (sweetener: String, code: String) in
            self.mk(name: "Zero Soda \(sweetener)", size: "355 ml", sugar: 0, kcal: 5,
                    nova: 4, caffeine: 0,
                    categories: ["beverages", "sodas"],
                    ingredients: "carbonated water, \(sweetener), natural flavor",
                    additives: [.init(name: sweetener, risk: .low, code: code, tier: .mild)])
        }
        let erythritol = try #require(ScoringEngineV4.score(base("erythritol", "e968")))
        let xylitol = try #require(ScoringEngineV4.score(base("xylitol", "e967")))
        #expect(DrinksScoring.containsErythritol(base("erythritol", "e968")))
        #expect(erythritol.base < xylitol.base,
                "erythritol \(erythritol.base) must score below xylitol \(xylitol.base)")
    }

    // MARK: F3 — continuity of drag and undercut

    /// The old stepwise operating points are preserved exactly…
    @Test func dragPreservesCalibratedOperatingPoints() {
        let drag = { (caf: Double, sugar: Double) in
            DrinksScoring.stackingDrag(tier1: 0, sugarG: sugar, cafMg: caf,
                                       isEnergy: true, isSports: false,
                                       hasStimulants: false)
        }
        #expect(drag(140, 0) == 13)   // 8 base + 5
        #expect(drag(199.9, 0) == 21) // 8 base + ~13 (Celsius operating point)
        #expect(drag(80, 27) == 22)   // 8 base + 14 sugar (Red Bull operating point)
        #expect(drag(160, 53.9) == 30) // Monster operating point (8 + 8 + 14)
    }

    /// …and the space between them has no cliffs: a 1 mg caffeine change can
    /// never move the drag by more than 1 point.
    @Test func dragHasNoCaffeineCliffs() {
        var previous = DrinksScoring.stackingDrag(
            tier1: 0, sugarG: 11, cafMg: 0, isEnergy: true,
            isSports: false, hasStimulants: true)
        for mg in stride(from: 0.0, through: 400.0, by: 1.0) {
            let d = DrinksScoring.stackingDrag(
                tier1: 0, sugarG: 11, cafMg: mg, isEnergy: true,
                isSports: false, hasStimulants: true)
            #expect(d >= previous, "drag decreased at \(mg) mg")
            #expect(d - previous <= 1, "drag cliff at \(mg) mg: \(previous) → \(d)")
            previous = d
        }
    }

    /// A 0.2 g sugar change never moves the drag by more than 1 point
    /// (steepest anchor slope is 2.8 pts/g — continuous, not cliffed).
    @Test func dragHasNoSugarCliffs() {
        var previous = DrinksScoring.stackingDrag(
            tier1: 0, sugarG: 0, cafMg: 80, isEnergy: true,
            isSports: false, hasStimulants: false)
        for g in stride(from: 0.0, through: 60.0, by: 0.2) {
            let d = DrinksScoring.stackingDrag(
                tier1: 0, sugarG: g, cafMg: 80, isEnergy: true,
                isSports: false, hasStimulants: false)
            #expect(d >= previous, "drag decreased at \(g) g")
            #expect(d - previous <= 1, "drag cliff at \(g) g: \(previous) → \(d)")
            previous = d
        }
    }

    /// Same continuity contract for the sugar-cap undercut.
    @Test func undercutHasNoCliffs() {
        for energy in [false, true] {
            var previous = DrinksScoring.sugarCapUndercut(sugarG: 0, cafMg: 150,
                                                          isEnergy: energy)
            for g in stride(from: 0.0, through: 60.0, by: 0.2) {
                let u = DrinksScoring.sugarCapUndercut(sugarG: g, cafMg: 150,
                                                       isEnergy: energy)
                #expect(u >= previous && u - previous <= 1,
                        "undercut cliff at \(g) g (energy=\(energy))")
                previous = u
            }
            previous = DrinksScoring.sugarCapUndercut(sugarG: 30, cafMg: 0,
                                                      isEnergy: energy)
            for mg in stride(from: 0.0, through: 400.0, by: 1.0) {
                let u = DrinksScoring.sugarCapUndercut(sugarG: 30, cafMg: mg,
                                                       isEnergy: energy)
                #expect(u >= previous && u - previous <= 1,
                        "undercut cliff at \(mg) mg (energy=\(energy))")
                previous = u
            }
        }
    }

    /// F4a — the FVN discount is gone: a nectar-tagged sugary drink scores its
    /// full free sugar (WHO: juice sugars are free sugars).
    @Test func fvnDiscountRemoved() {
        let nectar = mk(name: "Peach Nectar Drink", size: "355 ml", sugar: 10,
                        kcal: 45, fvn: 50, nova: 3, caffeine: 0,
                        categories: ["beverages", "nectars"],
                        ingredients: "water, peach puree, sugar")
        let serving = DrinksScoring.effectiveServing(for: nectar)
        let g = DrinksScoring.sugarGramsPerServing(nectar, serving: serving)
        let raw = DrinksScoring.sugarGramsPerServingRaw(nectar, serving: serving)
        #expect(g == raw, "nectar free sugar must not be FVN-discounted")
    }
}
