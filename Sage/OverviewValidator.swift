import Foundation

// MARK: - Overview text safety (mirrors backend validator)

enum OverviewValidator {

    private static let additivePresenceEN: [String] = [
        "presence of", "contains", "has additives", "riskier additives",
        "artificial", "preservative", "emulsifier", "thickener",
        "stabilizer", "sweetener",
    ]
    private static let additivePresencePT: [String] = [
        "presença de", "contém", "aditivos", "conservante", "espessante",
    ]
    private static let packagingClaimsEN: [String] = [
        "packaged in plastic", "plastic packaging", "harmful packaging",
    ]
    private static let thinDataPhrases: [String] = [
        "data is thin", "limited data", "provisional", "where data is thin",
        "label data is limited",
    ]

    /// camelCase token like wholeGrain / flourOxidizers (internal rule ids).
    private static let camelCaseToken = try! NSRegularExpression(
        pattern: #"\b[a-z]+[A-Z][a-zA-Z]+\b"#
    )

    /// Returns the matched forbidden phrase, if any.
    static func forbiddenPhrase(in text: String, ctx: ScoringEngineV4.OverviewContext) -> String? {
        // Em dash / en dash — always reject (style, not epistemic).
        if text.contains("\u{2014}") { return "em dash" }
        if text.contains("\u{2013}") { return "en dash" }

        // Fail closed on internal rule identifiers — but allow ids that are also
        // legitimate display topics in this payload (e.g. "authenticity").
        let allowedTopics = Set(
            ctx.rules.map(\.topic)
            + ctx.topPositive.map(\.topic)
            + ctx.topNegative.map(\.topic)
        )
        for id in ctx.knownRuleIds {
            if allowedTopics.contains(id) { continue }
            if text.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: id))\b"#,
                          options: .regularExpression) != nil {
                return id
            }
        }
        let ns = text as NSString
        if let match = camelCaseToken.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            return ns.substring(with: match.range)
        }

        let lower = text.lowercased()
        if !ctx.hasScoreableIngredientSignal {
            for phrase in additivePresenceEN + additivePresencePT where lower.contains(phrase) {
                return phrase
            }
            if lower.range(of: #"\be\d{3}\b"#, options: .regularExpression) != nil {
                return "E-number"
            }
        }
        let s7Unknown = ctx.rules.contains { $0.rule == "S7" && $0.evidenceTier == "unknown-tier" }
        if s7Unknown {
            for phrase in packagingClaimsEN where lower.contains(phrase) {
                return phrase
            }
        }

        let allData = ctx.confidence >= 0.80
            && !ctx.rules.contains { $0.evidenceTier == "unknown-tier" }
        if allData {
            for phrase in thinDataPhrases where lower.contains(phrase) {
                return phrase
            }
        }

        let absDelta = abs(ctx.deltaValue)
        if absDelta == 1 {
            if lower.range(of: #"\b1 points\b"#, options: .regularExpression) != nil
                || lower.range(of: #"\bone points\b"#, options: .regularExpression) != nil {
                return "1 points"
            }
            if lower.contains("points lower") || lower.contains("points higher")
                || lower.contains("points below") || lower.contains("points above") {
                if lower.range(of: #"\b1 points\b"#, options: .regularExpression) != nil {
                    return "1 points"
                }
            }
        }

        // Overall binding cap must be named when present (V5.0.6).
        if let cap = ctx.overallBindingCap {
            let needles: [String] = {
                switch cap.kind {
                case "freeSugar":
                    return ["capped at \(cap.value)", "concentrated sugar", "free sugar", "caloric sweetener"]
                case "transFat":
                    return ["trans fat", "capped at \(cap.value)"]
                case "nns":
                    return ["non-nutritive", "capped at \(cap.value)", "sweetener"]
                default:
                    return ["capped at \(cap.value)"]
                }
            }()
            if !needles.contains(where: { lower.contains($0.lowercased()) }) {
                return "overallBindingCap"
            }
        }

        // Unknown-tier rules cannot be described as measured deficiencies.
        for rule in ctx.rules where rule.evidenceTier == "unknown-tier" {
            let topic = rule.topic.lowercased()
            let missingOk = lower.contains("missing") || lower.contains("unknown")
                || lower.contains("can't verify") || lower.contains("cannot verify")
                || lower.contains("no ") || lower.contains("data is")
            let measuredHit = lower.contains("held back by \(topic)")
                || lower.contains("held back mainly by \(topic)")
                || lower.contains("low \(topic)")
                || lower.contains("limited \(topic)")
                || (rule.rule == "S13" && (
                    lower.contains("held back by micronutrient")
                    || lower.contains("limited micronutrient")
                    || lower.contains("low micronutrient")
                ))
            if measuredHit && !missingOk {
                return rule.topic
            }
        }

        // Fiber is a real contributor only when the payload mentions it — a rule /
        // contributor topic referencing fiber (the generic S12 "protein and
        // fiber") or a displayed nutrient level. Dairy (milk / yogurt / cheese)
        // scores protein + calcium and has no fiber, so a fiber claim there is
        // invented and must fall back to the template.
        let fiberInPayload = ctx.rules.contains { $0.topic.lowercased().contains("fiber") }
            || ctx.topPositive.contains { $0.topic.lowercased().contains("fiber") }
            || ctx.topNegative.contains { $0.topic.lowercased().contains("fiber") }
            || ctx.deltaDrivers.contains { $0.topic.lowercased().contains("fiber") }
            || ctx.nutrientLevels.contains { $0.lowercased().contains("fiber") }
        if !fiberInPayload,
           lower.range(of: #"\bfib(?:er|re)s?\b"#, options: .regularExpression) != nil {
            return "fiber not in payload"
        }

        // List-claims may only name avoidMatches / restriction short labels.
        if let claim = falseListClaim(in: lower, ctx: ctx) {
            return claim
        }

        // V5.0.9 — nutrient badge / additive phrasing must match structured input.
        if let bad = nutrientBadgeContradiction(in: lower, ctx: ctx) {
            return bad
        }
        if lower.contains("beneficial additive") || lower.contains("beneficial additives") {
            return "beneficial additives"
        }
        // V5.1.0 — redistributed S15 must not be described as a measured deficiency.
        if ctx.rules.contains(where: { $0.rule == "S15" && $0.evidenceTier == "unknown-tier" }) {
            if lower.contains("held back by fat quality")
                || lower.contains("poor fat quality")
                || lower.contains("refined seed oil") && !lower.contains("missing") {
                return "S15 unknown-tier"
            }
        }

        return nil
    }

    /// Catches "high sugar" when badge is OK/GOOD, "low protein" when OK/GOOD, etc.
    private static func nutrientBadgeContradiction(
        in lower: String, ctx: ScoringEngineV4.OverviewContext
    ) -> String? {
        // nutrientLevels lines look like "sugar: high (22g)" / "protein: ok".
        var badge: [String: String] = [:]
        for line in ctx.nutrientLevels {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            guard parts.count == 2 else { continue }
            let name = parts[0]
            let rest = parts[1]
            if rest.hasPrefix("high") { badge[name] = "high" }
            else if rest.hasPrefix("low") { badge[name] = "low" }
            else if rest.hasPrefix("good") { badge[name] = "good" }
            else if rest.hasPrefix("ok") || rest.hasPrefix("mod") { badge[name] = "ok" }
        }

        func contradicts(_ nutrient: String, claimed: String) -> Bool {
            guard let b = badge[nutrient] else { return false }
            switch claimed {
            case "high":
                return b == "ok" || b == "good" || b == "low"
            case "low":
                return b == "ok" || b == "good" || b == "high"
            case "moderate", "mod":
                return b == "high" || b == "low" || b == "good"
            default:
                return false
            }
        }

        let claims: [(String, String, [String])] = [
            ("sugar", "high", ["high sugar", "sugar is high", "high in sugar"]),
            ("sugar", "moderate", ["moderate sugar", "moderately sugary", "moderate sugar content"]),
            ("sugar", "low", ["low sugar", "sugar is low"]),
            ("protein", "low", ["low protein", "lower protein", "limited protein", "protein levels"]),
            ("protein", "high", ["high protein"]),
            ("saturated fat", "low", ["low saturated", "low sat fat"]),
        ]
        // "lower protein levels" is ambiguous — flag when protein badge is ok/good.
        if let b = badge["protein"], (b == "ok" || b == "good" || b == "high"),
           lower.contains("lower protein") || lower.contains("low protein")
            || (lower.contains("limited protein") && !lower.contains("diluted")) {
            return "protein badge contradiction"
        }
        if let b = badge["sugar"], (b == "ok" || b == "good" || b == "low"),
           lower.contains("moderate sugar") {
            return "sugar badge contradiction"
        }
        if let b = badge["sugar"], b == "high",
           lower.contains("moderate sugar") {
            return "sugar badge contradiction"
        }
        for (nutrient, claimed, phrases) in claims {
            for phrase in phrases where lower.contains(phrase) {
                if contradicts(nutrient, claimed: claimed) {
                    return "\(nutrient) badge contradiction"
                }
            }
        }
        return nil
    }

    /// Detects "(also) on your (avoid) list: …" naming items not in the payload.
    private static func falseListClaim(in lower: String, ctx: ScoringEngineV4.OverviewContext) -> String? {
        let allowed: Set<String> = Set(
            ctx.avoidMatches.map { $0.lowercased() }
            + (ctx.hardGate.map { [$0.shortLabel.lowercased()] } ?? [])
            + ctx.firedCaps.map { $0.shortLabel.lowercased() }
        )
        // Match "on your avoid list" / "on your list:" fragments and collect named items.
        let patterns = [
            #"on your avoid list[^.:]*[: ]+([^.]+)"#,
            #"on your list:\s*([^.]+)"#,
            #"also on your list:\s*([^.]+)"#,
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: lower)
            else { continue }
            let blob = String(lower[range])
            let parts = blob
                .components(separatedBy: CharacterSet(charactersIn: ",;"))
                .flatMap { $0.components(separatedBy: " and ") }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != "which" && !$0.hasPrefix("which ") }
            for part in parts {
                // Strip trailing "which is/are…"
                let cleaned = part
                    .replacingOccurrences(of: #"\s+which\b.*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { continue }
                // "contains X, which is on your avoid list" — X already validated via avoidMatches earlier in sentence.
                if allowed.contains(where: { cleaned.contains($0) || $0.contains(cleaned) }) {
                    continue
                }
                // Health-cap short labels must never appear as list claims.
                if ["free sugar", "trans fat", "non-nutritive sweetener"].contains(cleaned) {
                    return "false list claim: \(cleaned)"
                }
                if !allowed.isEmpty || cleaned == "free sugar" {
                    return "false list claim: \(cleaned)"
                }
            }
        }
        // Bare "also on your list: free sugar" without capture edge cases.
        if lower.contains("on your list") || lower.contains("on your avoid list") {
            for banned in ["free sugar", "trans fat", "non-nutritive sweetener"] {
                if lower.contains(banned), !allowed.contains(banned) {
                    return "false list claim: \(banned)"
                }
            }
        }
        return nil
    }

    static func isValid(_ text: String, ctx: ScoringEngineV4.OverviewContext) -> Bool {
        forbiddenPhrase(in: text, ctx: ctx) == nil
    }
}
