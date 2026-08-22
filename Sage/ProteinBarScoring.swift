import Foundation

/// V5.5 — protein-bar rule shapes (`protein_bars` profile). All tunables live
/// in `RulesetV5.json` → `proteinBars`; this file only knows the shapes.
///
/// Why protein bars get their own rules (SCORING_V5.md §"V5.5.0 Protein bars"):
/// - they rode `snacks` / `general` depending on whether OFF happened to tag
///   `snacks` (OFF files `protein-bars` under *bodybuilding-supplements*), so
///   the same bar scored 54–68 across barcodes;
/// - protein — the reason the product exists — carried 4 % of the score, and
///   the protein sources that make it a protein bar (whey / milk / soy
///   isolates) were docked four separate times (S1 text signal, S2 NOVA-4,
///   S12 isolate discount, S14 isolate score);
/// - a date bar with 4 g protein and 40 g sugar/100 g outscored every real
///   protein bar because FVN ≈ 100 laundered its sugar to zero.
///
/// What the profile measures (health only, Sage identity):
/// - S12 `proteinBar`: protein *delivery* — grams per serving + share of
///   energy (amount), source quality on a DIAAS-style table weighted by label
///   position × typical protein density (a collagen pad counts 0.25), and
///   fiber with isolated fibers at half credit;
/// - S2 `proteinBar`: evidence-based processing — distinct ultra-processing
///   marker *families* in the list (flavors, NNS, polyols, humectants, refined
///   syrups, isolated fibers, emulsifiers, gums, refined hard fats, compound
///   coatings, colors, preservatives, modified starch). Protein isolates are
///   never a marker: they are the point of the product;
/// - S3 `proteinBar`: the fruit/veg/nut sugar discount is capped (date paste
///   is free sugar in the UK definition; at least half counts);
/// - S6 `proteinBar`: the drinks sweetener tiers plus a declared-polyol load
///   dock (EU labels carry "of which polyols");
/// - S14 `proteinBar`: protein sources are neutral in the real-food ratio
///   (neither whole food nor a dock) and protein isolate markers don't count
///   against the list; syrups / maltodextrin / modified starch still do.
enum ProteinBarScoring {

    // MARK: Routing

    static func fallbackProfiles(_ rs: RulesetV4) -> Set<String> {
        Set(rs.proteinBars?.gate.fallbackProfiles ?? ["snacks", "general", "grains", "whole_foods"])
    }

    /// Composition envelope for anything wearing a protein-bar tag: OFF's
    /// `protein-bars` tag is inherited by protein powders and shakes.
    static func passesGuard(_ p: Product, rs: RulesetV4) -> Bool {
        guard let g = rs.proteinBars?.gate else { return true }
        let n = p.nutrients
        if let kcal = n.kcal, kcal < g.minKcal || kcal > g.maxKcal { return false }
        if let prot = n.protein_g, prot > g.maxProteinG { return false }
        return true
    }

    /// Share of energy from protein (4 kcal/g), nil without both inputs.
    static func proteinShareOfEnergy(_ n: Nutrients) -> Double? {
        guard let prot = n.protein_g, let kcal = n.kcal, kcal > 0 else { return nil }
        return prot * 4 / kcal
    }

    private static func wordMatch(_ word: String, in text: String) -> Bool {
        if word.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }),
           word.unicodeScalars.allSatisfy({ $0.isASCII }) {
            return text.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: word))\b"#,
                              options: .regularExpression) != nil
        }
        return text.contains(word)
    }

    static func looksLikeBar(_ p: Product, rs: RulesetV4) -> Bool {
        guard let g = rs.proteinBars?.gate else { return false }
        let tags = Set(p.categories ?? [])
        if !tags.isDisjoint(with: g.barTags) { return true }
        let name = p.name.lowercased()
        if g.barWords.contains(where: { wordMatch($0, in: name) }) { return true }
        // OFF US imports often carry no categories and a flavor-only name
        // ("Chocolate Sea Salt"); the brand is where "bar" lives (RXBAR,
        // Quest Bar, Perfect Bar, Larabar, GoMacro MacroBar).
        let brand = p.brand.lowercased()
        return g.barWords.contains(where: { wordMatch($0, in: brand) }) || brand.hasSuffix("bar")
    }

    static func namedProtein(_ p: Product, rs: RulesetV4) -> Bool {
        guard let g = rs.proteinBars?.gate else { return false }
        let name = p.name.lowercased()
        return g.proteinWords.contains { wordMatch($0, in: name) }
    }

    /// Tag-independent gate: a bar (tag or name) inside the composition
    /// envelope that is either marketed on protein (protein word in the name,
    /// ≥ 12 % of energy from protein — the EU "source of protein" claim floor)
    /// or genuinely high-protein (≥ 20 % of energy, the EU "high protein"
    /// claim, and ≥ 10 g/100 g). Neither name nor tag alone qualifies.
    static func hasProteinBarEvidence(_ p: Product, rs: RulesetV4) -> Bool {
        guard let g = rs.proteinBars?.gate else { return false }
        guard looksLikeBar(p, rs: rs), passesGuard(p, rs: rs) else { return false }
        guard let share = proteinShareOfEnergy(p.nutrients), let prot = p.nutrients.protein_g else { return false }
        if namedProtein(p, rs: rs), share >= g.minProteinShareNamed { return true }
        return share >= g.minProteinShareUnnamed && prot >= g.minProteinGUnnamed
    }

    // MARK: Serving

    private static let gramsRegex = try! NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)\s*(?:g|gr|gram|grams|gramm|grammes|grammi|gramos|gramas)\b"#)
    private static let ouncesRegex = try! NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)\s*(?:oz|onz|ounce|ounces)\b"#)

    /// "1 bar (60 g)" / "60g" / "2.12 oz (60 g)" / "45 gram" → grams.
    static func parseGrams(_ raw: String?) -> Double? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let s = raw.lowercased().replacingOccurrences(of: "\u{00a0}", with: " ")
        let ns = s as NSString
        if let m = gramsRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            let v = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")
            if let d = Double(v), d > 0 { return d }
        }
        if let m = ouncesRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            // "fl oz" is a liquid serving, never a bar.
            let prefix = ns.substring(to: m.range.location)
            if prefix.hasSuffix("fl ") || prefix.hasSuffix("fl.") || prefix.hasSuffix("fl") { return nil }
            let v = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")
            if let d = Double(v), d > 0 { return d * 28.3495 }
        }
        return nil
    }

    /// Serving in grams: declared serving, else the pack size when it is a
    /// single bar, else the configured default (flagged estimated).
    static func servingGrams(_ p: Product, cfg: RulesetV4.ProteinBarConfig) -> (grams: Double, estimated: Bool) {
        let s = cfg.serving
        if let g = parseGrams(p.servingSize), g >= s.minG, g <= s.maxG { return (g, false) }
        if let g = parseGrams(p.size), g >= s.minG, g <= s.maxG { return (g, false) }
        return (s.defaultG, true)
    }

    // MARK: S12 — protein delivery

    struct SourceHit: Equatable {
        let phrase: String
        let match: String
        var credit: Double
        let weight: Double
    }

    private static let sourceSkipWords = [
        "fiber", "fibre", "lecithin", "oil", "starch", "syrup", "extract", "flavor", "flavour",
        "aroma", "arôme", "emulsifier", "colour", "color", "sweetener", "butter oil",
    ]

    private static func bestSource(for phrase: String, cfg: RulesetV4.ProteinBarConfig) -> RulesetV4.ProteinBarConfig.Source? {
        if sourceSkipWords.contains(where: { phrase.contains($0) }) { return nil }
        var best: RulesetV4.ProteinBarConfig.Source? = nil
        for src in cfg.s12.sources where phrase.contains(src.match) {
            if best == nil || src.match.count > best!.match.count { best = src }
        }
        return best
    }

    /// Position-weighted source quality. Labels are amount-ordered, so each
    /// successive source carries `rankDecay` of the previous one's weight,
    /// scaled by the source's typical protein density (a whole-food peanut at
    /// 25 % protein contributes far less of the bar's protein than a 90 %
    /// isolate listed after it). Parenthetical sub-lists ("protein blend
    /// (milk protein isolate, whey protein isolate)") contribute their
    /// specific sources instead of the head.
    static func proteinQuality(ingredientsText: String?, cfg: RulesetV4.ProteinBarConfig) -> (credit: Double?, hits: [SourceHit]) {
        guard let text = ingredientsText, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return (nil, []) }
        let toks = BreadScoring.topLevelTokens(IngredientIntegrity.strippingTrailingStatements(text))
        var hits: [SourceHit] = []
        var rankW = 1.0
        func add(_ phrase: String, _ src: RulesetV4.ProteinBarConfig.Source) {
            hits.append(SourceHit(phrase: phrase, match: src.match, credit: src.credit, weight: rankW * src.density))
            rankW *= cfg.s12.rankDecay
        }
        for tok in toks {
            let innerHits = tok.inner.compactMap { raw -> (String, RulesetV4.ProteinBarConfig.Source)? in
                bestSource(for: raw, cfg: cfg).map { (raw, $0) }
            }
            if !innerHits.isEmpty {
                for (phrase, src) in innerHits { add(phrase, src) }
            } else if let src = bestSource(for: tok.head, cfg: cfg) {
                add(tok.head, src)
            }
        }
        guard !hits.isEmpty else { return (nil, []) }
        // Complementary plant blends (pea + rice) cover each other's limiting
        // amino acids; both members take the blend credit.
        for pair in cfg.s12.complementaryPairs where pair.count == 2 {
            let a = hits.contains { $0.match == pair[0] }, b = hits.contains { $0.match == pair[1] }
            if a, b {
                for i in hits.indices where pair.contains(hits[i].match) {
                    hits[i].credit = max(hits[i].credit, cfg.s12.complementaryCredit)
                }
            }
        }
        let den = hits.reduce(0.0) { $0 + $1.weight }
        guard den > 0 else { return (nil, hits) }
        let num = hits.reduce(0.0) { $0 + $1.credit * $1.weight }
        return (min(1, max(0, num / den)), hits)
    }

    /// Isolated-fiber ingredient among the first three tokens — then most of
    /// the declared fiber is the isolate, not the food matrix.
    static func leadsWithIsolatedFiber(_ p: Product, cfg: RulesetV4.ProteinBarConfig) -> Bool {
        guard let text = p.ingredientsText else { return false }
        guard let fam = cfg.s2.upfMarkers.first(where: { $0.family == "isolated fibers" }) else { return false }
        let toks = BreadScoring.topLevelTokens(IngredientIntegrity.strippingTrailingStatements(text)).prefix(3)
        return toks.contains { tok in
            let phrases = [tok.head] + tok.inner
            return phrases.contains { ph in fam.text.contains { ph.contains($0) } }
        }
    }

    static func s12Credit(_ p: Product, cfg: RulesetV4.ProteinBarConfig) -> (Double, Bool, String) {
        let g = cfg.s12
        let n = p.nutrients
        guard let prot = n.protein_g else {
            return (g.unknownCredit, false, "protein undeclared → unknown")
        }
        let (serving, estimated) = servingGrams(p, cfg: cfg)
        let perServing = prot * serving / 100
        let servingCredit = min(1, max(0, perServing / g.servingFullG))
        var notes: [String] = []
        let amount: Double
        if let share = proteinShareOfEnergy(n) {
            let shareCredit = min(1, max(0, share / g.shareFull))
            amount = 0.5 * servingCredit + 0.5 * shareCredit
            notes.append(String(format: "%.1f g/serving (%.0f g%@) share %.2f → amount %.2f",
                                perServing, serving, estimated ? " est." : "", share, amount))
        } else {
            amount = servingCredit
            notes.append(String(format: "%.1f g/serving (%.0f g%@), kcal unknown → amount %.2f",
                                perServing, serving, estimated ? " est." : "", amount))
        }
        let q = proteinQuality(ingredientsText: p.ingredientsText, cfg: cfg)
        let quality = q.credit ?? g.unknownQuality
        if let c = q.credit {
            let srcs = q.hits.prefix(4).map { $0.match }.joined(separator: ", ")
            notes.append(String(format: "quality %.2f (%@)", c, srcs))
        } else {
            notes.append(String(format: "quality unknown → %.2f", quality))
        }
        let fiber: Double
        if let f = n.fiber_g {
            var fc = min(1, max(0, f / g.fiberFullG))
            var fnote = String(format: "fiber %.1f g", f)
            if leadsWithIsolatedFiber(p, cfg: cfg) {
                fc *= g.isolatedFiberDamp
                fnote += String(format: " isolated ×%.2f", g.isolatedFiberDamp)
            }
            fiber = fc
            notes.append(fnote + String(format: " → %.2f", fc))
        } else {
            fiber = g.unknownFiberCredit
            notes.append(String(format: "fiber undeclared → %.2f", fiber))
        }
        // Quality only matters for protein that is actually there: a 4 g
        // date-and-nut bar must not bank a quality prior, and a collagen pad
        // scales a real 20 g down rather than being averaged in.
        let proteinCredit = amount * (g.qualityFloor + (1 - g.qualityFloor) * quality)
        notes.append(String(format: "protein %.2f", proteinCredit))
        let f = g.proteinWeight * proteinCredit + g.fiberWeight * fiber
        return (min(1, max(0, f)), true, notes.joined(separator: "; "))
    }

    // MARK: S2 — evidence-based processing

    static func upfMarkerFamilies(_ p: Product, cfg: RulesetV4.ProteinBarConfig) -> [String] {
        let hay = (p.ingredientsText ?? "").lowercased().replacingOccurrences(of: "_", with: "")
        let codes = Set(p.additives.compactMap { $0.code?.lowercased() })
        var found: [String] = []
        for m in cfg.s2.upfMarkers {
            let textHit = m.text.contains { hay.contains($0) }
            let codeHit = !codes.isDisjoint(with: Set((m.codes ?? []).map { $0.lowercased() }))
            if textHit || codeHit { found.append(m.family) }
        }
        return found
    }

    /// Share of top-level tokens the engine can name: whole-food whitelist,
    /// protein source, marker family, water, salt, or an additive code.
    /// OFF's OCR'd `ingredients_text` is regularly a nutrition table, a
    /// best-before line or a language the marker lists don't cover — for
    /// those, "no markers found" must not read as "clean".
    static func recognizedShare(_ p: Product, cfg: RulesetV4.ProteinBarConfig) -> Double? {
        guard let text = p.ingredientsText, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let toks = BreadScoring.topLevelTokens(IngredientIntegrity.strippingTrailingStatements(text))
        guard !toks.isEmpty else { return nil }
        let markerText = cfg.s2.upfMarkers.flatMap { $0.text }
        let saltWords = ["salt", "sea salt", "sel", "sale", "salz", "sal", "zout", "suola"]
        var hits = 0
        for tok in toks {
            let phrases = [tok.head] + tok.inner
            let ok = phrases.contains { ph in
                IngredientIntegrity.isWholeFoodToken(ph)
                    || IngredientIntegrity.isWaterToken(ph)
                    || saltWords.contains(ph)
                    || bestSource(for: ph, cfg: cfg) != nil
                    || markerText.contains { ph.contains($0) }
                    || ph.range(of: #"\be\d{3}[a-z]?\b"#, options: .regularExpression) != nil
            }
            if ok { hits += 1 }
        }
        return Double(hits) / Double(toks.count)
    }

    static func s2Credit(_ p: Product, cfg: RulesetV4.ProteinBarConfig) -> (Double, Bool, String) {
        let hasList = !(p.ingredientsText ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        guard hasList else {
            switch p.novaGroup {
            case 1, 2: return (cfg.s2.novaLowNoList, true, "S2 protein bar: no list, NOVA \(p.novaGroup)")
            case 3: return (cfg.s2.novaThreeNoList, true, "S2 protein bar: no list, NOVA 3")
            case 4: return (cfg.s2.novaFourNoList, true, "S2 protein bar: no list, NOVA 4")
            default: return (cfg.s2.unknownCredit, false, "S2 protein bar: no list, no NOVA")
            }
        }
        if let share = recognizedShare(p, cfg: cfg), share < cfg.s2.minRecognizedShare {
            return (cfg.s2.unknownCredit, false,
                    String(format: "S2 protein bar: list not recognized (%.0f%% known tokens) → unknown", share * 100))
        }
        let fams = upfMarkerFamilies(p, cfg: cfg)
        let n = fams.count
        let f: Double
        if n == 0 {
            f = cfg.s2.clean
        } else {
            let ladder = cfg.s2.markerCredits
            f = ladder[min(n, ladder.count) - 1]
        }
        let note = n == 0
            ? "S2 protein bar: no ultra-processing markers → \(String(format: "%.2f", f))"
            : "S2 protein bar: \(n) marker famil\(n == 1 ? "y" : "ies") (\(fams.joined(separator: ", "))) → \(String(format: "%.2f", f))"
        return (f, true, note)
    }

    // MARK: S6 — sweeteners + polyol load

    static func s6Credit(_ p: Product, cfg: RulesetV4.ProteinBarConfig) -> (Double, Bool, String?) {
        if let share = recognizedShare(p, cfg: cfg), share < cfg.s2.minRecognizedShare {
            return (0.50, false, "S6 protein bar: list not recognized → unknown")
        }
        let base = DrinksScoring.s6Credit(p)
        var f = base.0
        var note: String? = nil
        // An EU "sweeteners (...)" declaration whose specific names were lost
        // (truncated OCR) is still a sweetened product — unspecified, not none.
        if base.1, f >= 0.999 {
            let hay = (p.ingredientsText ?? "").lowercased()
            let generic = ["sweetener", "sweeteners", "édulcorant", "edulcorante", "dolcificante",
                           "süßungsmittel", "süssungsmittel", "zoetstof", "sötningsmedel", "sødemiddel",
                           "søtningsstoff", "makeutusaine", "substancja słodząca", "substancje słodzące", "sladidl"]
            let negated = ["no sweetener", "no artificial sweetener", "without sweetener", "sans édulcorant",
                           "sin edulcorante", "senza dolcificant", "ohne süßungsmittel", "zonder zoetstof"]
            if generic.contains(where: { hay.contains($0) }), !negated.contains(where: { hay.contains($0) }) {
                return (0.5, true, "S6 protein bar: sweeteners declared, none identified → 0.50")
            }
        }
        if base.1, let poly = p.nutrients.polyols_g, poly > 0 {
            let steps = cfg.s6.polyolLoadG
            let factors = cfg.s6.polyolLoadFactors
            var factor = 1.0
            for (i, g) in steps.enumerated() where poly >= g && i < factors.count {
                factor = factors[i]
            }
            if factor < 1 {
                f *= factor
                note = String(format: "S6 protein bar: %.1f g polyols/100 g → ×%.2f", poly, factor)
            }
        }
        return (min(1, max(0, f)), base.1, note)
    }

    // MARK: S14 — real food with protein sources neutral

    static func s14Credit(_ p: Product, cfg: RulesetV4.ProteinBarConfig) -> (Double, Bool, String?) {
        let b = IngredientIntegrity.evaluate(ingredientsText: p.ingredientsText,
                                            neutralTokenKw: cfg.s14.neutralTokenKw,
                                            neutralIsolateMarkers: cfg.s14.neutralIsolateMarkers)
        guard b.hadData else { return (0, false, nil) }
        let note = String(format: "S14 protein bar: whole %.2f, count %d, sweetener %.2f, isolate %.2f (protein sources neutral)",
                          b.wholeFoodRatio, b.ingredientCount, b.sweetenerScore, b.isolateScore)
        return (b.fraction, true, note)
    }
}
