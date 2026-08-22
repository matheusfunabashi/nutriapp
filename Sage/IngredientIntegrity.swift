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
    /// Trailing allergen / advisory statements are not ingredients
    /// ("…, Malted Wheat Flour. ALLERGEN ADVICE: …", "Contains: Wheat, Sesame").
    static func strippingTrailingStatements(_ text: String) -> String {
        let lower = text.lowercased()
        var cut = lower.endIndex
        for marker in ["allergen advice", "allergy advice", "allergen information",
                       "may contain", "contains:", "contém:", "contiene:", "contient:",
                       "kann spuren", "pode conter", "può contenere", "peut contenir",
                       // Back-of-pack boilerplate pasted after the list.
                       "if you have any questions", "questions or comments", "please call",
                       "write to us", "consumer relations", "distributed by", "manufactured by",
                       "manufactured for", "produced for", "packed for", "best before",
                       "store in a cool", "keep refrigerated", "ingrédients :", "ingrédients:",
                       "ingredientes:", "ingredienti:", "zutaten:"] {
            if let r = lower.range(of: marker), r.lowerBound < cut { cut = r.lowerBound }
        }
        return cut == lower.endIndex ? text : String(text[..<cut])
    }

    /// False when the field holds marketing prose rather than a list: long
    /// sentences (≥ 9 words per token) *and* second-person / brand-voice words
    /// ("your favorite sandwich", "we honor", "let's salute"). Punctuation-poor
    /// OCR lists ("Cocoa mass Sugar Cocoa butter Soy lecithin") are long but
    /// have no such words and must stay lists.
    static func looksLikeIngredientList(_ text: String?) -> Bool {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return false }
        let parts = tokens(from: text)
        guard !parts.isEmpty else { return false }
        let words = parts.reduce(0) { $0 + $1.split(separator: " ").count }
        let avg = Double(words) / Double(parts.count)
        guard parts.count <= 10, avg >= 9 else { return true }
        let lower = text.lowercased()
        let voice = ["you", "your", "we", "our", "us", "let's", "every", "enjoy", "perfect",
                     "delicious", "proud", "tradition", "favorite", "favourite", "birthday"]
        let hits = voice.filter { lower.range(of: #"\b\#($0)\b"#, options: .regularExpression) != nil }.count
        return hits < 2
    }

    static func tokens(from text: String) -> [String] {
        var cleaned = strippingTrailingStatements(text)
        while let open = cleaned.range(of: "("),
              let close = cleaned.range(of: ")", range: open.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(open.lowerBound..<close.upperBound)
        }
        while let open = cleaned.range(of: "["),
              let close = cleaned.range(of: "]", range: open.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(open.lowerBound..<close.upperBound)
        }
        // OFF allergen markup wraps words in underscores ("_Œufs_ frais");
        // underscores are word characters to a regex, so strip them everywhere.
        cleaned = cleaned.replacingOccurrences(of: "_", with: "")
        return cleaned
            .components(separatedBy: CharacterSet(charactersIn: ",;•\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) }
            // V5.3: trailing sentence punctuation and OFF allergen markup
            // ("Eggs." / "_Œufs_ frais" / "honey*") are not part of the
            // ingredient. Before this, every list ending in a period failed the
            // whitelist on its last token — a single-ingredient "Eggs." scored
            // 0.55 instead of 1.0.
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "._*:")) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Identity-preserving qualifiers: "organic milk" is still milk. The list
    /// deliberately excludes words that change the food itself — stripping
    /// "whole" would turn whole wheat flour into (refined) wheat flour.
    private static let strippableQualifiers = [
        "organic", "raw", "fresh", "local", "cultured", "pasteurized",
        "pasteurised", "homogenized", "homogenised", "unhomogenized",
        "unhomogenised", "grade a", "100%",
        // V5.3 egg qualifiers — housing / size / form words that leave the
        // food itself unchanged ("free range eggs" is still eggs).
        "free range", "free-range", "cage free", "cage-free", "pasture raised",
        "pasture-raised", "pastured", "barn", "hen", "liquid", "hard boiled",
        "hard-boiled", "boiled", "cooked", "large", "medium", "grade aa",
        "usda grade a", "usda grade aa",
        // V5.4 bread qualifiers — milling / fortification words that leave the
        // flour itself unchanged ("unbleached enriched wheat flour" is wheat
        // flour; "stone ground whole wheat flour" is whole wheat flour).
        // "bleached" is deliberately not strippable (a chemical treatment).
        "unbleached", "enriched", "fortified", "stone ground", "stone-ground",
        "stoneground", "sprouted", "toasted", "cracked", "rolled", "malted",
        "kibbled", "sifted", "untreated", "filtered", "sea", "kosher",
    ]

    /// Plain water is not an ingredient to judge (Oasis excludes it too); it
    /// is dropped from the S14 whole-food ratio so "whole wheat flour, water,
    /// salt" is not 1/3 real food. Other liquids (milk, oil) stay.
    private static let waterTokens: Set<String> = [
        "water", "filtered water", "purified water", "spring water", "artesian water",
        "artesian spring water", "carbonated water", "sparkling water", "eau", "acqua",
        "água", "agua", "wasser", "aqua",
    ]

    static func isWaterToken(_ token: String) -> Bool {
        waterTokens.contains(token) || waterTokens.contains { token.hasPrefix($0 + " ") }
    }

    /// Exact whitelist match, or ingredient that starts with a multi-word whitelist entry.
    /// Avoids loose substring hits (e.g. "powdered sugar" ≠ "sugar").
    /// V5.2: leading identity-preserving qualifiers are stripped before a
    /// retry, so "organic milk" / "raw milk" / "fresh goat milk" match.
    static func isWholeFoodToken(_ token: String) -> Bool {
        if matchesWhitelist(token) { return true }
        var t = token
        var stripped = true
        while stripped {
            stripped = false
            for q in strippableQualifiers where t.hasPrefix(q + " ") {
                t = String(t.dropFirst(q.count + 1))
                stripped = true
            }
        }
        return t != token && matchesWhitelist(t)
    }

    private static func isWholeFood(_ token: String) -> Bool {
        isWholeFoodToken(token)
    }

    private static func matchesWhitelist(_ token: String) -> Bool {
        keywords.whole_food_whitelist.contains { kw in
            token == kw || token.hasPrefix(kw + " ")
        }
    }

    /// - `neutralTokenKw`: tokens containing any of these are dropped from the
    ///   whole-food ratio (neither whole food nor a dock) — V5.5 protein bars
    ///   pass their protein sources here. Never dropped from the count.
    /// - `neutralIsolateMarkers`: isolate markers that don't count against the
    ///   list (protein isolate markers on a protein bar); syrups, maltodextrin
    ///   and modified starch still do.
    static func evaluate(ingredientsText: String?,
                         neutralTokenKw: [String] = [],
                         neutralIsolateMarkers: [String] = []) -> Breakdown {
        guard let raw = ingredientsText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return Breakdown(fraction: 0, hadData: false, wholeFoodRatio: 0, countScore: 0,
                             sweetenerScore: 0, isolateScore: 0, ingredientCount: 0,
                             sweetenerMatches: [], isolateMatches: [])
        }

        // V5.4: water is excluded from the whole-food ratio (never from the
        // ingredient count — a long list is still a long list).
        let allParts = tokens(from: raw)
        let parts = allParts.filter { t in
            !isWaterToken(t) && !neutralTokenKw.contains { t.contains($0) }
        }
        let count = allParts.count
        guard count > 0 else {
            return Breakdown(fraction: 0, hadData: false, wholeFoodRatio: 0, countScore: 0,
                             sweetenerScore: 0, isolateScore: 0, ingredientCount: 0,
                             sweetenerMatches: [], isolateMatches: [])
        }

        let wholeHits = parts.filter(isWholeFood).count
        let wholeFoodRatio = parts.isEmpty ? 0 : Double(wholeHits) / Double(parts.count)

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

        let isolateNeedles = neutralIsolateMarkers.isEmpty
            ? keywords.isolate_markers
            : keywords.isolate_markers.filter { !neutralIsolateMarkers.contains($0) }
        let isolateMatches = uniqueMatches(in: raw.lowercased(), needles: isolateNeedles)
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
        // V5.4: "concentrate" alone caught "raisin juice concentrate" / "apple
        // juice concentrate" and halved S12 on breads and bars that contain no
        // isolate protein at all — only *protein* concentrates qualify.
        let proteinish = ["isolate", "isolado", "isolato", "whey protein", "milk protein",
                          "soy protein", "protein blend", "protein concentrate",
                          "proteína concentrada", "concentrado de proteína",
                          "concentrato di proteine", "proteine concentrate"]
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
