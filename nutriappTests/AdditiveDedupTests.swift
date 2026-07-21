import Testing
import Foundation
@testable import Sage

struct AdditiveDedupTests {

    @Test func collapsesPolyphosphateHierarchyAndNameAlias() {
        let result = AdditiveDetector.scan(
            ingredientsText: "Seasoning contains sodium hexametaphosphate.",
            offAdditiveTags: ["en:e452", "en:e452i", "en:e452vi"],
            hasUnrecognizedIngredients: false
        )
        let codes = result.additives.map(\.eNumber)
        #expect(codes == ["E452"])
        let poly = try! #require(result.additives.first)
        #expect(Set(poly.detectedAs.map { $0.uppercased() }).isSuperset(of: ["E452I", "E452VI"])
                || poly.detectedAs.count >= 2)

        let products = result.additives.map { AdditiveCatalog.productAdditive(from: $0) }
        #expect(products.count == 1)
        #expect(products[0].risk == .moderate)
        #expect(products[0].name.localizedCaseInsensitiveContains("polyphosphate"))
        #expect(SeverityBar.counts(for: products)[.unrated] == nil
                || SeverityBar.counts(for: products)[.unrated] == 0)
    }

    @Test func collapsesLecithinSubtypes() {
        let result = AdditiveDetector.scan(
            ingredientsText: nil,
            offAdditiveTags: ["en:e322", "en:e322ii"],
            hasUnrecognizedIngredients: false
        )
        #expect(result.additives.map(\.eNumber) == ["E322"])
        let mapped = result.additives.map { AdditiveCatalog.productAdditive(from: $0) }
        #expect(mapped.count == 1)
        #expect(mapped[0].risk == .low)
    }

    @Test func doesNotMergeDistinctAdditives() {
        let result = AdditiveDetector.scan(
            ingredientsText: nil,
            offAdditiveTags: ["en:e330", "en:e331"],
            hasUnrecognizedIngredients: false
        )
        #expect(Set(result.additives.map(\.eNumber)) == Set(["E330", "E331"]))
    }

    @Test func parentENumberStripsRomanKeepsLetterSubtypes() {
        #expect(AdditiveDetector.parentENumber("E452i") == "E452")
        #expect(AdditiveDetector.parentENumber("E452vi") == "E452")
        #expect(AdditiveDetector.parentENumber("E322ii") == "E322")
        #expect(AdditiveDetector.parentENumber("E150d") == "E150d")
        #expect(AdditiveDetector.parentENumber("en:e452i") == "E452")
    }

    @Test func severityCountsIncludeUnratedAndSumToTotal() {
        let additives = [
            ProductAdditive(name: "A", risk: .low, code: "e330"),
            ProductAdditive(name: "B", risk: .moderate, code: "e452"),
            ProductAdditive(name: "C", risk: .high, code: "e250"),
            ProductAdditive(name: "D", risk: .unrated, code: "e999"),
            ProductAdditive(name: "E", risk: .unrated, code: "e998"),
        ]
        let counts = SeverityBar.counts(for: additives)
        let sum = (counts[.low] ?? 0) + (counts[.moderate] ?? 0)
            + (counts[.high] ?? 0) + (counts[.unrated] ?? 0)
        #expect(sum == additives.count)
        #expect(counts[.unrated] == 2)
        #expect(counts[.low] == 1)
    }

    @Test func knowledgeBaseRatesMonoDiglyceridesLow() {
        let hit = Additive(eNumber: "E471", tier: .mild,
                           commonName: "Mono- & diglycerides")
        let p = AdditiveCatalog.productAdditive(from: hit)
        #expect(p.risk == .low)
        #expect(p.note != nil && !(p.note!.isEmpty))
    }
}
