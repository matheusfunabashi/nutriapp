import Foundation

/// V5.4 — bread-specific rule shapes (`bread` profile). All tunables live in
/// `RulesetV5.json` → `bread`; this file only knows the shapes.
///
/// Why bread gets its own rules (SCORING_V5.md §"V5.4.0 Bread"):
/// - the legacy `wholeGrain` rule was a binary keyword hit on name +
///   ingredients + tags, so 2 % rye flour in a white sourdough earned the
///   full whole-grain credit and 85 / 96 shelf breads scored 1.0 on it;
/// - generic S12 spends 60 % of its weight on axes bread cannot earn
///   (protein per kcal against a 15 g/100 kcal anchor, fruit/veg share);
/// - OFF's NOVA tag is noisy on bread (a baguette tagged NOVA 1, Ezekiel
///   tagged 3 on one barcode and 4 on the next) and NOVA 3 is the *best*
///   class a bread can be, so S2 compressed every traditional loaf to 0.4;
/// - the "whole foods" whitelist accepted refined "wheat flour" but not
///   "whole wheat flour".
enum BreadScoring {

    // MARK: Grain tokens

    /// One top-level ingredient with its parenthetical sub-list kept
    /// (`IngredientIntegrity.tokens` strips parentheticals, but whole-grain
    /// evidence often lives inside them: "Grains (whole kernel rye, …)").
    struct Token: Equatable {
        let head: String
        let inner: [String]
    }

    /// Split on top-level commas / semicolons only; nested brackets are kept
    /// with their parent. Lower-cased, whitespace-normalized, OFF allergen
    /// underscores and trailing punctuation removed.
    static func topLevelTokens(_ text: String) -> [Token] {
        var depth = 0
        var current = ""
        var pieces: [String] = []
        for ch in text {
            switch ch {
            case "(", "[": depth += 1; current.append(ch)
            case ")", "]": depth = max(0, depth - 1); current.append(ch)
            case ",", ";", "•", "\n":
                if depth == 0 { pieces.append(current); current = "" } else { current.append(ch) }
            default: current.append(ch)
            }
        }
        pieces.append(current)
        return pieces.compactMap { raw -> Token? in
            var s = raw.replacingOccurrences(of: "_", with: "").lowercased()
            s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { return nil }
            var inner: [String] = []
            var head = s
            // "(35%)" / "(6 %)" is an amount, not a sub-list — fold it into the head.
            s = s.replacingOccurrences(of: #"\(\s*(\d+(?:[.,]\d+)?\s*%)\s*\)"#, with: " $1", options: .regularExpression)
            if let open = s.firstIndex(where: { $0 == "(" || $0 == "[" }) {
                head = String(s[..<open])
                var tail = String(s[s.index(after: open)...])
                // "wheat flour (with added calcium, iron) 32%" — a declared
                // amount after the bracket belongs to the head, not the sub-list.
                if let close = tail.lastIndex(where: { $0 == ")" || $0 == "]" }) {
                    let after = String(tail[tail.index(after: close)...])
                    if after.contains("%") { head += " " + after.trimmingCharacters(in: .whitespaces) }
                    tail = String(tail[..<close])
                }
                let closed = tail.trimmingCharacters(in: CharacterSet(charactersIn: ")] "))
                inner = closed.split(whereSeparator: { $0 == "," || $0 == ";" })
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ._*:()[]")) }
                    .filter { !$0.isEmpty }
            }
            head = head.trimmingCharacters(in: CharacterSet(charactersIn: " ._*:"))
            guard !head.isEmpty else { return nil }
            return Token(head: head, inner: inner)
        }
    }

    enum GrainClass: Equatable { case whole, partial, refined }

    private static func contains(_ hay: String, any kws: [String]) -> Bool {
        kws.contains { hay.contains($0) }
    }

    /// Classify one ingredient phrase. Whole wins over refined so "whole wheat
    /// flour" (which contains "wheat flour") is whole; ignore words (malt,
    /// gluten, nut flours) are not grain bases at all.
    static func classify(_ phrase: String, cfg: RulesetV4.BreadConfig) -> GrainClass? {
        if contains(phrase, any: cfg.grainIgnoreKw) { return nil }
        if contains(phrase, any: cfg.wholeGrainKw) { return .whole }
        if contains(phrase, any: cfg.partialWholeKw) { return .partial }
        if contains(phrase, any: cfg.refinedKw) { return .refined }
        return nil
    }

    struct GrainBreakdown: Equatable {
        /// Position-weighted whole-grain share of the grain base, 0–1.
        let share: Double
        let hadGrainTokens: Bool
        let classified: [(String, GrainClass)]
        let note: String
        static func == (a: GrainBreakdown, b: GrainBreakdown) -> Bool {
            a.share == b.share && a.hadGrainTokens == b.hadGrainTokens && a.note == b.note
        }
    }

    /// Whole-grain share of the grain base. Grain tokens are ranked by
    /// position (labels are amount-ordered) with halving weights — the first
    /// grain is what the loaf is made of, the fourth is a sprinkle. A token
    /// whose parenthetical sub-list names grains ("organic wheat (organic
    /// wheat flour, organic whole wheat flour)") contributes its sub-grains in
    /// order instead of its head.
    static func wholeGrainShare(ingredientsText: String?, cfg: RulesetV4.BreadConfig) -> GrainBreakdown {
        guard let text = ingredientsText, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return GrainBreakdown(share: 0, hadGrainTokens: false, classified: [], note: "no list")
        }
        // (phrase, class, position index, declared percent)
        var grains: [(String, GrainClass, Int, Double?)] = []
        let toks = topLevelTokens(strippedText(text))
        let n = max(toks.count, 1)
        for (idx, tok) in toks.enumerated() {
            let headClass = classify(tok.head, cfg: cfg)
            let innerGrains = tok.inner.compactMap { raw -> (String, GrainClass, Double?)? in
                // Bare mill words inside a grain head inherit the grain:
                // "rye (flour, bran)" → rye flour, rye bran.
                let phrase = (headClass != nil && bareMillWords.contains(where: { raw == $0 || raw.hasPrefix($0 + " ") }))
                    ? tok.head + " " + raw : raw
                return classify(phrase, cfg: cfg).map { (phrase, $0, declaredPercent(raw)) }
            }
            if !innerGrains.isEmpty {
                // "wheat flour (wheat flour, calcium carbonate, …)" — the head and
                // its first sub-grain are the same thing; don't double count.
                if let headClass, innerGrains.count == 1, innerGrains[0].1 == headClass {
                    grains.append((tok.head, headClass, idx, declaredPercent(tok.head) ?? innerGrains[0].2))
                } else {
                    for g in innerGrains { grains.append((g.0, g.1, idx, g.2)) }
                }
            } else if let headClass {
                grains.append((tok.head, headClass, idx, declaredPercent(tok.head)))
            }
        }
        guard !grains.isEmpty else {
            return GrainBreakdown(share: 0, hadGrainTokens: false, classified: [], note: "no grain tokens")
        }
        // Weight = rank decay × list position (amount order), unless the
        // label declares a percentage — then the percentage is the weight.
        var num = 0.0, den = 0.0
        var rankW = 1.0
        for (_, c, idx, pct) in grains {
            let credit: Double
            switch c {
            case .whole: credit = 1.0
            case .partial: credit = cfg.partialCredit
            case .refined: credit = 0.0
            }
            let w = pct.map { max(0.001, $0 / 100) } ?? (rankW * Double(n - idx) / Double(n))
            num += credit * w
            den += w
            rankW *= cfg.rankDecay
        }
        let share = den > 0 ? num / den : 0
        let classified = grains.map { ($0.0, $0.1) }
        let desc = grains.prefix(6).map { "\($0.0)=\($0.1)" + ($0.3.map { String(format: " %.0f%%", $0) } ?? "") }
            .joined(separator: ", ")
        return GrainBreakdown(share: share, hadGrainTokens: true, classified: classified,
                              note: String(format: "share %.2f (%@)", share, desc))
    }

    private static let bareMillWords = ["flour", "bran", "flakes", "meal", "kernels", "grains", "germ", "semolina"]

    private static func strippedText(_ text: String) -> String {
        IngredientIntegrity.strippingTrailingStatements(text)
    }

    private static let percentRegex = try! NSRegularExpression(pattern: #"(\d+(?:[.,]\d+)?)\s*%"#)

    /// "wholemeal wheat flour (35%)" / "rye flour 12,5 %" → 35 / 12.5.
    static func declaredPercent(_ phrase: String) -> Double? {
        let ns = phrase as NSString
        guard let m = percentRegex.firstMatch(in: phrase, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let v = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")
        guard let d = Double(v), d > 0, d <= 100 else { return nil }
        return d
    }

    /// `wholeGrain` (`bread` variant): graded share, then label-truth checks.
    /// Returns (fraction, hadData, note).
    static func wholeGrainCredit(_ p: Product, cfg: RulesetV4.BreadConfig) -> (Double, Bool, String) {
        let gb = wholeGrainShare(ingredientsText: p.ingredientsText, cfg: cfg)
        let name = p.name.lowercased()
        let tags = Set((p.categories ?? []) + (p.labels ?? []))
        guard gb.hadGrainTokens else {
            // No list (or no grain words in it): tag / name evidence only,
            // unknown-tier — never full credit on a claim.
            let claimed = !tags.isDisjoint(with: cfg.wholeTagFallback)
                || contains(name, any: cfg.nameWholeClaims)
            let f = claimed ? cfg.unknownWholeCredit : cfg.unknownCredit
            return (f, false, "wholeGrain bread: \(gb.note) → \(claimed ? "claimed" : "unclaimed") prior \(String(format: "%.2f", f))")
        }
        var share = gb.share
        var notes = [gb.note]
        // Regulated / explicit front-label claim ("100% whole wheat", UK
        // "wholemeal" bread must be all-wholemeal flour by law) backs a
        // whole-first list up to near-full credit — but never rescues a list
        // whose first grain is refined.
        if share >= 0.5, contains(name, any: cfg.nameWholeClaims),
           gb.classified.first?.1 == .whole, share < cfg.nameClaimShare {
            notes.append(String(format: "name claim → %.2f", cfg.nameClaimShare))
            share = cfg.nameClaimShare
        }
        // Fiber cross-check: a whole-grain claim must show up on the panel.
        if share >= 0.5, let fiber = p.nutrients.fiber_g {
            for cap in cfg.fiberCaps.sorted(by: { $0.belowG < $1.belowG }) where fiber < cap.belowG {
                if share > cap.maxShare {
                    notes.append(String(format: "fiber %.1f g < %.1f → cap %.2f", fiber, cap.belowG, cap.maxShare))
                    share = cap.maxShare
                }
                break
            }
        }
        return (min(1, max(0, share)), true, "wholeGrain bread: " + notes.joined(separator: "; "))
    }

    // MARK: S2 — evidence-based processing

    /// Distinct ultra-processing marker *families* in the list (text phrases
    /// and additive codes both map to a family so "DATEM" + E472e count once).
    static func upfMarkerFamilies(_ p: Product, cfg: RulesetV4.BreadConfig) -> [String] {
        let hay = (p.ingredientsText ?? "").lowercased().replacingOccurrences(of: "_", with: "")
        let codes = Set(p.additives.compactMap { $0.code?.lowercased() })
        var found: [String] = []
        for m in cfg.upfMarkers {
            let textHit = m.text.contains { hay.contains($0) }
            let codeHit = !codes.isDisjoint(with: Set((m.codes ?? []).map { $0.lowercased() }))
            if textHit || codeHit { found.append(m.family) }
        }
        return found
    }

    /// S2 `bread`: 0 marker families → traditional bread credit (NOVA 3 is the
    /// best class a bread can be — flour + water + salt + leaven *is* NOVA 3);
    /// each marker family steps the credit down. With no ingredient list the
    /// OFF NOVA tag is the fallback, capped at the traditional credit (a
    /// bread tagged NOVA 1 is a data error, not a whole food).
    static func s2Credit(_ p: Product, cfg: RulesetV4.BreadConfig) -> (Double, Bool, String) {
        let hasList = !(p.ingredientsText ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        guard hasList else {
            switch p.novaGroup {
            case 1, 2, 3: return (cfg.s2.traditional, true, "S2 bread: no list, NOVA \(p.novaGroup) → traditional cap")
            case 4: return (cfg.s2.novaFourNoList, true, "S2 bread: no list, NOVA 4")
            default: return (cfg.s2.unknownCredit, false, "S2 bread: no list, no NOVA")
            }
        }
        let fams = upfMarkerFamilies(p, cfg: cfg)
        let n = fams.count
        let f: Double
        if n == 0 {
            f = cfg.s2.traditional
        } else {
            let ladder = cfg.s2.markerCredits
            f = ladder[min(n, ladder.count) - 1]
        }
        let note = n == 0
            ? "S2 bread: no ultra-processing markers → traditional \(String(format: "%.2f", f))"
            : "S2 bread: \(n) marker famil\(n == 1 ? "y" : "ies") (\(fams.joined(separator: ", "))) → \(String(format: "%.2f", f))"
        return (f, true, note)
    }

    // MARK: S12 — grain nutrition (fiber + protein)

    static func hasIsolatedFiber(_ p: Product, cfg: RulesetV4.BreadConfig) -> Bool {
        let hay = (p.ingredientsText ?? "").lowercased()
        return cfg.isolatedFiberKw.contains { hay.contains($0) }
    }

    /// Fiber per 100 g is the axis the whole-grain literature actually runs
    /// on (plus the part of the panel bread always declares); protein
    /// separates sprouted / seeded loaves from starch-based ones. No per-kcal
    /// density (bread is ~250 kcal across the board) and no fruit/veg share.
    /// Isolated fibers (oat fiber, cellulose, polydextrose, inulin) on a
    /// non-whole-grain base earn half — the evidence for added isolated
    /// fiber is weaker than for intrinsic cereal fiber (FDA 2016 fiber rule).
    static func s12GrainCredit(_ p: Product, cfg: RulesetV4.BreadConfig) -> (Double, Bool, String) {
        let g = cfg.s12
        let n = p.nutrients
        let protCredit = n.protein_g.map { min(1, max(0, $0 / g.proteinTargetG)) }
        if let fiber = n.fiber_g {
            var fib = min(1, max(0, (fiber - g.fiberZeroG) / (g.fiberFullG - g.fiberZeroG)))
            var notes: [String] = [String(format: "fiber %.1f g → %.2f", fiber, fib)]
            if hasIsolatedFiber(p, cfg: cfg) {
                let share = wholeGrainShare(ingredientsText: p.ingredientsText, cfg: cfg).share
                if share < 0.5 {
                    fib *= g.isolatedFiberDamp
                    notes.append(String(format: "isolated fiber ×%.2f", g.isolatedFiberDamp))
                }
            }
            let pr = protCredit ?? 0.5
            notes.append(String(format: "protein %@ → %.2f", n.protein_g.map { String(format: "%.1f g", $0) } ?? "n/a", pr))
            let f = g.fiberWeight * fib + g.proteinWeight * pr
            return (f, true, "S12 grain: " + notes.joined(separator: ", "))
        }
        // Fiber undeclared: prior from the whole-grain evidence, unknown-tier.
        let share = wholeGrainShare(ingredientsText: p.ingredientsText, cfg: cfg).share
        let prior = share >= 0.5 ? g.unknownFiberPriorWhole : g.unknownFiberPrior
        let pr = protCredit ?? 0.5
        let f = g.fiberWeight * prior + g.proteinWeight * pr
        return (f, false, String(format: "S12 grain: fiber undeclared → prior %.2f (share %.2f), protein → %.2f", prior, share, pr))
    }

    // MARK: S4 — sodium plausibility

    /// OFF community data regularly carries salt in the wrong unit (0.001 g
    /// for 1 g). A bread that lists salt yet declares under
    /// `minSodiumMgWithSalt` per 100 g is a data error, not a low-salt loaf.
    static func sodiumIsImplausible(_ p: Product, cfg: RulesetV4.BreadConfig) -> Bool {
        guard let na = p.nutrients.sodium_mg, na < cfg.sodium.minSodiumMgWithSalt,
              let text = p.ingredientsText else { return false }
        let tokens = IngredientIntegrity.tokens(from: text)
        return tokens.contains { t in
            cfg.sodium.saltWords.contains { t == $0 || t.hasSuffix(" " + $0) || t.hasPrefix($0 + " ") }
        }
    }
}
