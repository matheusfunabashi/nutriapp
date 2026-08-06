import Testing
import Foundation
@testable import Sage

// Top Rated v1 (TOPRATED_SPEC.md). The pure ranking is tested with injected
// candidates; the category-population checks use the bundled seed.
@MainActor
struct TopRatedTests {

    private func candidates(_ json: String) -> [AlternativeCandidate] {
        try! JSONDecoder().decode([AlternativeCandidate].self, from: Data(json.utf8))
    }

    @Test func itemsCapAtTwentyAndSortDescending() {
        // 22 sodas with increasing sugar → decreasing Overall. items() keeps the
        // best 20, ordered high→low, and drops the two worst.
        let entries = (0..<22).map { i in
            """
            {"barcode":"B\(i)","name":"Soda \(i)","brand":"Br\(i)",
             "countries":["us"],
             "categories_tags":["en:beverages","en:sodas"],
             "ingredients_text":"carbonated water, sugar","nova_group":4,
             "nutriments":{"sugars_100g":\(i),"added-sugars_100g":\(i),"energy-kcal_100g":40}}
            """
        }
        let items = TopRated.items(from: candidates("[\(entries.joined(separator: ","))]"),
                                   profile: MockData.user, ruleset: .bundled)
        #expect(items.count == 20)                                            // capped
        #expect(items.map(\.score) == items.map(\.score).sorted(by: >))       // best first
        #expect(!items.contains { $0.product.name == "Soda 21" })             // worst dropped
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
        let pool = candidates("""
        [
          {"barcode":"BR1","name":"Guarana Zero","brand":"Antarctica",
           "countries":["br"],"categories_tags":["en:sodas"],
           "ingredients_text":"water, sweetener","nova_group":4,
           "nutriments":{"sugars_100g":0,"energy-kcal_100g":1}},
          {"barcode":"US1","name":"Diet Cola","brand":"ColaCo",
           "countries":["us"],"categories_tags":["en:sodas"],
           "ingredients_text":"water, sweetener","nova_group":4,
           "nutriments":{"sugars_100g":0,"energy-kcal_100g":1}},
          {"barcode":"BOTH","name":"Shared Cola","brand":"Global",
           "countries":["us","br"],"categories_tags":["en:sodas"],
           "ingredients_text":"water, sweetener","nova_group":4,
           "nutriments":{"sugars_100g":0,"energy-kcal_100g":1}}
        ]
        """)
        let items = TopRated.items(from: pool, profile: MockData.user, ruleset: .bundled,
                                   markets: ["us"])
        #expect(items.map(\.product.id).sorted() == ["BOTH", "US1"])
        #expect(items.allSatisfy { $0.countries.contains("us") })
    }

    @Test func energyDrinksTopRatedIsUSOnly() {
        #expect(TopRated.allowedMarkets(for: .energyDrinks) == ["us"])
        let pool = candidates("""
        [
          {"barcode":"UK1","name":"Prime Punch","brand":"PRIME",
           "countries":["uk"],"categories_tags":["en:energy-drinks"],
           "ingredients_text":"water, sugar, caffeine","nova_group":4,
           "nutriments":{"sugars_100g":0,"energy-kcal_100g":10,"caffeine_100g":0.032}},
          {"barcode":"CA1","name":"Guru Lite","brand":"Guru",
           "countries":["ca"],"categories_tags":["en:energy-drinks"],
           "ingredients_text":"water, organic cane sugar","nova_group":4,
           "nutriments":{"sugars_100g":5,"energy-kcal_100g":20}},
          {"barcode":"US1","name":"Celsius Tropical","brand":"CELSIUS",
           "countries":["us"],"categories_tags":["en:energy-drinks"],
           "ingredients_text":"carbonated water, caffeine","nova_group":4,
           "nutriments":{"sugars_100g":0,"energy-kcal_100g":10,"caffeine_100g":0.032}},
          {"barcode":"USUK","name":"Shared Can","brand":"Global",
           "countries":["us","uk"],"categories_tags":["en:energy-drinks"],
           "ingredients_text":"water, caffeine","nova_group":4,
           "nutriments":{"sugars_100g":0,"energy-kcal_100g":10}}
        ]
        """)
        let items = TopRated.items(from: pool, profile: MockData.user, ruleset: .bundled,
                                   markets: TopRated.allowedMarkets(for: .energyDrinks))
        #expect(items.map(\.product.id).sorted() == ["US1", "USUK"])
        #expect(items.allSatisfy { $0.countries.contains("us") })
        #expect(!items.contains { $0.product.id == "UK1" || $0.product.id == "CA1" })
    }
}
