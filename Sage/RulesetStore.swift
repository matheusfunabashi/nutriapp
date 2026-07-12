import Foundation

/// Where the last downloaded ruleset is persisted between launches.
private func rulesetFileURL() -> URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                       in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("RulesetV4.json")
}

/// Holds the active scoring-v4 ruleset: the last successfully downloaded copy
/// if one exists and decodes, else the bundled default (SCORING_V4.md §10).
///
/// Engineering contract (§11): the refresh is fire-and-forget — it is never
/// awaited on the launch or scan path, and offline simply means the current
/// ruleset keeps working. A downloaded ruleset only replaces the active one
/// after it has fully decoded, so a corrupt download can never brick scoring.
@MainActor
enum RulesetStore {

    private(set) static var current: RulesetV4 = {
        if let data = try? Data(contentsOf: rulesetFileURL()),
           let rs = try? JSONDecoder().decode(RulesetV4.self, from: data) {
            return rs
        }
        return .bundled
    }()

    /// Detached background refresh: cheap version probe first, full download
    /// only on mismatch. Safe to call on every launch.
    static func refreshInBackground(backend: BackendService) {
        let activeVersion = current.version
        Task.detached(priority: .utility) {
            guard let remote = await backend.rulesetVersion(),
                  remote != activeVersion,
                  let (data, rs) = await backend.fetchRuleset()
            else { return }
            try? data.write(to: rulesetFileURL(), options: .atomic)
            await MainActor.run { current = rs }
        }
    }
}
