import Testing
import Foundation
@testable import Sage

// "Better Alternatives" (ALTERNATIVES_SPEC.md). Three layers:
//  • `Alternatives.select` — pure ranking logic, tested with mocks.
//  • `SageCategory.shelf` / `anchorTag` / `form` — routing + fit.
//  • `Alternatives.rankOutcome` — the engine-backed gates (evidence, market,
//    safety, fit, diversity) over hand-built candidates.
struct AlternativesTests {

    // MARK: select() — pure selection (margin · floor preference · order · cap)

    private struct M: RankableAlternative {
        let score: Int; let sharedTag: Bool; let countries: [String]
        init(_ s: Int, shared: Bool = false, countries: [String] = ["us"]) {
            score = s; sharedTag = shared; self.countries = countries
        }
    }

    @Test func selectMarginGateAndFallback() {
        let r = Alternatives.select(baseline: 40, from: [M(54), M(52), M(49)])
        #expect(r.map(\.score) == [54, 52])
    }

    @Test func selectPrefersGoodOverMarginOnly() {
        let r = Alternatives.select(baseline: 40, from: [M(58), M(52)])
        #expect(r.map(\.score) == [58])
    }

    @Test func selectSharedTagRanksFirst() {
        let r = Alternatives.select(baseline: 30, from: [M(50, shared: false), M(45, shared: true)])
        #expect(r.map(\.score) == [45, 50])
        #expect(r.first?.sharedTag == true)
    }

    @Test func selectCapsAtThree() {
        let r = Alternatives.select(baseline: 30, from: [M(41), M(42), M(43), M(44), M(45)])
        #expect(r.count == 3)
        #expect(r.map(\.score) == [45, 44, 43])
    }

    @Test func selectEmptyWhenNothingClearsMargin() {
        #expect(Alternatives.select(baseline: 70, from: [M(72), M(75)]).isEmpty)
    }

    @Test func selectFiltersToAllowedMarkets() {
        // US-only (ALTERNATIVES_SPEC §8): non-US peers are filtered out even when
        // higher-scoring, so UK / CA / BR never surface as suggestions.
        let pool = [
            M(60, countries: ["us"]),
            M(70, countries: ["br"]),        // excluded despite the top score
            M(58, countries: ["uk"]),        // excluded — not US
            M(55, countries: ["ca"]),        // excluded — not US
        ]
        let r = Alternatives.select(baseline: 40, from: pool)
        #expect(r.map(\.score) == [60])                    // only the US peer
        #expect(r.allSatisfy { $0.countries == ["us"] })
    }

    @Test func regionFromBarcodeBrazil() {
        #expect(AlternativesRegion.from(barcode: "7891000100103") == .br)
        #expect(AlternativesRegion.from(barcode: "7901234567890") == .br)
        #expect(AlternativesRegion.from(barcode: "0049000005345") == .us)
    }

    // MARK: US-market barcode evidence

    @Test func usMarketEvidenceFromBarcodes() {
        // UPC-A (12 → leading 0) and 13-digit US prefixes.
        #expect(Alternatives.hasUSMarketEvidence(barcode: "012000107351"))
        #expect(Alternatives.hasUSMarketEvidence(barcode: "0012000107351"))
        #expect(Alternatives.hasUSMarketEvidence(barcode: "1210002000956"))   // 121 ∈ 100–139
        // UPC-E (Trader Joe's / Kroger / Mountain Dew can) vs EAN-8 (M&S).
        #expect(Alternatives.hasUSMarketEvidence(barcode: "01208500"))
        #expect(!Alternatives.hasUSMarketEvidence(barcode: "29436620"))
        // ALDI US / Lidl US private label on German prefixes.
        #expect(Alternatives.hasUSMarketEvidence(barcode: "4099100008654"))
        #expect(Alternatives.hasUSMarketEvidence(barcode: "4061462171123"))
        // Community-tagged foreign SKUs: Hungarian Coke, Polish Hortex,
        // Israeli juice, German Brüggen oats, Latvian curd snack.
        #expect(!Alternatives.hasUSMarketEvidence(barcode: "5993330000152"))
        #expect(!Alternatives.hasUSMarketEvidence(barcode: "5900500024368"))
        #expect(!Alternatives.hasUSMarketEvidence(barcode: "7290115208047"))
        #expect(!Alternatives.hasUSMarketEvidence(barcode: "4008713756661"))
        #expect(!Alternatives.hasUSMarketEvidence(barcode: "4750050341405"))
        // Non-GS1 ids (fixtures / internal codes) carry no evidence either way.
        #expect(Alternatives.hasUSMarketEvidence(barcode: "US1"))
        // Korean ramen is the US instant-noodle aisle — allowed on that shelf only.
        #expect(Alternatives.hasUSMarketEvidence(barcode: "8801045009209", shelf: .instantNoodles))
        #expect(!Alternatives.hasUSMarketEvidence(barcode: "8801045009209", shelf: .soda))
        #expect(!Alternatives.hasUSMarketEvidence(barcode: "8801045009209"))
    }

    // MARK: shelf routing

    private func mapped(_ categoriesTags: [String], name: String = "n", brand: String? = nil) -> Product {
        OpenFoodFactsService.mapCandidate(
            barcode: "x", name: name, brands: brand, ingredientsText: nil,
            additivesTags: nil, nutriments: nil, nutriscoreGrade: nil, novaGroup: 1,
            imageURL: nil, categoriesTags: categoriesTags, labelsTags: nil)
    }

    @Test func shelfRoutesAndAnchors() {
        let juice = mapped(["en:beverages", "en:fruit-juices", "en:grape-juices"])
        #expect(SageCategory.shelf(for: juice) == .juice)
        #expect(SageCategory.shelf(for: juice)?.anchorTag(for: juice) == "grape-juices")

        #expect(SageCategory.shelf(for: mapped(["en:dairies", "en:cheeses"])) == .cheese)
        #expect(SageCategory.shelf(for: mapped(["en:dairies", "en:yogurts", "en:greek-yogurts"])) == .yogurt)
    }

    @Test func shelfIsNilForUnshelvedScans() {
        #expect(SageCategory.shelf(for: mapped(["en:beverages", "en:coffees"])) == nil)
        #expect(SageCategory.shelf(for: mapped(["en:beverages", "en:waters"])) == nil)
        #expect(SageCategory.shelf(for: mapped(["en:meats", "en:hams"])) == nil)
        #expect(SageCategory.shelf(for: mapped([])) == nil)
    }

    @Test func newShelvesRouteCalibrationFixtures() {
        #expect(SageCategory.shelf(for: mapped([
            "en:spreads", "en:peanut-butters", "en:nuts"
        ])) == .nutButtersAndSpreads)
        #expect(SageCategory.shelf(for: mapped([
            "en:snacks", "en:cereal-bars"
        ])) == .snackBars)
        #expect(SageCategory.shelf(for: mapped([
            "en:dairies", "en:milks"
        ])) == .milks)
        #expect(SageCategory.shelf(for: mapped([
            "en:dairies", "en:butters"
        ])) == .fatsAndOils)
        #expect(SageCategory.shelf(for: mapped([
            "en:margarines"
        ])) == .fatsAndOils)
        #expect(SageCategory.shelf(for: mapped([
            "en:vegetable-oils", "en:coconut-oils"
        ])) == .fatsAndOils)
        #expect(SageCategory.shelf(for: mapped([
            "en:vegetable-oils", "en:olive-oils"
        ])) == .fatsAndOils)
        #expect(SageCategory.shelf(for: mapped([
            "en:meals", "en:dried-products", "en:instant-noodles"
        ])) == .instantNoodles)
    }

    @Test func energyDrinksRouteToOwnShelf() {
        // Plain energy drink → energyDrinks.
        #expect(SageCategory.shelf(for: mapped(["en:beverages", "en:energy-drinks"])) == .energyDrinks)
        // Cross-tagged en:sodas (like some Red Bulls) still route to energyDrinks
        // because its def is matched before soda — so a Red Bull always gets peers.
        #expect(SageCategory.shelf(for: mapped([
            "en:beverages", "en:carbonated-drinks", "en:soft-drinks", "en:sodas", "en:energy-drinks",
        ])) == .energyDrinks)
        // A regular soda (no energy-drinks tag) stays on the soda shelf.
        #expect(SageCategory.shelf(for: mapped(["en:beverages", "en:sodas", "en:colas"])) == .soda)
    }

    @Test func anchorTagNilWhenOnlyRootTagMatched() {
        let p = mapped(["en:beverages", "en:sodas"])
        #expect(SageCategory.shelf(for: p) == .soda)
        #expect(SageCategory.shelf(for: p)?.anchorTag(for: p) == nil)
    }

    @Test func routingNoLongerStealsFriesFormulaOrDrySoba() {
        // Frozen fries live under `chips-and-fries`; they must not get crisps.
        #expect(SageCategory.shelf(for: mapped(["en:frozen-foods", "en:chips-and-fries", "en:french-fries"])) == nil)
        // Infant formula never gets food alternatives.
        #expect(SageCategory.shelf(for: mapped(["en:baby-foods", "en:baby-milks", "en:infant-formulas"])) == .babyFood)
        let formula = mapped(["en:baby-foods", "en:baby-milks", "en:infant-formulas"], name: "Similac Pro-Advance")
        #expect(SageCategory.babyFood.form(of: formula)?.suggestible == false)
        #expect(SageCategory.shelf(for: mapped(["en:baby-milks", "en:infant-formulas"])) == nil)
        // Plain dry noodles are pasta, not instant ramen.
        #expect(SageCategory.shelf(for: mapped(["en:pastas", "en:noodles"])) == .pasta)
    }

    // MARK: forms — swap compatibility

    @Test func formsSeparateLoavesFromTortillasAndCheddarFromCottage() {
        let loaf = mapped(["en:breads", "en:whole-wheat-breads"], name: "100% Whole Wheat Bread")
        let tortilla = mapped(["en:breads", "en:tortillas"], name: "Ezekiel 4:9 Original Tortillas")
        #expect(SageCategory.bread.form(of: loaf)?.id == "loaf")
        #expect(SageCategory.bread.form(of: tortilla)?.id == "flat")
        #expect(!SageCategory.bread.isSwapCompatible(scanned: loaf, candidate: tortilla))
        #expect(SageCategory.bread.isSwapCompatible(scanned: tortilla, candidate: tortilla))

        let cheddar = mapped(["en:cheeses", "en:cheddar-cheese"], name: "Sharp Cheddar")
        let cottage = mapped(["en:cheeses"], name: "Cottage Cheese", brand: "Daisy")
        #expect(SageCategory.cheese.form(of: cottage)?.id == "fresh")
        #expect(!SageCategory.cheese.isSwapCompatible(scanned: cheddar, candidate: cottage))
        #expect(SageCategory.cheese.isSwapCompatible(scanned: cottage, candidate: cottage))
    }

    @Test func formsNeverSuggestBakingChocolateCrackersOrTablets() {
        let bar = mapped(["en:chocolates", "en:dark-chocolates"], name: "Excellence 70% Cocoa")
        let baking = mapped(["en:chocolates", "en:dark-chocolates"], name: "Cacao unsweetened chocolate premium baking bar")
        let larabar = mapped(["en:chocolates"], name: "Chocolate Chip Cookie Dough", brand: "LÄRABAR")
        #expect(!SageCategory.chocolate.isSwapCompatible(scanned: bar, candidate: baking))
        #expect(!SageCategory.chocolate.isSwapCompatible(scanned: bar, candidate: larabar))

        let cookie = mapped(["en:biscuits", "en:chocolate-chip-cookies"], name: "Chocolate Chip Cookies")
        let oatcake = mapped(["en:biscuits", "en:biscuits-and-crackers"], name: "Fruit & Seed Oatcakes", brand: "Nairn's")
        #expect(!SageCategory.cookies.isSwapCompatible(scanned: cookie, candidate: oatcake))

        let energy = mapped(["en:beverages", "en:energy-drinks"], name: "Monster Energy")
        let tablets = mapped(["en:beverages", "en:energy-drinks"], name: "Sport Hydration +Caffeine Effervescent Electrolyte Drink Tablets", brand: "nuun")
        #expect(!SageCategory.energyDrinks.isSwapCompatible(scanned: energy, candidate: tablets))
    }

    @Test func formsKeepDairyAndPlantMilksApart() {
        let oat = mapped(["en:plant-milks", "en:oat-milks"], name: "Oatmilk")
        let cow = mapped(["en:milks", "en:whole-milks"], name: "Whole Milk")
        #expect(!SageCategory.milks.isSwapCompatible(scanned: oat, candidate: cow))
        #expect(!SageCategory.milks.isSwapCompatible(scanned: cow, candidate: oat))
        #expect(SageCategory.milks.isSwapCompatible(scanned: cow, candidate: cow))
    }

    @Test func formsKeepHotCerealAwayFromReadyToEat() {
        let cheerios = mapped(["en:breakfast-cereals"], name: "Cheerios")
        let oats = mapped(["en:breakfast-cereals", "en:rolled-oats"], name: "Old Fashioned Oats")
        #expect(!SageCategory.cereal.isSwapCompatible(scanned: cheerios, candidate: oats))
        let muesli = mapped(["en:breakfast-cereals", "en:mueslis"], name: "Old Country Style Muesli")
        #expect(SageCategory.cereal.isSwapCompatible(scanned: cheerios, candidate: muesli))
    }

    // MARK: rankOutcome() — engine-backed gates (uses the bundled V5 ruleset)

    /// MockData.user carries a "Low-sugar diet" restriction, which (correctly)
    /// makes every 14 g/100 ml juice unsafe to suggest. The gate tests below
    /// want a plain profile so they exercise one gate at a time.
    private var neutral: UserProfile {
        var p = MockData.user
        p.restrictions = []
        p.preferences = []
        p.avoidList = nil
        p.allergies = nil
        p.personalizeScoring = false
        return p
    }

    private func candidates(_ json: String) -> [AlternativeCandidate] {
        try! JSONDecoder().decode([AlternativeCandidate].self, from: Data(json.utf8))
    }

    /// A gate-complete US grape-juice cocktail (HFCS, NOVA 4) as the scan.
    private func scannedCocktail(profile: UserProfile? = nil) -> Product {
        let profile = profile ?? neutral
        let c = candidates("""
        [{"barcode":"0049000000001","name":"Grape Juice Cocktail","brand":"ValueBrand",
          "categories_tags":["en:fruit-juices","en:juices","en:grape-juices"],
          "ingredients_text":"water, high fructose corn syrup, grape juice concentrate, citric acid","nova_group":4,
          "countries":["us"],
          "nutriments":{"sugars_100g":13,"proteins_100g":0,"energy-kcal_100g":55,
                        "sodium_100g":0.01,"saturated-fat_100g":0,"fiber_100g":0}}]
        """)[0]
        let raw = OpenFoodFactsService.mapCandidate(
            barcode: c.barcode, name: c.name, brands: c.brand, ingredientsText: c.ingredientsText,
            additivesTags: c.additivesTags, nutriments: c.nutriments, nutriscoreGrade: c.nutriscoreGrade,
            novaGroup: c.novaGroup, imageURL: c.imageURL, categoriesTags: c.categoriesTags, labelsTags: c.labelsTags)
        guard case .scored(let p) = ScoringEngineV4.scoreProduct(raw, for: profile, ruleset: .bundled)
        else { fatalError("scanned did not score") }
        return p
    }

    /// A gate-complete, US-coded 100 % grape juice candidate (NOVA 1).
    private func betterJuice(barcode: String = "0049000000002", name: String = "Organic Grape Juice",
                             brand: String = "PureRoots", ingredients: String = "organic grape juice",
                             nova: Int = 1, countries: String = "\"us\"", extra: String = "") -> String {
        """
        {"barcode":"\(barcode)","name":"\(name)","brand":"\(brand)",
          "categories_tags":["en:fruit-juices","en:juices","en:grape-juices"],
          "ingredients_text":"\(ingredients)","nova_group":\(nova),
          "countries":[\(countries)],\(extra)
          "nutriments":{"sugars_100g":14,"proteins_100g":0.5,"energy-kcal_100g":62,
                        "sodium_100g":0.01,"saturated-fat_100g":0,"fiber_100g":0.2,
                        "fruits-vegetables-nuts-estimate-from-ingredients_100g":100}}
        """
    }

    @Test func rankExcludesScannedBarcodeAndDuplicates() {
        let scanned = scannedCocktail()
        let cands = candidates("[" + [
            betterJuice(),
            // Same barcode as the scan.
            betterJuice(barcode: "0049000000001", name: "Grape Juice Cocktail", brand: "ValueBrand",
                        ingredients: "water, high fructose corn syrup", nova: 4),
            // Other SKU of the scanned product (brand + name collide).
            betterJuice(barcode: "0049000000003", name: "Grape Juice Cocktail 64 fl oz", brand: "ValueBrand",
                        ingredients: "water, high fructose corn syrup", nova: 4),
        ].joined(separator: ",") + "]")
        let picks = Alternatives.rank(scanned: scanned, candidates: cands,
                                      profile: neutral, ruleset: .bundled)
        #expect(!picks.contains { $0.product.id == "0049000000001" })
        #expect(!picks.contains { $0.product.brand == "ValueBrand" })
        #expect(picks.contains { $0.product.id == "0049000000002" })
    }

    @Test func rankDropsThinRecordsThatScoreHighByMissingData() {
        // A NOVA-less, ingredient-less "Diet X" re-scores very high because the
        // unknown rules are dropped — it must never be suggested.
        let scanned = scannedCocktail()
        let cands = candidates("[" + [
            betterJuice(),
            """
            {"barcode":"0049000000009","name":"Mystery Juice","brand":"Thin",
              "categories_tags":["en:fruit-juices","en:grape-juices"],
              "countries":["us"],
              "nutriments":{"sugars_100g":0,"proteins_100g":0,"energy-kcal_100g":0,
                            "sodium_100g":0.01,"saturated-fat_100g":0}}
            """,
        ].joined(separator: ",") + "]")
        let picks = Alternatives.rank(scanned: scanned, candidates: cands,
                                      profile: neutral, ruleset: .bundled)
        #expect(!picks.contains { $0.product.id == "0049000000009" })
        #expect(picks.contains { $0.product.id == "0049000000002" })
    }

    @Test func rankDropsCommunityTaggedForeignBarcodes() {
        // Stamped `us` by OFF's country tags, but a Polish GS1 prefix.
        let scanned = scannedCocktail()
        let cands = candidates("[" + [
            betterJuice(barcode: "5900500024368", name: "Sok pomidorowy", brand: "Hortex"),
            betterJuice(),
        ].joined(separator: ",") + "]")
        let picks = Alternatives.rank(scanned: scanned, candidates: cands,
                                      profile: neutral, ruleset: .bundled)
        #expect(!picks.contains { $0.product.id == "5900500024368" })
        #expect(picks.contains { $0.product.id == "0049000000002" })
    }

    @Test func rankRespectsAllergiesAndAvoidList() {
        var profile = neutral
        profile.allergies = ["Tree nuts"]
        profile.avoidList = ["carrageenan"]
        let scanned = scannedCocktail(profile: profile)
        let cands = candidates("[" + [
            betterJuice(barcode: "0049000000004", name: "Grape & Almond Juice", brand: "NutCo",
                        ingredients: "grape juice, almond milk"),
            betterJuice(barcode: "0049000000005", name: "Creamy Grape Juice", brand: "GumCo",
                        ingredients: "grape juice, carrageenan"),
            betterJuice(),
        ].joined(separator: ",") + "]")
        let picks = Alternatives.rank(scanned: scanned, candidates: cands,
                                      profile: profile, ruleset: .bundled)
        #expect(!picks.contains { $0.product.id == "0049000000004" })
        #expect(!picks.contains { $0.product.id == "0049000000005" })
        #expect(picks.contains { $0.product.id == "0049000000002" })
    }

    @Test func rankCapsOnePerBrandAndCarriesReasons() {
        let scanned = scannedCocktail()
        let cands = candidates("[" + [
            betterJuice(barcode: "0049000000002", name: "Organic Grape Juice", brand: "PureRoots"),
            betterJuice(barcode: "0049000000006", name: "Organic Grape Juice 64 oz", brand: "PureRoots"),
            betterJuice(barcode: "0049000000007", name: "Organic Concord Grape Juice", brand: "PureRoots"),
            betterJuice(barcode: "0049000000008", name: "100% Grape Juice", brand: "OtherCo"),
        ].joined(separator: ",") + "]")
        let picks = Alternatives.rank(scanned: scanned, candidates: cands,
                                      profile: neutral, ruleset: .bundled)
        let brands = picks.map { $0.product.brand }
        #expect(brands.filter { $0 == "PureRoots" }.count == 1)
        #expect(brands.contains("OtherCo"))
        // HFCS cocktail (NOVA 4) → 100 % juice (NOVA 1): processing is the reason.
        #expect(picks.allSatisfy { $0.delta >= Alternatives.margin })
        #expect(picks.first?.reasons.contains("Minimally processed") == true)
        #expect(picks.allSatisfy { $0.reasons.count <= AlternativeReasons.maxReasons })
    }

    @Test func rankOutcomeUnscored() {
        var unscored = scannedCocktail()
        unscored.overallScore = nil
        let outcome = Alternatives.rankOutcome(scanned: unscored, candidates: [],
                                               profile: neutral, ruleset: .bundled)
        #expect(outcome == .unscored)
    }

    @Test func rankOutcomeAlreadyTopOfShelf() {
        var high = scannedCocktail()
        high.overallScore = 90
        high.yourScore = 90
        let weak = candidates("[" + betterJuice(barcode: "0049000000010", name: "Weak Juice", brand: "X",
                                                 ingredients: "water, sugar, grape juice", nova: 4) + "]")
        let outcome = Alternatives.rankOutcome(scanned: high, candidates: weak,
                                               profile: neutral, ruleset: .bundled)
        #expect(outcome == .alreadyTopOfShelf || outcome == .noBetterPeers)
        if case .suggestions = outcome { Issue.record("expected empty suggestions for score 90") }
    }

    @Test func suggestNoShelf() {
        let p = mapped(["en:meats", "en:hams"])
        var scored = p
        scored.overallScore = 50
        let outcome = Alternatives.suggest(for: scored, candidates: { _ in [] },
                                           profile: neutral, ruleset: .bundled)
        #expect(outcome == .noShelf)
    }

    // MARK: reasons

    @Test func reasonsAreLabelDerivedAndCapped() {
        var a = mapped(["en:sodas"], name: "Cola")
        var b = mapped(["en:sodas"], name: "Better Cola")
        a.nutrients.sugar_g = 10.6; b.nutrients.sugar_g = 2.0
        a.nutrients.sodium_mg = 400; b.nutrients.sodium_mg = 50
        a.novaGroup = 4; b.novaGroup = 3
        let r = AlternativeReasons.reasons(scanned: a, alternative: b)
        #expect(r.count == 2)
        #expect(r.first == "Less sugar")
        #expect(r.contains("Less processed"))
        // Tiny absolute differences never read as a reason.
        var c = b
        c.nutrients.sugar_g = 1.6
        #expect(!AlternativeReasons.reasons(scanned: b, alternative: c).contains("Less sugar"))
    }

    // MARK: Top Rated image URLs

    @Test func imageURLPrefersCandidateOFFURL() {
        let c = candidates("""
        [{"barcode":"7891991000833","name":"Soda Antarctica","brand":"Antarctica",
          "image_url":"https://images.openfoodfacts.org/images/products/789/199/100/0833/front_pt.20.400.jpg",
          "categories_tags":["en:sodas"],"nova_group":4,
          "nutriments":{"sugars_100g":10,"energy-kcal_100g":40}}]
        """)[0]
        let url = Alternatives.imageURL(for: c)
        #expect(url.contains("openfoodfacts.org"))
        #expect(!url.contains("sage-backend"))
    }

    @Test func imageURLFallsBackToWorkerWhenMissing() {
        let c = candidates("""
        [{"barcode":"7891991000833","name":"Soda Antarctica","brand":"Antarctica",
          "categories_tags":["en:sodas"],"nova_group":4,
          "nutriments":{"sugars_100g":10,"energy-kcal_100g":40}}]
        """)[0]
        #expect(c.imageURL == nil)
        let url = Alternatives.imageURL(for: c)
        #expect(url == BackendService.productImageURL(barcode: "7891991000833"))
    }

    @Test func scoredKeepsOFFImageForBrazilianBarcode() {
        let c = candidates("""
        [{"barcode":"7891991000833","name":"Soda Antarctica","brand":"Antarctica",
          "image_url":"https://images.openfoodfacts.org/images/products/789/199/100/0833/front_pt.20.400.jpg",
          "categories_tags":["en:sodas","en:sweetened-beverages"],
          "ingredients_text":"water, sugar","nova_group":4,"countries":["br"],
          "nutriments":{"sugars_100g":10,"proteins_100g":0,"energy-kcal_100g":40,
                        "sodium_100g":0.01,"saturated-fat_100g":0,"fiber_100g":0}}]
        """)[0]
        let scored = Alternatives.scored(c, profile: neutral, ruleset: .bundled)
        #expect(scored != nil)
        #expect(scored?.product.imageURL?.contains("openfoodfacts.org") == true)
        #expect(scored?.product.listImageURL != nil)
    }
}
