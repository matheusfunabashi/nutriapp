import Foundation

/// Where the last downloaded ruleset is persisted between launches.
private func rulesetFileURL() -> URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                       in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("RulesetV5.json")
}

/// Holds the active scoring-v5 ruleset: the last successfully downloaded copy
/// if one exists and decodes, else the bundled default (SCORING_V5.md).
///
/// V5.1.0 kill switch: `flags.rulesetV510Enabled` (ruleset JSON + UserDefaults
/// cache, hardcoded default `true`). When false, `current` is the frozen
/// bundled v5.0.9 ruleset and v5.1.0 engine paths stay off.
@MainActor
enum RulesetStore {

    private static let flagKey = "rulesetV510Enabled"
    /// Hardcoded default when nothing is cached / remote yet.
    static let hardcodedV510Default = true

    private static var _active: RulesetV4 = {
        let bundled = RulesetV4.bundled
        if let data = try? Data(contentsOf: rulesetFileURL()),
           let rs = try? JSONDecoder().decode(RulesetV4.self, from: data),
           rs.version >= bundled.version {
            if let flag = rs.flags?.rulesetV510Enabled {
                UserDefaults.standard.set(flag, forKey: flagKey)
            }
            return rs
        }
        return bundled
    }()

    /// Remote / cached kill switch. Default ON.
    static var v510Enabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: flagKey) != nil {
                return UserDefaults.standard.bool(forKey: flagKey)
            }
            return hardcodedV510Default
        }
        set { UserDefaults.standard.set(newValue, forKey: flagKey) }
    }

    /// Ruleset used for scoring. Kill switch OFF → frozen v5.0.9.
    static var current: RulesetV4 {
        v510Enabled ? _active : .bundledV509
    }

    /// Detached background refresh: cheap version probe first, full download
    /// only when the server has a *strictly newer* ruleset.
    static func refreshInBackground(backend: BackendService) {
        let activeVersion = _active.version
        Task.detached(priority: .utility) {
            guard let remote = await backend.rulesetVersion(),
                  remote > activeVersion,
                  let (data, rs) = await backend.fetchRuleset()
            else { return }
            try? data.write(to: rulesetFileURL(), options: .atomic)
            await MainActor.run {
                if let flag = rs.flags?.rulesetV510Enabled {
                    v510Enabled = flag
                }
                _active = rs
            }
        }
    }

    /// Test / debug override.
    static func setActiveForTesting(_ rs: RulesetV4) {
        _active = rs
        if let flag = rs.flags?.rulesetV510Enabled {
            v510Enabled = flag
        }
    }
}
