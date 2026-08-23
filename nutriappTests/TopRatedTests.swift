import Testing
import Foundation
@testable import Sage

// Top Rated v1 (TOPRATED_SPEC.md). The pure ranking is tested with injected
// candidates; the category-population checks use the bundled seed.
//
// Fixtures carry a full core-nutrition table (kcal, sugar, satfat, sodium,
// protein) because Top Rated's eligibility gate requires real label data —
// a nutrition table, ingredients, and known NOVA — before a product may rank.
@MainActor
struct TopRatedTests {

    private func candidates(_ json: String) -> [AlternativeCandidate] {
        try! JSONDecoder().decode([AlternativeCandidate].self, from: Data(json.utf8))
    }

    /// A gate-complete US soda candidate; `sugar` varies the score.
    private func soda(_ barcode: String, name: String, brand: String,
                      sugar: Int, countries: String = "\"us\"",
                      imageURL: String? = nil) -> String {
        """
        {"barcode":"\(barcode)","name":"\(name)","brand":"\(brand)",
         "countries":[\(countries)],
         \(imageURL.map { "\"image_url\":\"\($0)\"," } ?? "")
         "categories_tags":["en:beverages","en:sodas"],
         "ingredients_text":"carbonated water, sugar","nova_group":4,
         "nutriments":{"sugars_100g":\(sugar),"added-sugars_100g":\(sugar),
                       "energy-kcal_100g":40,"sodium_100g":0.01,
                       "proteins_100g":0,"saturated-fat_100g":0}}
        """
    }

    @Test func itemsCapAtMaxItemsAndSortDescending() {
        // 12 sodas with increasing sugar → decreasing Overall. items() keeps
        // the best 10, ordered high→low, and drops the worst.
        let entries = (0..<12).map {
            soda("B\($0)", name: "Soda \($0)", brand: "Br\($0)", sugar: $0)
        }
        let items = TopRated.items(from: candidates("[\(entries.joined(separator: ","))]"),
                                   profile: MockData.user, ruleset: .bundled)
        #expect(TopRated.maxItems == 10)
        #expect(items.count == TopRated.maxItems)                             // capped
        #expect(items.map(\.score) == items.map(\.score).sorted(by: >))       // best first
        #expect(!items.contains { $0.product.name == "Soda 11" })             // worst dropped
    }

    @Test func waterAndCoffeeHaveNoTopRated() {
        // The two excluded categories carry no data (TOPRATED_SPEC §2).
        #expect(SageCategory.water.hasTopRated == false)
        #expect(SageCategory.coffee.hasTopRated == false)
    }

    @Test func populatedCategoryYieldsRankedList() {
        let items = TopRated.items(for: .soda, profile: MockData.user)
        #expect(!items.isEmpty)
        #expect(items.count <= TopRated.maxItems)
        #expect(items.map(\.score) == items.map(\.score).sorted(by: >))
    }

    @Test func itemsAreUSOnly() {
        // Alternatives shelves mix `us` + `br`. Top Rated must drop non-US
        // candidates even when they outscore US peers (TOPRATED_SPEC §8).
        let pool = candidates("[" + [
            soda("BR1", name: "Guarana Zero", brand: "Antarctica", sugar: 0,
                 countries: "\"br\""),
            soda("US1", name: "Diet Cola", brand: "ColaCo", sugar: 0),
            soda("BOTH", name: "Shared Cola", brand: "Global", sugar: 0,
                 countries: "\"us\",\"br\""),
        ].joined(separator: ",") + "]")
        let items = TopRated.items(from: pool, profile: MockData.user, ruleset: .bundled,
                                   markets: ["us"])
        #expect(items.map(\.product.id).sorted() == ["BOTH", "US1"])
        #expect(items.allSatisfy { $0.countries.contains("us") })
    }

    @Test func topRatedIsUSOnlyForEveryShelf() {
        // TOPRATED_SPEC §8 — the browse tab is US-only. The dataset still
        // carries UK/CA/BR candidates, but both Top Rated and Better Options
        // now filter to US, so those never surface.
        #expect(SageCategory.allCases.allSatisfy {
            TopRated.allowedMarkets(for: $0) == ["us"]
        })
    }

    @Test func energyDrinksTopRatedIsUSOnly() {
        #expect(TopRated.allowedMarkets(for: .energyDrinks) == ["us"])
        let pool = candidates("[" + [
            soda("UK1", name: "Prime Punch", brand: "PRIME", sugar: 0,
                 countries: "\"uk\""),
            soda("CA1", name: "Guru Lite", brand: "Guru", sugar: 5,
                 countries: "\"ca\""),
            soda("US1", name: "Celsius Tropical", brand: "CELSIUS", sugar: 0),
            soda("USUK", name: "Shared Can", brand: "Global", sugar: 0,
                 countries: "\"us\",\"uk\""),
        ].joined(separator: ",") + "]")
        let items = TopRated.items(from: pool, profile: MockData.user, ruleset: .bundled,
                                   markets: TopRated.allowedMarkets(for: .energyDrinks))
        #expect(items.map(\.product.id).sorted() == ["US1", "USUK"])
        #expect(items.allSatisfy { $0.countries.contains("us") })
        #expect(!items.contains { $0.product.id == "UK1" || $0.product.id == "CA1" })
    }

    // MARK: Eligibility gate

    @Test func gateExcludesDataStarvedCandidates() {
        // Missing ingredients, missing NOVA, or a thin nutrition table (fewer
        // than three core fields) must exclude a candidate outright — even
        // though all three still *score* (the engine's minimum bar is lower).
        // Only the complete product may rank.
        let pool = candidates("""
        [
          \(soda("OK", name: "Cola Complete", brand: "A", sugar: 1)),
          {"barcode":"NOING","name":"Cola Mystery","brand":"B",
           "countries":["us"],"categories_tags":["en:sodas"],"nova_group":4,
           "nutriments":{"sugars_100g":0,"energy-kcal_100g":1,"sodium_100g":0.01,
                         "proteins_100g":0,"saturated-fat_100g":0}},
          {"barcode":"NONOVA","name":"Cola NoNova","brand":"C",
           "countries":["us"],"categories_tags":["en:sodas"],
           "ingredients_text":"water, sugar",
           "nutriments":{"sugars_100g":0,"energy-kcal_100g":1,"sodium_100g":0.01,
                         "proteins_100g":0,"saturated-fat_100g":0}},
          {"barcode":"THIN","name":"Cola Thin","brand":"D",
           "countries":["us"],"categories_tags":["en:sodas"],
           "ingredients_text":"water, sugar","nova_group":4,
           "nutriments":{"sugars_100g":0,"energy-kcal_100g":1}}
        ]
        """)
        let items = TopRated.items(from: pool, profile: MockData.user, ruleset: .bundled)
        #expect(items.map(\.product.id) == ["OK"])
    }

    @Test func provisionalMilkStillEligible() {
        // V5.6: retail fluid milk is pasteurized by law unless labelled raw,
        // so the processing default became evidence and a fully documented
        // milk no longer wears the provisional banner at all — and is
        // eligible for Top Rated.
        let pool = candidates("""
        [{"barcode":"MILK1","name":"Whole Milk","brand":"Dairy Co",
          "countries":["us"],"categories_tags":["en:dairies","en:milks","en:whole-milks"],
          "ingredients_text":"milk, vitamin d3","nova_group":1,
          "nutriments":{"sugars_100g":5,"energy-kcal_100g":66,"sodium_100g":0.054,
                        "proteins_100g":3.3,"saturated-fat_100g":2.1,"fiber_100g":0}}]
        """)
        let items = TopRated.items(from: pool, profile: MockData.user, ruleset: .bundled)
        #expect(items.map(\.product.id) == ["MILK1"])
        #expect(!ScoringEngineV4.isProvisionalScore(items[0].product, ruleset: .bundled))
    }

    // MARK: Variety (brand cap + market-variant dedupe)

    @Test func brandCapKeepsListVaried() {
        // Five SKUs of one brand → only the best two rank; other brands fill
        // the remaining slots even at lower scores.
        let entries = (0..<5).map {
            soda("HD\($0)", name: "Vanilla \($0)", brand: "Haagen-Dazs", sugar: $0)
        } + [soda("OTHER", name: "Root Beer", brand: "Small Batch", sugar: 9)]
        let items = TopRated.items(from: candidates("[\(entries.joined(separator: ","))]"),
                                   profile: MockData.user, ruleset: .bundled)
        #expect(items.count == 3)
        #expect(items.filter { $0.product.brand == "Haagen-Dazs" }.count == TopRated.maxPerBrand)
        #expect(items.contains { $0.product.id == "OTHER" })
        // The two kept SKUs are the brand's best-scoring ones.
        #expect(items.map(\.product.id).contains("HD0"))
        #expect(items.map(\.product.id).contains("HD1"))
    }

    @Test func brandCapBucketsAliases() {
        // "Quaker" and "Quaker Oats" are one brand: together they get
        // maxPerBrand slots, not maxPerBrand each.
        let entries = [
            soda("Q1", name: "Steel Cut Oats", brand: "Quaker", sugar: 0),
            soda("Q2", name: "Quick Oats", brand: "Quaker Oats", sugar: 1),
            soda("Q3", name: "Old Fashioned Oats", brand: "Quaker", sugar: 2),
            soda("Q4", name: "One Minute Oats", brand: "Quaker Oats", sugar: 3),
            soda("OTHER", name: "Rolled Oats", brand: "Bob's Red Mill", sugar: 9),
        ]
        let items = TopRated.items(from: candidates("[\(entries.joined(separator: ","))]"),
                                   profile: MockData.user, ruleset: .bundled)
        #expect(items.filter { $0.product.brand.hasPrefix("Quaker") }.count == TopRated.maxPerBrand)
        #expect(items.contains { $0.product.id == "OTHER" })
    }

    @Test func marketVariantsCollapseToUSVariant() {
        // The same product listed per-market (diacritics, size suffix, separate
        // barcodes) is one row, and the US variant wins the score tie — its
        // barcode resolves to a real pack shot on the backend.
        let pool = candidates("[" + [
            soda("CA9", name: "Crème Glacée Vanille 500 ml", brand: "Häagen-Dazs",
                 sugar: 2, countries: "\"ca\""),
            soda("US9", name: "Creme Glacee Vanille", brand: "Haagen-Dazs", sugar: 2),
        ].joined(separator: ",") + "]")
        let items = TopRated.items(from: pool, profile: MockData.user, ruleset: .bundled)
        #expect(items.map(\.product.id) == ["US9"])
    }

    @Test func listKeyFoldsDiacriticsAndUnits() {
        #expect(TopRated.listKey(brand: "Häagen-Dazs", name: "Crème Glacée Vanille 500 ml")
                == TopRated.listKey(brand: "Haagen-Dazs", name: "Creme Glacee Vanille"))
        #expect(TopRated.listKey(brand: "Quaker", name: "Quick Oats 1 kg")
                == TopRated.listKey(brand: "Quaker", name: "Quick Oats"))
        // Different products must not collide.
        #expect(TopRated.listKey(brand: "Quaker", name: "Quick Oats")
                != TopRated.listKey(brand: "Quaker", name: "Steel Cut Oats"))
    }

    // MARK: Image quality preference

    @Test func goodImagesFillBeforeLowImages() {
        // Top Rated is a visual surface: a pack-shot candidate outranks a
        // higher-scoring kitchen-counter photo, which still fills a later
        // slot rather than vanishing. Un-annotated candidates count as good.
        let pool = candidates("""
        [
          {"barcode":"LOWIMG","name":"Best Cola","brand":"A","countries":["us"],
           "image_quality":"low",
           "categories_tags":["en:sodas"],
           "ingredients_text":"water, sugar","nova_group":4,
           "nutriments":{"sugars_100g":0,"energy-kcal_100g":1,"sodium_100g":0.01,
                         "proteins_100g":0,"saturated-fat_100g":0}},
          {"barcode":"GOODIMG","name":"Good Cola","brand":"B","countries":["us"],
           "image_quality":"good",
           "categories_tags":["en:sodas"],
           "ingredients_text":"water, sugar","nova_group":4,
           "nutriments":{"sugars_100g":5,"energy-kcal_100g":20,"sodium_100g":0.01,
                         "proteins_100g":0,"saturated-fat_100g":0}},
          {"barcode":"NOANNO","name":"Legacy Cola","brand":"C","countries":["us"],
           "categories_tags":["en:sodas"],
           "ingredients_text":"water, sugar","nova_group":4,
           "nutriments":{"sugars_100g":9,"energy-kcal_100g":40,"sodium_100g":0.01,
                         "proteins_100g":0,"saturated-fat_100g":0}}
        ]
        """)
        let items = TopRated.items(from: pool, profile: MockData.user, ruleset: .bundled)
        #expect(items.map(\.product.id) == ["GOODIMG", "NOANNO", "LOWIMG"])
    }

    // MARK: Image fallback (item 5a)

    @Test func scoredCandidateKeepsOFFFallbackImage() throws {
        // US candidates point at the backend pack-shot slot, but the dataset's
        // own OFF photo must survive as the fallback so a backend 404 degrades
        // to a real photo instead of the glyph.
        let off = "https://images.openfoodfacts.org/images/products/012/345/678/9012/front_en.3.400.jpg"
        let pool = candidates("[" +
            soda("0123456789012", name: "Cola", brand: "A", sugar: 1, imageURL: off)
        + "]")
        let scored = Alternatives.scored(pool[0], profile: MockData.user, ruleset: .bundled)
        let product = try #require(scored).product
        #expect(product.imageURL == BackendService.productImageURL(barcode: "0123456789012"))
        #expect(product.imageFallbackURL == off)
    }

    @Test func fallbackOmittedWhenPrimaryIsAlreadyOFF() throws {
        // Non-US candidates keep their OFF photo as the primary (the
        // resolver may rewrite it to another size of the same asset) — no
        // backend URL, and no self-referential fallback.
        let off = "https://images.openfoodfacts.org/images/products/789/100/000/0017/front_pt.2.400.jpg"
        let pool = candidates("""
        [{"barcode":"7891000000017","name":"Guarana","brand":"Antarctica",
          "countries":["br"],"categories_tags":["en:sodas"],
          "image_url":"\(off)",
          "ingredients_text":"water, sugar","nova_group":4,
          "nutriments":{"sugars_100g":5,"energy-kcal_100g":40,"sodium_100g":0.01,
                        "proteins_100g":0,"saturated-fat_100g":0}}]
        """)
        let scored = Alternatives.scored(pool[0], profile: MockData.user, ruleset: .bundled)
        let product = try #require(scored).product
        #expect(product.imageURL?.hasPrefix("https://images.openfoodfacts.org/") == true)
        #expect(product.imageFallbackURL == nil)
    }
}
