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
    /// Post-rule diet/energy stacking drag (points).
    let stackingDrag: Int
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
    static func effectiveServing(for product: Product) -> DrinksEffectiveServing {
        let containerMl = parseVolumeMilliliters(product.size)
        if let c = containerMl, c > 0, c <= singleServeMaxMl {
            return DrinksEffectiveServing(ml: c, estimatedServing: false, usedWholeContainer: true)
        }

        let declared = parseVolumeMilliliters(product.servingSize)

        // Large multi-serve package + ~100 ml panel reference → ignore panel, use category dose.
        if let c = containerMl, c > singleServeMaxMl,
           let s = declared, isPanelReferenceServing(ml: s) {
            let dose = categoryTypicalDoseMl(for: product)
            return DrinksEffectiveServing(ml: dose, estimatedServing: true, usedWholeContainer: false)
        }

        // Genuine consumption serving surviving panel-ref discard.
        if let s = declared, s >= 100, s <= singleServeMaxMl {
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
    private static let volumeParsers: [(NSRegularExpression, Double)] = {
        let specs: [(String, Double)] = [
            (#"(\d+(?:\.\d+)?)\s*(?:fl\.?\s*oz|floz|fluid\s*ounces?)"#, 29.5735),
            (#"(\d+(?:\.\d+)?)\s*ml\b"#, 1.0),
            (#"(\d+(?:\.\d+)?)\s*cl\b"#, 10.0),
            (#"(\d+(?:\.\d+)?)\s*l\b"#, 1000.0),
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

    /// Caffeine cap per effective serving. 100 = no cap.
    /// Safety net (~45 at 160 mg); rule credit + stacking should usually land below it.
    static func caffeineCap(mgPerServing: Double) -> Int {
        if mgPerServing <= 80 { return 100 }
        if mgPerServing >= 300 { return 28 }
        if mgPerServing <= 160 {
            let t = (mgPerServing - 80) / (160 - 80)
            return Int((100.0 + (45.0 - 100.0) * t).rounded())
        }
        let t = (mgPerServing - 160) / (300 - 160)
        return Int((45.0 + (28.0 - 45.0) * t).rounded())
    }

    /// Tier-1 sweetener presence → hard cap 55 (safety net; credits should usually bind first).
    static func sweetenerCap(hasTier1: Bool) -> Int {
        hasTier1 ? 55 : 100
    }

    // MARK: Nutrients per serving

    /// Raw total sugar g/serving (no FVN discount) — juice_100 S3 + juice sugar cap.
    static func sugarGramsPerServingRaw(_ p: Product, serving: DrinksEffectiveServing) -> Double? {
        guard let total = p.nutrients.sugar_g else { return nil }
        return total * (serving.ml / 100)
    }

    /// Effective sugar g/serving for regular drinks.
    /// Always total `sugars_100g` (never `added-sugars_100g`). FVN discount max 15%
    /// only for leftover juice-like / nectar products.
    static func sugarGramsPerServing(_ p: Product, serving: DrinksEffectiveServing) -> Double? {
        guard let total = p.nutrients.sugar_g else { return nil }
        let fvn = p.nutrients.fvn ?? 0
        let discount: Double
        if isJuiceCategory(p) {
            discount = min(0.15, fvn / 100)
        } else {
            discount = 0
        }
        let per100 = total * (1 - discount)
        return per100 * (serving.ml / 100)
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
        f -= 0.10 * Double(d.tier3)
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

    static func s8Credit(_ p: Product, serving: DrinksEffectiveServing) -> (Double, Bool, Double, Bool) {
        let (mg, estimated) = caffeineMgPerServing(p, serving: serving)
        var f = caffeineCreditCurve(mg)
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
    static func stackingDrag(
        tier1: Int,
        sugarG: Double,
        cafMg: Double,
        isEnergy: Bool,
        isSports: Bool,
        hasStimulants: Bool
    ) -> Int {
        var d = 0
        if tier1 > 0 {
            // Diet / sports: strong NNS count drag so scores land below sweetenerCap.
            // Energy: lighter NNS drag — caffeine/stimulant stack does the rest.
            if isEnergy {
                d += 6 + 6 * tier1          // 1→12, 2→18
            } else {
                d += 12 + 10 * tier1        // 1→22, 2→32
            }
        }
        if isSports && tier1 > 0 {
            d += 8
        }
        if isEnergy {
            d += 8
            if cafMg >= 140 { d += 5 }
            if cafMg >= 180 { d += 6 }
            // ~200 mg/can (e.g. Celsius 56.3×355 ≈ 199.9) — keep below cold-press juice floor.
            if cafMg >= 195 { d += 2 }
            if hasStimulants { d += 4 }
            if sugarG >= 20 { d += 8 }
            if sugarG >= 25 && cafMg >= 70 { d += 6 }
        }
        return d
    }

    /// Extra pull below sugarCap when heavy sugar stacks with serious caffeine.
    static func sugarCapUndercut(sugarG: Double, cafMg: Double, isEnergy: Bool) -> Int {
        guard sugarG >= 20 else { return 0 }
        var u = 0
        if cafMg >= 120 { u += 5 }
        if cafMg >= 160 { u += 5 }
        if isEnergy && sugarG >= 20 { u += 8 }
        if isEnergy && sugarG >= 25 && cafMg >= 70 { u += 4 }
        return u
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
        guard let grams = sugarGramsPerServing(p, serving: serving) else {
            return (0.25, false, nil)
        }
        let thresholds = rs.s3Thresholds["drinksServing"] ?? [2, 8, 16, 30]
        let (f, had) = ScoringEngineV4.stepped(grams, thresholds: thresholds, unknownCredit: 0.25)
        return (f, had, grams)
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

        let (s8f, s8had, cafMg, cafEst) = s8Credit(p, serving: serving)
        if cafEst && isEnergyDrink(p) { lowData = true }
        _ = s8had

        let (s4f, s4had) = s4Credit(p, serving: serving, rs: rs)
        let (s7f, s7had) = s7Credit(p, rs: rs)
        _ = s4had; _ = s7had

        var weights: [String: Double] = [
            "S1": 22, "S3": 40, "S8": 14, "S6": 12, "S4": 6, "S7": 6,
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
            "S1": s1f, "S3": s3f, "S8": s8f, "S6": s6f, "S4": s4f, "S7": s7f,
        ]
        let had: [String: Bool] = [
            "S1": s1had, "S3": s3had, "S8": true, "S6": s6had, "S4": s4had, "S7": s7had,
        ]

        let order = ["S1", "S3", "S8", "S6", "S4", "S7"]
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
        }
        let weighted = max(floorScore, earnedPoints)

        let sCap = isJuice100
            ? juiceSugarCap(gramsPerServing: sugarG ?? 0)
            : sugarCap(gramsPerServing: sugarG ?? 0)
        let cCap = caffeineCap(mgPerServing: cafMg)
        let wCap = sweetenerCap(hasTier1: hasTier1)

        var final = min(weighted, sCap, cCap, wCap)
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
            bindingCapId: binding,
            weightedScore: weighted,
            finalScore: max(floorScore, final),
            rules: rules,
            sweetenerReasonKeys: sweetKeys,
            riskFactorCount: riskFactorCount(for: p, tiers: tiers),
            micronutrientBoost: boost,
            stackingDrag: drag
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
