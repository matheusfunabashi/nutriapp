import Testing
import Foundation
@testable import Sage

/// V5.5.0 — dedicated `protein_bars` profile.
/// Protein bars used to ride `snacks` or `general` depending on whether OFF
/// happened to tag `snacks` (OFF files `protein-bars` under
/// *bodybuilding-supplements*), so the same bar scored 54–68 across barcodes;
/// protein carried 4 % of the score and the protein sources that make a
/// protein bar were docked four times (S1 text signal, S2 NOVA-4, S12 isolate
/// discount, S14 isolate score); a 4 g-protein date bar outscored every real
/// protein bar because FVN ≈ 100 laundered 40 g/100 g of sugar. Covers:
/// routing (tag + guard + evidence gate), serving parsing, S12 protein
/// delivery (amount / source quality / fiber), S2 marker families, S3 capped
/// fruit-sugar discount, S6 tiers + polyol load, S14 neutral protein sources
/// and plural-nut whitelist, S1 exemptions, S4 plausibility, S15 palm kernel,
/// and the calibration ladder.
struct ProteinBarScoringV55Tests {

    private let rs = RulesetV4.bundled

    private func bar(
        name: String = "Protein Bar", brand: String = "B",
        ing: String? = "milk protein isolate, whey protein isolate, almonds, sea salt",
        kcal: Double? = 350, prot: Double? = 30, sug: Double? = 5, addSug: Double? = nil,
        fib: Double? = 6, sat: Double? = 4, na: Double? = 300, fvn: Double? = nil,
        polyols: Double? = nil, nova: Int = 4,
        additives: [ProductAdditive] = [],
        categories: [String]? = ["snacks", "sweet-snacks", "bars", "protein-bars"],
        labels: [String]? = nil, serving: String? = "1 bar (60 g)", size: String = ""
    ) -> Product {
        var p = Product(
            id: name, name: name, brand: brand, size: size, glyph: "🍫",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: Nutrients(sugar_g: sug, sodium_mg: na, satFat_g: sat,
                                 fiber_g: fib, protein_g: prot, calcium_mg: nil,
                                 kcal: kcal, fvn: fvn, addedSugar_g: addSug,
                                 polyols_g: polyols),
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ing, imageURL: nil,
            labels: labels, packagingMaterials: nil, origins: nil,
            ingredientShares: nil, categories: categories
        )
        p.servingSize = serving
        return p
    }

    private func add(_ code: String, _ tier: AdditiveTier = .mild) -> ProductAdditive {
        ProductAdditive(name: code, risk: .low, code: code, tier: tier)
    }

    private func rule(_ id: String, _ p: Product) -> V4RuleResult? {
        ScoringEngineV4.score(p, ruleset: rs)?.rules.first { $0.rule == id }
    }
    private func score(_ p: Product) -> Int { ScoringEngineV4.score(p, ruleset: rs)!.base }
    private func route(_ p: Product) -> String { ScoringEngineV4.route(p, ruleset: rs) }
    private var cfg: RulesetV4.ProteinBarConfig { rs.proteinBars! }

    // MARK: Real-world fixtures (label values per 100 g)

    private var rxbar: Product {
        bar(name: "RXBAR Chocolate Sea Salt",
            ing: "dates, egg whites, almonds, cashews, chocolate, natural chocolate flavor, sea salt",
            kcal: 404, prot: 23.1, sug: 25, addSug: 0, fib: 9.6, sat: 3.8, na: 500, fvn: 85, nova: 3,
            serving: "1 bar (52 g)")
    }
    private var quest: Product {
        bar(name: "Quest Protein Bar Cookies & Cream",
            ing: "protein blend (milk protein isolate, whey protein isolate), soluble corn fiber, almonds, water, erythritol, natural flavors, cocoa butter, sea salt, calcium carbonate, sucralose, steviol glycosides (stevia)",
            kcal: 317, prot: 35, sug: 1.7, addSug: 0, fib: 23, sat: 5, na: 383,
            additives: [add("e968", .moderate), add("e955", .moderate), add("e960", .mild), add("e170", .exempt)],
            serving: "1 bar (60 g)")
    }
    private var barebells: Product {
        bar(name: "Barebells Salty Peanut",
            ing: "milk protein, collagen hydrolysate, peanuts (10%), sweeteners (maltitol, sucralose), humectant (glycerol), cocoa butter, palm fat, whole milk powder, cocoa mass, water, rapeseed oil, salt, emulsifier (soy lecithin), flavouring, skimmed milk powder, lactose",
            kcal: 364, prot: 36, sug: 3.1, fib: 4.0, sat: 7.3, na: 600, polyols: 20,
            additives: [add("e965", .soft), add("e955", .moderate), add("e422", .soft), add("e322", .soft)],
            serving: "55 g")
    }
    private var perfectBar: Product {
        bar(name: "Perfect Bar Peanut Butter",
            ing: "organic peanut butter, organic honey, organic nonfat dry milk, organic dried whole egg powder, rice protein, dried whole food powder (organic kale, organic flax seed, organic apple, organic carrot, organic spinach), organic sunflower oil, sea salt",
            kcal: 508, prot: 26, sug: 29, addSug: 27, fib: 4.6, sat: 4.6, na: 277, nova: 3,
            serving: "1 bar (65 g)")
    }
    private var thinkBar: Product {
        bar(name: "think! High Protein Brownie Crunch",
            ing: "protein blend (soy protein isolate, calcium caseinate, whey protein isolate), glycerin, chocolate flavored coating (maltitol, palm kernel oil, cocoa powder, whey protein concentrate, soy lecithin, natural flavor, sucralose), maltitol syrup, soy crisps (soy protein isolate, rice flour, salt), cocoa (processed with alkali), water, palm kernel oil, natural flavors, sucralose, salt, soy lecithin",
            kcal: 383, prot: 33, sug: 0, addSug: 0, fib: 1.7, sat: 8.3, na: 450,
            additives: [add("e422", .soft), add("e965", .soft), add("e322", .soft), add("e955", .moderate)],
            serving: "1 bar (60 g)")
    }
    private var cleanBar: Product {
        bar(name: "Egg White Almond Bar",
            ing: "egg whites, almonds, peanuts, pumpkin seeds, sea salt",
            kcal: 450, prot: 30, sug: 3, addSug: 0, fib: 8, sat: 3, na: 300, nova: 3,
            serving: "50 g")
    }

    // MARK: Ruleset shape

    @Test func proteinBarsProfileExistsAndSumsTo100() throws {
        #expect(rs.version >= "2026.08-v5.5.0")
        let profile = try #require(rs.profiles["protein_bars"])
        #expect(profile.reduce(0) { $0 + $1.w } == 100)
        #expect(profile.first { $0.rule == "S12" }?.variant == "proteinBar")
        #expect(profile.first { $0.rule == "S2" }?.variant == "proteinBar")
        #expect(profile.first { $0.rule == "S3" }?.variant == "proteinBar")
        #expect(profile.first { $0.rule == "S6" }?.variant == "proteinBar")
        #expect(profile.first { $0.rule == "S14" }?.variant == "proteinBar")
        #expect(profile.contains { $0.rule == "S12" && $0.w >= 24 }, "protein delivery is the largest factor")
        #expect(rs.proteinBars != nil)
        #expect(rs.router.contains { $0.match == "protein-bars" && $0.profile == "protein_bars" })
        #expect(rs.router.contains { $0.match == "protein-energy-bars" && $0.profile == "protein_bars" })
        // The protein-bar entries precede the generic snack / cereal entries.
        let idxBar = rs.router.firstIndex { $0.match == "protein-bars" }!
        let idxSnacks = rs.router.firstIndex { $0.match == "snacks" }!
        let idxCereal = rs.router.firstIndex { $0.match == "breakfast-cereals" }!
        #expect(idxBar < idxSnacks && idxBar < idxCereal)
        #expect(cfg.s2.upfMarkers.allSatisfy { !$0.family.lowercased().contains("protein") },
                "protein isolates are never an ultra-processing marker on a protein bar")
    }

    // MARK: Routing

    @Test func taggedProteinBarsRouteToProteinBars() {
        #expect(route(quest) == "protein_bars")
        #expect(route(bar(categories: ["dietary-supplements", "bodybuilding-supplements", "protein-bars"])) == "protein_bars",
                "OFF's supplement-only tagging (no `snacks`) used to fall to general")
        #expect(route(bar(categories: ["snacks", "sweet-snacks", "bars", "cereal-bars", "protein-bars"])) == "protein_bars",
                "protein-bars outranks the cereal / snack entries")
    }

    @Test func guardRejectsPowdersAndShakesWearingTheTag() {
        let powder = bar(name: "Whey protein powder", ing: "whey protein concentrate, cocoa, sucralose",
                         kcal: 380, prot: 75, sug: 5, fib: 1, sat: 2, na: 200,
                         categories: ["dietary-supplements", "protein-powders", "protein-bars"])
        #expect(route(powder) != "protein_bars")
        let shake = bar(name: "Protein shake", ing: "water, milk protein, cocoa, sucralose",
                        kcal: 62, prot: 8, sug: 1, fib: 0, sat: 0.3, na: 60,
                        categories: ["dietary-supplements", "protein-bars"])
        #expect(route(shake) != "protein_bars")
    }

    @Test func evidenceGateCatchesBarsOffTheTag() {
        // Marketed on protein + ≥12 % of energy from protein, tagged only as a cereal bar.
        let kindProtein = bar(name: "KIND Protein Crunchy Peanut Butter",
                              ing: "peanuts, soy protein isolate, honey, ...",
                              kcal: 536, prot: 24, sug: 17, fib: 7, sat: 8, na: 142,
                              categories: ["snacks", "sweet-snacks", "bars", "cereal-bars"])
        #expect(route(kindProtein) == "protein_bars")
        // Genuinely high-protein bar with no protein word in the name, no tags
        // at all — "bar" lives in the brand (OFF US imports).
        let untagged = bar(name: "Chocolate Sea Salt", brand: "RXBAR", ing: "dates, egg whites, almonds, cashews, chocolate, natural chocolate flavor, sea salt",
                           kcal: 404, prot: 23.1, sug: 25, fib: 9.6, sat: 3.8, na: 500, nova: 3,
                           categories: nil, serving: "1 bar (52 g)")
        #expect(route(untagged) == "protein_bars")
        // Neither tag, nor bar word, nor bar brand → not a bar (falls to general).
        let nameless = bar(name: "Chocolate Sea Salt", brand: "Acme", ing: "dates, egg whites, almonds, cashews, chocolate, natural chocolate flavor, sea salt",
                           kcal: 404, prot: 23.1, sug: 25, fib: 9.6, sat: 3.8, na: 500, nova: 3,
                           categories: nil, serving: "1 bar (52 g)")
        #expect(route(nameless) == "general")
        // Same bar, tagged snacks only → still a protein bar.
        let snackTagged = bar(name: "Chocolate Sea Salt", ing: "dates, egg whites, almonds, cashews, chocolate, natural chocolate flavor, sea salt",
                              kcal: 404, prot: 23.1, sug: 25, fib: 9.6, sat: 3.8, na: 500, nova: 3,
                              categories: ["snacks", "sweet-snacks", "bars"])
        #expect(route(snackTagged) == "protein_bars")
    }

    @Test func ordinarySnackBarsStayOnSnacks() {
        // KIND Dark Chocolate Nuts & Sea Salt: 12 % of energy from protein, no protein word.
        let kind = bar(name: "KIND Dark Chocolate Nuts & Sea Salt",
                       ing: "mixed nuts (almonds, peanuts, walnuts), chicory root fiber, honey, palm kernel oil, sugar, cocoa",
                       kcal: 500, prot: 15, sug: 12.5, fib: 17.5, sat: 7.5, na: 312,
                       categories: ["snacks", "sweet-snacks", "bars", "nut-bars"])
        #expect(route(kind) == "snacks")
        // Clif Bar original: 16.7 % of energy from protein, not marketed on protein.
        let clif = bar(name: "Clif Bar Crunchy Peanut Butter",
                       ing: "organic rolled oats, organic brown rice syrup, organic peanut butter, soy protein isolate",
                       kcal: 382, prot: 16, sug: 26, fib: 7, sat: 2.2, na: 426,
                       categories: ["snacks", "sweet-snacks", "bars", "energy-bars"])
        #expect(route(clif) == "snacks")
        // Larabar: 8 % of energy from protein.
        let lara = bar(name: "Larabar Apple Pie", ing: "dates, almonds, unsweetened apples, walnuts, raisins, cinnamon",
                       kcal: 444, prot: 8.9, sug: 40, fib: 11, sat: 1.1, na: 0, nova: 1,
                       categories: ["snacks", "sweet-snacks", "bars", "fruit-bars"])
        #expect(route(lara) == "snacks")
        // "Protein" in the name but 10 % of energy from protein → not a protein bar.
        let weak = bar(name: "Protein granola bar", ing: "oats, honey, peanuts",
                       kcal: 450, prot: 11, sug: 20, fib: 5, sat: 3, na: 200,
                       categories: ["snacks", "sweet-snacks", "bars", "cereal-bars"])
        #expect(route(weak) == "snacks")
        // Dairy never rerails through the gate (not a fallback profile).
        let cheeseBar = bar(name: "Cheddar cheese bar", ing: "pasteurized milk, salt, cultures, enzymes",
                            kcal: 400, prot: 25, sug: 0.5, fib: 0, sat: 21, na: 650, nova: 3,
                            categories: ["dairies", "cheeses", "cheddar-cheese"])
        #expect(route(cheeseBar) == "yogurt_cheese")
    }

    // MARK: Serving

    @Test func servingGramsParse() {
        #expect(ProteinBarScoring.parseGrams("1 bar (60 g)") == 60)
        #expect(ProteinBarScoring.parseGrams("60g") == 60)
        #expect(ProteinBarScoring.parseGrams("2.12 oz (60g)") == 60)
        #expect(ProteinBarScoring.parseGrams("45 gram") == 45)
        #expect(ProteinBarScoring.parseGrams("12 x 60 g") == 60)
        #expect(ProteinBarScoring.parseGrams("1 serving (45 g)") == 45)
        #expect(ProteinBarScoring.parseGrams("250 ml") == nil)
        #expect(ProteinBarScoring.parseGrams("1.7 fl oz") == nil)
        #expect(ProteinBarScoring.parseGrams("2.1 oz").map { abs($0 - 59.5) < 0.5 } == true)
        let declared = ProteinBarScoring.servingGrams(bar(serving: "1 bar (55 g)"), cfg: cfg)
        #expect(declared.grams == 55 && !declared.estimated)
        let fromSize = ProteinBarScoring.servingGrams(bar(serving: nil, size: "52 g"), cfg: cfg)
        #expect(fromSize.grams == 52 && !fromSize.estimated)
        let multipack = ProteinBarScoring.servingGrams(bar(serving: nil, size: "135 g"), cfg: cfg)
        #expect(multipack.grams == cfg.serving.defaultG && multipack.estimated,
                "a multipack weight is not a serving → default, flagged estimated")
    }

    // MARK: S12 — protein delivery

    @Test func proteinAmountDrivesS12() throws {
        let high = try #require(rule("S12", quest))
        #expect(high.fraction >= 0.85, "35 g/100 g, 21 g per bar, 44 % of energy → full amount")
        #expect(high.note?.contains("isolate discount") != true, "no ×0.5 isolate discount on protein bars")
        let low = bar(name: "Protein Bar", ing: "dates, almonds, walnuts", kcal: 444, prot: 8.9, sug: 40, fib: 11, sat: 1.1, na: 0, nova: 1, serving: "45 g")
        let lowR = try #require(rule("S12", low))
        #expect(lowR.fraction < 0.45, "4 g per bar / 8 % of energy earns little even with full fiber")
        // Same per-100 g protein, bigger bar → more protein per serving → higher credit.
        let small = bar(kcal: 400, prot: 25, serving: "40 g")
        let big = bar(kcal: 400, prot: 25, serving: "70 g")
        #expect(rule("S12", big)!.fraction > rule("S12", small)!.fraction)
        // Energy share guards against calorie-padding: same grams per bar, more calories → lower.
        let dense = bar(kcal: 550, prot: 20, serving: "60 g")
        let lean = bar(kcal: 300, prot: 20, serving: "60 g")
        #expect(rule("S12", lean)!.fraction > rule("S12", dense)!.fraction)
    }

    @Test func proteinSourceQualityTable() {
        func q(_ ing: String) -> Double? { ProteinBarScoring.proteinQuality(ingredientsText: ing, cfg: cfg).credit }
        #expect(q("whey protein isolate, cocoa") == 1.0)
        #expect(q("milk protein isolate, whey protein concentrate, almonds")! > 0.95)
        #expect(q("egg whites, dates, almonds")! > 0.9)
        #expect(q("hydrolysed collagen, cocoa")! <= 0.3, "collagen is an incomplete protein")
        #expect(q("soy protein isolate")! > 0.85 && q("soy protein isolate")! < 1.0)
        #expect(q("pea protein")! < 0.85)
        #expect(q("pea protein, brown rice protein")! >= 0.89, "complementary plant blend")
        #expect(q("brown rice protein")! < 0.6)
        // Collagen listed second behind milk protein drags the blend down, but
        // less than a collagen-led bar.
        let milkThenCollagen = q("milk protein, collagen hydrolysate, peanuts")!
        let collagenThenMilk = q("collagen hydrolysate, milk protein, peanuts")!
        #expect(milkThenCollagen > collagenThenMilk)
        #expect(milkThenCollagen < 0.9 && milkThenCollagen > 0.6)
        // Parenthetical blends contribute their specific sources, not the head.
        #expect(q("protein blend (milk protein isolate, whey protein isolate), cocoa") == 1.0)
        // Density weighting: a 25 %-protein peanut listed first does not outweigh the isolate behind it.
        #expect(q("roasted peanuts, soy protein isolate, whey protein concentrate")! > 0.8)
        #expect(q("dates, cocoa") == nil, "no protein source → unknown")
    }

    @Test func fiberCreditDampsIsolatedFibers() throws {
        let questR = try #require(rule("S12", quest))
        #expect(questR.note?.contains("isolated") == true, "soluble corn fiber leads the list")
        let rxR = try #require(rule("S12", rxbar))
        #expect(rxR.note?.contains("isolated") != true)
        // Identical macros, fiber from oats vs from soluble corn fiber.
        let intrinsic = bar(ing: "milk protein isolate, oats, almonds", fib: 10)
        let isolated = bar(ing: "milk protein isolate, soluble corn fiber, almonds", fib: 10)
        #expect(rule("S12", intrinsic)!.fraction > rule("S12", isolated)!.fraction)
    }

    // MARK: S2 — evidence-based processing

    @Test func s2CountsMarkerFamiliesNotNova() throws {
        #expect(ProteinBarScoring.upfMarkerFamilies(perfectBar, cfg: cfg).isEmpty)
        #expect(try #require(rule("S2", perfectBar)).fraction == cfg.s2.clean)
        let rx = ProteinBarScoring.upfMarkerFamilies(rxbar, cfg: cfg)
        #expect(rx == ["flavorings"])
        #expect(try #require(rule("S2", rxbar)).fraction == cfg.s2.markerCredits[0])
        let q = ProteinBarScoring.upfMarkerFamilies(quest, cfg: cfg)
        #expect(Set(q) == ["flavorings", "non-nutritive sweeteners", "sugar alcohols", "isolated fibers"],
                "calcium carbonate (a fortificant) is not a color marker; protein isolates never count")
        #expect(ProteinBarScoring.upfMarkerFamilies(barebells, cfg: cfg).count >= 5)
        #expect(try #require(rule("S2", barebells)).fraction <= 0.2)
        // NOVA 4 no longer flattens: a NOVA-4-tagged clean list beats a NOVA-3 candy build.
        #expect(rule("S2", cleanBar)!.fraction > rule("S2", bar(ing: barebells.ingredientsText, nova: 3))!.fraction)
        // No list → NOVA fallback, capped well below clean.
        #expect(rule("S2", bar(ing: nil, nova: 4))!.fraction == cfg.s2.novaFourNoList)
        let unknown = try #require(rule("S2", bar(ing: nil, nova: 0)))
        #expect(!unknown.hadData)
    }

    // MARK: S3 — capped fruit-sugar discount, no sweetener cap

    @Test func dateSugarCountsAtLeastHalf() throws {
        let dates = bar(name: "Protein Bar", ing: "dates, egg whites, almonds", kcal: 420, prot: 22, sug: 40, fib: 8, sat: 1, na: 100, fvn: 100, nova: 3)
        let s3 = try #require(rule("S3", dates))
        #expect(s3.fraction < 0.6, "40 g/100 g from dates is not free of charge")
        // The same product on the generic snacks path scored S3 = 1.0 — the
        // whole point of the cap.
        var snack = dates; snack.categories = ["snacks", "sweet-snacks", "bars", "fruit-bars"]
        snack.nutrients.protein_g = 8   // below the evidence gate
        #expect(route(snack) == "snacks")
        #expect(rule("S3", snack)!.fraction == 1.0)
    }

    @Test func sweetenerSubstitutionCapDoesNotStackOnProteinBars() throws {
        // Quest: 1.7 g sugar with sucralose/stevia/erythritol — S3 stays on the
        // sugar grams, S6 carries the sweetener verdict.
        #expect(try #require(rule("S3", quest)).fraction == 1.0)
        #expect(try #require(rule("S6", quest)).fraction == 0.0)
    }

    // MARK: S6 — sweetener tiers + polyol load

    @Test func sweetenerTiersAndPolyolLoad() throws {
        #expect(try #require(rule("S6", rxbar)).fraction == 1.0)
        let stevia = bar(ing: "milk protein isolate, almonds, stevia extract", additives: [add("e960", .mild)])
        #expect(abs(try #require(rule("S6", stevia)).fraction - 0.70) < 0.01)
        let maltitolLight = bar(ing: "milk protein isolate, almonds, maltitol", polyols: 5, additives: [add("e965", .soft)])
        let maltitolHeavy = bar(ing: "milk protein isolate, almonds, maltitol", polyols: 25, additives: [add("e965", .soft)])
        let light = try #require(rule("S6", maltitolLight)).fraction
        let heavy = try #require(rule("S6", maltitolHeavy)).fraction
        #expect(light > heavy)
        #expect(abs(heavy - light * cfg.s6.polyolLoadFactors.last!) < 0.01)
        #expect(rule("S6", maltitolHeavy)?.note?.contains("polyols") == true)
    }

    // MARK: S14 — neutral protein sources, plural nuts

    @Test func proteinSourcesAreNeutralInRealFood() throws {
        let b = IngredientIntegrity.evaluate(
            ingredientsText: "milk protein isolate, whey protein isolate, almonds, sea salt",
            neutralTokenKw: cfg.s14.neutralTokenKw, neutralIsolateMarkers: cfg.s14.neutralIsolateMarkers)
        #expect(abs(b.wholeFoodRatio - 0.5) < 0.01, "almonds ✓ / sea salt ✗ — the isolates are out of the ratio")
        #expect(b.isolateScore == 1.0, "protein isolate markers don't count against the bar")
        // Maltodextrin still does.
        let m = IngredientIntegrity.evaluate(
            ingredientsText: "milk protein isolate, maltodextrin, almonds",
            neutralTokenKw: cfg.s14.neutralTokenKw, neutralIsolateMarkers: cfg.s14.neutralIsolateMarkers)
        #expect(m.isolateScore < 1.0)
        // Generic path unchanged: protein isolates still dock on ordinary foods.
        let generic = IngredientIntegrity.evaluate(ingredientsText: "milk protein isolate, whey protein isolate, almonds, sea salt")
        #expect(generic.isolateScore < 1.0)
    }

    @Test func pluralNutsAndNutButtersAreWholeFoods() {
        #expect(IngredientIntegrity.isWholeFoodToken("almonds"))
        #expect(IngredientIntegrity.isWholeFoodToken("peanuts"))
        #expect(IngredientIntegrity.isWholeFoodToken("cashews"))
        #expect(IngredientIntegrity.isWholeFoodToken("roasted peanuts"))
        #expect(IngredientIntegrity.isWholeFoodToken("peanut butter"))
        #expect(IngredientIntegrity.isWholeFoodToken("organic almond butter"))
        #expect(IngredientIntegrity.isWholeFoodToken("mixed nuts"))
        #expect(IngredientIntegrity.isWholeFoodToken("nonfat dry milk"))
        #expect(IngredientIntegrity.isWholeFoodToken("cocoa mass"))
        #expect(!IngredientIntegrity.isWholeFoodToken("whey protein isolate"))
        #expect(!IngredientIntegrity.isWholeFoodToken("soluble corn fiber"))
        let nuts = IngredientIntegrity.evaluate(ingredientsText: "almonds, peanuts, cashews, walnuts")
        #expect(nuts.wholeFoodRatio == 1.0)
    }

    // MARK: S1 / S4 / S15

    @Test func isolateTextSignalsAreExemptOnProteinBars() throws {
        let p = bar(ing: "milk protein isolate, whey protein isolate, almonds, sea salt")
        #expect(try #require(rule("S1", p)).fraction == 1.0,
                "whey / milk protein isolate are the protein source, not an additive signal here")
        // On an ordinary snack the text signal still docks.
        var snack = p; snack.categories = ["snacks", "sweet-snacks", "biscuits"]; snack.nutrients.protein_g = 6
        #expect(route(snack) == "snacks")
        #expect(try #require(rule("S1", snack)).fraction < 1.0)
    }

    @Test func implausibleSodiumIsUnknownNotSalty() throws {
        let r = try #require(rule("S4", bar(na: 161_538)))
        #expect(!r.hadData)
        #expect(abs(r.fraction - 0.30) < 0.001)
        #expect(try #require(rule("S4", bar(na: 400))).hadData)
    }

    @Test func palmKernelOilIsRefinedHardFat() throws {
        let r = try #require(rule("S15", bar(ing: "milk protein isolate, palm kernel oil, cocoa")))
        #expect(r.hadData && r.fraction <= 0.2)
        let nuts = try #require(rule("S15", bar(ing: "milk protein isolate, mixed nuts (almonds, peanuts), cocoa butter")))
        #expect(nuts.fraction == 1.0, "mixed nuts count as a whole-food fat source")
    }

    // MARK: Calibration

    @Test func calibrationLadder() {
        let clean = score(cleanBar)
        let rx = score(rxbar)
        let q = score(quest)
        let perfect = score(perfectBar)
        let bb = score(barebells)
        let think = score(thinkBar)
        #expect(clean >= 85, "egg-white + nut bar, no sugar, no sweeteners: \(clean)")
        #expect(rx >= 75, "RXBAR is Excellent-band: \(rx)")
        #expect(rx > q, "whole-food protein bar beats the NNS / isolated-fiber build: \(rx) vs \(q)")
        #expect(q >= 60 && q < 75, "Quest: high protein, low sugar, but NNS + isolated fiber → Good: \(q)")
        #expect(perfect >= 60 && perfect < 75, "Perfect Bar: clean list but 27 g added sugar → Good: \(perfect)")
        #expect(q > bb, "Quest beats a maltitol / palm-fat / collagen-padded build: \(q) vs \(bb)")
        #expect(bb > think, "Barebells beats a palm-kernel coated soy-crisp build: \(bb) vs \(think)")
        #expect(think >= 45, "still far from the floor — 20 g protein per bar is real: \(think)")
        #expect(clean > rx && rx > perfect)
    }

    @Test func sameBarScoresTheSameWhateverTheTags() {
        // Field QA: RXBAR Chocolate Sea Salt scored 54–68 across barcodes
        // depending on `snacks` vs supplement tagging and the NOVA tag.
        let a = rxbar
        var b = rxbar; b.categories = ["dietary-supplements", "bodybuilding-supplements", "protein-bars"]; b.novaGroup = 4
        var c = rxbar; c.categories = ["snacks", "sweet-snacks", "bars"]; c.novaGroup = 0
        #expect(route(a) == "protein_bars" && route(b) == "protein_bars" && route(c) == "protein_bars")
        #expect(score(a) == score(b) && score(b) == score(c),
                "NOVA tag and snack tagging no longer move a protein bar: \(score(a)) / \(score(b)) / \(score(c))")
    }

    @Test func overviewTopicStaysProteinAndFiber() throws {
        let ctx = try #require(ScoringEngineV4.overviewContext(for: quest, profile: MockData.user, ruleset: rs))
        #expect(ctx.rules.contains { $0.rule == "S12" && $0.topic == "protein and fiber" })
    }
}
