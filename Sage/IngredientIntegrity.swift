import Foundation

/// S14 — ingredient integrity (formulation honesty), not nutrition quantity.
/// Keywords live in `ingredient_integrity_keywords.json` (EN/PT/IT).
enum IngredientIntegrity {

    struct Keywords: Codable {
        let sweetener_systems: [String]
        let isolate_markers: [String]
        let whole_food_whitelist: [String]
        let intrinsic_sugar_sources: [String]?
    }

    struct Breakdown: Equatable {
        let fraction: Double
        let hadData: Bool
        let wholeFoodRatio: Double
        let countScore: Double
        let sweetenerScore: Double
        let isolateScore: Double
        let ingredientCount: Int
        let sweetenerMatches: [String]
        let isolateMatches: [String]
    }

    private final class BundleToken {}

    static let keywords: Keywords = {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "ingredient_integrity_keywords", withExtension: "json")
                ?? Bundle.main.url(forResource: "ingredient_integrity_keywords", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let kw = try? JSONDecoder().decode(Keywords.self, from: data)
        else {
            return Keywords(sweetener_systems: [], isolate_markers: [],
                            whole_food_whitelist: [], intrinsic_sugar_sources: [])
        }
        return kw
    }()

    /// Split ingredient text into tokens (comma / bullet / semicolon).
    /// Parenthetical asides are stripped (not flattened into the token).
    static func tokens(from text: String) -> [String] {
        var cleaned = text
        while let open = cleaned.range(of: "("),
              let close = cleaned.range(of: ")", range: open.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(open.lowerBound..<close.upperBound)
        }
        while let open = cleaned.range(of: "["),
              let close = cleaned.range(of: "]", range: open.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return cleaned
            .components(separatedBy: CharacterSet(charactersIn: ",;•\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) }
            .filter { !$0.isEmpty }
    }

    /// Exact whitelist match, or ingredient that starts with a multi-word whitelist entry.
    /// Avoids loose substring hits (e.g. "powdered sugar" ≠ "sugar").
    private static func isWholeFood(_ token: String) -> Bool {
        keywords.whole_food_whitelist.contains { kw in
            token == kw || token.hasPrefix(kw + " ")
        }
    }

    static func evaluate(ingredientsText: String?) -> Breakdown {
        guard let raw = ingredientsText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return Breakdown(fraction: 0, hadData: false, wholeFoodRatio: 0, countScore: 0,
                             sweetenerScore: 0, isolateScore: 0, ingredientCount: 0,
                             sweetenerMatches: [], isolateMatches: [])
        }

        let parts = tokens(from: raw)
        let count = parts.count
        guard count > 0 else {
            return Breakdown(fraction: 0, hadData: false, wholeFoodRatio: 0, countScore: 0,
                             sweetenerScore: 0, isolateScore: 0, ingredientCount: 0,
                             sweetenerMatches: [], isolateMatches: [])
        }

        let wholeHits = parts.filter(isWholeFood).count
        let wholeFoodRatio = Double(wholeHits) / Double(count)

        let countScore: Double
        switch count {
        case ...7: countScore = 1.0
        case 8...14: countScore = 0.6
        default: countScore = 0.2
        }

        let sweetenerMatches = uniqueMatches(in: raw.lowercased(), needles: keywords.sweetener_systems)
        let sweetenerScore: Double
        switch sweetenerMatches.count {
        case 0: sweetenerScore = 1.0
        case 1: sweetenerScore = 0.5
        default: sweetenerScore = 0.15
        }

        let isolateMatches = uniqueMatches(in: raw.lowercased(), needles: keywords.isolate_markers)
        let isolateScore: Double
        switch isolateMatches.count {
        case 0: isolateScore = 1.0
        case 1: isolateScore = 0.4
        default: isolateScore = 0.1
        }

        let f = 0.45 * wholeFoodRatio
            + 0.25 * countScore
            + 0.20 * sweetenerScore
            + 0.10 * isolateScore

        return Breakdown(
            fraction: min(1, max(0, f)),
            hadData: true,
            wholeFoodRatio: wholeFoodRatio,
            countScore: countScore,
            sweetenerScore: sweetenerScore,
            isolateScore: isolateScore,
            ingredientCount: count,
            sweetenerMatches: sweetenerMatches,
            isolateMatches: isolateMatches
        )
    }

    static func hasIsolateProtein(ingredientsText: String?) -> Bool {
        let b = evaluate(ingredientsText: ingredientsText)
        guard b.hadData else { return false }
        let proteinish = ["isolate", "isolado", "isolato", "whey protein", "milk protein",
                          "soy protein", "protein blend", "concentrado", "concentrate"]
        let hay = (ingredientsText ?? "").lowercased()
        return proteinish.contains { hay.contains($0) }
    }

    static func sweetenerSystemMatches(ingredientsText: String?) -> [String] {
        evaluate(ingredientsText: ingredientsText).sweetenerMatches
    }

    /// True when sugar is plausibly intrinsic (dairy / fruit / honey) and the
    /// formula is simple (≤6 ingredients, no additives).
    static func qualifiesForIntrinsicSugarDiscount(
        ingredientsText: String?, additivesEmpty: Bool
    ) -> (ok: Bool, reason: String?) {
        guard additivesEmpty else { return (false, nil) }
        let b = evaluate(ingredientsText: ingredientsText)
        guard b.hadData, b.ingredientCount > 0, b.ingredientCount <= 6 else { return (false, nil) }
        let sources = keywords.intrinsic_sugar_sources ?? []
        let hay = (ingredientsText ?? "").lowercased()
        let hit = sources.first(where: { hay.contains($0) })
        guard let hit else { return (false, nil) }
        let kind: String
        if ["milk", "cream", "leite", "creme", "nata", "latte", "panna"].contains(where: { hit.contains($0) }) {
            kind = "dairy sugar"
        } else if ["honey", "mel", "miele"].contains(where: { hit.contains($0) }) {
            kind = "honey sugar"
        } else {
            kind = "fruit sugar"
        }
        return (true, "\(kind), \(b.ingredientCount) ingredients, 0 additives")
    }

    private static func uniqueMatches(in hay: String, needles: [String]) -> [String] {
        var found: [String] = []
        let sorted = needles.sorted { $0.count > $1.count }
        for kw in sorted {
            guard hay.contains(kw) else { continue }
            // Prefer longer phrases; skip if a longer match already covers this span loosely.
            if found.contains(where: { $0.contains(kw) || kw.contains($0) && $0.count >= kw.count }) {
                continue
            }
            found.append(kw)
        }
        return found
    }
}
