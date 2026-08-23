import Testing
import Foundation
@testable import Sage

/// V5.6.0 — Dairy in four forms (SCORING_V5.md §"V5.6.0 Dairy").
/// dairy_milk / dairy_fermented / dairy_cheese / dairy_cream, free sugar with
/// a lactose allowance, marker-family processing, form & cultures, the S13
/// reference prior, the sparse-record identity gate, and the routing evidence
/// gates (creams off the oils profile, plant-based off dairy, protein shakes
/// to drinks, infant formula unsupported).
struct DairyScoringV56Tests {

    private let rs = RulesetV4.bundled

    private func product(
        kcal: Double? = 61, protein: Double? = 3.2, sugar: Double? = 4.8,
        addedSugar: Double? = nil, satFat: Double? = 1.9, sodium: Double? = 43,
        calcium: Double? = 113, potassium: Double? = nil, vitaminD: Double? = nil,
        nova: Int = 1, name: String, ingredientsText: String? = "milk, vitamin d3",
        additives: [ProductAdditive] = [], labels: [String]? = nil,
        categories: [String]? = ["dairies", "milks", "whole-milks"],
        servingSize: String? = nil
    ) -> Product {
        var nutrients = Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                  fiber_g: nil, protein_g: protein, calcium_mg: calcium,
                                  kcal: kcal, fvn: nil, addedSugar_g: addedSugar)
        nutrients.potassium_mg = potassium
        nutrients.vitaminD_ug = vitaminD
        var p = Product(
            id: name, name: name, brand: "B", size: "", glyph: "🥛",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: nutrients,
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            labels: labels, packagingMaterials: nil, origins: nil,
            ingredientShares: nil, categories: categories
        )
        p.servingSize = servingSize
        return p
    }

    private func rule(_ id: String, _ r: V4Result) -> V4RuleResult? {
        r.rules.first { $0.rule == id }
    }

    // MARK: Routing — four forms

    @Test func fourFormsRoute() {
        #expect(ScoringEngineV4.route(product(name: "milk")) == "dairy_milk")
        #expect(ScoringEngineV4.route(product(
            name: "yogurt", categories: ["dairies", "yogurts"])) == "dairy_fermented")
        #expect(ScoringEngineV4.route(product(
            name: "cheddar", categories: ["dairies", "cheeses", "cheddar-cheese"])) == "dairy_cheese")
        #expect(ScoringEngineV4.route(product(
            name: "sour cream", categories: ["dairies", "creams", "sour-creams"])) == "dairy_cream")
    }

    /// D01 — creams no longer score as olive oil. Sour cream was 95 and
    /// half-and-half 97 on the `fats` profile.
    @Test func creamsLeaveTheOilsProfile() {
        let sour = ScoringEngineV4.score(product(
            kcal: 198, protein: 2.4, sugar: 3, satFat: 11, sodium: 31, calcium: 101,
            nova: 3, name: "sour cream", ingredientsText: "cultured cream",
            categories: ["dairies", "creams", "sour-creams"]))!
        #expect(sour.profileId == "dairy_cream")
        #expect(sour.base >= 55 && sour.base <= 72, "sour cream is Good, not Excellent: \(sour.base)")

        let heavy = ScoringEngineV4.score(product(
            kcal: 340, protein: 2.8, sugar: 2.9, satFat: 23, sodium: 27, calcium: 66,
            nova: 1, name: "heavy cream", ingredientsText: "cream",
            categories: ["dairies", "creams"]))!
        #expect(heavy.base >= 45 && heavy.base <= 62, "heavy cream sits at the Good/OK line: \(heavy.base)")

        let half = ScoringEngineV4.score(product(
            kcal: 130, protein: 3, sugar: 4, satFat: 7, sodium: 40, calcium: 105,
            nova: 1, name: "half and half", ingredientsText: "milk, cream",
            categories: ["dairies", "creams", "half-and-half"]))!
        #expect(half.base >= 68 && half.base <= 80)
        #expect(half.base > sour.base && sour.base > heavy.base)
    }

    /// Cheese-tagged mascarpone is cream by composition.
    @Test func mascarponeScoresAsCream() {
        let r = ScoringEngineV4.score(product(
            kcal: 429, protein: 4.6, sugar: 3.3, satFat: 29, sodium: 40, calcium: 60,
            nova: 3, name: "mascarpone", ingredientsText: "pasteurized cream, citric acid",
            categories: ["dairies", "cheeses", "mascarpone", "cream-cheeses"]))!
        #expect(r.profileId == "dairy_cream")
        #expect(r.base < 60)
    }

    /// D06 — infant formula is unsupported, not "Bad".
    @Test func infantFormulaIsUnsupported() {
        let formula = product(
            kcal: 510, protein: 10.5, sugar: 56, satFat: 11, sodium: 140, calcium: 400,
            nova: 4, name: "Infant formula stage 1",
            ingredientsText: "nonfat milk, lactose, oils",
            categories: ["baby-foods", "infant-formulas"])
        #expect(ScoringEngineV4.route(formula) == "unsupported")
    }

    /// …but a protein shake wearing a junk `baby-milks` tag is not formula.
    @Test func formulaTagNeedsFormulaEvidence() {
        let shake = product(
            kcal: 31, protein: 6.4, sugar: 0.3, satFat: 0, sodium: 90, calcium: 200,
            nova: 4, name: "French Vanilla High Protein Shake",
            ingredientsText: "ultrafiltered skim milk, natural flavors, salt, pectin, monk fruit, stevia leaf extract",
            categories: ["dairies", "milks", "baby-milks"])
        #expect(ScoringEngineV4.route(shake) == "drinks")
    }

    /// Plant-based products riding dairy tags leave the dairy family; the
    /// match is word-bounded so goat milk never reads as oat milk.
    @Test func plantBasedLeavesDairy() {
        let almond = product(
            kcal: 15, protein: 0.4, sugar: 0, satFat: 0, sodium: 58, calcium: 180,
            nova: 4, name: "Almondmilk", ingredientsText: "almondmilk (filtered water, almonds), calcium carbonate, sea salt",
            categories: ["dairies", "milks"])
        #expect(ScoringEngineV4.route(almond) == "plant_milk")

        let vegan = product(
            kcal: 300, protein: 0, sugar: 0, satFat: 20, sodium: 900, calcium: nil,
            nova: 4, name: "Creamy Original Slices",
            ingredientsText: "filtered water, coconut oil, modified potato starch",
            categories: ["dairies", "cheeses", "sliced-cheeses"])
        #expect(ScoringEngineV4.route(vegan) == "general")

        let goat = product(
            kcal: 69, protein: 3.6, sugar: 4.5, satFat: 2.7, sodium: 50, calcium: 134,
            name: "Goat milk", ingredientsText: "pasteurized goat milk, vitamin d3",
            categories: ["dairies", "milks", "goat-milks"])
        #expect(ScoringEngineV4.route(goat) == "dairy_milk")

        let nonVegan = product(
            kcal: 403, protein: 23, sugar: 0.5, satFat: 21, sodium: 650, calcium: 710,
            nova: 3, name: "cheddar", ingredientsText: "pasteurized milk, cheese cultures, salt, enzymes",
            labels: ["non-vegan"], categories: ["dairies", "cheeses", "cheddar-cheese"])
        #expect(ScoringEngineV4.route(nonVegan) == "dairy_cheese",
                "a 'non-vegan' label is not plant evidence")
    }

    /// Sweetened, flavored protein shakes tagged `milks` score as drinks;
    /// plain high-protein milk stays on the milk profile.
    @Test func proteinShakeGate() {
        let core = product(
            kcal: 60, protein: 10, sugar: 2, satFat: 0.5, sodium: 80, calcium: 230,
            nova: 4, name: "CORE POWER High Protein Milk Shake Chocolate",
            ingredientsText: "ultra-filtered milk, cocoa, natural flavors, acesulfame potassium, sucralose",
            additives: [ProductAdditive(name: "sucralose", risk: .moderate, code: "e955", tier: .moderate)],
            categories: ["dairies", "milks"])
        #expect(ScoringEngineV4.route(core) == "drinks")

        let plainProtein = product(
            kcal: 75, protein: 5, sugar: 5, satFat: 2, sodium: 48, calcium: 150,
            name: "PROTEIN Milk", ingredientsText: "milk, ultra-filtered skim milk, lactase enzyme, vitamin d3",
            categories: ["dairies", "milks"])
        #expect(ScoringEngineV4.route(plainProtein) == "dairy_milk")
    }

    // MARK: Milk

    @Test func plainMilkCalibration() {
        let whole = ScoringEngineV4.score(product(name: "whole milk"))!
        let skim = ScoringEngineV4.score(product(
            kcal: 34, protein: 3.4, sugar: 5.0, satFat: 0.1, sodium: 42, calcium: 122,
            name: "skim milk", ingredientsText: "fat free milk, vitamin a palmitate, vitamin d3",
            categories: ["dairies", "milks", "skimmed-milks"]))!
        #expect(whole.base >= 95, "plain milk is a top-shelf whole food: \(whole.base)")
        #expect(abs(whole.base - skim.base) <= 2, "fat level is preference: \(whole.base) vs \(skim.base)")
    }

    /// D07 — UHT is a small dock (~3 pts), not 4.5; ultrafiltration is a
    /// minor process, not ultra-processing; raw keeps the 54 cap.
    @Test func processingLadder() {
        let plain = ScoringEngineV4.score(product(name: "milk"))!
        let uht = ScoringEngineV4.score(product(
            name: "uht milk", categories: ["dairies", "milks", "uht-milks"]))!
        let uf = ScoringEngineV4.score(product(
            kcal: 50, protein: 5.4, sugar: 2.5, satFat: 1.9, sodium: 50, calcium: 160,
            nova: 4, name: "ultrafiltered milk",
            ingredientsText: "reduced fat ultra-filtered milk, lactase enzyme, vitamin a palmitate, vitamin d3",
            categories: ["dairies", "milks", "ultrafiltered-milks"]))!
        let raw = ScoringEngineV4.score(product(
            name: "raw milk", ingredientsText: "raw milk",
            categories: ["dairies", "milks", "raw-milks"]))!
        #expect(plain.base > uht.base)
        #expect(plain.base - uht.base <= 5)
        #expect(uf.base >= 90, "membrane filtration is not a triple penalty: \(uf.base)")
        #expect(raw.base == 54)
        let dpUHT = rule("dairyProcessing", uht)!
        #expect(abs(dpUHT.fraction - 0.7) < 0.001)
        let dpPlain = rule("dairyProcessing", plain)!
        #expect(dpPlain.hadData, "pasteurized-by-law default is evidence, not assumption")
        #expect(abs(dpPlain.fraction - 1.0) < 0.001)
    }

    /// D08 — a sparse record inside the milk envelope takes the identity
    /// prior, not the packaged-food 0.20 unknown.
    @Test func sparseMilkIdentityGate() {
        let sparse = ScoringEngineV4.score(product(
            nova: 0, name: "whole milk no data", ingredientsText: nil,
            categories: ["dairies", "milks"]))!
        #expect(sparse.base >= 82, "plain-milk envelope, no list → provisional, not punitive: \(sparse.base)")
        let s1 = rule("S1", sparse)!
        #expect(!s1.hadData && abs(s1.fraction - 0.75) < 0.001)

        // Outside the envelope (sugar 11) the prior drops.
        let sweet = ScoringEngineV4.score(product(
            kcal: 88, sugar: 11, nova: 0, name: "mystery flavored milk", ingredientsText: nil,
            categories: ["dairies", "milks"]))!
        let s1Sweet = rule("S1", sweet)!
        #expect(abs(s1Sweet.fraction - 0.45) < 0.001)
    }

    /// D10 — fortification (DHA, choline, folic acid, prebiotic fibre) is not
    /// processing.
    @Test func extendedFortificationExemption() {
        let plain = ScoringEngineV4.score(product(name: "milk"))!
        let dha = ScoringEngineV4.score(product(
            nova: 4, name: "milk with dha",
            ingredientsText: "milk, dha algal oil, choline chloride, folic acid, vitamin d3"))!
        #expect(abs(plain.base - dha.base) <= 2,
                "fortifying milk is a public-health win: \(plain.base) vs \(dha.base)")
    }

    /// Plausibility — a per-serving panel entered as per 100 g is rescaled
    /// through the declared serving.
    @Test func perServingPanelIsRescaled() {
        let wrong = product(
            kcal: 150, protein: 8, sugar: 11, satFat: 4.5, sodium: 120, calcium: 280,
            name: "whole milk", categories: ["dairies", "milks", "whole-milks"],
            servingSize: "240 ml")
        let r = ScoringEngineV4.score(wrong)!
        #expect(rule("S3", r)!.fraction > 0.9, "11 g per 240 ml is 4.6 g/100 ml of lactose")
        #expect(r.base >= 90)
    }

    // MARK: Fermented

    @Test func fermentedCalibration() {
        let plain = ScoringEngineV4.score(product(
            kcal: 61, protein: 3.5, sugar: 4.7, satFat: 2.1, sodium: 46, calcium: 121,
            name: "plain yogurt", ingredientsText: "cultured pasteurized whole milk, live active cultures",
            categories: ["dairies", "yogurts"]))!
        let greek = ScoringEngineV4.score(product(
            kcal: 57, protein: 10.3, sugar: 3.0, satFat: 0, sodium: 36, calcium: 110,
            name: "plain nonfat greek", ingredientsText: "grade a pasteurized skimmed milk, live active yogurt cultures",
            categories: ["dairies", "yogurts", "greek-yogurts"]))!
        #expect(plain.base >= 88)
        #expect(greek.base >= plain.base)
        #expect(greek.base >= 93)
    }

    /// D03 — lactose is not free sugar; declared added sugar wins with no
    /// further discount; an implausible added value (above total) is ignored.
    @Test func lactoseAllowanceAndAddedSugar() {
        let plain = ScoringEngineV4.score(product(
            kcal: 61, protein: 3.5, sugar: 4.7, satFat: 2.1, sodium: 46, calcium: 121,
            name: "plain yogurt", ingredientsText: "cultured milk, live cultures",
            categories: ["dairies", "yogurts"]))!
        #expect(rule("S3", plain)!.fraction == 1.0, "4.7 g lactose is not free sugar")

        // Noosa-style: 4 clean ingredients, 9 g declared added sugar — the old
        // intrinsic ×0.7 discount put this at 85; the free-sugar cap holds it
        // out of Excellent.
        let noosa = ScoringEngineV4.score(product(
            kcal: 123, protein: 4.8, sugar: 13.2, addedSugar: 9, satFat: 3.9,
            sodium: 55, calcium: 150, nova: 3, name: "honey yoghurt",
            ingredientsText: "pasteurized whole milk, cane sugar, honey, live active cultures",
            categories: ["dairies", "yogurts"]))!
        #expect(noosa.base <= 66, "a dessert yogurt is never Excellent: \(noosa.base)")

        // OFF copy-paste error: added 11.5 g on a plain Greek with 3.5 g total.
        let bogus = ScoringEngineV4.score(product(
            kcal: 59, protein: 10.6, sugar: 3.5, addedSugar: 11.5, satFat: 0,
            sodium: 36, calcium: 110, name: "plain greek",
            ingredientsText: "cultured pasteurized grade a nonfat milk",
            categories: ["dairies", "yogurts", "greek-yogurts"]))!
        #expect(bogus.base >= 90, "added > total is a data error, not a dessert: \(bogus.base)")
    }

    /// D02 — the sugar axis outranks the clean-label axis: a 4-ingredient
    /// dessert yogurt lands below a fruit Greek yogurt with pectin.
    @Test func sugarBeatsCleanLabel() {
        let noosa = ScoringEngineV4.score(product(
            kcal: 123, protein: 4.8, sugar: 13.2, addedSugar: 9, satFat: 3.9,
            sodium: 55, calcium: 150, nova: 3, name: "honey yoghurt",
            ingredientsText: "pasteurized whole milk, cane sugar, honey, live active cultures",
            categories: ["dairies", "yogurts"]))!
        let chobani = ScoringEngineV4.score(product(
            kcal: 87, protein: 8, sugar: 10, addedSugar: 6, satFat: 0, sodium: 40,
            calcium: 100, nova: 3, name: "strawberry greek",
            ingredientsText: "cultured nonfat milk, cane sugar, strawberries, water, fruit pectin, natural flavors, locust bean gum, lemon juice concentrate",
            additives: [ProductAdditive(name: "pectin", risk: .low, code: "e440", tier: .soft),
                        ProductAdditive(name: "locust bean gum", risk: .low, code: "e410", tier: .soft)],
            categories: ["dairies", "yogurts", "greek-yogurts"]))!
        #expect(chobani.base > noosa.base,
                "less added sugar wins: fruit Greek \(chobani.base) vs dessert \(noosa.base)")
    }

    /// Tier-1 sweeteners on fermented dairy take the NNS ceiling.
    @Test func sweetenerCapOnFermented() {
        let light = ScoringEngineV4.score(product(
            kcal: 50, protein: 5, sugar: 4, addedSugar: 0.5, satFat: 0, sodium: 40,
            calcium: 100, nova: 4, name: "light yogurt",
            ingredientsText: "cultured nonfat milk, water, strawberries, modified food starch, sucralose, acesulfame potassium",
            additives: [ProductAdditive(name: "sucralose", risk: .moderate, code: "e955", tier: .moderate),
                        ProductAdditive(name: "acesulfame k", risk: .moderate, code: "e950", tier: .moderate)],
            categories: ["dairies", "yogurts"]))!
        #expect(light.base <= rs.dairy!.sweetenerCap)

        // A "no sucralose" label is not a sweetener hit.
        let labelled = ScoringEngineV4.score(product(
            kcal: 67, protein: 11.3, sugar: 2.7, satFat: 0, sodium: 40, calcium: 120,
            name: "plain skyr", ingredientsText: "pasteurized skim milk, live active cultures",
            labels: ["no-sucralose", "no-aspartame"],
            categories: ["dairies", "yogurts", "skyr"]))!
        #expect(labelled.base >= 90, "negated labels must not read as sweeteners: \(labelled.base)")
    }

    /// D09 — milk protein concentrate is the product's own protein, not an
    /// isolate to halve S12 for.
    @Test func milkProteinConcentrateExemptFromIsolateHalving() {
        let pro = ScoringEngineV4.score(product(
            kcal: 80, protein: 13.3, sugar: 4.7, addedSugar: 2.7, satFat: 0,
            sodium: 50, calcium: 130, nova: 4, name: "high protein yogurt",
            ingredientsText: "cultured grade a nonfat milk, milk protein concentrate, water, cane sugar, natural flavors",
            categories: ["dairies", "yogurts", "greek-yogurts"]))!
        let s12 = rule("S12", pro)!
        #expect(s12.note?.contains("isolate") != true, "no ×0.5 for dairy-derived protein")
        #expect(s12.fraction > 0.8)
    }

    /// Missing sodium on a yogurt is an omission, not a risk (D14).
    @Test func fermentedSodiumPrior() {
        let r = ScoringEngineV4.score(product(
            kcal: 57, protein: 10.3, sugar: 3.0, satFat: 0, sodium: nil, calcium: 110,
            name: "greek, no sodium", ingredientsText: "pasteurized skim milk, live active cultures",
            categories: ["dairies", "yogurts", "greek-yogurts"]))!
        let s4 = rule("S4", r)!
        #expect(!s4.hadData && abs(s4.fraction - 0.9) < 0.001)
    }

    // MARK: Cheese

    @Test func cheeseLadder() {
        func cheese(_ name: String, kcal: Double, prot: Double, sat: Double,
                    na: Double, ca: Double, sugar: Double = 1,
                    ing: String = "pasteurized milk, cheese cultures, salt, enzymes",
                    cats: [String] = ["dairies", "cheeses"]) -> Int {
            ScoringEngineV4.score(product(
                kcal: kcal, protein: prot, sugar: sugar, satFat: sat, sodium: na,
                calcium: ca, nova: 3, name: name, ingredientsText: ing,
                categories: cats))!.base
        }
        let cottage = cheese("cottage", kcal: 98, prot: 11, sat: 2.7, na: 390, ca: 80,
                             sugar: 3, ing: "cultured skim milk, cream, salt",
                             cats: ["dairies", "cheeses", "cottage-cheeses"])
        let swiss = cheese("swiss", kcal: 380, prot: 27, sat: 18, na: 192, ca: 890)
        let cheddar = cheese("cheddar", kcal: 403, prot: 23, sat: 21, na: 650, ca: 710,
                             sugar: 0.5, cats: ["dairies", "cheeses", "cheddar-cheese"])
        let feta = cheese("feta", kcal: 264, prot: 14, sat: 15, na: 917, ca: 493, sugar: 4)
        let halloumi = cheese("halloumi", kcal: 321, prot: 22, sat: 17, na: 1200, ca: 700,
                              cats: ["dairies", "cheeses", "halloumi"])
        #expect(cottage >= 80)
        #expect(swiss >= 80, "low-sodium Swiss earns its protein and calcium: \(swiss)")
        #expect(cheddar >= 65 && cheddar < 75, "cheddar is Good, not Excellent: \(cheddar)")
        #expect(feta < cheddar, "feta's sodium outweighs its lower fat: \(feta) vs \(cheddar)")
        #expect(halloumi == rs.dairy!.cheeseSodiumCap.cap,
                "≥1200 mg sodium tops out in the OK band: \(halloumi)")
        #expect(cheddar > halloumi)
    }

    /// The form rule: emulsifying salts read as processed cheese; vegetable
    /// oil reads as an analogue; anti-caking is a small dock; raw-milk aged
    /// cheese takes a graded dock, never the fluid-milk 54 cap.
    @Test func cheeseFormRule() {
        let american = ScoringEngineV4.score(product(
            kcal: 280, protein: 16, sugar: 7, satFat: 12, sodium: 1300, calcium: 530,
            nova: 4, name: "american singles",
            ingredientsText: "cheddar cheese (milk, cheese culture, salt, enzymes), skim milk, milkfat, milk protein concentrate, whey, sodium citrate, salt, sodium phosphate, sorbic acid",
            categories: ["dairies", "cheeses", "processed-cheese", "sliced-cheeses"]))!
        #expect(american.base < 55, "processed singles stay in the OK band: \(american.base)")
        let form = rule("dairyForm", american)!
        #expect(abs(form.fraction - 0.35) < 0.001)

        let analogue = ScoringEngineV4.score(product(
            kcal: 250, protein: 14, sugar: 9, satFat: 6, sodium: 1400, calcium: 430,
            nova: 4, name: "cheese product",
            ingredientsText: "skim milk, milk, canola oil, milk protein concentrate, whey, sodium phosphate, modified food starch",
            categories: ["dairies", "cheeses", "processed-cheese"]))!
        #expect(abs(rule("dairyForm", analogue)!.fraction - 0.1) < 0.001)

        let rawCheddar = product(
            kcal: 403, protein: 23, sugar: 0.5, satFat: 21, sodium: 650, calcium: 710,
            nova: 3, name: "raw milk cheddar", ingredientsText: "raw milk, salt, cultures, enzymes",
            categories: ["dairies", "cheeses", "cheddar-cheese", "raw-milk-cheeses"])
        let raw = ScoringEngineV4.score(rawCheddar)!
        #expect(abs(rule("dairyForm", raw)!.fraction - 0.8) < 0.001)
        let gate = ScoringEngineV4.applyBaseCaps(base: 100, product: rawCheddar, rs: rs)
        #expect(!gate.fired.contains { $0.id == "rawMilkCap" })
    }

    /// Raw fluid milk keeps the cap; raw fermented milk now takes it too.
    @Test func rawCapScope() {
        let rawKefir = product(
            kcal: 60, protein: 3.5, sugar: 4.9, satFat: 2.0, sodium: 50, calcium: 125,
            name: "raw milk kefir", ingredientsText: "raw milk, kefir cultures",
            categories: ["dairies", "kefir", "raw-milks"])
        let gate = ScoringEngineV4.applyBaseCaps(base: 100, product: rawKefir, rs: rs)
        #expect(gate.fired.contains { $0.id == "rawMilkCap" })
    }

    // MARK: S13 reference prior

    @Test func s13DairyPriorAndLifts() {
        let plain = ScoringEngineV4.score(product(potassium: nil, name: "milk"))!
        let s13 = rule("S13", plain)!
        #expect(s13.hadData, "the reference prior is evidence of the food's identity")
        #expect(abs(s13.fraction - 0.70) < 0.001, "no declared lifts on a bare panel; got \(s13.fraction)")

        let fortified = ScoringEngineV4.score(product(
            calcium: 125, potassium: 150, vitaminD: 1.1, name: "vitamin d milk"))!
        let s13F = rule("S13", fortified)!
        #expect(s13F.fraction > 0.85, "declared vitamin D + potassium + calcium lift the prior")
    }

    // MARK: S14 — whitelist and neutral tokens

    @Test func dairyTokensReadAsRealFood() {
        #expect(IngredientIntegrity.isWholeFoodToken("certified organic grade a milk"))
        #expect(IngredientIntegrity.isWholeFoodToken("reduced fat ultra-filtered milk"))
        #expect(IngredientIntegrity.isWholeFoodToken("a2 milk"))
        #expect(IngredientIntegrity.isWholeFoodToken("grade a pasteurized skimmed milk and cream"))
        #expect(IngredientIntegrity.isWholeFoodToken("live active yogurt cultures"))
        #expect(IngredientIntegrity.isWholeFoodToken("live and active kefir cultures"))
        #expect(IngredientIntegrity.isWholeFoodToken("lactic acid bacteria"))
        #expect(IngredientIntegrity.isWholeFoodToken("lait"))
        #expect(IngredientIntegrity.isWholeFoodToken("mjölk"))
        // Curing agents dressed as cultures stay off, and refined fractions
        // never read as whole food whatever prefix they carry.
        #expect(!IngredientIntegrity.isWholeFoodToken("cultured dextrose"))
        #expect(!IngredientIntegrity.isWholeFoodToken("ultrafiltered milk protein isolate"))
    }

    @Test func periodSeparatedListsTokenize() {
        let toks = IngredientIntegrity.tokens(from: "reduced fat milk. vitamin a palmitate, vitamin d3")
        #expect(toks.count == 3)
        // Abbreviated culture names keep their periods.
        let cultures = IngredientIntegrity.tokens(from: "skim milk, l. bulgaricus, s. thermophilus")
        #expect(cultures.count == 3)
    }

    /// Salt / enzymes / rennet / lactase are neutral in a dairy list — a
    /// cheddar's four ingredients are all cheesemaking, not a 50 % real-food
    /// ratio.
    @Test func neutralTokensOnDairy() {
        let cheddar = ScoringEngineV4.score(product(
            kcal: 403, protein: 23, sugar: 0.5, satFat: 21, sodium: 650, calcium: 710,
            nova: 3, name: "cheddar", ingredientsText: "cultured pasteurized milk, salt, enzymes",
            categories: ["dairies", "cheeses", "cheddar-cheese"]))!
        #expect(abs(rule("S14", cheddar)!.fraction - 1.0) < 0.001)
    }

    // MARK: Engine bugs surfaced by the audit

    /// D12 — OFF's junk `low-sugars` nutrition tag must not trip the
    /// free-sugar ceiling (a 0 g-sugar grated parmesan was capped at 34).
    @Test func lowSugarsTagIsNotACaloricSweetener() {
        let parm = product(
            kcal: 400, protein: 40, sugar: 0, satFat: 20, sodium: 1600, calcium: 1100,
            nova: 3, name: "grated parmesan",
            ingredientsText: "parmesan cheese (pasteurized part-skim milk, cheese culture, salt, enzymes), cellulose powder, potassium sorbate",
            categories: ["dairies", "cheeses", "parmigiano-reggiano", "low-sugars", "no-added-sugar"])
        let gate = ScoringEngineV4.applyBaseCaps(base: 100, product: parm, rs: rs)
        #expect(!gate.fired.contains { $0.id == "freeSugarCeiling" })
        // The very-high-sodium cap is the one that should fire.
        #expect(gate.fired.contains { $0.id == "dairySodiumCap" })
    }

    /// D13 — annatto / natamycin / cellulose / gelatin / modified starch are
    /// soft-tier; GRAS acidulants are exempt.
    @Test func benignAdditiveTiers() {
        #expect(AdditiveCatalog.scoringTier(code: "e160b", base: .mild) == .soft)
        #expect(AdditiveCatalog.scoringTier(code: "e235", base: .unclassified) == .soft)
        #expect(AdditiveCatalog.scoringTier(code: "e460", base: .unclassified) == .soft)
        #expect(AdditiveCatalog.scoringTier(code: "e1442", base: .unclassified) == .soft)
        #expect(AdditiveCatalog.scoringTier(code: "e330", base: .mild) == .exempt)
        // Emulsifying salts and carrageenan keep their tiers.
        #expect(AdditiveCatalog.scoringTier(code: "e339", base: .moderate) == .moderate)
        #expect(AdditiveCatalog.scoringTier(code: "e407", base: .moderate) == .moderate)
    }
}
