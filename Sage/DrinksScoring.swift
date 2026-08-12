import Foundation

// MARK: - Drinks scoring v2.3 (cap-based)
//
// Profiles `drinks` and `juice_100`. Shared utilities: effective serving,
// sugar/caffeine/sweetener caps, tiered S6, S8 caffeine. Wired from ScoringEngineV4.

struct DrinksEffectiveServing: Equatable {
    let ml: Double
    /// True when we fell back to 355 ml (container unknown/oversized + no sane serving).
    let estimatedServing: Bool
    /// True when container ≤600 ml forced whole-container serving (anti-gaming).
    let usedWholeContainer: Bool
}

struct DrinksScoreBreakdown {
    let profileId: String
    let effectiveServingMl: Double
    let estimatedServing: Bool
    let lowDataConfidence: Bool
    let sugarPerServingG: Double?
    let caffeinePerServingMg: Double?
    let caffeineEstimated: Bool
    let sugarCap: Int
    let caffeineCap: Int
    let sweetenerCap: Int
    /// M3: cream visibility — 100 when satfat is trace or data is missing.
    let satFatCap: Int
    /// Cap id that bound the final score, if any (`sugarCap` / `caffeineCap` / `sweetenerCap`).
    let bindingCapId: String?
    let weightedScore: Int
    let finalScore: Int
    let rules: [V4RuleResult]
    /// Tier-1 / Tier-2 reason keys for S6 hits (UI copy).
    let sweetenerReasonKeys: [String]
    /// Non-exempt additives + sweetener hits (summary / golden table).
    let riskFactorCount: Int
    /// Flat +3 applied on juice_100 (0 otherwise).
    let micronutrientBoost: Int
    /// Merit credits earned (brew polyphenols / dairy nutrition), applied
    /// before caps — a capped product can never merit its way up.
    let meritBoost: Int
    /// Post-rule diet/energy stacking drag (points).
    let stackingDrag: Int
    /// Packaging leach-pathway credit (glass 1.0 → PVC 0.0), surfaced as a
    /// sustainability badge. **Not part of the health score** — the evidence
    /// does not support ranking one clean liquid above another on its bottle.
    let packagingCredit: Double
    /// False when packaging material is missing or unrecognized.
    let packagingHadData: Bool
}

enum DrinksScoring {

    static let floorScore = 10
    static let singleServeMaxMl: Double = 600
    static let fallbackServingMl: Double = 355

    // MARK: Effective serving (anti-gaming)

    /// Shared by sugar, caffeine, sodium, and all drinks / juice_100 caps.
    ///
    /// Anti-gaming: container ≤600 ml → whole container. Larger containers use a
    /// genuine declared serving when present; OFF nutrition-panel "100 ml"
    /// references are discarded and replaced by a category-typical dose.
    /// Smallest plausible drink container; below this the parse is treated as
    /// junk data rather than a real serving (fuzzer finding — a "5 ml" soda
    /// would otherwise score its sugar load on a 5 ml dose).
    static let minPlausibleContainerMl: Double = 30

    static func effectiveServing(for product: Product) -> DrinksEffectiveServing {
        let containerMl = parseVolumeMilliliters(product.size)
        if let c = containerMl, c >= minPlausibleContainerMl, c <= singleServeMaxMl {
            return DrinksEffectiveServing(ml: c, estimatedServing: false, usedWholeContainer: true)
        }

        let declared = parseVolumeMilliliters(product.servingSize)

        // Large multi-serve package + ~100 ml panel reference → ignore panel, use category dose.
        if let c = containerMl, c > singleServeMaxMl,
           let s = declared, isPanelReferenceServing(ml: s) {
            let dose = categoryTypicalDoseMl(for: product)
            return DrinksEffectiveServing(ml: dose, estimatedServing: true, usedWholeContainer: false)
        }

        // Genuine consumption serving surviving panel-ref discard. Field QA:
        // on a multi-serve container the declared serving is floored at the
        // category-typical dose — a 1 L cola declaring a 250 ml serving was
        // scoring 29 while the identical liquid in a 355 ml can scored 20.
        // Same anti-gaming rationale as whole-container ≤600 ml.
        if let s = declared, s >= 100, s <= singleServeMaxMl {
            if let c = containerMl, c > singleServeMaxMl {
                let dose = categoryTypicalDoseMl(for: product)
                if s < dose {
                    return DrinksEffectiveServing(ml: dose, estimatedServing: true,
                                                  usedWholeContainer: false)
                }
            }
            return DrinksEffectiveServing(ml: s, estimatedServing: false, usedWholeContainer: false)
        }

        return DrinksEffectiveServing(ml: fallbackServingMl, estimatedServing: true, usedWholeContainer: false)
    }

    /// OFF nutrition-panel reference (~100 ml), not a consumption dose.
    static func isPanelReferenceServing(ml: Double) -> Bool {
        abs(ml - 100) < 1.0
    }

    /// Category-typical consumption dose when a panel reference is discarded.
    static func categoryTypicalDoseMl(for product: Product) -> Double {
        if isEnergyDrink(product) { return 250 }
        if isSportsOrElectrolyte(product) { return 355 }
        if isColaSoda(product) || isSoftDrinkOrSoda(product) { return 355 }
        if isIcedCoffee(product) || isIcedTea(product) { return 355 }
        if isJuiceCategory(product) { return 200 }  // glass-dose; juice_100 shares this path
        return fallbackServingMl
    }

    static func isSoftDrinkOrSoda(_ p: Product) -> Bool {
        let tags = (p.categories ?? []).map { $0.lowercased() }
        let needles = ["sodas", "soft-drinks", "colas", "carbonated-drinks", "sweetened-beverages"]
        return tags.contains { tag in needles.contains { tag.contains($0) } }
    }

    /// Cached volume parsers — built once; safe under Swift Testing parallelism.
    /// Negative lookbehind rejects minus-signed quantities ("-5 ml" is junk,
    /// not a 5 ml container) — found by the property fuzzer.
    private static let volumeParsers: [(NSRegularExpression, Double)] = {
        let specs: [(String, Double)] = [
            (#"(?<!-)(\d+(?:\.\d+)?)\s*(?:fl\.?\s*oz|floz|fluid\s*ounces?)"#, 29.5735),
            (#"(?<!-)(\d+(?:\.\d+)?)\s*ml\b"#, 1.0),
            (#"(?<!-)(\d+(?:\.\d+)?)\s*cl\b"#, 10.0),
            (#"(?<!-)(\d+(?:\.\d+)?)\s*l\b"#, 1000.0),
        ]
        return specs.compactMap { pattern, factor in
            (try? NSRegularExpression(pattern: pattern)).map { ($0, factor) }
        }
    }()

    /// Parse free-form volume text (quantity / serving_size) → ml.
    static func parseVolumeMilliliters(_ raw: String?) -> Double? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let s = raw.lowercased()
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "\u{00a0}", with: " ")

        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        for (re, factor) in volumeParsers {
            if let match = re.firstMatch(in: s, range: full),
               match.numberOfRanges >= 2,
               match.range(at: 1).location != NSNotFound {
                let value = Double(ns.substring(with: match.range(at: 1))) ?? 0
                if value > 0 { return value * factor }
            }
        }
        return nil
    }

    // MARK: Category helpers

    static func isJuiceCategory(_ p: Product) -> Bool {
        let tags = (p.categories ?? []).map { $0.lowercased() }
        return tags.contains { $0.contains("juice") || $0.contains("nectar") }
    }

    /// Juice tags without nectar — used for juice_100 eligibility.
    static func isPureJuiceCategory(_ p: Product) -> Bool {
        let tags = (p.categories ?? []).map { $0.lowercased() }
        let hasJuice = tags.contains { $0.contains("juice") }
        let hasNectar = tags.contains { $0.contains("nectar") }
        return hasJuice && !hasNectar
    }

    static func isSportsOrElectrolyte(_ p: Product) -> Bool {
        let tags = (p.categories ?? []).map { $0.lowercased() }
        let needles = ["sports-drink", "sports-drinks", "electrolyte", "isotonic", "energy-hydration"]
        return tags.contains { tag in needles.contains { tag.contains($0) } }
            || tags.contains("sports-drinks")
    }

    static func isEnergyDrink(_ p: Product, ruleset rs: RulesetV4 = .bundled) -> Bool {
        let tags = (p.categories ?? []).map { $0.lowercased() }
        if tags.contains(where: { $0.contains("energy-drink") }) { return true }
        return hasEnergyDrinkEvidence(p, rs: rs)
    }

    /// Caffeine ≥ threshold AND a stimulant ingredient — independent of OFF tags.
    static func hasEnergyDrinkEvidence(_ p: Product, rs: RulesetV4 = .bundled) -> Bool {
        guard let cfg = rs.energyDrinkEvidence else { return false }
        // Measured caffeine only — category defaults would recurse through isEnergyDrink.
        guard let caf = p.caffeine_mg, caf >= cfg.minCaffeineMgPer100ml else { return false }
        return matchesStimulantIngredients(p, names: cfg.stimulantIngredients)
    }

    static func isColaSoda(_ p: Product) -> Bool {
        let tags = (p.categories ?? []).map { $0.lowercased() }
        let hay = ([p.name] + tags).joined(separator: " ").lowercased()
        return hay.contains("cola") || tags.contains { $0.contains("colas") }
    }

    static func isIcedTea(_ p: Product) -> Bool {
        let tags = (p.categories ?? []).map { $0.lowercased() }
        return tags.contains { $0.contains("iced-tea") }
    }

    static func isIcedCoffee(_ p: Product) -> Bool {
        let tags = (p.categories ?? []).map { $0.lowercased() }
        return tags.contains { $0.contains("iced-coffee") || $0.contains("coffee-drink") }
    }

    private static let juice100AllowedAdditiveCodes: Set<String> = [
        "e300", "e330",
    ]
    private static let juice100AllowedAdditiveNames = [
        "ascorbic acid", "acido ascorbico", "citric acid", "acido citrico",
    ]

    /// 100% juice profile entry — ALL criteria must hold.
    static func qualifiesAsJuice100(_ p: Product) -> Bool {
        guard isPureJuiceCategory(p) else { return false }
        let fvn = p.nutrients.fvn ?? 0
        guard fvn >= 95 else { return false }
        if let added = p.nutrients.addedSugar_g, added > 0 { return false }

        let tiers = detectSweetenerTiers(p)
        if tiers.hadData && (tiers.tier1 + tiers.tier2 + tiers.tier3) > 0 { return false }
        // Missing ingredient data: cannot confirm "no sweeteners / only ascorbic|citric".
        if !tiers.hadData { return false }

        for add in p.additives {
            let code = add.code?.lowercased() ?? ""
            if juice100AllowedAdditiveCodes.contains(code) { continue }
            let name = folded(add.name)
            if juice100AllowedAdditiveNames.contains(where: { name.contains(folded($0)) }) {
                continue
            }
            // Unknown / empty code with unrecognized name → disqualify.
            return false
        }
        return true
    }

    // MARK: Curves

    /// Piecewise-linear interpolation over ascending `anchors`; flat outside the range.
    /// Non-increasing anchors therefore yield a non-increasing curve (I20).
    static func interpolate(_ x: Double, anchors: [(Double, Double)]) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return 0 }
        if x <= first.0 { return first.1 }
        if x >= last.0 { return last.1 }
        for i in 0..<(anchors.count - 1) {
            let (x0, y0) = anchors[i]
            let (x1, y1) = anchors[i + 1]
            if x <= x1 {
                let t = (x - x0) / (x1 - x0)
                return y0 + (y1 - y0) * t
            }
        }
        return last.1
    }

    // MARK: Caps

    /// Sugar cap per effective serving (regular drinks). 100 = no cap.
    static func sugarCap(gramsPerServing: Double) -> Int {
        if gramsPerServing <= 16 { return 100 }
        if gramsPerServing >= 30 { return 20 }
        let t = (gramsPerServing - 16) / (30 - 16)
        return Int((55.0 + (20.0 - 55.0) * t).rounded())
    }

    /// Juice_100 sugar cap — J-curve (glass OK, bottle-dose capped).
    static func juiceSugarCap(gramsPerServing: Double) -> Int {
        if gramsPerServing <= 20 { return 100 }
        if gramsPerServing >= 40 { return 36 }
        let t = (gramsPerServing - 20) / (40 - 20)
        return Int((60.0 + (36.0 - 60.0) * t).rounded())
    }

    /// Caffeine cap per effective serving (Track 2). 100 = no cap.
    /// Starts biting at 60 mg rather than 80, and lands harder at the top of
    /// the range. Monotonically non-increasing by construction (I20).
    static let caffeineCapAnchors: [(Double, Double)] = [
        (60, 100), (160, 52), (200, 40), (300, 25),
    ]

    static func caffeineCap(mgPerServing: Double) -> Int {
        Int(interpolate(mgPerServing, anchors: caffeineCapAnchors).rounded())
    }

    /// M3 — saturated-fat cap so cream is visible (data-present only). A
    /// whole-milk latte (~3.6 g/serving) lands mid-80s; cream-class RTDs
    /// (≥10 g/serving, Frappuccino territory) cap at soda level. Missing
    /// satfat data → no cap, same convention as the other caps.
    static let satFatCapAnchors: [(Double, Double)] = [
        (2, 95), (8, 40), (12, 25),
    ]
    static let satFatNoCapMaxGPerServing: Double = 2

    static func satFatCap(gramsPerServing: Double) -> Int {
        if gramsPerServing <= satFatNoCapMaxGPerServing { return 100 }
        return Int(interpolate(gramsPerServing, anchors: satFatCapAnchors).rounded())
    }

    // MARK: Merit layer (drinks) — the profile is otherwise deficit-only.
    /// Unsweetened brew (non-energy tea/coffee RTD, ≤2 g free sugar, no
    /// sweeteners): coffee/tea polyphenol evidence.
    static let brewPolyphenolMerit = 3
    static let brewMeritMaxFreeSugarG: Double = 2
    /// Real dairy content (dairy evidence + protein ≥2.5 g/100 ml): protein and
    /// calcium credited, not just lactose excused.
    static let dairyNutritionMerit = 3
    static let dairyMeritMinProteinPer100ml: Double = 2.5

    /// A non-Tier-1 sweetener holds a drink one point short of Excellent…
    static let nonSugarSweetenerCap = 74
    /// …unless the drink is essentially sugar-free, which stays eligible (I19).
    static let traceSugarGPerServing: Double = 2

    /// Tier-1 sweetener presence → hard cap 55 (safety net; credits should usually bind first).
    ///
    /// Tier-2 / Tier-3 (polyols, stevia / monk fruit) cap just below Excellent
    /// once the drink carries more than trace sugar: a sweetened drink is not a
    /// "best choice", while a genuinely sugar-free one still can be. This is the
    /// mechanism behind I19 — precautionary, consistent with the Tier-1 framing.
    static func sweetenerCap(hasTier1: Bool,
                             hasLowerTierSweetener: Bool = false,
                             sugarGPerServing: Double = 0) -> Int {
        if hasTier1 { return 55 }
        if hasLowerTierSweetener, sugarGPerServing > traceSugarGPerServing {
            return nonSugarSweetenerCap
        }
        return 100
    }

    // MARK: Nutrients per serving

    /// Raw total sugar g/serving (no FVN discount) — juice_100 S3 + juice sugar cap.
    static func sugarGramsPerServingRaw(_ p: Product, serving: DrinksEffectiveServing) -> Double? {
        guard let total = p.nutrients.sugar_g else { return nil }
        return total * (serving.ml / 100)
    }

    /// M2 — dairy ingredient evidence for the lactose allowance.
    /// Plant-milk phrases are stripped first so "oat milk" / "leite de coco"
    /// never count as dairy; then unambiguous dairy terms are matched.
    static func hasDairyIngredientEvidence(_ p: Product, rs: RulesetV4 = .bundled) -> Bool {
        guard let cfg = rs.dairyLactoseAllowance else { return false }
        var hay = folded(p.ingredientsText ?? "")
        guard !hay.isEmpty else { return false }
        for phrase in cfg.plantMilkPhrases {
            hay = hay.replacingOccurrences(of: folded(phrase), with: " ")
        }
        return cfg.dairyTerms.contains { !folded($0).isEmpty && hay.contains(folded($0)) }
    }

    /// M2 — free sugar per 100 ml for dairy RTDs.
    /// WHO's free-sugar definition excludes intrinsic milk sugars, so up to
    /// `gPer100ml` (≈4.8, whole-milk lactose) is exempt. A *positive* declared
    /// added-sugar value is trusted instead when sane (OFF's bogus
    /// `added-sugars: 0` on plainly sweetened drinks stays untrusted, matching
    /// the existing S3 convention).
    static func freeSugarPer100mlAfterLactose(
        total: Double, p: Product, rs: RulesetV4
    ) -> Double {
        guard let cfg = rs.dairyLactoseAllowance,
              hasDairyIngredientEvidence(p, rs: rs) else { return total }
        if let added = p.nutrients.addedSugar_g, added > 0, added <= total {
            return added
        }
        return max(0, total - cfg.gPer100ml)
    }

    /// Effective sugar g/serving for regular drinks.
    /// Total `sugars_100g` minus the dairy lactose allowance (M2) where dairy
    /// evidence exists (never `added-sugars_100g` alone). FVN discount max 15%
    /// only for leftover juice-like / nectar products.
    static func sugarGramsPerServing(_ p: Product, serving: DrinksEffectiveServing,
                                     rs: RulesetV4 = .bundled) -> Double? {
        guard let total = p.nutrients.sugar_g else { return nil }
        if hasDairyIngredientEvidence(p, rs: rs) {
            let free = freeSugarPer100mlAfterLactose(total: total, p: p, rs: rs)
            return free * (serving.ml / 100)
        }
        // F4a: no FVN discount. WHO counts juice sugars fully as free sugars —
        // fruit content is not a license to discount them. (Milk lactose above
        // is the one WHO-sanctioned exemption.)
        return total * (serving.ml / 100)
    }

    /// Caffeine mg per 100 ml — measured or category default.
    static func caffeineMgPer100ml(_ p: Product) -> (mg: Double, estimated: Bool) {
        if let mg = p.caffeine_mg, mg >= 0 {
            return (mg, false)
        }
        if isEnergyDrink(p) { return (32, true) }
        if isIcedCoffee(p) { return (25, true) }
        if isColaSoda(p) { return (10, true) }
        if isIcedTea(p) { return (8, true) }
        return (0, true)
    }

    static func caffeineMgPerServing(_ p: Product, serving: DrinksEffectiveServing)
    -> (mg: Double, estimated: Bool) {
        let (per100, estimated) = caffeineMgPer100ml(p)
        return (per100 * (serving.ml / 100), estimated)
    }

    // MARK: S6 — tiered sweeteners

    enum SweetenerTier: Int {
        case tier1 = 1, tier2 = 2, tier3 = 3
    }

    private static let tier1Codes: Set<String> = [
        "e950", "e951", "e952", "e954", "e955", "e961", "e962", "e969",
    ]
    private static let tier2Codes: Set<String> = [
        "e968", "e967", "e420", "e965", "e421", "e953",
    ]
    private static let tier3Codes: Set<String> = [
        "e960", "e957",
    ]

    // Allulose / alulose / psicose are neutral (no S6 penalty) — omit from tier maps.

    private static func folded(_ s: String) -> String {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
    }

    /// Name → canonical E-number so text + code don't double-count the same sweetener.
    private static let tier1NameToCode: [(String, String)] = [
        ("aspartame", "e951"), ("sucralose", "e955"),
        ("acesulfame", "e950"), ("acessulfame", "e950"),
        ("saccharin", "e954"), ("sacarina", "e954"),
        ("neotame", "e961"), ("advantame", "e969"),
        ("cyclamate", "e952"), ("ciclamato", "e952"),
    ]
    private static let tier2NameToCode: [(String, String)] = [
        ("erythritol", "e968"), ("eritritol", "e968"),
        ("xylitol", "e967"), ("xilitol", "e967"),
        ("sorbitol", "e420"), ("maltitol", "e965"),
        ("mannitol", "e421"), ("manitol", "e421"),
        ("isomalt", "e953"),
    ]
    private static let tier3NameToCode: [(String, String)] = [
        ("stevia", "e960"), ("estevia", "e960"), ("steviol", "e960"),
        ("glicosideo", "e960"), ("glicosideos de esteviol", "e960"),
        ("monk fruit", "monkfruit"), ("monkfruit", "monkfruit"),
        ("fruta do monge", "monkfruit"), ("thaumatin", "e957"),
    ]

    static func detectSweetenerTiers(_ p: Product)
    -> (tier1: Int, tier2: Int, tier3: Int, reasonKeys: [String], hadData: Bool) {
        guard p.additiveIngredientTextMissing != true, p.hasIngredientData else {
            return (0, 0, 0, [], false)
        }
        let codes = Set(p.additives.compactMap { $0.code?.lowercased() })
        var canon1: Set<String> = []
        var canon2: Set<String> = []
        var canon3: Set<String> = []

        for c in codes {
            if tier1Codes.contains(c) { canon1.insert(c) }
            else if tier2Codes.contains(c) { canon2.insert(c) }
            else if tier3Codes.contains(c) { canon3.insert(c) }
        }

        let hay = folded(
            ([p.ingredientsText ?? ""] + (p.labels ?? []) + [p.name]).joined(separator: " ")
        )

        for (name, code) in tier1NameToCode where hay.contains(folded(name)) {
            canon1.insert(code)
        }
        for (name, code) in tier2NameToCode where hay.contains(folded(name)) {
            canon2.insert(code)
        }
        for (name, code) in tier3NameToCode where hay.contains(folded(name)) {
            canon3.insert(code)
        }

        var keys: [String] = []
        if !canon1.isEmpty { keys.append("who_conditional_recommendation") }
        if !canon2.isEmpty { keys.append("emerging_evidence") }
        return (canon1.count, canon2.count, canon3.count, keys, true)
    }

    /// F4b — erythritol detection (code or name), for the extra Tier-2 dock.
    static func containsErythritol(_ p: Product) -> Bool {
        if p.additives.contains(where: { $0.code?.lowercased() == "e968" }) { return true }
        let hay = folded(
            ([p.ingredientsText ?? ""] + (p.labels ?? []) + [p.name]).joined(separator: " ")
        )
        return hay.contains("erythritol") || hay.contains("eritritol")
    }

    static func s6Credit(_ p: Product) -> (Double, Bool, [String]) {
        let d = detectSweetenerTiers(p)
        guard d.hadData else { return (0.50, false, []) }
        var f = 1.0
        // Tier 1 (aspartame / Ace-K / sucralose / …): strong per-sweetener credit hit.
        if d.tier1 > 0 {
            f = 0.10 - 0.10 * Double(d.tier1 - 1)
        }
        // Tier 2 polyols — medium; Tier 3 stevia/monk — light (stevia alone → 0.90).
        f -= 0.25 * Double(d.tier2)
        // F4b: erythritol carries an extra precautionary dock within Tier 2 —
        // prospective cohorts associate circulating erythritol with higher
        // cardiovascular event risk, evidence the other polyols don't share.
        if containsErythritol(p) {
            f -= 0.10
        }
        // Tier 3 (stevia / monk fruit), Track 2: first hit lands on 0.70, each
        // additional −0.10. Previously ~0.90, which was cosmetic.
        if d.tier3 > 0 {
            f -= 0.30 + 0.10 * Double(d.tier3 - 1)
        }
        return (max(0, f), true, d.reasonKeys)
    }

    // MARK: S8 — caffeine

    private static let stimulantMarkersFallback = [
        "guarana", "taurine", "yerba mate", "erva mate", "mate extract",
    ]

    static func hasEnergyStimulants(_ p: Product, rs: RulesetV4 = .bundled) -> Bool {
        let names = rs.energyDrinkEvidence?.stimulantIngredients ?? stimulantMarkersFallback
        return matchesStimulantIngredients(p, names: names)
    }

    private static func matchesStimulantIngredients(_ p: Product, names: [String]) -> Bool {
        let hay = folded(p.ingredientsText ?? "")
        return names.contains { !folded($0).isEmpty && hay.contains(folded($0)) }
    }

    /// M4 — non-energy coffee/tea RTDs get EFSA-anchored caffeine handling:
    /// single doses ≤200 mg and ≤400 mg/day carry no safety concern for
    /// adults, and moderate coffee/tea intake is neutral-to-favorable in
    /// cohorts. `energyDrinkEvidence` outranks the tag match (I27), so a
    /// stimulant-stacked product wearing tea tags stays on the strict path.
    static func isNonEnergyTeaCoffeeRTD(_ p: Product, rs: RulesetV4 = .bundled) -> Bool {
        guard !isEnergyDrink(p, ruleset: rs) else { return false }
        let tags = (p.categories ?? []).map { $0.lowercased() }
        let needles = ["iced-tea", "iced-coffee", "coffee-drink", "tea-based",
                       "teas", "coffees", "matcha"]
        return tags.contains { tag in needles.contains { tag.contains($0) } }
    }

    /// Gentle credit for the coffee/tea class — no meaningful dock ≤100 mg,
    /// moderate to 200, steep beyond 300.
    static let coffeeTeaCaffeineCreditAnchors: [(Double, Double)] = [
        (0, 1.00), (60, 0.97), (120, 0.82), (200, 0.55), (300, 0.25), (400, 0.00),
    ]
    /// Gentle cap for the coffee/tea class — starts at the EFSA single-dose
    /// mark instead of 60 mg. Monotonic by construction, like the strict cap.
    static let coffeeTeaCaffeineCapAnchors: [(Double, Double)] = [
        (200, 100), (300, 70), (400, 40),
    ]

    static func coffeeTeaCaffeineCap(mgPerServing: Double) -> Int {
        Int(interpolate(mgPerServing, anchors: coffeeTeaCaffeineCapAnchors).rounded())
    }

    static func s8Credit(_ p: Product, serving: DrinksEffectiveServing) -> (Double, Bool, Double, Bool) {
        let (mg, estimated) = caffeineMgPerServing(p, serving: serving)
        var f = isNonEnergyTeaCoffeeRTD(p)
            ? interpolate(mg, anchors: coffeeTeaCaffeineCreditAnchors)
            : caffeineCreditCurve(mg)
        if isEnergyDrink(p) {
            // Energy base drag on the caffeine rule (stacking with S6 / additives).
            if mg >= 100 { f = max(0, f - 0.10) }
            if hasEnergyStimulants(p) {
                f = max(0, f - 0.25)
            }
        }
        let hadData = !estimated || isEnergyDrink(p)
        return (f, hadData || estimated, mg, estimated)
    }

    /// Steeper caffeine credit — meaningful subtraction above ~80–150 mg/serving.
    static func caffeineCreditCurve(_ mg: Double) -> Double {
        let anchors: [(Double, Double)] = [
            (0, 1.00), (40, 0.85), (80, 0.55), (120, 0.25), (160, 0.05), (200, 0.00),
        ]
        if mg <= anchors[0].0 { return anchors[0].1 }
        if mg >= anchors.last!.0 { return 0 }
        for i in 0..<(anchors.count - 1) {
            let (x0, y0) = anchors[i]
            let (x1, y1) = anchors[i + 1]
            if mg <= x1 {
                let t = (mg - x0) / (x1 - x0)
                return y0 + (y1 - y0) * t
            }
        }
        return 0
    }

    /// Post-rule stacking drag so diet/energy products spread below caps (points 0–100).
    // F3: piecewise-linear anchors replace stepwise thresholds so a 2 mg data
    // revision on OFF can never flip a product across a cliff. Anchors are set
    // at the calibrated fixture operating points (140/180/200 mg etc.), so
    // golden scores are preserved while the space BETWEEN anchors is smooth.
    static let energyCaffeineDragAnchors: [(Double, Double)] = [
        (100, 0), (140, 5), (180, 11), (200, 13),
    ]
    static let energySugarDragAnchors: [(Double, Double)] = [
        (15, 0), (20, 8),
    ]
    static let energySugarCaffeineComboDragAnchors: [(Double, Double)] = [
        (20, 0), (25, 6),
    ]
    /// 0→1 ramp gating sugar+caffeine combo terms (was a hard `cafMg >= 70`).
    static let comboCaffeineGateAnchors: [(Double, Double)] = [
        (40, 0), (70, 1),
    ]

    static func stackingDrag(
        tier1: Int,
        sugarG: Double,
        cafMg: Double,
        isEnergy: Bool,
        isSports: Bool,
        hasStimulants: Bool
    ) -> Int {
        var d = 0.0
        if tier1 > 0 {
            // Diet / sports: strong NNS count drag so scores land below sweetenerCap.
            // Energy: lighter NNS drag — caffeine/stimulant stack does the rest.
            // Integer counts, not continuous inputs — no cliff to smooth.
            if isEnergy {
                d += Double(6 + 6 * tier1)  // 1→12, 2→18
            } else {
                d += Double(12 + 10 * tier1)  // 1→22, 2→32
            }
        }
        if isSports && tier1 > 0 {
            d += 8
        }
        if isEnergy {
            d += 8
            d += interpolate(cafMg, anchors: energyCaffeineDragAnchors)
            if hasStimulants { d += 4 }
            d += interpolate(sugarG, anchors: energySugarDragAnchors)
            d += interpolate(sugarG, anchors: energySugarCaffeineComboDragAnchors)
                * interpolate(cafMg, anchors: comboCaffeineGateAnchors)
        }
        return Int(d.rounded())
    }

    /// Extra pull below sugarCap when heavy sugar stacks with serious caffeine.
    // F3 continuous anchors — same operating points as the old thresholds,
    // smooth in between (the old hard `sugarG >= 20` guard becomes a 15→20 ramp).
    static let undercutCaffeineAnchors: [(Double, Double)] = [
        (100, 0), (120, 5), (160, 10),
    ]
    static let undercutSugarGateAnchors: [(Double, Double)] = [
        (15, 0), (20, 1),
    ]
    static let undercutEnergySugarAnchors: [(Double, Double)] = [
        (15, 0), (20, 8),
    ]
    static let undercutEnergyComboAnchors: [(Double, Double)] = [
        (20, 0), (25, 4),
    ]

    static func sugarCapUndercut(sugarG: Double, cafMg: Double, isEnergy: Bool) -> Int {
        let sugarGate = interpolate(sugarG, anchors: undercutSugarGateAnchors)
        var u = interpolate(cafMg, anchors: undercutCaffeineAnchors) * sugarGate
        if isEnergy {
            u += interpolate(sugarG, anchors: undercutEnergySugarAnchors)
            u += interpolate(sugarG, anchors: undercutEnergyComboAnchors)
                * interpolate(cafMg, anchors: comboCaffeineGateAnchors)
        }
        return Int(u.rounded())
    }

    // MARK: S4 — sodium (drinks)

    static func s4Credit(_ p: Product, serving: DrinksEffectiveServing, rs: RulesetV4) -> (Double, Bool) {
        guard let per100 = p.nutrients.sodium_mg else { return (0.30, false) }
        let perServing = per100 * (serving.ml / 100)
        if isSportsOrElectrolyte(p) {
            // No penalty ≤250 mg; linear 250→500; 0 above 500.
            if perServing <= 250 { return (1.0, true) }
            if perServing >= 500 { return (0.0, true) }
            let t = (perServing - 250) / (500 - 250)
            return (1.0 - t, true)
        }
        // Other drinks: existing per-100g curve on per-serving equivalent scaled
        // to 100ml basis for threshold compatibility — use per-serving against
        // thresholds that were written per 100g; convert serving to "as if 100ml"
        // by evaluating stepped on per100 still (sodium density), which matches
        // prior drinks S4 behavior for non-sports.
        return ScoringEngineV4.stepped(per100, thresholds: rs.s4Thresholds, unknownCredit: 0.30)
    }

    // MARK: S7 packaging
    // TODO: consider moving packaging out of health score into a separate sustainability badge

    static func s7Credit(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        let map = rs.s7Materials ?? [:]
        guard let materials = p.packagingMaterials, !materials.isEmpty else {
            return (0.40, false)
        }
        var worst: Double?
        for m in materials {
            if let credit = map[m.lowercased()] {
                worst = min(worst ?? credit, credit)
            }
        }
        guard let credit = worst else { return (0.40, false) }
        return (credit, true)
    }

    // MARK: S3 sugar credit

    /// Drinks S3 credit anchors (Track 2), g sugar per effective serving → credit.
    /// The low end is steepened so a lightly sweetened "better-for-you" soda
    /// stops scoring like unsweetened sparkling water.
    static let defaultDrinksS3Anchors: [(Double, Double)] = [
        (1, 1.00), (5, 0.60), (8, 0.48), (16, 0.25), (30, 0.00),
    ]

    /// Ruleset-supplied anchors, falling back to `defaultDrinksS3Anchors`.
    static func drinksS3Anchors(_ rs: RulesetV4) -> [(Double, Double)] {
        guard let raw = rs.s3DrinksServingCurve, raw.count >= 2 else {
            return defaultDrinksS3Anchors
        }
        let parsed = raw.compactMap { pair -> (Double, Double)? in
            pair.count == 2 ? (pair[0], pair[1]) : nil
        }
        // Malformed config must not silently reshape the curve.
        return parsed.count == raw.count ? parsed : defaultDrinksS3Anchors
    }

    static func drinksS3CreditCurve(_ grams: Double, rs: RulesetV4) -> Double {
        interpolate(grams, anchors: drinksS3Anchors(rs))
    }

    /// juice_100 curve: ≤6 → 1.0, 10 → 0.55, 14 → 0.25, ≥18 → 0.
    static func juiceS3CreditCurve(_ grams: Double) -> Double {
        let anchors: [(Double, Double)] = [
            (6, 1.00), (10, 0.55), (14, 0.25), (18, 0.00),
        ]
        if grams <= anchors[0].0 { return anchors[0].1 }
        if grams >= anchors.last!.0 { return 0 }
        for i in 0..<(anchors.count - 1) {
            let (x0, y0) = anchors[i]
            let (x1, y1) = anchors[i + 1]
            if grams <= x1 {
                let t = (grams - x0) / (x1 - x0)
                return y0 + (y1 - y0) * t
            }
        }
        return 0
    }

    static func s3Credit(_ p: Product, serving: DrinksEffectiveServing, rs: RulesetV4,
                         profileId: String)
    -> (Double, Bool, Double?) {
        if profileId == "juice_100" {
            guard let grams = sugarGramsPerServingRaw(p, serving: serving) else {
                return (0.25, false, nil)
            }
            return (juiceS3CreditCurve(grams), true, grams)
        }
        guard let grams = sugarGramsPerServing(p, serving: serving, rs: rs) else {
            return (0.25, false, nil)
        }
        return (drinksS3CreditCurve(grams, rs: rs), true, grams)
    }

    static func riskFactorCount(for p: Product, tiers: (tier1: Int, tier2: Int, tier3: Int, reasonKeys: [String], hadData: Bool)) -> Int {
        var n = 0
        for add in p.additives {
            let code = add.code?.lowercased() ?? ""
            if juice100AllowedAdditiveCodes.contains(code) { continue }
            let name = folded(add.name)
            if juice100AllowedAdditiveNames.contains(where: { name.contains(folded($0)) }) {
                continue
            }
            n += 1
        }
        if tiers.hadData {
            n += tiers.tier1 + tiers.tier2 + tiers.tier3
        }
        return n
    }

    // MARK: Assemble drinks / juice_100 score

    /// Evaluate drinks or juice_100 rules + caps.
    static func score(product p: Product, ruleset rs: RulesetV4,
                      profileId: String = "drinks",
                      ruleMultipliers: [String: Double] = [:])
    -> DrinksScoreBreakdown? {
        guard p.hasMinimumData else { return nil }
        let isJuice100 = profileId == "juice_100"
        let serving = effectiveServing(for: p)

        var lowData = false
        if serving.estimatedServing { lowData = true }

        let (s1f, s1had) = ScoringEngineV4.evaluatePublicS1(p, rs: rs)
        if !s1had { lowData = true }

        let (s3f, s3had, sugarG) = s3Credit(p, serving: serving, rs: rs, profileId: profileId)

        let (s6f, s6had, sweetKeys) = s6Credit(p)
        if !s6had { lowData = true }
        let tiers = detectSweetenerTiers(p)
        let hasTier1 = tiers.hadData && tiers.tier1 > 0
        let hasLowerTierSweetener = tiers.hadData && (tiers.tier2 + tiers.tier3) > 0

        let (s8f, s8had, cafMg, cafEst) = s8Credit(p, serving: serving)
        if cafEst && isEnergyDrink(p) { lowData = true }
        _ = s8had

        let (s4f, s4had) = s4Credit(p, serving: serving, rs: rs)
        // Packaging is a sustainability signal, not a health one — computed for
        // the badge, deliberately excluded from the weighted score. See F1.
        let (packagingCredit, packagingHadData) = s7Credit(p, rs: rs)
        _ = s4had

        // S7 packaging removed (F1); its 6 points redistribute *proportionally*
        // across the surviving rules rather than by hand — S4 sodium is ~1.000
        // for nearly every drink, so weighting it up would hand near-free points
        // to zero-sugar energy drinks and break the juice-beats-energy ordering.
        var weights: [String: Double] = [
            "S1": 23, "S3": 43, "S8": 15, "S6": 13, "S4": 6,
        ]
        for (k, m) in ruleMultipliers {
            if let w = weights[k] { weights[k] = w * m }
        }
        if let w8 = weights["S8"] {
            weights["S8"] = min(25, max(8, w8))
        }
        let sumW = weights.values.reduce(0, +)
        if sumW > 0 {
            for k in weights.keys { weights[k]! = weights[k]! * (100.0 / sumW) }
        }

        let fractions: [String: Double] = [
            "S1": s1f, "S3": s3f, "S8": s8f, "S6": s6f, "S4": s4f,
        ]
        let had: [String: Bool] = [
            "S1": s1had, "S3": s3had, "S8": true, "S6": s6had, "S4": s4had,
        ]

        let order = ["S1", "S3", "S8", "S6", "S4"]
        var rules: [V4RuleResult] = []
        var earned = 0.0
        for id in order {
            let w = weights[id] ?? 0
            let f = fractions[id] ?? 0
            earned += w * f
            var note: String? = nil
            if id == "S6", !sweetKeys.isEmpty {
                note = "sweetenerReasons: " + sweetKeys.joined(separator: ",")
            }
            if id == "S8", cafEst {
                note = String(format: "caffeine estimated %.0f mg/serving", cafMg)
            }
            if id == "S3", let g = sugarG {
                note = String(format: "S3 %.1f g / %.0f ml", g, serving.ml)
            }
            rules.append(V4RuleResult(rule: id, weight: w, fraction: f,
                                      hadData: had[id] ?? false, note: note))
        }

        var boost = 0
        var merit = 0
        var earnedPoints = Int((earned / 100.0 * 100).rounded())
        let stimulants = hasEnergyStimulants(p)
        let drag: Int
        if isJuice100 {
            drag = 0
            boost = 3
            earnedPoints += boost
            if (sugarG ?? 0) >= 20 {
                earnedPoints = min(earnedPoints, 54)
            }
        } else {
            drag = stackingDrag(
                tier1: tiers.hadData ? tiers.tier1 : 0,
                sugarG: sugarG ?? 0,
                cafMg: cafMg,
                isEnergy: isEnergyDrink(p),
                isSports: isSportsOrElectrolyte(p),
                hasStimulants: stimulants
            )
            earnedPoints -= drag
            // Merit layer — the drinks profile is otherwise deficit-only.
            // Small, evidence-anchored credits, applied BEFORE caps so a
            // capped product (e.g. a Frappuccino) can never merit its way up:
            // safety nets outrank bonuses, no health-washing.
            let noSweeteners = tiers.hadData
                && (tiers.tier1 + tiers.tier2 + tiers.tier3) == 0
            if isNonEnergyTeaCoffeeRTD(p),
               (sugarG ?? 0) <= brewMeritMaxFreeSugarG, noSweeteners {
                // Unsweetened brew: coffee/tea polyphenols, neutral-to-favorable
                // in large cohorts.
                merit += brewPolyphenolMerit
            }
            if hasDairyIngredientEvidence(p, rs: rs),
               (p.nutrients.protein_g ?? 0) >= dairyMeritMinProteinPer100ml {
                // Real dairy content: protein + calcium, credited rather than
                // merely excusing lactose. Kombucha's fermentation stays
                // uncredited — trial evidence is too weak to score.
                merit += dairyNutritionMerit
            }
            earnedPoints = min(100, earnedPoints + merit)
        }
        let weighted = max(floorScore, earnedPoints)

        let sCap = isJuice100
            ? juiceSugarCap(gramsPerServing: sugarG ?? 0)
            : sugarCap(gramsPerServing: sugarG ?? 0)
        let cCap = isNonEnergyTeaCoffeeRTD(p)
            ? coffeeTeaCaffeineCap(mgPerServing: cafMg)
            : caffeineCap(mgPerServing: cafMg)
        let wCap = sweetenerCap(hasTier1: hasTier1,
                                hasLowerTierSweetener: hasLowerTierSweetener,
                                sugarGPerServing: sugarG ?? 0)
        // M3: cream visibility — only when satfat data exists.
        let fCap: Int = {
            guard let satPer100 = p.nutrients.satFat_g else { return 100 }
            return satFatCap(gramsPerServing: satPer100 * (serving.ml / 100))
        }()

        var final = min(weighted, sCap, cCap, wCap, fCap)
        // Caffeine may pull below the sugar cap when both loads are serious.
        if !isJuice100 {
            let undercut = sugarCapUndercut(sugarG: sugarG ?? 0, cafMg: cafMg,
                                            isEnergy: isEnergyDrink(p))
            if undercut > 0, sCap < 100 {
                final = min(final, max(floorScore, sCap - undercut))
            }
        }
        let binding: String? = {
            let pairs: [(String, Int)] = [
                ("sugarCap", sCap), ("caffeineCap", cCap), ("sweetenerCap", wCap),
                ("satFatCap", fCap),
            ]
            // Binding only if a cap equals final and is below pre-cap weighted.
            let bindingPairs = pairs.filter { $0.1 < weighted && $0.1 == final }
            return bindingPairs.sorted { $0.0 < $1.0 }.first?.0
        }()

        return DrinksScoreBreakdown(
            profileId: profileId,
            effectiveServingMl: serving.ml,
            estimatedServing: serving.estimatedServing,
            lowDataConfidence: lowData,
            sugarPerServingG: sugarG,
            caffeinePerServingMg: cafMg,
            caffeineEstimated: cafEst,
            sugarCap: sCap,
            caffeineCap: cCap,
            sweetenerCap: wCap,
            satFatCap: fCap,
            bindingCapId: binding,
            weightedScore: weighted,
            finalScore: max(floorScore, final),
            rules: rules,
            sweetenerReasonKeys: sweetKeys,
            riskFactorCount: riskFactorCount(for: p, tiers: tiers),
            micronutrientBoost: boost,
            meritBoost: merit,
            stackingDrag: drag,
            packagingCredit: packagingCredit,
            packagingHadData: packagingHadData
        )
    }
}

// S1 access for DrinksScoring — thin wrapper over private evaluate.
extension ScoringEngineV4 {
    static func evaluatePublicS1(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        let (f, had, _) = _evaluateForDrinks("S1", variant: nil, product: p, rs: rs, profileId: "drinks")
        return (f, had)
    }

    static func evaluatePublic(rule: String, variant: String?, product: Product,
                               rs: RulesetV4, profileId: String)
    -> (Double, Bool, String?) {
        _evaluateForDrinks(rule, variant: variant, product: product, rs: rs, profileId: profileId)
    }
}
