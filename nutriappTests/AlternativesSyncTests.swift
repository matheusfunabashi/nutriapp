import Testing
import Foundation
@testable import Sage

/// Guards iOS ↔ Worker alternatives drift + ruleset stamp discipline.
struct AlternativesSyncTests {

    @Test func bundledMatchesBackendAlternativesBytes() throws {
        let bundle = Bundle(for: AlternativesSyncToken.self)
        let appURL = Bundle.main.url(forResource: "Alternatives", withExtension: "json")
            ?? bundle.url(forResource: "Alternatives", withExtension: "json")
        let appData = try #require(appURL.flatMap { try? Data(contentsOf: $0) })

        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let backendURL = repoRoot.appendingPathComponent("backend/src/alternatives.json")
        let backendData = try Data(contentsOf: backendURL)

        #expect(appData == backendData,
                "Sage/Alternatives.json and backend/src/alternatives.json must be byte-identical.")
    }

    @Test func alternativesRulesetVersionMatchesBundledRuleset() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let altURL = repoRoot.appendingPathComponent("Sage/Alternatives.json")
        let altData = try Data(contentsOf: altURL)
        let alt = try JSONDecoder().decode(AlternativesFile.self, from: altData)
        #expect(alt.rulesetVersion == RulesetV4.bundled.version,
                "alternatives.json ruleset_version (\(alt.rulesetVersion ?? "nil")) must match bundled ruleset (\(RulesetV4.bundled.version)). Regenerate via TopRatedBuilder.")
    }
}

private final class AlternativesSyncToken {}
