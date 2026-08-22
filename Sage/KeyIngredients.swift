import Foundation

/// Per-ingredient verdicts for the product page's "Key ingredients" list and
/// the real-food / worth-limiting tallies under the overview.
///
/// Every verdict is label-derived. A token is matched, in order, against the
/// product's detected additives, the curated `IngredientKnowledgeBase`, and
/// the engine's own keyword tables — S15 fat tiers, the S14 whole-food
/// whitelist, sweetener systems, isolate markers. Nothing here reads the LLM
/// overview and nothing scores: it is an explanation layer over signals the
/// ruleset already uses, so a row can never disagree with the number.
enum KeyIngredients {

    /// Ordered by how urgently the row wants attention; also the list order.
    enum Verdict: Int, Comparable, Hashable, Codable {
        case avoid = 0, limit, good, neutral

        static func < (a: Verdict, b: Verdict) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .avoid:   return String(localized: "Avoid")
            case .limit:   return String(localized: "Limit")
            case .good:    return String(localized: "Good")
            case .neutral: return String(localized: "Fine")
            }
        }

        init?(key: String) {
            switch key.lowercased() {
            case "avoid":   self = .avoid
            case "limit":   self = .limit
            case "good":    self = .good
            case "neutral", "fine": self = .neutral
            default: return nil
            }
        }
    }

    struct Item: Identifiable, Hashable {
        var id: String { "\(position)-\(token)" }
        /// Normalized label token ("cane sugar").
        let token: String
        /// Display name ("Cane sugar").
        let name: String
        let verdict: Verdict
        /// 0-based position in the ingredient list (recipe order = share order).
        let position: Int
        /// Declared or OFF-estimated recipe share, when the record carries one.
        let share: Double?
        let shareIsDeclared: Bool
        /// One or two sentences on why this verdict — the sheet's "In this product".
        let reason: String
        /// Ingredient-general explainer from the knowledge base; nil when the
        /// verdict came from an engine table.
        let about: String?
        /// When the token is one of the product's detected additives the sheet
        /// hands over to the additive detail (code, tier, sources).
        let additive: ProductAdditive?
    }

    struct Analysis: Hashable {
        /// Sorted: avoid, limit, good, neutral; recipe order within a verdict.
        let items: [Item]
        /// All tokens on the label (duplicates included).
        let total: Int
        var goodCount: Int { items.filter { $0.verdict == .good }.count }
        var watchCount: Int { items.filter { $0.verdict == .avoid || $0.verdict == .limit }.count }
        var hasAvoid: Bool { items.contains { $0.verdict == .avoid } }
    }

    // MARK: Analyze

    static func analyze(_ product: Product) -> Analysis? {
        guard let raw = product.ingredientsText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              IngredientIntegrity.looksLikeIngredientList(raw)
        else { return nil }
        let tokens = IngredientIntegrity.tokens(from: raw)
        guard !tokens.isEmpty else { return nil }

        let shares = product.ingredientShares ?? []
        var items: [Item] = []
        var seen = Set<String>()
        for (i, token) in tokens.enumerated() {
            // "salt" listed twice is one row.
            guard !seen.contains(token) else { continue }
            seen.insert(token)
            let c = classify(token: token, product: product)
            let share = share(for: token, in: shares)
            let name = c.additive.map(additiveDisplayName) ?? displayName(token)
            items.append(Item(token: token, name: name, verdict: c.verdict,
                              position: i, share: share?.value,
                              shareIsDeclared: share?.declared ?? false,
                              reason: c.reason, about: c.about, additive: c.additive))
        }
        items.sort { ($0.verdict, $0.position) < ($1.verdict, $1.position) }
        return Analysis(items: items, total: tokens.count)
    }

    // MARK: Classification

    private struct Classification {
        let verdict: Verdict
        let reason: String
        var about: String? = nil
        var additive: ProductAdditive? = nil
    }

    private static func classify(token: String, product: Product) -> Classification {
        // 1. A detected additive — the additive KB owns the detail.
        if let a = matchingAdditive(token: token, in: product.additives) {
            switch a.risk {
            case .high:
                return .init(verdict: .avoid,
                             reason: "Detected as \(a.name) — a high-risk additive in Sage's table (regulator warnings, restrictions or well-known concerns).",
                             additive: a)
            case .moderate:
                return .init(verdict: .limit,
                             reason: "Detected as \(a.name) — rated moderate risk: evidence or intake limits suggest a closer look, not a hard avoid.",
                             additive: a)
            case .low:
                return .init(verdict: .neutral,
                             reason: "Detected as \(a.name) — a low-risk additive at typical food-use levels.",
                             additive: a)
            case .unrated:
                return .init(verdict: .neutral,
                             reason: "Detected as \(a.name) — not yet rated by Sage, so it stays neutral rather than guessed.",
                             additive: a)
            }
        }

        // 2. Curated knowledge base (most specific match wins).
        if let e = IngredientKnowledgeBase.entry(matching: token) {
            return .init(verdict: e.verdictValue, reason: e.why.resolved(), about: e.summary.resolved())
        }

        // 3. Engine tables.
        if IngredientIntegrity.isWaterToken(token) {
            return .init(verdict: .neutral, reason: "Water — not judged, and left out of the real-food ratio.")
        }
        let fat = FatQuality.keywords
        if fat.tier_zero.contains(where: { fatMatches($0, token: token) }) {
            return .init(verdict: .avoid,
                         reason: "Hydrogenated or interesterified fat — the industrial trans-fat family, the ruleset's lowest fat tier.")
        }
        if fat.tier_high.contains(where: { fatMatches($0, token: token) }) {
            return .init(verdict: .good, reason: "Minimally refined fat in Sage's top fat-quality tier.")
        }
        if fat.tier_low.contains(where: { fatMatches($0, token: token) }) {
            return .init(verdict: .limit,
                         reason: "Refined seed oil. The omega-6 'inflammation' story is weak in human trials; Sage docks it for the refining and the missing polyphenols, not as a toxin.")
        }
        if IngredientIntegrity.keywords.sweetener_systems.contains(where: { token.contains($0) }) {
            return .init(verdict: .limit,
                         reason: "Non-nutritive sweetener. Safe at regulated levels, but the ruleset docks sweetener systems — they keep a product tasting like dessert.")
        }
        if sugarWords.contains(where: { token.contains($0) }) {
            return .init(verdict: .limit, reason: "A form of added sugar — position in the list says how much.")
        }
        if IngredientIntegrity.isWholeFoodToken(token) {
            return .init(verdict: .good, reason: "A whole food — counts toward Sage's real-food ratio.")
        }
        if flavorWords.contains(where: { token.contains($0) }) {
            return .init(verdict: .neutral,
                         reason: "Flavoring of undisclosed composition. No evidence of harm at food levels; it's one of the markers Sage uses to recognize ultra-processing, not a dock on its own.")
        }
        if IngredientIntegrity.keywords.isolate_markers.contains(where: { token.contains($0) }) {
            return .init(verdict: .neutral,
                         reason: "An isolate, concentrate or modified form — a processed ingredient Sage notes without docking on its own.")
        }
        return .init(verdict: .neutral, reason: "Not in Sage's tables — left neutral rather than guessed.")
    }

    private static let sugarWords = [
        "sugar", "syrup", "dextrose", "maltodextrin", "fructose", "glucose", "sucrose",
        "juice concentrate", "nectar", "molasses", "caramel",
        "açúcar", "acucar", "xarope", "zucchero", "sciroppo", "azúcar", "jarabe", "sucre", "sirop",
    ]
    private static let flavorWords = [
        "flavor", "flavour", "aroma", "arôme", "arome", "sabor",
    ]

    private static func fatMatches(_ kw: String, token: String) -> Bool {
        token == kw || token.hasPrefix(kw + " ") || token.hasSuffix(" " + kw)
            || token.contains(" " + kw + " ") || token.contains(kw)
    }

    /// Token → one of the product's detected additives, via a printed code
    /// ("E150c"), the detector's label synonyms, or the common name.
    private static func matchingAdditive(token: String, in additives: [ProductAdditive]) -> ProductAdditive? {
        guard !additives.isEmpty else { return nil }
        let norm = AdditiveDetector.normalize(token)
        let codesInToken = Set(AdditiveDetector.extractCodes(from: token).map { $0.lowercased() })
        for a in additives {
            var codes: [String] = []
            if let c = a.code { codes.append(c.lowercased()) }
            codes.append(contentsOf: (a.detectedAs ?? []).map { $0.lowercased() })
            if codes.contains(where: { codesInToken.contains($0) || codesInToken.contains("e" + $0) }) {
                return a
            }
            let code = a.code ?? codes.first ?? ""
            let terms = AdditiveDetector.matchTerms(forCode: code)
            if terms.contains(where: { !$0.isEmpty && norm.contains($0) }) { return a }
            // Class stems: "caramel colour iii" → "caramel color" matches a
            // label that says "caramel color" when OFF tagged the subtype.
            let stems = terms.map(classStem).filter { $0.count >= 5 }
            let tokenStem = classStem(norm)
            if stems.contains(where: { tokenStem.contains($0) }) { return a }
            // "Ammonia Caramel (E150C)" → "ammonia caramel"
            let bare = a.name.components(separatedBy: " (").first.map(AdditiveDetector.normalize) ?? ""
            if bare.count >= 4, norm.contains(bare) { return a }
        }
        return nil
    }

    /// Drops a trailing roman-numeral subtype and unifies UK/US spelling so
    /// additive classes compare by stem.
    private static func classStem(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "colour", with: "color")
            .replacingOccurrences(of: "flavour", with: "flavor")
        for suffix in [" iii", " ii", " iv", " i", " vi", " v"] where t.hasSuffix(suffix) {
            t = String(t.dropLast(suffix.count))
            break
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Additive rows take the additive's curated name — OFF label text is
    /// often OCR ("Ašpartame", "Pótasshum benzoate").
    private static func additiveDisplayName(_ a: ProductAdditive) -> String {
        let bare = a.name.components(separatedBy: " (").first ?? a.name
        return bare.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Helpers

    private static func displayName(_ token: String) -> String {
        guard let first = token.first else { return token }
        return String(first).uppercased() + token.dropFirst()
    }

    /// Best-effort join to OFF's parsed ingredient shares ("whole-grain-oats").
    private static func share(for token: String,
                              in shares: [IngredientShare]) -> (value: Double, declared: Bool)? {
        guard !shares.isEmpty else { return nil }
        let hyphenated = token.replacingOccurrences(of: " ", with: "-")
        let hit = shares.first { $0.name == hyphenated }
            ?? shares.first { $0.name.hasSuffix("-" + hyphenated) || hyphenated.hasSuffix("-" + $0.name) }
        guard let hit else { return nil }
        if let p = hit.percent { return (p, true) }
        if let e = hit.percentEstimate { return (e, false) }
        return nil
    }
}

// MARK: - Knowledge base

/// Curated, evidence-tiered entries for the ingredients that show up on most
/// labels but are not additives (sugars, fats, flours, proteins, flavorings).
/// `match` terms are matched exact / as a trailing phrase / as a leading
/// phrase, and the longest matching term wins — so "extra virgin olive oil"
/// beats "olive oil" beats "oil", and "organic cane sugar" lands on cane sugar.
enum IngredientKnowledgeBase {
    typealias LocalizedString = AdditiveKnowledgeBase.LocalizedString

    struct Entry: Codable, Equatable {
        let id: String
        let name: LocalizedString
        let verdict: String
        let match: [String]
        /// What the ingredient is (general).
        let summary: LocalizedString
        /// Why Sage rates it the way it does (the row's reason line).
        let why: LocalizedString

        var verdictValue: KeyIngredients.Verdict {
            KeyIngredients.Verdict(key: verdict) ?? .neutral
        }
    }

    private final class BundleToken {}

    static let entries: [Entry] = {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "IngredientKnowledgeBase", withExtension: "json")
                ?? Bundle.main.url(forResource: "IngredientKnowledgeBase", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return list
    }()

    static func entry(matching token: String) -> Entry? {
        var best: (entry: Entry, length: Int)?
        for e in entries {
            for m in e.match where matches(token, term: m) {
                if best == nil || m.count > best!.length { best = (e, m.count) }
            }
        }
        return best?.entry
    }

    static func matches(_ token: String, term: String) -> Bool {
        token == term
            || token.hasPrefix(term + " ")
            || token.hasSuffix(" " + term)
            || token.contains(" " + term + " ")
    }
}
