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
}
