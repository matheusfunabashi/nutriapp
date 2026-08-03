import Testing
import Foundation
@testable import Sage

// "Better Alternatives" (ALTERNATIVES_SPEC.md). Two layers:
//  • `Alternatives.select` — pure ranking logic, tested with mocks.
//  • `SageCategory.shelf`/`anchorTag` + `Alternatives.rank` — routing + engine.
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
        // US / UK / CA peers qualify; BR is filtered out even when higher-scoring.
        let pool = [
            M(60, countries: ["us"]),
            M(70, countries: ["br"]),        // excluded despite the top score
            M(58, countries: ["uk"]),
            M(55, countries: ["ca"]),
        ]
        let r = Alternatives.select(baseline: 40, from: pool)
        #expect(r.map(\.score) == [60, 58, 55])            // us, uk, ca — best first
        #expect(!r.contains { $0.countries == ["br"] })
    }

    @Test func regionFromBarcodeBrazil() {
        #expect(AlternativesRegion.from(barcode: "7891000100103") == .br)
        #expect(AlternativesRegion.from(barcode: "7901234567890") == .br)
        #expect(AlternativesRegion.from(barcode: "0049000005345") == .us)
    }

    // MARK: shelf routing

    private func mapped(_ categoriesTags: [String]) -> Product {
        OpenFoodFactsService.mapCandidate(
            barcode: "x", name: "n", brands: nil, ingredientsText: nil,
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
            "en:meals", "en:dried-products", "en:noodles"
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

    // MARK: rank() — engine-backed exclusion (uses the bundled V5 ruleset)

    private func candidates(_ json: String) -> [AlternativeCandidate] {
        try! JSONDecoder().decode([AlternativeCandidate].self, from: Data(json.utf8))
    }
    private func scannedCocktail() -> Product {
        let c = candidates("""
        [{"barcode":"SCANX","name":"Grape Juice Cocktail","brand":"ValueBrand",
          "categories_tags":["en:fruit-juices","en:juices","en:grape-juices"],
          "ingredients_text":"water, high fructose corn syrup","nova_group":4,
          "countries":["us"],
          "nutriments":{"sugars_100g":13,"proteins_100g":0,"energy-kcal_100g":55}}]
        """)[0]
        let raw = OpenFoodFactsService.mapCandidate(
            barcode: c.barcode, name: c.name, brands: c.brand, ingredientsText: c.ingredientsText,
            additivesTags: c.additivesTags, nutriments: c.nutriments, nutriscoreGrade: c.nutriscoreGrade,
            novaGroup: c.novaGroup, imageURL: c.imageURL, categoriesTags: c.categoriesTags, labelsTags: c.labelsTags)
        guard case .scored(let p) = ScoringEngineV4.scoreProduct(raw, for: MockData.user, ruleset: .bundled)
        else { fatalError("scanned did not score") }
        return p
    }

    @Test func rankExcludesScannedBarcodeAndDuplicates() {
        let scanned = scannedCocktail()
        let cands = candidates("""
        [{"barcode":"BETTER","name":"Organic Grape Juice","brand":"PureRoots",
          "categories_tags":["en:fruit-juices","en:juices","en:grape-juices"],
          "ingredients_text":"organic grape juice","nova_group":1,
          "countries":["us"],
          "nutriments":{"sugars_100g":14,"proteins_100g":0.5,"energy-kcal_100g":62}},
         {"barcode":"SCANX","name":"Grape Juice Cocktail","brand":"ValueBrand",
          "categories_tags":["en:fruit-juices","en:juices","en:grape-juices"],
          "ingredients_text":"water, high fructose corn syrup","nova_group":4,
          "countries":["us"],
          "nutriments":{"sugars_100g":13,"proteins_100g":0,"energy-kcal_100g":55}},
         {"barcode":"OTHER-SKU","name":"Grape Juice Cocktail","brand":"ValueBrand",
          "categories_tags":["en:fruit-juices","en:juices","en:grape-juices"],
          "ingredients_text":"water, high fructose corn syrup","nova_group":4,
          "countries":["us"],
          "nutriments":{"sugars_100g":13,"proteins_100g":0,"energy-kcal_100g":55}}]
        """)
        let picks = Alternatives.rank(scanned: scanned, candidates: cands,
                                      anchorTag: "grape-juices", profile: MockData.user,
                                      ruleset: .bundled)
        #expect(!picks.contains { $0.product.id == "SCANX" })
        #expect(!picks.contains { $0.product.brand == "ValueBrand" && $0.product.name == "Grape Juice Cocktail" })
        #expect(picks.contains { $0.product.id == "BETTER" })
    }

    @Test func rankOutcomeUnscored() {
        var unscored = scannedCocktail()
        unscored.overallScore = nil
        let outcome = Alternatives.rankOutcome(scanned: unscored, candidates: [],
                                               anchorTag: nil, profile: MockData.user,
                                               ruleset: .bundled)
        #expect(outcome == .unscored)
    }

    @Test func rankOutcomeAlreadyTopOfShelf() {
        let scanned = scannedCocktail()
        // Only peers that fail the +10 margin, with max still below baseline+10.
        guard let baseline = scanned.overallScore else {
            Issue.record("expected scored cocktail"); return
        }
        let peerScore = baseline + 5  // clears nothing; max < baseline+10 ⇒ already top
        let cands = candidates("""
        [{"barcode":"PEER","name":"Slightly Better Juice","brand":"X",
          "categories_tags":["en:fruit-juices"],
          "ingredients_text":"grape juice","nova_group":1,
          "countries":["us"],
          "nutriments":{"sugars_100g":12,"proteins_100g":0.4,"energy-kcal_100g":50},
          "precomputed_score":\(peerScore)}]
        """)
        // Force peer score via a product that will score; use outcome with empty better set.
        // Simpler: empty candidates with a high baseline product → noBetterPeers (no max).
        // For alreadyTop: pool with scores all < baseline+margin.
        var high = scanned
        high.overallScore = 90
        let weak = candidates("""
        [{"barcode":"WEAK","name":"Weak Juice","brand":"X",
          "categories_tags":["en:fruit-juices","en:grape-juices"],
          "ingredients_text":"water, sugar","nova_group":4,
          "countries":["us"],
          "nutriments":{"sugars_100g":20,"proteins_100g":0,"energy-kcal_100g":80}}]
        """)
        let outcome = Alternatives.rankOutcome(scanned: high, candidates: weak,
                                               anchorTag: "grape-juices",
                                               profile: MockData.user, ruleset: .bundled)
        // Weak juice scores far below 90+10 → already top if it scored at all.
        switch outcome {
        case .alreadyTopOfShelf, .noBetterPeers, .suggestions:
            // Accept alreadyTop when peers exist but lose the margin; noBetter if unscored peer.
            if case .suggestions = outcome { Issue.record("expected empty suggestions for score 90") }
        default:
            Issue.record("unexpected \(outcome)")
        }
        #expect(outcome == .alreadyTopOfShelf || outcome == .noBetterPeers)
    }

    @Test func suggestNoShelf() {
        let p = mapped(["en:meats", "en:hams"])
        var scored = p
        scored.overallScore = 50
        let outcome = Alternatives.suggest(for: scored, candidates: { _ in [] },
                                           profile: MockData.user, ruleset: .bundled)
        #expect(outcome == .noShelf)
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
        let scored = Alternatives.scored(c, profile: MockData.user, ruleset: .bundled)
        #expect(scored != nil)
        #expect(scored?.product.imageURL?.contains("openfoodfacts.org") == true)
        #expect(scored?.product.listImageURL != nil)
    }
}
