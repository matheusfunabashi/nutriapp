import Foundation

// MARK: - Scoring v4 (SCORING_V4.md) — category-aware rule engine
//
// Phase B: engine + bundled ruleset + router + three profiles (general,
// drinks, snacks). NOT yet wired to the UI — v3 remains the shipped engine
// until calibration locks weights/bands and the anchors pass (§12/§16).
//
// Architecture contract (§10): all tunable data — weights, tiers, thresholds,
// router, bands — lives in RulesetV4.json; this file only knows the rule
// *shapes*. Every rule returns a fraction ∈ [0,1] and never sees its weight,
// so the v1.0 point-rescaling bug class cannot exist. Score = Σ(w·f)/Σw,
// floored at 10 (never 0). No severity caps (§3.5, decided 2026-07-11).

// MARK: Ruleset (mirrors RulesetV4.json)

struct RulesetV4: Codable {
    struct Bands: Codable { let excellent: Int; let good: Int; let mediocre: Int }
    struct Dampening: Codable { let afterCount: Int; let factor: Double }
    struct ProfileRule: Codable { let rule: String; let w: Double; let variant: String? }
    struct RouterEntry: Codable { let match: String; let profile: String }

    struct SourceCredit: Codable { let match: String; let credit: Double }
    struct KwCredit: Codable { let kw: String; let credit: Double }
    struct PointsRule: Codable {
        let points: [String: Double]
        let denominator: Double
        let plantNeutral: Double?
    }
    struct CropRisk: Codable {
        let lowRisk: [String]; let highRisk: [String]
        let lowCredit: Double; let highCredit: Double; let riceCap: Double
    }

    let version: String
    let bands: Bands
    let tierFractions: [String: Double]
    let dampening: Dampening
    let additiveTiers: [String: String]
    let gumCodes: [String]
    let sweetenerCodes: [String]
    let textSignals: [String: String]
    let s3Thresholds: [String: [Double]]
    let s4Thresholds: [Double]
    let s5Thresholds: [String: [Double]]
    let s7Materials: [String: Double]
    let certLabels: [String]
    let profiles: [String: [ProfileRule]]
    let router: [RouterEntry]

    // Phase C category rules — optional so an older downloaded ruleset can't
    // crash decoding; evaluators fall back to unknown credit when absent.
    let waterSource: [SourceCredit]?
    let cropRisk: CropRisk?
    let dairyLabels: PointsRule?
    let dairyProcessing: [SourceCredit]?
    let dairyProcessingDefault: Double?
    let brewMaterial: [KwCredit]?
    let brewMaterialDefault: Double?
    let sweetenerType: [KwCredit]?
    let sweetenerTypeDefault: Double?
    let authenticityBad: [String]?
    let sweetenerProcessing: [KwCredit]?
    let sweetenerProcessingDefault: Double?
    let wholeGrainKw: [String]?
    let stabilizerPenalties: [String: Double]?
    let welfare: PointsRule?
    let heroCredit: [[Double]]?

    // S13 — beneficial micronutrient credit (positive-only). NRF-style: each
    // present nutrient contributes min(cap, %DV per 100g); the capped sum is
    // normalized by `target`. Optional so an older ruleset falls back to unknown.
    struct Micronutrients: Codable {
        let dv: [String: Double]        // nutrient key → daily reference value (mg)
        let capPerNutrient: Double      // one nutrient's max contribution (fraction of DV)
        let target: Double              // capped-sum that earns full credit
        let unknownCredit: Double       // neutral fraction when no micros reported
    }
    let micronutrients: Micronutrients?

    // Phase D personalization (SCORING_V4.md §7) — optional for back-compat.
    struct Multipliers: Codable {
        let objective: [String: [String: Double]]
        let goal: [String: [String: Double]]
        let slider: [String: [String: [String: Double]]]   // key → level → {rule: factor}
    }
    struct AvoidEntry: Codable { let codes: [String]?; let text: [String]?; let labels: [String]? }
    struct HardGates: Codable { let dietConflictCap: Int; let avoidListCap: Int }

    let multipliers: Multipliers?
    let avoidList: [String: AvoidEntry]?
    let hardGates: HardGates?

    /// Band label for a score under this ruleset (single source for all UI).
    func bandLabel(_ score: Int) -> String {
        if score >= bands.excellent { return "Excellent" }
        if score >= bands.good { return "Good" }
        if score >= bands.mediocre { return "Mediocre" }
        return "Bad"
    }

    private final class BundleToken {}

    /// The ruleset shipped inside the app. Phase C adds the background-refresh
    /// path; a downloaded ruleset would take precedence over this one.
    static let bundled: RulesetV4 = {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "RulesetV4", withExtension: "json")
                ?? Bundle.main.url(forResource: "RulesetV4", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rs = try? JSONDecoder().decode(RulesetV4.self, from: data)
        else {
            fatalError("RulesetV4.json missing or malformed — the app cannot score without it")
        }
        return rs
    }()
}

// MARK: Engine output

struct V4RuleResult {
    let rule: String
    let weight: Double
    let fraction: Double
    /// False when the rule fell back to its Tier-2 "unknown" credit — feeds
    /// the weight-backed Data Confidence (§3.2).
    let hadData: Bool
}

struct V4Result {
    let rulesetVersion: String
    let profileId: String
    let base: Int
    /// Weight-backed confidence: Σ(w where rule had data) / Σw.
    let confidence: Double
    let rules: [V4RuleResult]
}

// MARK: Engine

enum ScoringEngineV4 {

    static let floorScore = 10

    /// nil when the product fails the minimum-data requirement (§3.3) —
    /// callers show the insufficient-data state, never a made-up number.
    static func score(_ p: Product, ruleset rs: RulesetV4 = .bundled) -> V4Result? {
        guard p.hasMinimumData else { return nil }
        let profileId = route(p, ruleset: rs)
        guard let profile = rs.profiles[profileId] else { return nil }

        var results: [V4RuleResult] = []
        for pr in profile {
            let (f, had) = evaluate(pr.rule, variant: pr.variant, product: p, rs: rs)
            results.append(V4RuleResult(rule: pr.rule, weight: pr.w,
                                        fraction: f, hadData: had))
        }

        let totalW = results.reduce(0) { $0 + $1.weight }
        guard totalW > 0 else { return nil }
        let earned = results.reduce(0) { $0 + $1.weight * $1.fraction }
        let backed = results.filter(\.hadData).reduce(0) { $0 + $1.weight }

        let raw = earned / totalW * 100
        return V4Result(rulesetVersion: rs.version,
                        profileId: profileId,
                        base: max(floorScore, Int(raw.rounded())),
                        confidence: backed / totalW,
                        rules: results)
    }

    // MARK: Full scored product (Phase D — SCORING_V4.md §7)

    /// Outcome of the app-facing scoring path.
    enum Outcome {
        case scored(Product)      // Overall + Your Score filled in
        case unsupported          // water / alcohol → Sage doesn't rate these
        case insufficientData     // fails the minimum-data requirement
    }

    /// Drop-in replacement for the v3 `ScoringEngine.score`: returns the product
    /// with overallScore, yourScore, deltaReason, bonuses, and restrictions
    /// filled from the v4 rule engine + multiplier personalization + hard gates.
    static func scoreProduct(_ p: Product, for profile: UserProfile,
                             ruleset rs: RulesetV4 = .bundled) -> Outcome {
        guard p.hasMinimumData else { return .insufficientData }
        let profileId = route(p, ruleset: rs)
        if profileId == "unsupported" { return .unsupported }
        guard let ruleList = rs.profiles[profileId] else { return .insufficientData }

        // Evaluate every rule once; reuse for Overall and Your Score.
        let results = ruleList.map { pr -> V4RuleResult in
            let (f, had) = evaluate(pr.rule, variant: pr.variant, product: p, rs: rs)
            return V4RuleResult(rule: pr.rule, weight: pr.w, fraction: f, hadData: had)
        }
        let totalW = results.reduce(0) { $0 + $1.weight }
        guard totalW > 0 else { return .insufficientData }
        let overall = max(floorScore,
                          Int((results.reduce(0) { $0 + $1.weight * $1.fraction } / totalW * 100).rounded()))

        var out = p
        out.overallScore = overall
        out.bonuses = nutrientBonuses(p.nutrients)

        // Hard-gate: restriction / diet-pattern conflicts.
        out.restrictions = profile.autoFlagRestrictions
            ? restrictionInputs(profile).compactMap { name in
                evalRestriction(name, product: p).map { Restriction(type: $0.type, trigger: $0.trigger) }
              }
            : []

        guard profile.personalizeScoring else {
            out.yourScore = overall
            out.deltaReason = nil
            return .scored(out)
        }

        // Your Score = Σ(w·m·f) / Σ(w·m) — rule multipliers from objective,
        // health goals, and priority sliders (§7.2).
        let mult = ruleMultipliers(profile, rs: rs)
        var yEarned = 0.0, yTotal = 0.0
        for r in results {
            let m = mult[r.rule] ?? 1.0
            yEarned += r.weight * m * r.fraction
            yTotal += r.weight * m
        }
        var your = yTotal > 0 ? max(floorScore, Int((yEarned / yTotal * 100).rounded())) : overall

        // Reward-direction nutrient nudges: goals that reward a nutrient buried
        // inside a blended rule (build muscle → protein density; lose weight →
        // calorie lightness) can't be expressed as a rule multiplier, so apply
        // a small bounded Your-Score nudge (§7.2 "protein component" note).
        your = max(floorScore, min(100, your + nutrientNudge(profile.objective, p.nutrients)))

        // Hard-gate caps (§7.3, strongest wins): restriction conflict < avoid-list.
        let avoidHit = avoidListHit(p, profile: profile, rs: rs)
        if !out.restrictions.isEmpty { your = min(your, rs.hardGates?.dietConflictCap ?? 20) }
        if avoidHit != nil { your = min(your, rs.hardGates?.avoidListCap ?? 49) }

        out.yourScore = your
        out.deltaReason = deltaReasonV4(overall: overall, your: your,
                                        restriction: out.restrictions.first, avoid: avoidHit,
                                        results: results, mult: mult)
        return .scored(out)
    }

    /// Signed drivers for the backend /explain prompt (§7.5). Restriction /
    /// avoid conflicts lead; then the rules the user's profile most emphasized.
    static func signedFactors(_ p: Product, profile: UserProfile,
                              ruleset rs: RulesetV4 = .bundled) -> [String] {
        var factors: [String] = []
        if let r = p.restrictions.first {
            factors.append("- conflicts with your \(r.type) restriction (\(r.trigger))")
        }
        if let a = avoidListHit(p, profile: profile, rs: rs) {
            factors.append("- contains \(a), which you chose to avoid")
        }
        let profileId = route(p, ruleset: rs)
        guard let ruleList = rs.profiles[profileId] else { return factors }
        let mult = ruleMultipliers(profile, rs: rs)
        let scored = ruleList.map { pr -> (rule: String, f: Double, m: Double) in
            let (f, _) = evaluate(pr.rule, variant: pr.variant, product: p, rs: rs)
            return (pr.rule, f, mult[pr.rule] ?? 1.0)
        }
        // Emphasized rules first (biggest |m−1|·weight), then plain strong drivers.
        let ranked = scored.sorted {
            abs($0.m - 1) != abs($1.m - 1) ? abs($0.m - 1) > abs($1.m - 1) : $0.f < $1.f
        }
        for r in ranked.prefix(4) {
            guard let (label, positive) = ruleFactor(r.rule, fraction: r.f, product: p) else { continue }
            factors.append((positive ? "+ " : "- ") + label)
        }
        return Array(factors.prefix(5))
    }

    // MARK: Personalization helpers

    /// Per-rule multiplier from objective + health goals + priority sliders.
    private static func ruleMultipliers(_ profile: UserProfile, rs: RulesetV4) -> [String: Double] {
        guard let m = rs.multipliers else { return [:] }
        var out: [String: Double] = [:]
        func apply(_ table: [String: Double]?) {
            for (rule, factor) in table ?? [:] { out[rule, default: 1.0] *= factor }
        }
        apply(m.objective[profile.objective.lowercased()])
        for g in profile.healthGoals ?? [] { apply(m.goal[g.lowercased()]) }
        let sliders: [(String, Int?)] = [
            ("clean", profile.sliderCleanIngredients),
            ("nutrition", profile.sliderNutrition),
            ("environment", profile.sliderEnvironment),
            ("welfare", profile.sliderAnimalWelfare),
        ]
        for (key, level) in sliders where level != nil && level != 1 {
            apply(m.slider[key]?[String(level!)])
        }
        return out
    }

    /// Bounded Your-Score nudge for goals that reward a specific nutrient the
    /// blended rules dilute. Muscle: protein per 100 kcal. Weight loss: calorie
    /// lightness, gated so sugary drinks earn no lightness credit.
    private static func nutrientNudge(_ objective: String, _ n: Nutrients) -> Int {
        switch objective.lowercased() {
        case "build muscle":
            guard let kcal = n.kcal, kcal > 5, let prot = n.protein_g else { return 0 }
            let dens = min(1.0, (prot / (kcal / 100)) / 15)
            return Int(((dens - 0.35) * 16).rounded())      // ≈ −6 … +10
        case "lose weight":
            guard let kcal = n.kcal else { return 0 }
            let light = max(0, min(1, (500 - kcal) / 450))
            let sugarGate = 1 - min(1, (n.sugar_g ?? 0) / 25)
            return Int(((light * sugarGate - 0.3) * 12).rounded())   // ≈ −4 … +8
        default: return 0
        }
    }

    /// The product contains an item the user chose to avoid → item name, else nil.
    private static func avoidListHit(_ p: Product, profile: UserProfile, rs: RulesetV4) -> String? {
        guard let avoid = rs.avoidList, let chosen = profile.avoidList, !chosen.isEmpty else { return nil }
        let codes = Set(p.additives.compactMap(\.code))
        let text = (p.ingredientsText ?? "").lowercased()
        let labels = Set(p.labels ?? [])
        for item in chosen {
            guard let e = avoid[item.lowercased()] else { continue }
            if let c = e.codes, !codes.isDisjoint(with: Set(c)) { return item }
            if let t = e.text, t.contains(where: { text.contains($0) }) { return item }
            if let l = e.labels, !labels.isDisjoint(with: Set(l)) { return item }
        }
        return nil
    }

    /// Existing scoring restrictions plus the new single diet pattern (§7.1).
    private static func restrictionInputs(_ profile: UserProfile) -> [String] {
        var out = profile.restrictions
        if let d = profile.dietPattern, d.lowercased() != "none" { out.append(d) }
        return out
    }

    /// Deterministic restriction conflict check (ported from v3). keto is a
    /// no-op until carbohydrate data is carried on Nutrients.
    private static func evalRestriction(_ name: String, product p: Product) -> (type: String, trigger: String)? {
        let flags = Set(p.dietFlags ?? [])
        let n = p.nutrients
        switch name.lowercased() {
        case "vegan":       return flags.contains("non-vegan") ? ("vegan", "animal-derived ingredients") : nil
        case "vegetarian":  return flags.contains("non-vegetarian") ? ("vegetarian", "meat or fish") : nil
        case "low-sugar diet", "low sugar":
            if let s = n.sugar_g, s > 12.5 { return ("low-sugar diet", "high sugar") }; return nil
        case "low-sodium diet", "low-sodium", "low sodium":
            if let s = n.sodium_mg, s > 400 { return ("low-sodium diet", "high sodium") }; return nil
        case "gluten-free": return flags.contains("gluten") ? ("gluten-free", "gluten") : nil
        case "dairy-free":  return flags.contains("milk") ? ("dairy-free", "milk") : nil
        default:            return nil
        }
    }

    private static func nutrientBonuses(_ n: Nutrients) -> [String] {
        var b: [String] = []
        if let f = n.fiber_g, f >= 6 { b.append("fiber") }
        if let p = n.protein_g, p >= 12 { b.append("protein") }
        if let c = n.calcium_mg, c >= 120 { b.append("calcium") }
        if let i = n.iron_mg, i >= 4.5 { b.append("iron") }               // ≥25% DV
        if let k = n.potassium_mg, k >= 700 { b.append("potassium") }     // ≥15% DV
        return b
    }

    private static func deltaReasonV4(overall: Int, your: Int, restriction: Restriction?,
                                      avoid: String?, results: [V4RuleResult],
                                      mult: [String: Double]) -> DeltaReason? {
        if let r = restriction {
            return DeltaReason(tone: .negative,
                text: "Capped — contains \(r.trigger), which conflicts with your \(r.type) restriction.")
        }
        if let a = avoid {
            return DeltaReason(tone: .negative,
                text: "Capped — contains \(a), which you chose to avoid.")
        }
        let delta = your - overall
        guard abs(delta) >= 3 else { return nil }
        // Name the most emphasized rule as the driver.
        let driver = results.max {
            abs((mult[$0.rule] ?? 1) - 1) * $0.weight < abs((mult[$1.rule] ?? 1) - 1) * $1.weight
        }
        let label = driver.flatMap { ruleFactor($0.rule, fraction: $0.fraction, product: nil)?.0 } ?? "your goals"
        let positive = delta > 0
        return DeltaReason(tone: positive ? .positive : .negative,
            text: positive ? "Scores higher for you — \(label)." : "Scores lower for you — \(label).")
    }

    /// Human phrase + polarity for a rule at a given fraction, for factors and
    /// the deltaReason placeholder. Nutrient claims defer to the badge levels
    /// (NutrientLevels) so wording never contradicts the Breakdown card.
    private static func ruleFactor(_ rule: String, fraction f: Double,
                                   product p: Product?) -> (String, Bool)? {
        switch rule {
        case "S12": return f >= 0.4 ? ("good nutritional quality", true)
                                    : ("limited nutritional quality", false)
        case "S2":  return f >= 0.7 ? ("minimally processed", true) : ("highly processed", false)
        case "S1":  return f >= 0.85 ? ("clean ingredient list", true) : ("riskier additives", false)
        case "S3":
            if let n = p?.nutrients.sugar_g.map(NutrientLevels.sugar) {
                switch n { case .high: return ("high sugar", false)
                           case .moderate: return ("moderate sugar", false)
                           case .low: return ("low sugar", true) }
            }
            return f >= 0.6 ? ("low sugar", true) : ("high sugar", false)
        case "S4":
            if let n = p?.nutrients.sodium_mg.map(NutrientLevels.sodium), n == .high {
                return ("high sodium", false)
            }
            return f >= 0.6 ? nil : ("high sodium", false)
        case "S5":
            if let n = p?.nutrients.satFat_g.map(NutrientLevels.satFat), n == .high {
                return ("high saturated fat", false)
            }
            return f >= 0.6 ? nil : ("high saturated fat", false)
        case "S6":  return f >= 0.9 ? nil : ("artificial sweeteners", false)
        case "S13": return f >= 0.5 ? ("rich in vitamins & minerals", true) : nil
        default:    return nil
        }
    }

    /// Most-specific-first router over normalized category tags. OFF category
    /// arrays include ancestors, so exact tag membership is enough.
    static func route(_ p: Product, ruleset rs: RulesetV4 = .bundled) -> String {
        let tags = Set(p.categories ?? [])
        for entry in rs.router where tags.contains(entry.match) {
            return entry.profile
        }
        return "general"
    }

    // MARK: Rule dispatch

    private static func evaluate(_ rule: String, variant: String?,
                                 product p: Product, rs: RulesetV4) -> (Double, Bool) {
        switch rule {
        case "S1":  return s1(p, rs: rs)
        case "S2":  return s2(p)
        case "S3":  return s3(p, variant: variant ?? "foods", rs: rs)
        case "S4":  return stepped(p.nutrients.sodium_mg, thresholds: rs.s4Thresholds,
                                   unknownCredit: 0.30)
        case "S5":  return stepped(p.nutrients.satFat_g,
                                   thresholds: rs.s5Thresholds[variant ?? "standard"]
                                       ?? rs.s5Thresholds["standard"] ?? [3, 8, 15],
                                   unknownCredit: 0.40)
        case "S6":  return s6(p, rs: rs)
        case "S7":  return s7(p, rs: rs)
        case "S8":  return s8(p, rs: rs)
        case "S9":  return s9(p, rs: rs)
        case "S10": return s10(p, rs: rs)
        case "S11": return (!(p.origins ?? []).isEmpty ? 1.0 : 0.0, true)   // Tier-1
        case "S12": return s12(p)
        case "S13": return s13(p, rs: rs)
        case "waterSource":        return waterSource(p, rs: rs)
        case "mineralDisclosure":  return (p.nutrients.calcium_mg != nil ? 1.0 : 0.0, true)
        case "cropRisk":           return cropRisk(p, rs: rs)
        case "dairyLabels":        return pointsRule(p, rs.dairyLabels, plantAware: false)
        case "dairyQuality":       return pointsRule(p, rs.dairyLabels, plantAware: true)
        case "dairyProcessing":    return dairyProcessing(p, rs: rs)
        case "brewMaterial":       return brewMaterial(p, rs: rs)
        case "sweetenerType":      return kwLookup(haystack(p), rs.sweetenerType,
                                                   fallback: rs.sweetenerTypeDefault ?? 0.3)
        case "authenticity":       return authenticity(p, rs: rs)
        case "sweetenerProcessing": return kwLookup(haystack(p), rs.sweetenerProcessing,
                                                    fallback: rs.sweetenerProcessingDefault ?? 0.6)
        case "wholeGrain":         return wholeGrain(p, rs: rs)
        case "flourOxidizers":     return flourOxidizers(p)
        case "stabilizers":        return stabilizers(p, rs: rs)
        case "welfare":            return pointsRule(p, rs.welfare, plantAware: true)
        default:    return (0, false)   // unknown rule id in ruleset → earns nothing
        }
    }

    // MARK: Phase C category rules

    /// Searchable text for keyword rules: name + categories + labels + ingredients.
    private static func haystack(_ p: Product) -> String {
        ([p.name.lowercased(), p.ingredientsText?.lowercased() ?? ""]
         + (p.categories ?? []) + (p.labels ?? [])).joined(separator: " ")
    }

    private static let organicLabels: Set<String> = ["organic", "eu-organic", "usda-organic"]

    private static func s9(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        (Set(p.labels ?? []).isDisjoint(with: organicLabels) ? 0.0 : 1.0, true)   // Tier-1
    }

    private static func s10(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        guard let crops = rs.cropRisk.map({ $0.lowRisk + $0.highRisk }),
              let hero = (p.ingredientShares ?? []).first(where: { share in
                  crops.contains { share.name.contains($0) }
              })
        else { return (0.20, false) }
        // Declared percent wins; OFF's estimate is trusted at 75%.
        guard let pct = hero.percent ?? hero.percentEstimate.map({ $0 * 0.75 })
        else { return (0.20, false) }
        for step in rs.heroCredit ?? [[15, 1.0], [10, 0.8], [5, 0.5], [2, 0.2]]
        where step.count == 2 && pct >= step[0] {   // 10% is inside the 10–15 band
            return (step[1], true)
        }
        return (0.0, true)
    }

    private static func waterSource(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        let tags = Set(p.categories ?? [])
        for entry in rs.waterSource ?? [] where tags.contains(entry.match) {
            return (entry.credit, true)
        }
        return (0.0, true)   // Tier-1: a premium source is always printed
    }

    private static func cropRisk(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        guard let cfg = rs.cropRisk else { return (0.4, false) }
        if !Set(p.labels ?? []).isDisjoint(with: organicLabels) { return (1.0, true) }
        let hay = haystack(p)
        var credit = 0.4   // crop not identifiable → mid, Tier-1-ish
        if cfg.highRisk.contains(where: { hay.contains($0) }) { credit = cfg.highCredit }
        else if cfg.lowRisk.contains(where: { hay.contains($0) }) { credit = cfg.lowCredit }
        if hay.contains("rice") { credit = min(credit, cfg.riceCap) }
        return (credit, true)
    }

    /// Additive label credits capped at a denominator (dairy quality, welfare).
    private static func pointsRule(_ p: Product, _ cfg: RulesetV4.PointsRule?,
                                   plantAware: Bool) -> (Double, Bool) {
        guard let cfg else { return (0.4, false) }
        if plantAware, let neutral = cfg.plantNeutral,
           (p.dietFlags ?? []).contains("vegan") || haystack(p).contains("plant-based") {
            return (neutral, true)   // never penalized for not being dairy/meat
        }
        let labels = Set(p.labels ?? [])
        let pts = cfg.points.reduce(0.0) { labels.contains($1.key) ? $0 + $1.value : $0 }
        return (min(1.0, pts / cfg.denominator), true)   // Tier-1
    }

    private static func dairyProcessing(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        let tags = Set((p.categories ?? []) + (p.labels ?? []))
        for entry in rs.dairyProcessing ?? [] where tags.contains(entry.match) {
            return (entry.credit, true)
        }
        return (rs.dairyProcessingDefault ?? 0.85, true)   // fresh pasteurized default
    }

    private static func brewMaterial(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        let hay = haystack(p) + " " + (p.packagingMaterials ?? []).joined(separator: " ")
        for entry in rs.brewMaterial ?? [] where hay.contains(entry.kw) {
            return (entry.credit, true)
        }
        return (rs.brewMaterialDefault ?? 0.40, false)   // unknown bag material
    }

    private static func kwLookup(_ hay: String, _ table: [RulesetV4.KwCredit]?,
                                 fallback: Double) -> (Double, Bool) {
        for entry in table ?? [] where hay.contains(entry.kw) {
            return (entry.credit, true)
        }
        return (fallback, true)   // Tier-1: type is derivable from the label
    }

    private static func authenticity(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        let hay = haystack(p)
        if (rs.authenticityBad ?? []).contains(where: { hay.contains($0) }) {
            return (0.0, true)
        }
        if let shares = p.ingredientShares, shares.count == 1 { return (1.0, true) }
        return (0.6, true)
    }

    private static func wholeGrain(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        ((rs.wholeGrainKw ?? []).contains { haystack(p).contains($0) } ? 1.0 : 0.0, true)
    }

    private static func flourOxidizers(_ p: Product) -> (Double, Bool) {
        guard p.hasIngredientData else { return (0.30, false) }
        let codes = Set(p.additives.compactMap(\.code))
        return (codes.contains("e924") || codes.contains("e927a") ? 0.0 : 1.0, true)
    }

    private static func stabilizers(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        guard p.hasIngredientData else { return (0.30, false) }
        let pens = rs.stabilizerPenalties ?? [:]
        let total = p.additives.compactMap(\.code).reduce(0.0) { $0 + (pens[$1] ?? 0) }
        return (max(0, 1 - total), true)
    }

    // MARK: S1 — ingredient & additive risk

    private static func s1(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        guard p.additiveIngredientTextMissing != true, p.hasIngredientData else { return (0.20, false) }

        var penalties: [Double] = []
        var gumsCounted = 0
        for additive in p.additives {
            guard let code = additive.code else { continue }
            guard let fraction = s1Fraction(for: additive, code: code, rs: rs) else { continue }
            if rs.gumCodes.contains(code) {
                guard gumsCounted < 2 else { continue }   // gum cap
                gumsCounted += 1
            }
            penalties.append(fraction)
        }

        // Text-detected signals (HFCS, artificial/natural flavors) — things
        // OFF's additive tagger doesn't cover. One hit per signal.
        if let text = p.ingredientsText?.lowercased() {
            for (needle, tier) in rs.textSignals where text.contains(needle) {
                if let fraction = rs.tierFractions[tier] { penalties.append(fraction) }
            }
        }

        // Dampening: worst hits count in full; after `afterCount`, half.
        penalties.sort(by: >)
        var total = 0.0
        for (i, pen) in penalties.enumerated() {
            total += i < rs.dampening.afterCount ? pen : pen * rs.dampening.factor
        }
        return (max(0, 1 - total), true)
    }

    /// S1 penalty fraction from detector tier, with ruleset code lookup as fallback.
    private static func s1Fraction(for additive: ProductAdditive, code: String,
                                   rs: RulesetV4) -> Double? {
        if let tier = additive.tier {
            switch tier {
            case .major: return rs.tierFractions["A"]
            case .moderate: return rs.tierFractions["B"]
            case .mild: return rs.tierFractions["C"]
            case .soft: return rs.tierFractions["D"]
            case .exempt: return nil
            case .unclassified: return rs.tierFractions["C"]
            }
        }
        if let tier = rs.additiveTiers[code], let fraction = rs.tierFractions[tier] {
            return fraction
        }
        return rs.tierFractions["C"]
    }

    // MARK: S2 — processing level

    private static func s2(_ p: Product) -> (Double, Bool) {
        switch p.novaGroup {
        case 1: return (1.0, true)
        case 2: return (0.75, true)
        case 3: return (0.40, true)
        case 4: return (0.0, true)
        default: break
        }
        // NOVA unknown → ingredient-count fallback (still data-backed when a
        // parsed list exists).
        if let count = p.ingredientShares?.count, count > 0 {
            switch count {
            case 1...3:  return (0.85, true)
            case 4...7:  return (0.55, true)
            case 8...15: return (0.25, true)
            default:     return (0.0, true)
            }
        }
        return (0.40, false)
    }

    // MARK: S3 — added sugar (fvn-discounted fallback)

    private static func s3(_ p: Product, variant: String, rs: RulesetV4) -> (Double, Bool) {
        let thresholds = rs.s3Thresholds[variant] ?? rs.s3Thresholds["foods"]!
        if let added = p.nutrients.addedSugar_g {
            return stepped(added, thresholds: thresholds, unknownCredit: 0.25)
        }
        if let total = p.nutrients.sugar_g {
            // Total-sugar fallback, discounted by fruit/veg/nuts content so
            // intrinsic fruit/dairy sugar isn't scored like a soda's.
            let effective = total * (1 - min(1, (p.nutrients.fvn ?? 0) / 100))
            return stepped(effective, thresholds: thresholds, unknownCredit: 0.25)
        }
        return (0.25, false)
    }

    // MARK: S6 — artificial sweeteners

    private static func s6(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        guard p.hasIngredientData else { return (0.50, false) }
        let hits = p.additives.compactMap(\.code).filter(rs.sweetenerCodes.contains).count
        guard hits > 0 else { return (1.0, true) }
        return (max(0, 0.60 - 0.40 * Double(hits - 1)), true)
    }

    // MARK: S7 — packaging material (worst wins)

    private static func s7(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        guard let materials = p.packagingMaterials, !materials.isEmpty else {
            return (0.30, false)
        }
        // Longest keys first so "polystyrene" wins over "pet"-style collisions.
        let keys = rs.s7Materials.keys.sorted { $0.count > $1.count }
        let credits = materials.map { material -> Double in
            for key in keys where material.contains(key) {
                return rs.s7Materials[key]!
            }
            return 0.30   // material present but unrecognized → generic plastic tier
        }
        return (credits.min() ?? 0.30, true)
    }

    // MARK: S8 — certifications (Tier-1: absence = zero, but always "data")

    private static func s8(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        let labels = Set(p.labels ?? [])
        let hit = rs.certLabels.contains { labels.contains($0) }
        return (hit ? 1.0 : 0.0, true)
    }

    // MARK: S12 — nutrient quality (the v3 blocks, restoring positive nutrition)

    private static func s12(_ p: Product) -> (Double, Bool) {
        let n = p.nutrients
        let protDens: Double
        if let kcal = n.kcal, kcal < 5 {
            protDens = 0
        } else if let kcal = n.kcal, kcal > 0 {
            protDens = min(1, ((n.protein_g ?? 0) / (kcal / 100)) / 15)
        } else {
            protDens = 0
        }
        let fiber = min(1, (n.fiber_g ?? 0) / 8)
        let fvn = min(1, (n.fvn ?? 0) / 100)
        let f = 0.40 * protDens + 0.35 * fiber + 0.25 * fvn
        return (f, n.kcal != nil || n.fiber_g != nil || n.fvn != nil)
    }

    // MARK: S13 — beneficial micronutrient credit (positive-only)

    private static func s13(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        guard let cfg = rs.micronutrients else { return (0.35, false) }
        let n = p.nutrients
        let present: [String: Double?] = [
            "iron_mg": n.iron_mg, "potassium_mg": n.potassium_mg,
            "magnesium_mg": n.magnesium_mg, "zinc_mg": n.zinc_mg,
            "vitaminC_mg": n.vitaminC_mg, "calcium_mg": n.calcium_mg,
        ]
        var sum = 0.0
        var had = false
        for (key, dv) in cfg.dv {
            guard dv > 0, let v = present[key] ?? nil, v > 0 else { continue }
            had = true
            sum += min(cfg.capPerNutrient, v / dv)   // %DV per 100g, capped
        }
        // No micros reported → neutral, not a penalty; lowers Data Confidence.
        guard had else { return (cfg.unknownCredit, false) }
        return (min(1.0, sum / cfg.target), true)
    }

    // MARK: Shared helpers

    /// ≤t1 → 1.0 · ≤t2 → 0.60 · ≤t3 → 0.30 · above → 0. nil → unknown tier.
    private static func stepped(_ value: Double?, thresholds t: [Double],
                                unknownCredit: Double) -> (Double, Bool) {
        guard let v = value else { return (unknownCredit, false) }
        guard t.count == 3 else { return (unknownCredit, false) }
        if v <= t[0] { return (1.0, true) }
        if v <= t[1] { return (0.60, true) }
        if v <= t[2] { return (0.30, true) }
        return (0.0, true)
    }

    // MARK: - Debug breakdown (DEBUG builds only)

    #if DEBUG
    /// Per-rule breakdown for the in-app SCORE DEBUG panel. Re-evaluates the
    /// live scoring path so the printed table always matches the rings above it.
    static func debugText(_ p: Product, for profile: UserProfile,
                          ruleset rs: RulesetV4 = .bundled) -> String {
        guard p.hasMinimumData else { return "insufficient data — no score" }
        let profileId = route(p, ruleset: rs)
        if profileId == "unsupported" { return "unsupported category — Sage doesn't rate this" }
        guard let ruleList = rs.profiles[profileId] else { return "no profile '\(profileId)'" }

        let results = ruleList.map { pr -> (rule: String, w: Double, f: Double, had: Bool) in
            let (f, had) = evaluate(pr.rule, variant: pr.variant, product: p, rs: rs)
            return (pr.rule, pr.w, f, had)
        }
        let totalW = results.reduce(0) { $0 + $1.w }
        let earned = results.reduce(0) { $0 + $1.w * $1.f }
        let backed = results.filter(\.had).reduce(0) { $0 + $1.w }

        let mult = profile.personalizeScoring ? ruleMultipliers(profile, rs: rs) : [:]
        let personalized = !mult.isEmpty

        func pad(_ s: String, _ n: Int) -> String {
            s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
        }
        func f2(_ v: Double) -> String { String(format: "%.2f", v) }

        var lines: [String] = ["profile \(profileId) · ruleset \(rs.version)"]
        var header = pad("rule", 6) + pad("w", 5) + pad("f", 6) + pad("w·f", 7)
        if personalized { header += pad("m", 5) }
        header += "data"
        lines.append(header)
        for r in results {
            var row = pad(r.rule, 6) + pad(String(Int(r.w)), 5) + pad(f2(r.f), 6) + pad(f2(r.w * r.f), 7)
            if personalized { row += pad(f2(mult[r.rule] ?? 1.0), 5) }
            row += r.had ? "✓" : "—"
            lines.append(row)
        }
        lines.append("Σw \(Int(totalW)) · earned \(f2(earned)) · conf \(Int((backed / totalW * 100).rounded()))%")

        // Headline numbers straight from the live path so the table can't drift.
        if case .scored(let sp) = scoreProduct(p, for: profile, ruleset: rs) {
            lines.append("OVERALL \(sp.overallScore)   YOUR \(sp.yourScore)")
            if let d = sp.deltaReason { lines.append("Δ: \(d.text)") }
            if !sp.restrictions.isEmpty {
                lines.append("gates: " + sp.restrictions.map { "\($0.type)(\($0.trigger))" }.joined(separator: ", "))
            }
        }
        return lines.joined(separator: "\n")
    }
    #endif
}
