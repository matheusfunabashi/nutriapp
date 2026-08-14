import Testing
import Foundation
@testable import Sage

/// V5.2.0 — S12 `dairyDense` extension to yogurt_cheese.
/// The generic S12 (fiber/FVN = 60% of the rule) was structurally dead for
/// dairy; the dense variant blends absolute protein per 100 g with per-kcal
/// density (so yogurt outranks cream cheese without breaking whole-vs-nonfat
/// neutrality) plus calcium. Freed weight moved to S5/S4, which actually
/// separate cheeses.
struct YogurtCheeseV52Tests {

    private let rs = RulesetV4.bundled

    private func dairy(
        kcal: Double?, protein: Double?, sugar: Double? = nil,
        addedSugar: Double? = nil, satFat: Double? = nil, sodium: Double? = nil,
        calcium: Double? = nil, nova: Int = 1, name: String,
        ingredientsText: String? = nil,
        additives: [ProductAdditive] = [],
        categories: [String]? = ["dairies", "yogurts"]
    ) -> Product {
        Product(
            id: name, name: name, brand: "B", size: "", glyph: "🧀",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                 fiber_g: nil, protein_g: protein, calcium_mg: calcium,
                                 kcal: kcal, fvn: nil, addedSugar_g: addedSugar),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            labels: nil, packagingMaterials: nil, origins: nil,
            ingredientShares: nil, categories: categories
        )
    }

    private var wholeYogurt: Product {
        dairy(kcal: 61, protein: 3.5, sugar: 4.7, satFat: 2.1, sodium: 46,
              calcium: 121, name: "plain whole yogurt", ingredientsText: "cultured milk")
    }
    private var nonfatYogurt: Product {
        dairy(kcal: 56, protein: 3.8, sugar: 5.1, satFat: 0.1, sodium: 48,
              calcium: 125, name: "plain nonfat yogurt",
              ingredientsText: "cultured nonfat milk")
    }
    private var cheddar: Product {
        dairy(kcal: 402, protein: 25, sugar: 0.5, satFat: 21, sodium: 621,
              calcium: 721, nova: 3, name: "cheddar",
              ingredientsText: "milk, salt, cultures, enzymes",
              categories: ["dairies", "cheeses", "cheddar-cheese"])
    }
    private var creamCheese: Product {
        dairy(kcal: 342, protein: 5.9, sugar: 3.2, satFat: 19, sodium: 314,
              calcium: 97, nova: 4, name: "cream cheese",
              ingredientsText: "pasteurized milk and cream, salt, carob bean gum, cheese culture",
              additives: [ProductAdditive(name: "carob bean gum", risk: .low,
                                          code: "e410", tier: .mild)],
              categories: ["dairies", "cheeses", "cream-cheeses"])
    }

    private func s12(_ p: Product) -> V4RuleResult? {
        ScoringEngineV4.score(p)?.rules.first { $0.rule == "S12" }
    }

    @Test func dairyDenseVariantFires() {
        let r = s12(wholeYogurt)
        #expect(r?.note?.hasPrefix("dairyDense") == true)
        #expect((r?.fraction ?? 0) > 0.5, "plain yogurt earns its nutrient rule")
        #expect((r?.weight ?? 0) == 8)
    }

    @Test func wholeVsNonfatYogurtIsNearTie() {
        let whole = ScoringEngineV4.score(wholeYogurt)!.base
        let nonfat = ScoringEngineV4.score(nonfatYogurt)!.base
        #expect(abs(whole - nonfat) <= 1,
                "fat level is preference: whole \(whole) vs nonfat \(nonfat)")
    }

    @Test func plainYogurtIsExcellentSweetenedIsNot() {
        let plain = ScoringEngineV4.score(wholeYogurt)!.base
        let sweet = ScoringEngineV4.score(
            dairy(kcal: 99, protein: 3.3, sugar: 15, addedSugar: 10, satFat: 1.8,
                  sodium: 45, calcium: 110, nova: 3, name: "strawberry yogurt",
                  ingredientsText: "cultured milk, sugar, strawberries, pectin",
                  additives: [ProductAdditive(name: "pectin", risk: .low,
                                              code: "e440", tier: .exempt)]))!.base
        #expect(plain >= 85)
        #expect(plain - sweet >= 8,
                "added sugar must separate clearly: plain \(plain) vs sweetened \(sweet)")
    }

    @Test func yogurtOutranksCreamCheeseOnS12() {
        // Absolute grams alone can't do this (cream cheese has more protein
        // per 100 g than yogurt) — the per-kcal half of the blend does.
        let yog = s12(wholeYogurt)!.fraction
        let cc = s12(creamCheese)!.fraction
        #expect(yog > cc, "yogurt S12 \(yog) must beat cream cheese \(cc)")
    }

    @Test func cheddarImprovesButStaysBelowExcellent() {
        let r = ScoringEngineV4.score(cheddar)!
        #expect(s12(cheddar)!.fraction > 0.7, "real cheese earns protein+calcium")
        #expect(r.base >= 60 && r.base < 75,
                "sat fat + sodium keep cheddar out of Excellent, got \(r.base)")
    }

    @Test func rawMilkCheeseTakesProcessingDockWithoutFluidMilkCap() {
        let raw = dairy(kcal: 402, protein: 25, sugar: 0.5, satFat: 21, sodium: 621,
                    calcium: 721, nova: 3, name: "raw milk cheddar",
                    ingredientsText: "raw milk, salt, cultures, enzymes",
                    categories: ["dairies", "cheeses", "cheddar-cheese", "raw-milk-cheeses"])
        let r = ScoringEngineV4.score(raw)!
        let dp = r.rules.first { $0.rule == "dairyProcessing" }!
        #expect(abs(dp.fraction - 0.5) < 0.001)
        // The hard 54 cap is fluid-milk only (aged cheese is a different risk
        // class); cheese takes the graded dock instead.
        let gate = ScoringEngineV4.applyBaseCaps(base: 100, product: raw, rs: rs)
        #expect(!gate.fired.contains { $0.id == "rawMilkCap" })
        let pasteurized = ScoringEngineV4.score(cheddar)!.base
        #expect(r.base < pasteurized)
    }

    @Test func fermentedLadderIsOrdered() {
        let greek = ScoringEngineV4.score(
            dairy(kcal: 97, protein: 9.0, sugar: 4.0, satFat: 3.0, sodium: 35,
                  calcium: 110, name: "greek whole plain",
                  ingredientsText: "cultured pasteurized grade a milk, cream",
                  categories: ["dairies", "yogurts", "greek-yogurts"]))!.base
        let plain = ScoringEngineV4.score(wholeYogurt)!.base
        let ched = ScoringEngineV4.score(cheddar)!.base
        let cc = ScoringEngineV4.score(creamCheese)!.base
        #expect(greek >= plain)
        #expect(plain > ched)
        #expect(ched >= cc - 1, "cream cheese must not meaningfully outrank cheddar")
        #expect(plain - ched >= 10, "plain yogurt clearly above hard cheese")
    }

    @Test func traditionalCheeseTokensCountAsWholeFood() {
        #expect(IngredientIntegrity.isWholeFoodToken("cultures"))
        #expect(IngredientIntegrity.isWholeFoodToken("cultured milk"))
        #expect(IngredientIntegrity.isWholeFoodToken("rennet"))
        #expect(IngredientIntegrity.isWholeFoodToken("cheese cultures"))
        // Salt and generic "enzymes" deliberately stay off the whitelist.
        #expect(!IngredientIntegrity.isWholeFoodToken("enzymes"))
    }

    @Test func fortifiedYogurtIsNotPenalized() {
        let plain = ScoringEngineV4.score(wholeYogurt)!.base
        let fortified = ScoringEngineV4.score(
            dairy(kcal: 61, protein: 3.5, sugar: 4.7, satFat: 2.1, sodium: 46,
                  calcium: 121, nova: 3, name: "vit d yogurt",
                  ingredientsText: "cultured milk, vitamin d3"))!.base
        #expect(abs(plain - fortified) <= 1,
                "vitamin D in yogurt cost points: \(plain) vs \(fortified)")
    }

    @Test func cheeseNeverTriggersPowderReconstitution() {
        // Processed cheese listing "milk powder" is dense per 100 g by nature.
        let processed = dairy(kcal: 330, protein: 18, sugar: 6, satFat: 14,
                              sodium: 1200, calcium: 500, nova: 4,
                              name: "processed cheese",
                              ingredientsText: "cheese, whole milk powder, emulsifying salts",
                              categories: ["dairies", "cheeses", "processed-cheeses"])
        let n = ScoringEngineV4.dairyNormalized(processed, rs: rs, includePowder: false).nutrients
        #expect(n.kcal == 330)
        #expect(n.sodium_mg == 1200)
    }
}
