import Testing
import Foundation
@testable import Sage

/// V5.4.0 — dedicated `bread` profile.
/// Bread used to ride the shared `breads` grains profile: a binary keyword
/// whole-grain rule (2 % rye flour in a white sourdough earned the full
/// credit), a generic S12 that spent 60 % of its weight on axes bread can't
/// earn, OFF's noisy NOVA tag as the processing signal, no saturated-fat rule
/// (brioche outscored plain sourdough), and a "real food" whitelist that
/// accepted refined "wheat flour" but not "whole wheat flour". The shipped
/// shelf compressed into 50–75 with whole-kernel rye tied with white
/// sourdough. Covers: routing, graded whole-grain share (position, declared
/// %, sub-lists, name claims, fiber cross-check), evidence-based processing,
/// S12 grain variant, bread sodium anchors + plausibility, S14 fixes,
/// fortificant-exempt additives, and the calibration ladder.
struct BreadScoringV54Tests {

    private let rs = RulesetV4.bundled

    private func bread(
        name: String = "Bread",
        ing: String? = "whole wheat flour, water, salt, yeast",
        kcal: Double? = 250, prot: Double? = 10, fib: Double? = 6.5, sug: Double? = 2,
        addSug: Double? = nil, na: Double? = 450, sat: Double? = 0.4, nova: Int = 3,
        additives: [ProductAdditive] = [],
        categories: [String]? = ["breads"], labels: [String]? = nil
    ) -> Product {
        Product(
            id: name, name: name, brand: "B", size: "", glyph: "🍞",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sug, sodium_mg: na, satFat_g: sat,
                                 fiber_g: fib, protein_g: prot, calcium_mg: nil,
                                 kcal: kcal, fvn: nil, addedSugar_g: addSug),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ing, imageURL: nil,
            labels: labels, packagingMaterials: nil, origins: nil,
            ingredientShares: nil, categories: categories
        )
    }

    private func add(_ code: String, _ tier: AdditiveTier = .mild) -> ProductAdditive {
        ProductAdditive(name: code, risk: .low, code: code, tier: tier)
    }

    private func rule(_ id: String, _ p: Product) -> V4RuleResult? {
        ScoringEngineV4.score(p, ruleset: rs)?.rules.first { $0.rule == id }
    }
    private func score(_ p: Product) -> Int { ScoringEngineV4.score(p, ruleset: rs)!.base }
    private var cfg: RulesetV4.BreadConfig { rs.bread! }

    // MARK: Ruleset shape

    @Test func breadProfileExistsAndSumsTo100() throws {
        let profile = try #require(rs.profiles["bread"])
        #expect(profile.reduce(0) { $0 + $1.w } == 100)
        #expect(profile.first { $0.rule == "wholeGrain" }?.variant == "bread")
        #expect(profile.first { $0.rule == "S12" }?.variant == "grain")
        #expect(profile.first { $0.rule == "S2" }?.variant == "bread")
        #expect(profile.first { $0.rule == "S4" }?.variant == "bread")
        #expect(profile.contains { $0.rule == "S5" })
        #expect(!profile.contains { $0.rule == "S13" })
        #expect(rs.bread != nil)
        #expect(rs.s4ThresholdsByVariant?["bread"] != nil)
        #expect(rs.version >= "2026.08-v5.5.0")
    }

    @Test func grainStaplesStayOnGrainsProfile() {
        // Cereals / pasta / rice / oats keep the shared grains profile (formerly
        // `breads`, renamed so it can't be confused with `bread`), untouched.
        #expect(rs.router.contains { $0.match == "breakfast-cereals" && $0.profile == "grains" })
        #expect(rs.router.contains { $0.match == "pastas" && $0.profile == "grains" })
        #expect(rs.router.contains { $0.match == "rices" && $0.profile == "grains" })
        #expect(rs.profiles["grains"] != nil)
        #expect(rs.profiles["breads"] == nil)
    }

    // MARK: Routing

    @Test func breadTagsRouteToBread() {
        for tags in [["breads"], ["breads", "white-breads"], ["breads", "flatbreads", "pita-breads"],
                     ["breads", "bagels"], ["breads", "crispbreads"], ["breads", "tortillas"],
                     ["breads", "sourdough-breads"], ["breads", "rye-breads"]] {
            #expect(ScoringEngineV4.route(bread(categories: tags), ruleset: rs) == "bread", "\(tags)")
        }
        #expect(ScoringEngineV4.route(bread(categories: ["breakfast-cereals"]), ruleset: rs) == "grains")
    }

    // MARK: Whole-grain share (graded)

    @Test func wholeFirstListEarnsFullShare() {
        let g = BreadScoring.wholeGrainShare(
            ingredientsText: "Organic whole kernel rye, water, organic whole rye flour, sea salt, yeast", cfg: cfg)
        #expect(g.hadGrainTokens)
        #expect(g.share > 0.99)
        #expect(rule("wholeGrain", bread(ing: "Whole wheat flour, water, salt"))!.fraction == 1.0)
    }

    @Test func refinedListEarnsZero() {
        #expect(rule("wholeGrain", bread(ing: "Wheat flour, water, salt, yeast", fib: 2.5))!.fraction == 0)
        #expect(rule("wholeGrain", bread(ing: "Enriched wheat flour (flour, niacin, reduced iron), water, sugar, salt", fib: 2.2))!.fraction == 0)
    }

    @Test func traceRyeFlourNoLongerEarnsWholeGrainCredit() {
        // Legacy rule: any "rye" substring anywhere → 1.0. Now: refined first,
        // a trailing rye flour is a sprinkle.
        let f = rule("wholeGrain", bread(ing: "Wheat Flour (Wheat Flour, Calcium Carbonate, Iron, Niacin, Thiamin), Water, Rye Flour, Salt, Sourdough culture", fib: 3.0))!.fraction
        #expect(f < 0.2, "\(f)")
    }

    @Test func brownWashedWheatBreadGetsPartialNotFull() {
        let f = rule("wholeGrain", bread(
            ing: "Enriched wheat flour (wheat flour, niacin, reduced iron), water, high fructose corn syrup, whole wheat flour, yeast, wheat gluten, soybean oil, salt, caramel color",
            fib: 2.5, nova: 4))!.fraction
        #expect(f > 0.1 && f < 0.4, "\(f)")
    }

    @Test func declaredPercentOverridesPosition() {
        // 2.5 % sprouted spelt inside a seed mix is not a whole-grain loaf.
        let f = rule("wholeGrain", bread(
            ing: "Wheat Flour (Wheat Flour, Calcium, Iron), Water, Mixed Seeds (Golden Linseeds, Sunflower Seeds (6%), Sprouted Whole Spelt (Wheat) (2.5%)), Salt, Fermented Wheat Flour",
            fib: 4.7))!.fraction
        #expect(f < 0.1, "\(f)")
        // Half-and-half declared: wheat flour 32 %, wholemeal 32 %.
        let h = BreadScoring.wholeGrainShare(
            ingredientsText: "Water, Wheat Flour (with added Calcium, Iron) (32%), Wholemeal Flour (Wheat) (32%), Yeast, Salt", cfg: cfg).share
        #expect(abs(h - 0.5) < 0.05, "\(h)")
    }

    @Test func subListsAndBareMillWordsAreRead() {
        // "Grains (whole kernel rye, whole grain rye flour)" — the evidence is inside the brackets.
        let g = BreadScoring.wholeGrainShare(
            ingredientsText: "Grains (whole kernel rye, whole grain rye flour), water, natural sourdough, salt, yeast", cfg: cfg)
        #expect(g.share > 0.99, "\(g.share)")
        // "rye (flour, bran)" → rye flour + rye bran (partial, not refined "flour").
        let r = BreadScoring.wholeGrainShare(
            ingredientsText: "rye (flour, bran), toasted seeds & grains (buckwheat, sesame seeds, kibbled rye) 17%, salt", cfg: cfg)
        #expect(r.share >= 0.5, "\(r.share)")
    }

    @Test func wheatGlutenAndMaltAreNotGrainBases() {
        // A refined loaf with vital wheat gluten and malted barley flour is still 0.
        let f = BreadScoring.wholeGrainShare(
            ingredientsText: "Wheat flour, water, wheat gluten, malted barley flour, salt, yeast", cfg: cfg).share
        #expect(f == 0)
    }

    @Test func nameClaimBacksWholeFirstListOnly() {
        // UK "wholemeal" + wholemeal first + dusting starch → near full.
        let uk = rule("wholeGrain", bread(name: "Wholemeal Pitta",
            ing: "Wholemeal Wheatflour, Water, Yeast, Vinegar, Salt, Preservative: E282, Wheat Starch", fib: 7.2))!.fraction
        #expect(uk >= 0.9, "\(uk)")
        // "100% Whole Wheat" on the front of a refined-first list changes nothing.
        let fake = rule("wholeGrain", bread(name: "100% Whole Wheat Bread",
            ing: "Enriched wheat flour, water, sugar, whole wheat flour, salt", fib: 2.5))!.fraction
        #expect(fake < 0.4, "\(fake)")
    }

    @Test func fiberCrossCheckCapsClaims() {
        // Whole-first list but 2.5 g fiber: the panel contradicts the claim.
        let f = rule("wholeGrain", bread(ing: "Whole wheat flour, water, salt, yeast", fib: 2.5))!.fraction
        #expect(f <= 0.35, "\(f)")
        let mid = rule("wholeGrain", bread(ing: "Whole wheat flour, water, salt, yeast", fib: 4.5))!.fraction
        #expect(mid <= 0.7 && mid > 0.35, "\(mid)")
        // Undeclared fiber: no cap, full credit on evidence.
        #expect(rule("wholeGrain", bread(ing: "Whole wheat flour, water, salt, yeast", fib: nil))!.fraction == 1.0)
    }

    @Test func noListFallsBackToTagPriorUnknownTier() {
        let claimed = rule("wholeGrain", bread(ing: nil, categories: ["breads", "whole-wheat-breads"]))!
        #expect(claimed.hadData == false)
        #expect(claimed.fraction == cfg.unknownWholeCredit)
        let plain = rule("wholeGrain", bread(ing: nil))!
        #expect(plain.hadData == false)
        #expect(plain.fraction == cfg.unknownCredit)
    }

    // MARK: S2 — evidence-based processing

    @Test func traditionalListIsNovaThreeCreditRegardlessOfTag() {
        // OFF tags the same sprouted loaf NOVA 3 on one barcode and 4 on the next.
        let ezekiel = "Organic sprouted wheat, filtered water, organic sprouted barley, organic sprouted millet, organic malted barley, organic sprouted lentils, organic sprouted soybeans, organic sprouted spelt, fresh yeast, organic wheat gluten, sea salt"
        let n3 = rule("S2", bread(ing: ezekiel, nova: 3))!.fraction
        let n4 = rule("S2", bread(ing: ezekiel, nova: 4))!.fraction
        #expect(n3 == n4)
        #expect(n3 == cfg.s2.traditional)
        // A baguette tagged NOVA 1 is capped at the traditional credit.
        #expect(rule("S2", bread(ing: "Wheat flour, water, salt, yeast", nova: 1))!.fraction == cfg.s2.traditional)
    }

    @Test func markerFamiliesStepProcessingDown() {
        let one = rule("S2", bread(ing: "Wheat flour, water, salt, yeast, emulsifier: mono- and diglycerides of fatty acids", nova: 4))!.fraction
        let three = rule("S2", bread(ing: "Enriched wheat flour, water, high fructose corn syrup, soybean oil, salt, monoglycerides, DATEM, soy lecithin", nova: 4))!.fraction
        #expect(one < cfg.s2.traditional && one > three)
        #expect(three <= cfg.s2.markerCredits[2])
        // Same family via text and code counts once.
        let fams = BreadScoring.upfMarkerFamilies(
            bread(ing: "wheat flour, water, DATEM", additives: [add("e472e")]), cfg: cfg)
        #expect(fams.count == 1)
    }

    @Test func preservativesAndFortificantsAreNotMarkers() {
        // Calcium propionate, ascorbic acid, vinegar, cultured wheat flour and
        // UK flour fortification are group-3-compatible — not ultra-processing.
        let fams = BreadScoring.upfMarkerFamilies(bread(
            ing: "Wholemeal wheat flour, water, yeast, spirit vinegar, salt, preservative: calcium propionate, cultured wheat flour, flour treatment agent: ascorbic acid, calcium carbonate, iron, niacin, thiamin",
            additives: [add("e282"), add("e300"), add("e170")]), cfg: cfg)
        #expect(fams.isEmpty, "\(fams)")
    }

    @Test func noListFallsBackToNovaTag() {
        #expect(rule("S2", bread(ing: nil, nova: 3))!.fraction == cfg.s2.traditional)
        #expect(rule("S2", bread(ing: nil, nova: 4))!.fraction == cfg.s2.novaFourNoList)
        let unknown = rule("S2", bread(ing: nil, nova: 0))!
        #expect(unknown.hadData == false)
    }

    // MARK: S12 grain

    @Test func s12GrainIsFiberPlusProtein() {
        let ww = rule("S12", bread(prot: 10, fib: 7))!
        let white = rule("S12", bread(ing: "wheat flour, water, salt", prot: 9, fib: 2.5))!
        #expect(ww.fraction > 0.9)
        #expect(white.fraction < 0.4)
        #expect(ww.note?.hasPrefix("grain") == true)
        // Undeclared fiber → prior from whole-grain evidence, unknown-tier.
        let prior = rule("S12", bread(fib: nil))!
        #expect(prior.hadData == false)
        #expect(prior.fraction > rule("S12", bread(ing: "wheat flour, water, salt", fib: nil))!.fraction)
    }

    @Test func isolatedFiberOnRefinedBaseEarnsHalf() {
        let light = bread(ing: "Enriched wheat flour, water, wheat gluten, cellulose fiber, yeast, salt, sucralose", prot: 11, fib: 10, nova: 4)
        let whole = bread(ing: "Whole wheat flour, water, yeast, salt", prot: 11, fib: 10)
        #expect(rule("S12", light)!.fraction < rule("S12", whole)!.fraction - 0.25)
        // Oat fiber low in a whole-first list is not dampened.
        let daves = bread(ing: "Organic whole wheat, water, organic cane syrup, organic oat fiber, sea salt, yeast", prot: 11, fib: 9)
        #expect(rule("S12", daves)!.fraction > 0.9)
    }

    // MARK: S4 bread

    @Test func breadSodiumAnchorsRewardLowSaltLoaves() {
        #expect(rule("S4", bread(na: 200))!.fraction == 1.0)
        let typical = rule("S4", bread(na: 450))!.fraction
        let salty = rule("S4", bread(na: 700))!.fraction
        #expect(abs(typical - 0.6) < 0.01)
        #expect(abs(salty - 0.3) < 0.01)
    }

    @Test func implausibleSodiumOnSaltedLoafIsUnknownNotLow() {
        // OFF "salt 0.001 g" → 1 mg sodium on a loaf that lists salt.
        let r = rule("S4", bread(ing: "Wheat flour, water, salt, yeast", na: 1))!
        #expect(r.hadData == false)
        #expect(r.fraction == 0.30)
        // A genuinely unsalted corn tortilla keeps its full credit.
        let tortilla = rule("S4", bread(ing: "Corn masa flour, water, lime", na: 45))!
        #expect(tortilla.hadData && tortilla.fraction == 1.0)
    }

    // MARK: S14 generic fixes

    @Test func wholeGrainFloursAreRealFood() {
        #expect(IngredientIntegrity.isWholeFoodToken("whole wheat flour"))
        #expect(IngredientIntegrity.isWholeFoodToken("wholemeal wheat flour"))
        #expect(IngredientIntegrity.isWholeFoodToken("organic whole kernel rye"))
        #expect(IngredientIntegrity.isWholeFoodToken("unbleached enriched wheat flour"))
        #expect(IngredientIntegrity.isWholeFoodToken("stone ground whole wheat flour"))
        #expect(IngredientIntegrity.isWholeFoodToken("yeast"))
        #expect(IngredientIntegrity.isWholeFoodToken("sourdough culture"))
        #expect(!IngredientIntegrity.isWholeFoodToken("bleached wheat flour"))
        #expect(!IngredientIntegrity.isWholeFoodToken("salt"))
    }

    @Test func waterIsExcludedFromWholeFoodRatio() {
        let b = IngredientIntegrity.evaluate(ingredientsText: "whole wheat flour, water, salt")
        // whole wheat flour = real, salt = not; water dropped → 1/2, not 1/3.
        #expect(abs(b.wholeFoodRatio - 0.5) < 0.01)
        #expect(b.ingredientCount == 3)
    }

    @Test func juiceConcentrateIsNotAnIsolateProtein() {
        #expect(!IngredientIntegrity.hasIsolateProtein(ingredientsText: "whole wheat flour, water, raisin juice concentrate, salt"))
        #expect(IngredientIntegrity.hasIsolateProtein(ingredientsText: "water, whey protein concentrate, cocoa"))
        #expect(IngredientIntegrity.hasIsolateProtein(ingredientsText: "water, wheat protein isolate, oat fiber"))
    }

    @Test func trailingAllergenStatementsAreNotIngredients() {
        let toks = IngredientIntegrity.tokens(from: "Wheat flour, water, salt, malted wheat flour. ALLERGEN ADVICE: for allergens see ingredients in bold")
        #expect(toks.last == "malted wheat flour")
        #expect(IngredientIntegrity.tokens(from: "Wheat flour, water, sesame seeds. Contains: Wheat, Sesame").count == 3)
    }

    @Test func marketingProseIsNotAnIngredientList() {
        #expect(!IngredientIntegrity.looksLikeIngredientList(
            "Celebrate a slice of tradition. Whether it's stacked high with your favorite sandwich fixings or a timeless PB&J, our classic bread brings unmistakable softness to every bite. We are proud to support you."))
        // Punctuation-poor OCR lists and short single-ingredient statements stay lists.
        #expect(IngredientIntegrity.looksLikeIngredientList("Cocoa mass Sugar Cocoa butter Soy lecithin Vanilla Cocoa solids 70% minimum"))
        #expect(IngredientIntegrity.looksLikeIngredientList("pasteurised cows milk fermented with live kefir cultures"))
        #expect(IngredientIntegrity.looksLikeIngredientList("Whole grain wheat. bht added to preserve freshness."))
        #expect(IngredientIntegrity.looksLikeIngredientList("Eggs."))
    }

    @Test func enrichmentVitaminsAreExemptFromS1() {
        for code in ["e101", "e375", "e300", "e170"] {
            #expect(AdditiveCatalog.additive(for: "en:\(code)").tier == .exempt, "\(code)")
        }
        // Real additives keep their knowledge-base tier.
        #expect(AdditiveCatalog.additive(for: "en:e471").tier != .exempt)
        #expect(AdditiveCatalog.additive(for: "en:e322").tier != .exempt)
    }

    // MARK: Overview plumbing

    @Test func overviewUsesFiberAndProteinTopicForBread() throws {
        let ctx = try #require(ScoringEngineV4.overviewContext(
            for: bread(), profile: MockData.user, ruleset: rs))
        #expect(ctx.rules.first { $0.rule == "S12" }?.topic == "fiber and protein")
        #expect(ctx.rules.first { $0.rule == "wholeGrain" }?.topic == "whole grain content")
        #expect(!ctx.rules.contains { $0.rule == "S13" })
    }

    // MARK: Calibration ladder

    private var wholeRye: Product {
        bread(name: "Whole Rye Bread", ing: "Organic whole kernel rye, water, organic whole rye flour, sea salt, yeast",
              kcal: 190, prot: 5, fib: 8.5, sug: 1.5, na: 400, sat: 0.2, nova: 3, categories: ["breads", "rye-breads"])
    }
    private var wwSourdough: Product {
        bread(name: "Whole Wheat Sourdough", ing: "Whole wheat flour, water, salt",
              kcal: 240, prot: 10, fib: 6.5, sug: 1.5, na: 450, sat: 0.3, nova: 3)
    }
    private var ezekiel: Product {
        bread(name: "Sprouted Grain Bread",
              ing: "Organic sprouted wheat, filtered water, organic sprouted barley, organic sprouted millet, organic malted barley, organic sprouted lentils, organic sprouted soybeans, organic sprouted spelt, fresh yeast, organic wheat gluten, sea salt",
              kcal: 235, prot: 12, fib: 8.8, sug: 0, addSug: 0, na: 220, sat: 0.2, nova: 4)
    }
    private var davesKiller: Product {
        bread(name: "21 Whole Grains and Seeds",
              ing: "Organic whole wheat (organic whole wheat flour, organic cracked whole wheat), water, organic dried cane syrup, organic wheat gluten, organic 21 whole grains and seeds mix (organic whole flax seeds, organic sunflower seeds, organic rolled oats, organic pumpkin seeds, organic sesame seeds, organic barley flakes, organic millet, organic rye flakes, organic quinoa, organic amaranth, organic spelt), organic oat fiber, organic molasses, organic vinegar, sea salt, yeast, organic cultured wheat flour",
              kcal: 260, prot: 11, fib: 9, sug: 11, addSug: 11, na: 380, sat: 0.5, nova: 4)
    }
    private var naturesOwnWW: Product {
        bread(name: "100% Whole Wheat Bread",
              ing: "Whole wheat flour, water, yeast, brown sugar, wheat gluten, contains 2% or less of: salt, soybean oil, calcium propionate, DATEM, monoglycerides, cultured wheat flour, vinegar, citric acid, soy lecithin",
              kcal: 240, prot: 10.7, fib: 7.1, sug: 7.1, addSug: 5.4, na: 460, sat: 0.4, nova: 4,
              additives: [add("e282"), add("e472e"), add("e471"), add("e330"), add("e322")])
    }
    private var whiteSourdough: Product {
        bread(name: "Sourdough Bread", ing: "Wheat flour, water, salt, sourdough culture",
              kcal: 260, prot: 9, fib: 2.5, sug: 1, na: 500, sat: 0.3, nova: 3)
    }
    private var baguette: Product {
        bread(name: "Baguette", ing: "Wheat flour, water, salt, yeast",
              kcal: 270, prot: 9, fib: 2.5, sug: 2, na: 600, sat: 0.3, nova: 3, categories: ["breads", "baguettes"])
    }
    private var brioche: Product {
        bread(name: "Brioche", ing: "Wheat flour, eggs, butter, sugar, milk, yeast, salt",
              kcal: 350, prot: 8, fib: 1.5, sug: 10, na: 350, sat: 6, nova: 3)
    }
    private var wonder: Product {
        bread(name: "Classic White Bread",
              ing: "Enriched wheat flour (flour, barley malt, ferrous sulfate, niacin, thiamin mononitrate, riboflavin, folic acid), water, high fructose corn syrup, yeast, soybean oil, contains 2% or less of: salt, wheat gluten, calcium propionate (preservative), monoglycerides, DATEM, calcium sulfate, soy lecithin, ascorbic acid, enzymes",
              kcal: 270, prot: 8, fib: 2.2, sug: 6, addSug: 5, na: 480, sat: 0.5, nova: 4,
              additives: [add("e282"), add("e471"), add("e472e"), add("e516"), add("e322"), add("e300", .exempt)])
    }
    private var hawaiianRolls: Product {
        bread(name: "Original Hawaiian Sweet Rolls",
              ing: "Enriched flour (wheat flour, malted barley flour, niacin, reduced iron), water, sugar, butter, eggs, potato flour, yeast, salt, milk, soy lecithin, natural flavor, calcium propionate, monoglycerides, sodium stearoyl lactylate",
              kcal: 320, prot: 7, fib: 1.5, sug: 13, addSug: 12, na: 320, sat: 1.5, nova: 4,
              additives: [add("e322"), add("e282"), add("e471"), add("e481")])
    }
    private var flourTortilla: Product {
        bread(name: "Flour Tortillas",
              ing: "Enriched bleached wheat flour, water, vegetable shortening (interesterified and hydrogenated soybean oils), salt, sugar, leavening (sodium bicarbonate, sodium acid pyrophosphate), distilled monoglycerides, enzymes, fumaric acid, calcium propionate and sorbic acid (preservatives), wheat starch, dough conditioner (sodium metabisulfite)",
              kcal: 300, prot: 8, fib: 2, sug: 2, addSug: 1, na: 700, sat: 1.5, nova: 4,
              additives: [add("e500"), add("e450"), add("e471"), add("e297"), add("e282"), add("e200"), add("e223")],
              categories: ["breads", "tortillas"])
    }
    private var cornTortilla: Product {
        bread(name: "Corn Tortillas", ing: "Corn masa flour, water, lime",
              kcal: 220, prot: 6, fib: 6, sug: 1, na: 45, sat: 0.3, nova: 3, categories: ["breads", "tortillas"])
    }
    private var ketoBread: Product {
        bread(name: "Zero Net Carb Bread",
              ing: "Water, wheat protein isolate, modified wheat starch, oat fiber, wheat gluten, yeast, vegetable fiber, salt, soybean oil, calcium propionate, sorbic acid, natural flavor, sucralose",
              kcal: 180, prot: 20, fib: 15, sug: 0, na: 420, sat: 0.3, nova: 4,
              additives: [add("e282"), add("e200"), add("e955")])
    }
    private var glutenFree: Product {
        bread(name: "Gluten Free White Bread",
              ing: "Water, tapioca starch, brown rice flour, potato starch, canola oil, egg whites, sugar, yeast, psyllium husk, salt, xanthan gum, cultured dextrose, mono and diglycerides, calcium propionate",
              kcal: 250, prot: 3, fib: 2, sug: 4, addSug: 3, na: 400, sat: 0.5, nova: 4,
              additives: [add("e415"), add("e471"), add("e282")])
    }

    @Test func calibrationBands() {
        // Whole-grain / sprouted traditional loaves are Excellent.
        for p in [wholeRye, wwSourdough, ezekiel] { #expect(score(p) >= 85, "\(p.name)") }
        // Clean refined loaves sit in the low 60s (Good): refined, but honest.
        for p in [whiteSourdough, baguette] { let s = score(p); #expect(s >= 58 && s <= 66, "\(p.name) \(s)") }
        // Industrial whole wheat (additives, sugar, seed oil) lands Good, above white sourdough-ish.
        let no = score(naturesOwnWW); #expect(no >= 60 && no <= 70, "\(no)")
        // Sweet / fatty / ultra-processed: OK or Bad.
        #expect(score(brioche) < score(whiteSourdough))
        #expect(score(brioche) >= 50 && score(brioche) < 62)
        for p in [wonder, hawaiianRolls, flourTortilla, ketoBread] { let s = score(p); #expect(s < 45, "\(p.name) \(s)") }
        #expect(score(glutenFree) < 55)
        #expect(score(cornTortilla) >= 85)
    }

    @Test func calibrationLadder() {
        #expect(score(ezekiel) > score(wholeRye) - 8)
        #expect(score(wholeRye) > score(davesKiller) - 2)        // near-tie allowed, rye ≥ sweeter Dave's
        #expect(score(davesKiller) > score(naturesOwnWW) + 10)
        #expect(score(naturesOwnWW) > score(wonder) + 20)
        #expect(score(wwSourdough) > score(whiteSourdough) + 15)
        #expect(score(whiteSourdough) > score(hawaiianRolls) + 15)
        #expect(score(cornTortilla) > score(flourTortilla) + 40)
    }

    @Test func dataGapsNeverOutscoreEvidence() {
        // A bread with no list and no NOVA scores below the same loaf with a clean list.
        let blind = bread(name: "Bread", ing: nil, nova: 0)
        #expect(score(blind) < score(wwSourdough))
        #expect(ScoringEngineV4.score(blind, ruleset: rs)!.confidence < 1.0)
    }
}
