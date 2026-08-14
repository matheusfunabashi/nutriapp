import Testing
import Foundation
@testable import Sage

/// V5.2.0 — dairy-aware milk scoring.
/// Covers: dairyProcessing tag matching (real OFF plurals), raw-milk safety
/// gate, S14 qualifier stripping, S13 data floor, powdered-milk
/// reconstitution, fortification exemption, S12 dairy variant (protein +
/// calcium), and flavored-milk routing to the drinks path.
struct MilkScoringV52Tests {

    private let rs = RulesetV4.bundled

    private func milk(
        kcal: Double? = 64, protein: Double? = 3.3, sugar: Double? = 4.8,
        satFat: Double? = 2.4, sodium: Double? = 44, calcium: Double? = 120,
        addedSugar: Double? = nil, nova: Int = 1,
        name: String = "milk",
        ingredientsText: String? = "milk",
        additives: [ProductAdditive] = [],
        categories: [String]? = ["dairies", "milks"],
        labels: [String]? = nil,
        size: String = ""
    ) -> Product {
        Product(
            id: name, name: name, brand: "B", size: size, glyph: "🥛",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                 fiber_g: nil, protein_g: protein, calcium_mg: calcium,
                                 kcal: kcal, fvn: nil, addedSugar_g: addedSugar),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            labels: labels, packagingMaterials: nil, origins: nil,
            ingredientShares: nil, categories: categories
        )
    }

    private func rule(_ id: String, _ r: V4Result) -> V4RuleResult? {
        r.rules.first { $0.rule == id }
    }

    // MARK: dairyProcessing — real OFF tags must match

    @Test func uhtTagIsRecognized() {
        let p = milk(name: "uht", categories: ["dairies", "milks", "uht-milks"])
        let r = ScoringEngineV4.score(p)!
        let dp = rule("dairyProcessing", r)!
        #expect(dp.hadData)
        #expect(abs(dp.fraction - 0.40) < 0.001)
    }

    @Test func pasteurizedTagIsEvidenceNotAssumption() {
        let p = milk(categories: ["dairies", "milks", "pasteurised-milks"])
        let r = ScoringEngineV4.score(p)!
        let dp = rule("dairyProcessing", r)!
        #expect(dp.hadData)
        #expect(abs(dp.fraction - 0.85) < 0.001)
    }

    @Test func untaggedMilkStillFallsToUnknownDefault() {
        let p = milk()
        let r = ScoringEngineV4.score(p)!
        let dp = rule("dairyProcessing", r)!
        #expect(!dp.hadData)
        #expect(abs(dp.fraction - 0.85) < 0.001)
    }

    // MARK: Raw milk — processing credit + safety cap

    @Test func rawMilkFiresProcessingCreditAndSafetyCap() {
        let p = milk(name: "raw milk", ingredientsText: "raw milk",
                     categories: ["dairies", "milks", "raw-milks"])
        let r = ScoringEngineV4.score(p)!
        let dp = rule("dairyProcessing", r)!
        #expect(abs(dp.fraction - 0.50) < 0.001)
        let cap = rs.hardGates?.rawMilk?.cap ?? 54
        #expect(r.base == cap, "raw milk must land exactly on the safety cap, got \(r.base)")

        let gate = ScoringEngineV4.applyBaseCaps(base: 100, product: p, rs: rs)
        #expect(gate.fired.contains { $0.id == "rawMilkCap" })
        #expect(gate.capped == cap)
    }

    @Test func processingNameEvidenceRecognized() {
        let up = ScoringEngineV4.score(
            milk(name: "Fat Free Milk Lactose Free Ultra-Pasteurized"))!
        let dp = rule("dairyProcessing", up)!
        #expect(dp.hadData)
        #expect(abs(dp.fraction - 0.40) < 0.001)
    }

    @Test func yoghurtNameNeverMatchesUHT() {
        #expect(!ScoringEngineV4.matchesWord("uht", in: "creamy yoghurt drink"))
        #expect(ScoringEngineV4.matchesWord("uht", in: "uht semi skimmed milk"))
    }

    @Test func rawMilkNameEvidenceFiresCap() {
        let p = milk(name: "Farm Fresh Raw Milk")
        let gate = ScoringEngineV4.applyBaseCaps(base: 100, product: p, rs: rs)
        #expect(gate.fired.contains { $0.id == "rawMilkCap" })
        // Word boundary: "strawberry milk" contains no "raw milk".
        let straw = milk(name: "Strawberry Milk Fresh")
        let g2 = ScoringEngineV4.applyBaseCaps(base: 100, product: straw, rs: rs)
        #expect(!g2.fired.contains { $0.id == "rawMilkCap" })
    }

    @Test func pasteurizedMilkDoesNotFireRawCap() {
        let gate = ScoringEngineV4.applyBaseCaps(base: 100, product: milk(), rs: rs)
        #expect(!gate.fired.contains { $0.id == "rawMilkCap" })
    }

    // MARK: S14 — qualified ingredient names still count as whole food

    @Test func qualifiedMilkNamesMatchWholeFoodWhitelist() {
        #expect(IngredientIntegrity.isWholeFoodToken("milk"))
        #expect(IngredientIntegrity.isWholeFoodToken("organic milk"))
        #expect(IngredientIntegrity.isWholeFoodToken("raw milk"))
        #expect(IngredientIntegrity.isWholeFoodToken("goat milk"))
        #expect(IngredientIntegrity.isWholeFoodToken("fresh goat milk"))
        #expect(IngredientIntegrity.isWholeFoodToken("grade a pasteurized milk"))
        #expect(IngredientIntegrity.isWholeFoodToken("skimmed milk"))
        #expect(IngredientIntegrity.isWholeFoodToken("buttermilk"))
        // Stripping must not invent whole foods that aren't there.
        // ("organic corn syrup" is out of scope here: bare "corn syrup" already
        // prefix-matched whitelisted "corn" before qualifier stripping existed.)
        #expect(!IngredientIntegrity.isWholeFoodToken("organic high fructose corn syrup"))
        #expect(!IngredientIntegrity.isWholeFoodToken("ultrafiltered milk protein isolate"))
    }

    @Test func organicWordingCostsNothing() {
        let plain = ScoringEngineV4.score(milk())!
        let organic = ScoringEngineV4.score(
            milk(name: "organic", ingredientsText: "organic milk",
                 labels: ["organic", "grass-fed"]))!
        #expect(plain.base == organic.base,
                "wording 'organic milk' moved the score: \(plain.base) vs \(organic.base)")
    }

    @Test func goatMilkScoresLikeCowMilk() {
        let cow = ScoringEngineV4.score(milk())!
        let goat = ScoringEngineV4.score(
            milk(kcal: 69, protein: 3.6, sugar: 4.5, satFat: 2.7, sodium: 50,
                 calcium: 134, name: "goat milk", ingredientsText: "goat milk",
                 categories: ["dairies", "goat-milks"]))!
        #expect(abs(cow.base - goat.base) <= 1)
    }

    // MARK: S13 — reporting a micronutrient panel never scores below silence

    @Test func declaredCalciumNeverScoresBelowUnknown() {
        let with = ScoringEngineV4.score(milk())!
        let without = ScoringEngineV4.score(milk(calcium: nil, name: "no cal"))!
        let s13With = rule("S13", with)!
        let s13Without = rule("S13", without)!
        #expect(s13With.hadData)
        #expect(!s13Without.hadData)
        #expect(s13With.fraction >= s13Without.fraction)
        #expect(with.base >= without.base,
                "reporting calcium lowered the score: \(with.base) vs \(without.base)")
    }

    // MARK: S12 dairy variant — protein + calcium, fat-level neutral

    @Test func fatLevelIsNeutralWholeVsSkim() {
        let whole = ScoringEngineV4.score(milk())!
        let skim = ScoringEngineV4.score(
            milk(kcal: 35, protein: 3.5, sugar: 5.0, satFat: 0.1, calcium: 125,
                 name: "skim", categories: ["dairies", "milks", "skimmed-milks"]))!
        #expect(abs(whole.base - skim.base) <= 1,
                "whole \(whole.base) vs skim \(skim.base) must be a near-tie")
    }

    @Test func dairyS12UsesProteinAndCalcium() {
        let r = ScoringEngineV4.score(milk())!
        let s12 = rule("S12", r)!
        #expect(s12.note?.hasPrefix("dairy") == true)
        #expect(s12.fraction > 0.9, "plain milk earns its nutrient rule, got \(s12.fraction)")
        #expect(r.base >= 90, "clean pasteurized milk should be Excellent, got \(r.base)")
    }

    @Test func missingCalciumFallsBackToProteinAlone() {
        let r = ScoringEngineV4.score(milk(calcium: nil, name: "no cal"))!
        let s12 = rule("S12", r)!
        #expect(s12.hadData)
        #expect(s12.fraction > 0.9)
    }

    // MARK: Fortification exemption

    @Test func vitaminDFortificationIsFree() {
        let plain = ScoringEngineV4.score(milk())!
        let fortified = ScoringEngineV4.score(
            milk(nova: 3, name: "vit d milk",
                 ingredientsText: "milk, vitamin d3"))!
        #expect(plain.base == fortified.base,
                "vitamin D fortification cost points: \(plain.base) vs \(fortified.base)")
    }

    @Test func lactoseFreeMilkIsNotPenalizedForLactase() {
        let plain = ScoringEngineV4.score(milk())!
        let lf = ScoringEngineV4.score(
            milk(nova: 3, name: "lactose free",
                 ingredientsText: "milk, lactase enzyme",
                 categories: ["dairies", "milks", "lactose-free-milks"]))!
        #expect(abs(plain.base - lf.base) <= 1)
    }

    @Test func fortificationExemptionDoesNotLaunderRealProcessing() {
        // Ultrafiltered milk keeps its NOVA-4 and processing identity —
        // "ultrafiltered milk" is not on the whole-food whitelist, so the
        // exemption's NOVA reset must not apply.
        let uf = ScoringEngineV4.score(
            milk(kcal: 61, protein: 6.3, sugar: 2.5, satFat: 2.8, sodium: 48,
                 calcium: 190, nova: 4, name: "ultrafiltered",
                 ingredientsText: "ultrafiltered milk, lactase enzyme, vitamin a, vitamin d3",
                 categories: ["dairies", "milks", "ultrafiltered-milks"]))!
        let plain = ScoringEngineV4.score(milk())!
        #expect(rule("dairyProcessing", uf)!.fraction == 0.25)
        #expect(rule("S2", uf)!.fraction == 0.0)
        #expect(uf.base < plain.base - 10,
                "ultrafiltered must stay well below plain milk: \(uf.base) vs \(plain.base)")
    }

    // MARK: Powdered milk — judged as reconstituted, not as concentrate

    @Test func milkPowderIsReconstitutedBeforeThresholds() {
        let powder = milk(kcal: 496, protein: 26, sugar: 38, satFat: 16.7,
                          sodium: 371, calcium: 912, name: "whole milk powder",
                          ingredientsText: "whole milk powder",
                          categories: ["dairies", "milks-liquid-and-powder"])
        let r = ScoringEngineV4.score(powder)!
        #expect(rule("S3", r)!.fraction == 1.0, "reconstituted lactose is not a sugar bomb")
        #expect(rule("S5", r)!.fraction == 1.0)
        #expect(r.base >= 85)
    }

    @Test func liquidMilkNeverTriggersReconstitution() {
        // The `milks-liquid-and-powder` ancestor tag rides on liquid milks too;
        // kcal keeps them out of the powder path.
        let liquid = milk(name: "made with milk powder hint",
                          ingredientsText: "milk",
                          categories: ["dairies", "milks", "milks-liquid-and-powder"])
        let n = ScoringEngineV4.dairyNormalized(liquid, rs: rs).nutrients
        #expect(n.kcal == 64)
        #expect(n.sugar_g == 4.8)
    }

    // MARK: Flavored milk routes to the drinks path

    @Test func chocolateMilkRoutesToDrinks() {
        let choc = milk(kcal: 83, protein: 3.2, sugar: 10.5, satFat: 1.5,
                        sodium: 60, calcium: 115, addedSugar: 5.7, nova: 4,
                        name: "chocolate milk",
                        ingredientsText: "low-fat milk, sugar, cocoa, carrageenan",
                        additives: [ProductAdditive(name: "carrageenan", risk: .high,
                                                    code: "e407", tier: .major)],
                        categories: ["dairies", "milks", "chocolate-milks"],
                        size: "240 ml")
        #expect(ScoringEngineV4.route(choc) == "drinks")
        let r = ScoringEngineV4.score(choc)!
        let plain = ScoringEngineV4.score(milk())!
        #expect(r.base < plain.base - 15,
                "flavored milk must fall clearly below plain: \(r.base) vs \(plain.base)")
    }

    @Test func plainMilkStillRoutesToDairyProfile() {
        #expect(ScoringEngineV4.route(milk()) == "dairy_milk")
    }

    // MARK: Ladder — the ordering users should see

    @Test func milkLadderIsOrdered() {
        let vat = ScoringEngineV4.score(
            milk(name: "vat", labels: ["vat-pasteurized"]))!.base
        let pasteurized = ScoringEngineV4.score(milk())!.base
        let uht = ScoringEngineV4.score(
            milk(name: "uht", categories: ["dairies", "milks", "uht-milks"]))!.base
        let ultrafiltered = ScoringEngineV4.score(
            milk(kcal: 61, protein: 6.3, sugar: 2.5, satFat: 2.8, calcium: 190,
                 nova: 4, name: "uf",
                 ingredientsText: "ultrafiltered milk, lactase enzyme, vitamin a, vitamin d3",
                 categories: ["dairies", "milks", "ultrafiltered-milks"]))!.base
        let raw = ScoringEngineV4.score(
            milk(name: "raw", ingredientsText: "raw milk",
                 categories: ["dairies", "milks", "raw-milks"]))!.base
        #expect(vat >= pasteurized)
        #expect(pasteurized > uht)
        #expect(uht > ultrafiltered)
        #expect(ultrafiltered > raw, "unverifiable raw safety ranks below any pasteurized option")
        #expect(pasteurized >= 90 && raw <= 54)
    }
}
