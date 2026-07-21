import Testing
import Foundation
@testable import Sage

/// Guards iOS ↔ Worker ruleset drift (SCORING_V5 §9c).
struct RulesetSyncTests {

    @Test func bundledMatchesBackendRulesetBytes() throws {
        let bundle = Bundle(for: BundleToken.self)
        // Prefer the app target resource; fall back to repo path for SPM/test host.
        let appURL = Bundle.main.url(forResource: "RulesetV5", withExtension: "json")
            ?? bundle.url(forResource: "RulesetV5", withExtension: "json")
        let appData = try #require(appURL.flatMap { try? Data(contentsOf: $0) })

        // Locate backend/src/ruleset.json relative to this source file.
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent() // nutriappTests
            .deletingLastPathComponent() // repo
        let backendURL = repoRoot.appendingPathComponent("backend/src/ruleset.json")
        let backendData = try Data(contentsOf: backendURL)

        #expect(appData == backendData,
                "Sage/RulesetV5.json and backend/src/ruleset.json must be byte-identical. Run: cp Sage/RulesetV5.json backend/src/ruleset.json")
    }
}

/// Token so Bundle(for:) resolves the test bundle that also embeds RulesetV5 when needed.
private final class BundleToken {}
