import Foundation

/// S15 — fat quality from the ingredient list (not the sat-fat panel).
enum FatQuality {

    struct Keywords: Codable {
        let tier_high: [String]
        let tier_low: [String]
        let tier_zero: [String]
        let refining_markers: [String]
    }

    struct Breakdown: Equatable {
        let fraction: Double
        let hadData: Bool
        let sources: [String]
        let refiningApplied: Bool
        let note: String
    }

    private final class BundleToken {}

    static let keywords: Keywords = {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "fat_quality_keywords", withExtension: "json")
                ?? Bundle.main.url(forResource: "fat_quality_keywords", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let kw = try? JSONDecoder().decode(Keywords.self, from: data)
        else {
            return Keywords(tier_high: [], tier_low: [], tier_zero: [], refining_markers: [])
        }
        return kw
    }()

    static func evaluate(product p: Product) -> Breakdown {
        guard let text = p.ingredientsText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            // Whole-food with missing text — S1-style bypass.
            if (1...2).contains(p.novaGroup), p.additives.isEmpty {
                return Breakdown(fraction: 1.0, hadData: true, sources: [], refiningApplied: false,
                                 note: "S15 fatQuality: f 1.00 (whole-food bypass)")
            }
            return Breakdown(fraction: 0, hadData: false, sources: [], refiningApplied: false,
                             note: "S15 fatQuality: no data")
        }

        let tokens = IngredientIntegrity.tokens(from: text)
        guard !tokens.isEmpty else {
            return Breakdown(fraction: 0, hadData: false, sources: [], refiningApplied: false,
                             note: "S15 fatQuality: no data")
        }

        struct Hit { let name: String; let tier: Double; let index: Int }
        var hits: [Hit] = []
        let high = keywords.tier_high.sorted { $0.count > $1.count }
        let low = keywords.tier_low.sorted { $0.count > $1.count }
        let zero = keywords.tier_zero.sorted { $0.count > $1.count }

        for (i, token) in tokens.enumerated() {
            if let z = zero.first(where: { matches($0, token: token) }) {
                hits.append(Hit(name: z, tier: 0.0, index: i))
                continue
            }
            if let h = high.first(where: { matches($0, token: token) }) {
                hits.append(Hit(name: h, tier: 1.0, index: i))
                continue
            }
            if let l = low.first(where: { matches($0, token: token) }) {
                hits.append(Hit(name: l, tier: 0.15, index: i))
            }
        }

        // Whole-food bypass only when there is no ingredient list to inspect.
        // If a list exists but no fat source matched → missing data (redistribute),
        // never invent a perfect fat-quality score for unlabeled oils.
        if (1...2).contains(p.novaGroup), p.additives.isEmpty, hits.isEmpty {
            // Bare produce / single-ingredient whole foods without a fat keyword.
            let looksLikeOil = tokens.contains { t in
                t.contains("oil") || t.contains("óleo") || t.contains("olio")
                    || t.contains("shortening") || t.contains("gordura")
            }
            if !looksLikeOil {
                return Breakdown(fraction: 1.0, hadData: true, sources: [], refiningApplied: false,
                                 note: "S15 fatQuality: f 1.00 (whole-food bypass)")
            }
        }

        guard !hits.isEmpty else {
            return Breakdown(fraction: 0, hadData: false, sources: [], refiningApplied: false,
                             note: "S15 fatQuality: no fat sources")
        }

        let n = max(tokens.count, 1)
        var weighted = 0.0
        var wSum = 0.0
        for hit in hits {
            let w = Double(n - hit.index)
            weighted += hit.tier * w
            wSum += w
        }
        var f = wSum > 0 ? weighted / wSum : 0

        let hay = text.lowercased()
        let refining = keywords.refining_markers.contains { hay.contains($0) }
        let highOleic = hay.contains("high oleic") || hay.contains("high-oleic")
        let hasLow = hits.contains { abs($0.tier - 0.15) < 0.001 }
        let applyRefine = refining || (highOleic && hasLow)
        if applyRefine { f *= 0.75 }

        let names = hits.map(\.name)
        let nameList = names.joined(separator: ", ")
        let refineNote = applyRefine ? ", refined ×0.75" : ""
        let rawBefore = applyRefine ? f / 0.75 : f
        let note = String(
            format: "S15 fatQuality: f %.2f (%@%@) → %.2f",
            rawBefore, nameList, refineNote, f
        )
        return Breakdown(fraction: min(1, max(0, f)), hadData: true,
                         sources: names, refiningApplied: applyRefine, note: note)
    }

    private static func matches(_ kw: String, token: String) -> Bool {
        token == kw || token.hasPrefix(kw + " ") || token.hasSuffix(" " + kw)
            || token.contains(" " + kw + " ") || token.contains(kw)
    }
}
