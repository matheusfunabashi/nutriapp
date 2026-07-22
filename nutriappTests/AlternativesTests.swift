import Testing
import Foundation
@testable import Sage

// "Better Alternatives" v1 (ALTERNATIVES_SPEC.md). Two layers:
//  • `Alternatives.select` — pure ranking logic, tested with mocks (deterministic,
//    no scoring engine).
//  • `SageCategory.shelf`/`anchorTag` + `Alternatives.rank` — routing + the
//    engine-backed path, tested against the bundled V5 ruleset.
struct AlternativesTests {

    // MARK: select() — pure selection (margin · floor preference · order · cap)

    private struct M: RankableAlternative {
        let score: Int; let sharedTag: Bool
        init(_ s: Int, shared: Bool = false) { score = s; sharedTag = shared }
    }

    @Test func selectMarginGateAndFallback() {
        // baseline 40 → need ≥50; none reach the 55 floor, so the margin-only set
        // is returned (junk-shelf fallback). The +9 candidate (49) is dropped.
        let r = Alternatives.select(baseline: 40, from: [M(54), M(52), M(49)])
        #expect(r.map(\.score) == [54, 52])
    }

    @Test func selectPrefersGoodOverMarginOnly() {
        // Both clear the margin (≥50), but a "Good" (≥55) option exists, so the
        // sub-floor 52 is dropped in its favor.
        let r = Alternatives.select(baseline: 40, from: [M(58), M(52)])
        #expect(r.map(\.score) == [58])
    }

    @Test func selectSharedTagRanksFirst() {
        // Lower score but same-subtype tag wins ordering.
        let r = Alternatives.select(baseline: 30, from: [M(50, shared: false), M(45, shared: true)])
        #expect(r.map(\.score) == [45, 50])
        #expect(r.first?.sharedTag == true)
    }

    @Test func selectCapsAtThree() {
        let r = Alternatives.select(baseline: 30, from: [M(41), M(42), M(43), M(44), M(45)])
        #expect(r.count == 3)
        #expect(r.map(\.score) == [45, 44, 43])   // best first
    }

    @Test func selectEmptyWhenNothingClearsMargin() {
        #expect(Alternatives.select(baseline: 70, from: [M(72), M(75)]).isEmpty)
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
        // Coffee is scored but shelf-excluded; water is unsupported; unknown/none
        // → no shelf. All must yield nil so no alternatives row shows (§7).
        #expect(SageCategory.shelf(for: mapped(["en:beverages", "en:coffees"])) == nil)
        #expect(SageCategory.shelf(for: mapped(["en:beverages", "en:waters"])) == nil)
        #expect(SageCategory.shelf(for: mapped(["en:meats", "en:hams"])) == nil)
        #expect(SageCategory.shelf(for: mapped([])) == nil)
    }

    @Test func anchorTagNilWhenOnlyRootTagMatched() {
        let p = mapped(["en:beverages", "en:sodas"])   // shelf root only, no sub-tag
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
        // A better grape juice, plus the scan's own barcode and a same-name SKU.
        let cands = candidates("""
        [{"barcode":"BETTER","name":"Organic Grape Juice","brand":"PureRoots",
          "categories_tags":["en:fruit-juices","en:juices","en:grape-juices"],
          "ingredients_text":"organic grape juice","nova_group":1,
          "nutriments":{"sugars_100g":14,"proteins_100g":0.5,"energy-kcal_100g":62}},
         {"barcode":"SCANX","name":"Grape Juice Cocktail","brand":"ValueBrand",
          "categories_tags":["en:fruit-juices","en:juices","en:grape-juices"],
          "ingredients_text":"water, high fructose corn syrup","nova_group":4,
          "nutriments":{"sugars_100g":13,"proteins_100g":0,"energy-kcal_100g":55}},
         {"barcode":"OTHER-SKU","name":"Grape Juice Cocktail","brand":"ValueBrand",
          "categories_tags":["en:fruit-juices","en:juices","en:grape-juices"],
          "ingredients_text":"water, high fructose corn syrup","nova_group":4,
          "nutriments":{"sugars_100g":13,"proteins_100g":0,"energy-kcal_100g":55}}]
        """)
        let picks = Alternatives.rank(scanned: scanned, candidates: cands,
                                      anchorTag: "grape-juices", profile: MockData.user,
                                      ruleset: .bundled)
        // The scan's own barcode is never suggested…
        #expect(!picks.contains { $0.product.id == "SCANX" })
        // …nor any other SKU of the same product (same brand + name)…
        #expect(!picks.contains { $0.product.brand == "ValueBrand" && $0.product.name == "Grape Juice Cocktail" })
        // …but the genuinely-better grape juice is.
        #expect(picks.contains { $0.product.id == "BETTER" })
    }

    @Test func rankEmptyWhenScanUnscored() {
        // An unscored scan (nil Overall — e.g. water/sweetener) yields nothing.
        var unscored = scannedCocktail()
        unscored.overallScore = nil
        #expect(Alternatives.rank(scanned: unscored, candidates: [], anchorTag: nil,
                                  profile: MockData.user, ruleset: .bundled).isEmpty)
    }
}
