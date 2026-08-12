import Testing
import Foundation
@testable import Sage

/// Real-world corpus validation: every captured OFF beverage payload
/// (Fixtures/Bulk/, fetched from the live API, plus the original captured
/// fixtures) must route and score without violating structural invariants.
/// This is where OFF's data noise lives — junk tags, missing fields,
/// panel-reference servings, localized ingredient text.
@Suite(.serialized)
struct BulkOFFValidationTests {

    private static func fixtureURLs() -> [URL] {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let bulk = dir.appendingPathComponent("Bulk")
        let fm = FileManager.default
        var urls: [URL] = []
        for d in [dir, bulk] {
            let items = (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? []
            urls += items.filter { $0.lastPathComponent.hasPrefix("off_")
                && $0.pathExtension == "json" }
        }
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func load(_ url: URL) -> Product? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let code = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "off_", with: "")
        return try? OpenFoodFactsService.makeProduct(from: data, barcode: code)
    }

    /// Corpus must be present and non-trivial (guards against a silently
    /// empty directory making this suite vacuous).
    @Test func corpusIsNonTrivial() {
        #expect(Self.fixtureURLs().count >= 30,
                "expected ≥30 captured payloads, got \(Self.fixtureURLs().count)")
    }

    /// Every payload: parses or is skipped explicitly; if scored, the score is
    /// in [10, 100], deterministic, and structurally sane.
    @Test func corpusScoresAreSaneAndDeterministic() {
        var scored = 0, unsupported = 0, unparseable = 0
        for url in Self.fixtureURLs() {
            guard let p = load(url) else { unparseable += 1; continue }
            guard let r1 = ScoringEngineV4.score(p) else { unsupported += 1; continue }
            let r2 = ScoringEngineV4.score(p)!
            #expect(r1.base == r2.base, "\(p.name) nondeterministic")
            #expect((10...100).contains(r1.base),
                    "\(p.name) score \(r1.base) out of range")
            if let bd = r1.drinksBreakdown {
                #expect(bd.effectiveServingMl >= 30 && bd.effectiveServingMl <= 600,
                        "\(p.name) absurd serving \(bd.effectiveServingMl)ml")
                // A liquid serving requires liquid evidence somewhere: parseable
                // volume, or the documented 355ml fallback flagged as estimated.
                let hasVolume = DrinksScoring.parseVolumeMilliliters(p.size) != nil
                    || DrinksScoring.parseVolumeMilliliters(p.servingSize) != nil
                if !hasVolume {
                    #expect(bd.estimatedServing,
                            "\(p.name): no volume evidence but unflagged serving")
                }
            }
            scored += 1
        }
        print("BULK CORPUS: \(scored) scored, \(unsupported) unsupported, \(unparseable) unparseable")
        #expect(scored >= 20, "corpus should score at least 20 products")
    }

    /// Distribution table for eyeballing — every corpus product with its
    /// route, score, and binding cap.
    @Test func printCorpusDistribution() {
        var lines = ["=== BULK OFF CORPUS ==="]
        for url in Self.fixtureURLs() {
            guard let p = load(url) else {
                lines.append("\(url.lastPathComponent)\tUNPARSEABLE"); continue
            }
            let route = ScoringEngineV4.route(p)
            guard let r = ScoringEngineV4.score(p) else {
                lines.append("\(String(p.name.prefix(34)))\t-\t\(route)"); continue
            }
            let bind = r.drinksBreakdown?.bindingCapId ?? "-"
            lines.append("\(String(p.name.prefix(34)))\t\(r.base)\t\(r.profileId)\t\(bind)")
        }
        print(lines.joined(separator: "\n"))
    }
}
