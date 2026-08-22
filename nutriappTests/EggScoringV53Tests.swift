import Testing
import Foundation
@testable import Sage

/// V5.3.0 — dedicated `eggs` profile.
/// Eggs used to ride `whole_foods`, whose S12 is 80% fiber + FVN — axes an egg
/// can never earn — so the engine told users one of the most nutrient-dense
/// whole foods had "limited nutritional quality", and real OFF eggs scored
/// 47–76 depending on whether the label happened to carry NOVA, an ingredient
/// list, or a trailing period. Covers: routing (tag + guard + evidence gate),
/// NOVA inference, powder reconstitution, S12/S13 egg variants, enrichment
/// lift, S14 token/whitelist fixes, and the calibration ladder.
struct EggScoringV53Tests {

    private let rs = RulesetV4.bundled

    private func egg(
        kcal: Double? = 143, protein: Double? = 12.6, sugar: Double? = 0.4,
        satFat: Double? = 3.1, sodium: Double? = 142, calcium: Double? = nil,
        iron: Double? = nil, potassium: Double? = nil,
        vitD: Double? = nil, b12: Double? = nil, choline: Double? = nil,
        selenium: Double? = nil, omega3: Double? = nil,
        nova: Int = 1,
        name: String = "eggs",
        ingredientsText: String? = "eggs",
        additives: [ProductAdditive] = [],
        categories: [String]? = ["farming-products", "eggs", "chicken-eggs"],
        labels: [String]? = nil
    ) -> Product {
        Product(
            id: name, name: name, brand: "B", size: "", glyph: "🥚",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                 fiber_g: nil, protein_g: protein, calcium_mg: calcium,
                                 kcal: kcal, fvn: nil, addedSugar_g: nil,
                                 iron_mg: iron, potassium_mg: potassium,
                                 vitaminD_ug: vitD, vitaminB12_ug: b12, choline_mg: choline,
                                 selenium_ug: selenium, omega3_g: omega3),
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

    private func score(_ p: Product) -> Int { ScoringEngineV4.score(p, ruleset: rs)!.base }

    // MARK: Ruleset shape

    @Test func eggsProfileExistsAndSumsTo100() throws {
        let profile = try #require(rs.profiles["eggs"])
        #expect(profile.reduce(0) { $0 + $1.w } == 100)
        #expect(profile.first { $0.rule == "S12" }?.variant == "egg")
        #expect(profile.first { $0.rule == "S13" }?.variant == "egg")
        #expect(rs.eggs != nil)
        #expect(rs.router.contains { $0.match == "eggs" && $0.profile == "eggs" })
        #expect(!rs.router.contains { $0.match == "eggs" && $0.profile == "whole_foods" })
    }

    // MARK: Routing

    @Test func shellEggsRouteToEggs() {
        #expect(ScoringEngineV4.route(egg(), ruleset: rs) == "eggs")
        #expect(ScoringEngineV4.route(egg(ingredientsText: nil), ruleset: rs) == "eggs")
        #expect(ScoringEngineV4.route(egg(nova: 0, ingredientsText: nil), ruleset: rs) == "eggs")
    }

    @Test func processedEggProductsStayOnEggsProfile() {
        // The whole_foods NOVA gate used to push these to `general`, where S12
        // is equally dead for eggs. The eggs profile judges them itself.
        let hb = egg(kcal: 155, sugar: 1.1, satFat: 3.3, sodium: 180, nova: 3,
                     name: "Hard boiled eggs",
                     ingredientsText: "eggs, water, citric acid, sodium benzoate",
                     categories: ["eggs", "hard-boiled-egg"])
        #expect(ScoringEngineV4.route(hb, ruleset: rs) == "eggs")
        let whites = egg(kcal: 48, protein: 10, sugar: 1, satFat: 0, sodium: 190, nova: 4,
                         name: "Egg substitute",
                         ingredientsText: "egg whites, natural flavor, color (beta carotene), xanthan gum, guar gum",
                         categories: ["eggs", "egg-white"])
        #expect(ScoringEngineV4.route(whites, ruleset: rs) == "eggs")
    }

    @Test func scotchEggAndEggSaladFallThroughTheGuard() {
        let scotch = egg(kcal: 240, protein: 12, sugar: 1.5, satFat: 5, sodium: 650, nova: 4,
                         name: "Scotch eggs",
                         ingredientsText: "pork (42%), eggs (30%), breadcrumbs (wheat flour, salt), rapeseed oil, salt",
                         categories: ["eggs", "scotch-eggs"])
        #expect(ScoringEngineV4.route(scotch, ruleset: rs) != "eggs",
                "first ingredient is pork — not egg-dominant")
        let salad = egg(kcal: 220, protein: 7, sugar: 1.5, satFat: 3, sodium: 400, nova: 4,
                        name: "Egg salad",
                        ingredientsText: "hard boiled eggs, mayonnaise (soybean oil, egg yolks), celery, salt",
                        categories: ["eggs", "meals"])
        #expect(ScoringEngineV4.route(salad, ruleset: rs) != "eggs",
                "protein below a plain egg's floor — a dish, not an egg")
        let pastaLike = egg(kcal: 165, protein: 6.5, sugar: 1, satFat: 0.7, sodium: 12,
                            name: "Egg lasagne sheets",
                            ingredientsText: "durum wheat semolina, pasteurised whole egg 19%",
                            categories: ["eggs", "chicken-eggs"])
        #expect(ScoringEngineV4.route(pastaLike, ruleset: rs) != "eggs")
    }

    @Test func noIngredientListUsesCompositionEnvelope() {
        // Plain-egg composition without a list → eggs; a dish-like panel → not.
        #expect(ScoringEngineV4.route(egg(ingredientsText: nil), ruleset: rs) == "eggs")
        let rich = egg(kcal: 300, protein: 12, sugar: 2, satFat: 9, sodium: 500,
                       ingredientsText: nil, categories: ["eggs", "scotch-eggs"])
        #expect(ScoringEngineV4.route(rich, ruleset: rs) != "eggs")
    }

    @Test func untaggedEggProductRoutesByEvidence() {
        // OFF US imports often carry no categories at all. Name + first
        // ingredient + envelope is enough; either alone is not.
        let liquid = egg(kcal: 54, protein: 10.9, sugar: 0, satFat: 0, sodium: 185, nova: 4,
                         name: "Liquid Eggs",
                         ingredientsText: "egg whites (99%), natural flavor, xanthan gum, guar gum",
                         categories: nil)
        #expect(ScoringEngineV4.route(liquid, ruleset: rs) == "eggs")
        let noodles = egg(kcal: 350, protein: 13, sugar: 2, satFat: 1, sodium: 20, nova: 3,
                          name: "Egg noodles", ingredientsText: "durum wheat semolina, eggs",
                          categories: nil)
        #expect(ScoringEngineV4.route(noodles, ruleset: rs) != "eggs")
        let eggnog = egg(kcal: 135, protein: 4, sugar: 14, satFat: 3, sodium: 50, nova: 4,
                         name: "Eggnog", ingredientsText: "milk, sugar, egg yolks, cream",
                         categories: nil)
        #expect(ScoringEngineV4.route(eggnog, ruleset: rs) != "eggs",
                "\"eggnog\" is not the word egg, and milk leads the list")
    }

    // MARK: Normalization

    @Test func plainEggListIsNova1RegardlessOfTag() throws {
        // "pasteurized whole eggs" is NOVA 1 by NOVA's own definition; OFF
        // sometimes tags liquid eggs 3. Evidence outranks the tag.
        let liquid = egg(nova: 3, name: "liquid whole eggs",
                         ingredientsText: "pasteurized whole eggs", categories: ["eggs"])
        let r = try #require(ScoringEngineV4.score(liquid, ruleset: rs))
        #expect(abs(rule("S2", r)!.fraction - 1.0) < 0.001)
        #expect(abs(rule("S1", r)!.fraction - 1.0) < 0.001)
        #expect(r.base == score(egg()), "100% liquid egg scores like a shell egg")
    }

    @Test func unknownNovaPlainEggIsNova1ButAdditivesAreNot() throws {
        let unknown = egg(nova: 0, ingredientsText: nil)
        let r = try #require(ScoringEngineV4.score(unknown, ruleset: rs))
        #expect(abs(rule("S2", r)!.fraction - 1.0) < 0.001)
        #expect(r.base == score(egg()), "missing NOVA must not cost a plain egg 50 points")

        let brined = egg(nova: 0, name: "Hard boiled eggs",
                         ingredientsText: "eggs, water, citric acid, sodium benzoate")
        let rb = try #require(ScoringEngineV4.score(brined, ruleset: rs))
        #expect(rule("S2", rb)!.fraction < 1.0, "a preserved list never gets NOVA 1 by inference")
    }

    @Test func eggPowderIsJudgedAsReconstituted() throws {
        let powder = egg(kcal: 594, protein: 47, sugar: 2, satFat: 12.7, sodium: 523,
                         name: "Whole egg powder", ingredientsText: "whole eggs",
                         categories: ["eggs", "egg-powder"])
        #expect(ScoringEngineV4.route(powder, ruleset: rs) == "eggs")
        let r = try #require(ScoringEngineV4.score(powder, ruleset: rs))
        #expect(rule("S5", r)!.fraction > 0.95, "12.7 g sat fat /100 g powder is ~3.2 g as prepared")
        #expect(r.base >= score(egg()) - 3)
    }

    // MARK: S12 / S13 egg variants

    @Test func s12EggIsProteinOnlyAndWholeEggEarnsFullCredit() throws {
        let r = try #require(ScoringEngineV4.score(egg(), ruleset: rs))
        let s12 = rule("S12", r)!
        #expect(abs(s12.fraction - 1.0) < 0.001)
        #expect(s12.note?.hasPrefix("egg") == true)
        let whites = egg(kcal: 52, protein: 10.9, sugar: 0.7, satFat: 0, sodium: 166,
                         name: "egg whites", ingredientsText: "egg whites",
                         categories: ["eggs", "egg-white"])
        let rw = try #require(ScoringEngineV4.score(whites, ruleset: rs))
        #expect(rule("S12", rw)!.fraction < 1.0 && rule("S12", rw)!.fraction > 0.85)
    }

    @Test func s13EggPriorByFormAndEnrichmentLift() throws {
        let whole = try #require(ScoringEngineV4.score(egg(), ruleset: rs))
        let s13Whole = rule("S13", whole)!
        #expect(abs(s13Whole.fraction - rs.eggs!.s13Prior.whole) < 0.001)
        #expect(s13Whole.hadData, "a form prior is evidence about the food, not a missing-data state")

        let whites = egg(kcal: 52, protein: 10.9, sugar: 0.7, satFat: 0, sodium: 166,
                         name: "egg whites", ingredientsText: "egg whites",
                         categories: ["eggs", "egg-white"])
        let rw = try #require(ScoringEngineV4.score(whites, ruleset: rs))
        #expect(abs(rule("S13", rw)!.fraction - rs.eggs!.s13Prior.whites) < 0.001)

        // Whites detected from composition alone (no tag, no word): no yolk fat.
        let whitesByPanel = egg(kcal: 52, protein: 10.9, sugar: 0.7, satFat: 0, sodium: 166,
                                ingredientsText: nil, categories: ["eggs"])
        #expect(ScoringEngineV4.eggForm(whitesByPanel, rs: rs) == .whites)

        // An ordinary declared panel (vitamin D 2 µg, choline 294, selenium 31)
        // is the reference egg — no lift, so label completeness can't move the score.
        let ordinary = egg(calcium: 56, iron: 1.75, potassium: 138, vitD: 2.0, b12: 0.89,
                           choline: 294, selenium: 30.7)
        #expect(score(ordinary) == score(egg()))

        // Enrichment at/above ~2× reference lifts, capped.
        let enriched = egg(vitD: 12, b12: 2.0, omega3: 0.3, name: "enriched eggs")
        let re = try #require(ScoringEngineV4.score(enriched, ruleset: rs))
        let lift = rule("S13", re)!.fraction - s13Whole.fraction
        #expect(lift > 0.001)
        #expect(lift <= rs.eggs!.s13EnrichmentMaxLift + 0.001)
        #expect(score(enriched) > score(egg()))
        #expect(score(enriched) <= 99, "enriched is better, not perfect")
    }

    @Test func undeclaredSugarOnPlainEggUsesStructuralPrior() throws {
        let r = try #require(ScoringEngineV4.score(egg(sugar: nil), ruleset: rs))
        let s3 = rule("S3", r)!
        #expect(!s3.hadData)
        #expect(abs(s3.fraction - rs.eggs!.s3UnknownCredit) < 0.001)
        #expect(score(egg(sugar: nil)) >= score(egg()) - 1)
    }

    // MARK: S14 — egg wording must not cost points

    @Test func eggWordingAndMarkupDoNotCostRealFoodPoints() throws {
        let plain = score(egg())
        for text in ["Eggs.", "Hen eggs", "free range eggs", "pasture raised eggs",
                     "Free Range Hard Boiled Egg", "whole eggs", "_Œufs_ frais",
                     "Oeufs de poules élevées en plein air", "Œufs de caille.",
                     "huevos frescos", "ovos", "uova fresche", "Eier"] {
            let p = egg(ingredientsText: text)
            let r = try #require(ScoringEngineV4.score(p, ruleset: rs))
            #expect(abs(rule("S14", r)!.fraction - 1.0) < 0.001, "S14 for \(text)")
            #expect(r.base >= plain - 1, "\(text) scored \(r.base) vs \(plain)")
        }
    }

    @Test func trailingPeriodTokenFixIsGeneric() {
        #expect(IngredientIntegrity.tokens(from: "Wheat flour, sugar, salt.") == ["wheat flour", "sugar", "salt"])
        #expect(IngredientIntegrity.tokens(from: "_Eggs_, Water, Salt.") == ["eggs", "water", "salt"])
    }

    // MARK: Calibration ladder

    @Test func calibrationLadder() throws {
        let whole = score(egg())
        let frenchFreeRange = score(egg(kcal: 140, protein: 12.7, sugar: 0.3, satFat: 2.6, sodium: 124,
                                        ingredientsText: "Oeufs de poules élevées en plein air",
                                        categories: ["eggs", "chicken-eggs", "free-range-chicken-eggs"]))
        let organic = score(egg(name: "organic eggs", ingredientsText: "organic eggs", labels: ["organic"]))
        let pasture = score(egg(name: "Pasture Raised Eggs", ingredientsText: "pasture raised eggs"))
        let enriched = score(egg(vitD: 12, b12: 2.0, name: "enriched eggs"))
        let duck = score(egg(kcal: 185, protein: 12.8, sugar: 0.9, satFat: 3.7, sodium: 146,
                             name: "duck eggs", ingredientsText: "duck eggs", categories: ["eggs", "duck-eggs"]))
        let hardBoiledClean = score(egg(kcal: 155, sugar: 1.1, satFat: 3.3, sodium: 124,
                                        name: "Hard boiled eggs", ingredientsText: "eggs",
                                        categories: ["eggs", "hard-boiled-egg"]))
        let liquidWhole = score(egg(kcal: 143, protein: 12, name: "liquid whole eggs",
                                    ingredientsText: "whole eggs", categories: ["eggs"]))
        let whites = score(egg(kcal: 52, protein: 10.9, sugar: 0.7, satFat: 0, sodium: 166,
                               name: "100% liquid egg whites", ingredientsText: "egg whites",
                               categories: ["eggs", "egg-white"]))
        let yolk = score(egg(kcal: 322, protein: 15.9, sugar: 0.6, satFat: 9.6, sodium: 48,
                             name: "egg yolks", ingredientsText: "egg yolks", categories: ["eggs", "egg-yolk"]))
        let hardBoiledPreserved = score(egg(kcal: 155, sugar: 1.1, satFat: 3.3, sodium: 180, nova: 3,
                                            name: "Hard boiled eggs",
                                            ingredientsText: "eggs, water, citric acid, sodium benzoate",
                                            categories: ["eggs", "hard-boiled-egg"]))
        // Built the way the app builds it: the detector tags sodium benzoate.
        let pickled = score(egg(kcal: 140, protein: 11, sugar: 3.0, satFat: 3.0, sodium: 600, nova: 3,
                                name: "Pickled eggs",
                                ingredientsText: "eggs, water, vinegar, salt, sugar, spices, sodium benzoate",
                                additives: [ProductAdditive(name: "Sodium benzoate", risk: .moderate, code: "e211")],
                                categories: ["eggs", "boiled-eggs"]))
        let formulatedWhites = score(egg(kcal: 48, protein: 10, sugar: 1, satFat: 0, sodium: 190, nova: 4,
                                         name: "Egg substitute, original",
                                         ingredientsText: "egg whites, natural flavor, color (beta carotene), salt, onion powder, xanthan gum, guar gum, maltodextrin, calcium sulfate, vitamin e, zinc sulfate, vitamin b12, riboflavin, folic acid, vitamin d3",
                                         categories: ["eggs", "egg-white"]))

        // Housing / certification claims are not nutrients: same egg, same score.
        #expect(organic == whole)
        #expect(pasture == whole)
        #expect(abs(frenchFreeRange - whole) <= 1)
        // Form: shell = hard-boiled = 100% liquid; whites below whole; yolk below whole.
        #expect(hardBoiledClean == whole)
        #expect(abs(liquidWhole - whole) <= 2)
        #expect(whites < whole && whites >= whole - 9)
        #expect(yolk < whole)
        #expect(abs(duck - whole) <= 2)
        // Bands: plain eggs Excellent and near the ceiling but not at it.
        #expect(whole >= 94 && whole <= 98, "whole egg \(whole)")
        #expect(enriched > whole && enriched <= 99)
        #expect(whites >= rs.bands.excellent)
        // Processing ladder.
        #expect(hardBoiledPreserved < hardBoiledClean - 10)
        #expect(hardBoiledPreserved >= rs.bands.excellent)
        #expect(pickled < hardBoiledPreserved)
        // V5.4: vinegar is real food and water leaves the S14 ratio, which puts
        // pickled eggs exactly on the Excellent boundary (74 → 75).
        #expect(pickled >= rs.bands.good && pickled <= rs.bands.excellent)
        #expect(formulatedWhites < pickled)
        #expect(formulatedWhites >= rs.bands.good && formulatedWhites < 70, "formulated whites \(formulatedWhites)")
    }

    // MARK: Top Rated shelf

    @Test func eggsHaveTheirOwnShelfAndEggPastaStaysOnPasta() {
        #expect(SageCategory.shelf(for: egg(categories: ["eggs-and-their-products", "eggs", "chicken-eggs"])) == .eggs)
        #expect(SageCategory.shelf(for: egg(categories: ["eggs", "egg-white"])) == .eggs)
        #expect(SageCategory.eggs.anchorTag(for: egg(categories: ["eggs", "chicken-eggs", "free-range-chicken-eggs"])) == "free-range-chicken-eggs")
        // OFF cross-tags egg pasta under en:eggs; pasta is the more specific shelf.
        #expect(SageCategory.shelf(for: egg(categories: ["pastas", "egg-pastas", "eggs", "chicken-eggs"])) == .pasta)
        #expect(SageCategory.topRatedBrowse.contains(.eggs))
        #expect(SageCategory.eggs.topRatedHeroAsset == "eggs-tr")
    }

    // MARK: Overview plumbing

    @Test func overviewNeverClaimsFiberForEggsAndNeverCallsThemLimited() throws {
        let ctx = try #require(ScoringEngineV4.overviewContext(for: egg(), profile: MockData.user, ruleset: rs))
        #expect(ctx.rules.first { $0.rule == "S12" }?.topic == "protein")
        #expect(!ctx.rules.contains { $0.topic.lowercased().contains("fiber") })
        #expect(!ctx.topNegative.contains { $0.topic == "protein" || $0.topic == "micronutrients" })
        let factors = ScoringEngineV4.signedFactors(egg(), profile: MockData.user, ruleset: rs)
        #expect(!factors.contains { $0.contains("limited nutritional quality") })
    }
}
