import Foundation

// MARK: - Scoring v5 (SCORING_V5.md) — health-only category-aware rule engine
//
// Score measures HEALTH only. Ethics / environment / packaging factors are
// out unless they have a direct health pathway (e.g. brewMaterial microplastics,
// contaminantRisk arsenic). Architecture: all tunable data lives in
// RulesetV5.json; this file only knows rule *shapes*. Score = Σ(w·f)/Σw,
// floored at 10. Base caps (trans fat, free-sugar ceiling) can limit Overall;
// preference caps (diet/avoid) limit Your Score only.

// MARK: Ruleset (mirrors RulesetV5.json)

struct RulesetV4: Codable {
    struct Bands: Codable { let excellent: Int; let good: Int; let ok: Int }
    struct Dampening: Codable { let afterCount: Int; let factor: Double }
    struct ProfileRule: Codable { let rule: String; let w: Double; let variant: String? }
    struct RouterEntry: Codable { let match: String; let profile: String }
    struct RuleMeta: Codable {
        let displayName: String
        let driverKind: String   // "merit" | "hygiene"
    }

    struct SourceCredit: Codable { let match: String; let credit: Double }
    struct KwCredit: Codable { let kw: String; let credit: Double }
    struct PointsRule: Codable {
        let points: [String: Double]
        let denominator: Double
        let plantNeutral: Double?
    }
    /// Arsenic pathway for plant milks: rice capped; all other crops neutral.
    struct ContaminantRisk: Codable {
        let riceCap: Double
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
    /// Removed in v5 (packaging non-health); kept optional for older downloads.
    let s7Materials: [String: Double]?
    let certLabels: [String]?
    let profiles: [String: [ProfileRule]]
    let router: [RouterEntry]
    /// Human labels + driverKind for overview prose (fail closed when missing).
    var ruleMeta: [String: RuleMeta]? = nil

    // Category rules — optional so an older downloaded ruleset can't crash
    // decoding; evaluators fall back to unknown credit when absent.
    let waterSource: [SourceCredit]?
    let contaminantRisk: ContaminantRisk?
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
        /// Soft preference chips (V5.0.4). Optional so older downloaded rulesets decode.
        let preference: [String: [String: Double]]?
    }
    struct AvoidEntry: Codable { let codes: [String]?; let text: [String]?; let labels: [String]? }
    /// Personalization ceilings (§7.3). Stacked: effectiveCap = min(fired).
    /// Base gates (transFat, freeSugarCeiling) apply to Overall; preference
    /// gates (avoid/diet) apply to Your Score only.
    struct HardGates: Codable {
        let avoidListCap: Int
        /// Legacy flat ceiling for non-tapered diet conflicts (e.g. vegan).
        let dietConflictCap: Int?
        /// Per-restriction linear tapers (keys = restriction type, lowercased).
        let dietConflictTapers: [String: DietConflictTaper]?
        let transFat: TransFatGate?
        let freeSugarCeiling: FreeSugarCeiling?
        let nnsCeiling: NNSCeiling?

        struct DietConflictTaper: Codable {
            let metric: String      // "sugar_g" | "sodium_mg"
            let taperStart: Double
            let taperEnd: Double
            let minCap: Int
        }
        struct TransFatGate: Codable {
            let threshold: Double   // g/100g
            let cap: Int
        }
        struct FreeSugarCeiling: Codable {
            let cap: Int
        }
        struct NNSCeiling: Codable {
            let cap: Int
        }
    }

    let multipliers: Multipliers?
    let avoidList: [String: AvoidEntry]?
    let hardGates: HardGates?

    /// Band label for a score under this ruleset (single source for all UI).
    func bandLabel(_ score: Int) -> String {
        if score >= bands.excellent { return "Excellent" }
        if score >= bands.good { return "Good" }
        if score >= bands.ok { return "OK" }
        return "Bad"
    }

    func scoreTier(for score: Int) -> ScoreTier {
        if score >= bands.excellent { return .excellent }
        if score >= bands.good { return .good }
        if score >= bands.ok { return .poor }
        return .bad
    }

    /// All known rule ids (profiles ∪ meta keys) for validator fail-closed checks.
    var allRuleIds: [String] {
        var ids = Set<String>()
        if let keys = ruleMeta?.keys { ids.formUnion(keys) }
        for list in profiles.values {
            for pr in list { ids.insert(pr.rule) }
        }
        return Array(ids).sorted()
    }

    func displayName(for rule: String) -> String? {
        guard let name = ruleMeta?[rule]?.displayName, !name.isEmpty else { return nil }
        return name
    }

    func isMerit(_ rule: String) -> Bool {
        (ruleMeta?[rule]?.driverKind ?? "merit") == "merit"
    }

    private final class BundleToken {}

    /// The ruleset shipped inside the app. A downloaded ruleset takes
    /// precedence when newer (see RulesetStore).
    static let bundled: RulesetV4 = {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "RulesetV5", withExtension: "json")
                ?? Bundle.main.url(forResource: "RulesetV5", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rs = try? JSONDecoder().decode(RulesetV4.self, from: data)
        else {
            fatalError("RulesetV5.json missing or malformed — the app cannot score without it")
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
    /// Engine identity — bumped with health-only v5 rewrite.
    static let engineVersion = "v5"

    struct FVNResolution: Equatable {
        let value: Double?
        /// Nil for measured/absent values; category family for inferred values.
        let inferredFrom: String?
    }

    /// Resolve missing FVN from narrow whole-food category truth. The NOVA
    /// guard prevents processed derivatives from inheriting an ancestral tag.
    static func resolvedFVN(_ p: Product) -> FVNResolution {
        if let measured = p.nutrients.fvn {
            return FVNResolution(value: measured, inferredFrom: nil)
        }
        guard p.novaGroup == 1 || p.novaGroup == 2 else {
            return FVNResolution(value: nil, inferredFrom: nil)
        }
        let tags = Set(p.categories ?? [])
        let fruitTags: Set<String> = [
            "fruits", "fresh-fruits", "berries", "tropical-fruits",
        ]
        let vegetableTags: Set<String> = [
            "vegetables", "fresh-vegetables", "salads",
        ]
        if !tags.isDisjoint(with: fruitTags) {
            return FVNResolution(value: 100, inferredFrom: "fruits")
        }
        if !tags.isDisjoint(with: vegetableTags) {
            return FVNResolution(value: 100, inferredFrom: "vegetables")
        }
        if tags.contains("nuts") {
            return FVNResolution(value: 100, inferredFrom: "nuts")
        }
        if tags.contains("legumes") {
            return FVNResolution(value: 100, inferredFrom: "legumes")
        }
        return FVNResolution(value: nil, inferredFrom: nil)
    }

    /// Engine-level normalization used before any rule or cap evaluates.
    private static func applyingInferredFVN(to product: Product) -> Product {
        guard product.nutrients.fvn == nil,
              let inferred = resolvedFVN(product).value
        else { return product }
        var normalized = product
        normalized.nutrients.fvn = inferred
        return normalized
    }

    /// nil when the product fails the minimum-data requirement (§3.3) —
    /// callers show the insufficient-data state, never a made-up number.
    static func score(_ p: Product, ruleset rs: RulesetV4 = .bundled) -> V4Result? {
        let p = applyingInferredFVN(to: p)
        guard p.hasMinimumData else { return nil }
        let profileId = route(p, ruleset: rs)
        if profileId == "unsupported" || profileId == "unscored_sweetener" { return nil }
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
        var base = max(floorScore, Int(raw.rounded()))
        base = applyBaseCaps(base: base, product: p, rs: rs).capped
        return V4Result(rulesetVersion: rs.version,
                        profileId: profileId,
                        base: base,
                        confidence: backed / totalW,
                        rules: results)
    }

    // MARK: Full scored product (Phase D — SCORING_V4.md §7)

    /// Outcome of the app-facing scoring path.
    enum Outcome {
        case scored(Product)      // Overall + Your Score filled in
        /// Pure sweeteners etc. — data shown, health score withheld.
        case unscored(Product, reasonKey: String)
        case unsupported          // water / alcohol → Sage doesn't rate these
        case insufficientData     // fails the minimum-data requirement
    }

    /// Drop-in replacement for the v3 `ScoringEngine.score`: returns the product
    /// with overallScore, yourScore, deltaReason, bonuses, and restrictions
    /// filled from the v4 rule engine + multiplier personalization + hard gates.
    static func scoreProduct(_ p: Product, for profile: UserProfile,
                             ruleset rs: RulesetV4 = .bundled) -> Outcome {
        let originalProduct = p
        let p = applyingInferredFVN(to: p)
        guard p.hasMinimumData else { return .insufficientData }
        let profileId = route(p, ruleset: rs)
        if profileId == "unsupported" { return .unsupported }

        // Diet / avoid flags still run for unscored sweeteners — there is just
        // no number to cap.
        let restrictions: [Restriction] = profile.autoFlagRestrictions
            ? restrictionInputs(profile).compactMap { name in
                evalRestriction(name, product: p, ruleset: rs).map {
                    Restriction(type: $0.type, trigger: $0.trigger)
                }
              }
            : []

        if profileId == "unscored_sweetener" {
            var out = originalProduct
            out.scoreState = .unscored(reasonKey: "sweetener")
            out.overallScore = nil
            out.yourScore = nil
            out.bonuses = []
            out.firedCaps = nil
            out.bindingCap = nil
            out.overallFiredCaps = nil
            out.overallBindingCap = nil
            out.overview = nil
            out.overviewStale = false
            out.restrictions = restrictions
            return .unscored(out, reasonKey: "sweetener")
        }

        guard let ruleList = rs.profiles[profileId] else { return .insufficientData }

        // Evaluate every rule once; reuse for Overall and Your Score.
        let results = ruleList.map { pr -> V4RuleResult in
            let (f, had) = evaluate(pr.rule, variant: pr.variant, product: p, rs: rs)
            return V4RuleResult(rule: pr.rule, weight: pr.w, fraction: f, hadData: had)
        }
        let totalW = results.reduce(0) { $0 + $1.weight }
        guard totalW > 0 else { return .insufficientData }
        var overall = max(floorScore,
                          Int((results.reduce(0) { $0 + $1.weight * $1.fraction } / totalW * 100).rounded()))
        // Health hard gates on Overall (trans fat, free-sugar ceiling, NNS).
        let baseGate = applyBaseCaps(base: overall, product: p, rs: rs)
        overall = baseGate.capped

        // Keep raw OFF nutrients in the returned/stored product. Inference is
        // engine-local so debug can always distinguish it from measured FVN.
        var out = originalProduct
        out.scoreState = .scored
        out.overallScore = overall
        out.bonuses = nutrientBonuses(p.nutrients)
        out.overallFiredCaps = baseGate.fired.isEmpty ? nil : baseGate.fired
        out.overallBindingCap = baseGate.binding
        out.restrictions = restrictions

        guard profile.personalizeScoring else {
            out.yourScore = overall
            out.overview = nil
            out.overviewStale = true
            // Preference caps unused when personalization is off.
            out.firedCaps = nil
            out.bindingCap = nil
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

        // Preference caps (diet/avoid) only — overall health caps stay separate.
        let avoidHits = avoidListHits(p, profile: profile, rs: rs)
        let (prefFired, _, _) = applyCaps(weighted: your,
                                          restrictions: out.restrictions,
                                          avoidHits: avoidHits,
                                          nutrients: p.nutrients,
                                          rs: rs)
        // Numerically stack overall + preference ceilings onto Your Score.
        let stacked = baseGate.fired + prefFired
        if let effective = stacked.map(\.value).min() {
            your = min(your, effective)
        }
        let binding: ScoreCap? = {
            guard let effective = stacked.map(\.value).min() else { return nil }
            // Uncapped personalized score (before any cap).
            var uncapped = yTotal > 0
                ? max(floorScore, Int((yEarned / yTotal * 100).rounded()))
                : overall
            uncapped = max(floorScore, min(100, uncapped + nutrientNudge(profile.objective, p.nutrients)))
            guard uncapped > effective else { return nil }
            // Prefer a preference-kind binding for Your Score UI; fall back to
            // overall health caps when they alone bind.
            let preferenceFirst = stacked.filter { $0.value == effective }
                .sorted { a, b in
                    let rank: (ScoreCap) -> Int = {
                        switch $0.kind {
                        case "dietConflict": return 0
                        case "avoidList": return 1
                        case "transFat", "freeSugar", "nns": return 2
                        default: return 3
                        }
                    }
                    return rank(a) != rank(b) ? rank(a) < rank(b) : a.id < b.id
                }
            return preferenceFirst.first
        }()

        out.firedCaps = prefFired.isEmpty ? nil : prefFired
        out.bindingCap = {
            guard let b = binding, b.kind == "dietConflict" || b.kind == "avoidList"
            else { return nil }
            return b
        }()
        out.yourScore = your
        out.overview = nil
        out.overviewStale = true
        return .scored(out)
    }

    /// Signed drivers for the backend /explain prompt (§7.5). Restriction /
    /// avoid conflicts lead; then the rules the user's profile most emphasized.
    static func signedFactors(_ p: Product, profile: UserProfile,
                              ruleset rs: RulesetV4 = .bundled) -> [String] {
        let p = applyingInferredFVN(to: p)
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

    /// One factor that contributed to a rule's final multiplier (before clamp).
    struct MultiplierFactor: Equatable {
        let source: String       // "objective" | "goal" | "slider" | "preference"
        let selection: String    // e.g. "eat healthier", "high protein"
        let factor: Double
    }

    /// Per-rule multiplier with provenance; `product` is clamped to [0.5, 2.0].
    struct RuleMultiplierDetail: Equatable {
        let factors: [MultiplierFactor]
        var product: Double {
            let raw = factors.reduce(1.0) { $0 * $1.factor }
            return min(2.0, max(0.5, raw))
        }
    }

    /// Organic preference is display-only — no health-scoring pathway.
    static let organicPreferenceKey = "organic"

    /// True when the user opted into Organic and OFF labels confirm a certification.
    static func showsOrganicChip(product: Product, profile: UserProfile) -> Bool {
        let prefs = Set(profile.preferences.map { $0.lowercased() })
        guard prefs.contains(organicPreferenceKey) else { return false }
        let labels = Set((product.labels ?? []).map { $0.lowercased() })
        let organicTags: Set<String> = [
            "organic", "eu-organic", "usda-organic", "organic-certification",
        ]
        return !labels.isDisjoint(with: organicTags)
    }

    /// Per-rule multiplier breakdown from objective + goals + sliders + preferences.
    static func ruleMultiplierBreakdown(_ profile: UserProfile, rs: RulesetV4)
    -> [String: RuleMultiplierDetail] {
        guard let m = rs.multipliers else { return [:] }
        var factorsByRule: [String: [MultiplierFactor]] = [:]
        func apply(_ table: [String: Double]?, source: String, selection: String) {
            for (rule, factor) in table ?? [:] {
                factorsByRule[rule, default: []].append(
                    MultiplierFactor(source: source, selection: selection, factor: factor)
                )
            }
        }
        let objective = profile.objective.lowercased()
        apply(m.objective[objective], source: "objective", selection: objective)
        for g in profile.healthGoals ?? [] {
            let key = g.lowercased()
            apply(m.goal[key], source: "goal", selection: key)
        }
        let sliders: [(String, Int?)] = [
            ("clean", profile.sliderCleanIngredients),
            ("nutrition", profile.sliderNutrition),
        ]
        for (key, level) in sliders where level != nil && level != 1 {
            apply(m.slider[key]?[String(level!)], source: "slider", selection: "\(key):\(level!)")
        }
        let prefTable = m.preference ?? [:]
        for pref in profile.preferences {
            let key = pref.lowercased()
            // Organic is intentionally absent from the preference map.
            apply(prefTable[key], source: "preference", selection: key)
        }
        return factorsByRule.mapValues { RuleMultiplierDetail(factors: $0) }
    }

    /// Per-rule multiplier from objective + health goals + priority sliders + preferences.
    private static func ruleMultipliers(_ profile: UserProfile, rs: RulesetV4) -> [String: Double] {
        ruleMultiplierBreakdown(profile, rs: rs).mapValues(\.product)
    }

    /// Human phrase for a preference-sourced delta driver ("your high-protein preference").
    private static func preferenceDriverPhrase(_ selection: String) -> String {
        let hyphenated = selection.replacingOccurrences(of: " ", with: "-")
        return "your \(hyphenated) preference"
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
    static func avoidListHit(_ p: Product, profile: UserProfile, rs: RulesetV4) -> String? {
        avoidListHits(p, profile: profile, rs: rs).first
    }

    /// All avoid-list items that match this product (display order preserved).
    static func avoidListHits(_ p: Product, profile: UserProfile, rs: RulesetV4) -> [String] {
        guard let chosen = profile.avoidList, !chosen.isEmpty else { return [] }
        let avoid = rs.avoidList
        var hits: [String] = []
        for item in chosen {
            let entry = avoid?[item.lowercased()]
            if AvoidListMatcher.matches(item: item, entry: entry, product: p) {
                hits.append(item)
            }
        }
        return hits
    }

    /// Existing scoring restrictions plus the new single diet pattern (§7.1).
    private static func restrictionInputs(_ profile: UserProfile) -> [String] {
        var out = profile.restrictions
        if let d = profile.dietPattern, d.lowercased() != "none" { out.append(d) }
        return out
    }

    /// Deterministic restriction conflict check. Metric diets use taper thresholds
    /// from the ruleset when present; otherwise legacy fixed cutoffs.
    private static func evalRestriction(_ name: String, product p: Product,
                                        ruleset rs: RulesetV4 = .bundled)
    -> (type: String, trigger: String)? {
        let flags = Set(p.dietFlags ?? [])
        let n = p.nutrients
        let key = name.lowercased()
        switch key {
        case "vegan":       return flags.contains("non-vegan") ? ("vegan", "animal-derived ingredients") : nil
        case "vegetarian":  return flags.contains("non-vegetarian") ? ("vegetarian", "meat or fish") : nil
        case "low-sugar diet", "low sugar":
            let type = "low-sugar diet"
            if let taper = dietTaper(for: type, rs: rs), let s = n.sugar_g {
                // Fires only once sugar exceeds taperStart (inclusive start = no fire).
                return s > taper.taperStart ? (type, "high sugar") : nil
            }
            if let s = n.sugar_g, s > 12.5 { return (type, "high sugar") }
            return nil
        case "low-sodium diet", "low-sodium", "low sodium":
            let type = "low-sodium diet"
            if let taper = dietTaper(for: type, rs: rs), let s = n.sodium_mg {
                return s > taper.taperStart ? (type, "high sodium") : nil
            }
            if let s = n.sodium_mg, s > 400 { return (type, "high sodium") }
            return nil
        case "gluten-free": return flags.contains("gluten") ? ("gluten-free", "gluten") : nil
        case "dairy-free":  return flags.contains("milk") ? ("dairy-free", "milk") : nil
        default:            return nil
        }
    }

    private static func dietTaper(for type: String, rs: RulesetV4)
    -> RulesetV4.HardGates.DietConflictTaper? {
        rs.hardGates?.dietConflictTapers?[type.lowercased()]
    }

    /// Linear taper: ≤ start → 100; ≥ end → minCap; between → interpolate.
    static func taperedDietCap(amount: Double,
                               taper: RulesetV4.HardGates.DietConflictTaper) -> Int {
        if amount <= taper.taperStart { return 100 }
        if amount >= taper.taperEnd { return taper.minCap }
        let span = taper.taperEnd - taper.taperStart
        guard span > 0 else { return taper.minCap }
        let t = (amount - taper.taperStart) / span
        return Int((100.0 - (100.0 - Double(taper.minCap)) * t).rounded())
    }

    /// Cap for a single diet restriction (taper or flat legacy).
    static func dietCapValue(for restriction: Restriction, nutrients: Nutrients,
                             rs: RulesetV4) -> (value: Int, intensity: String)? {
        let type = restriction.type.lowercased()
        if let taper = dietTaper(for: type, rs: rs) {
            let amount: Double?
            switch taper.metric {
            case "sugar_g": amount = nutrients.sugar_g
            case "sodium_mg": amount = nutrients.sodium_mg
            default: amount = nil
            }
            guard let amount else { return nil }
            let value = taperedDietCap(amount: amount, taper: taper)
            guard value < 100 else { return nil }
            let intensity = amount >= taper.taperEnd ? "full" : "partial"
            return (value, intensity)
        }
        let flat = rs.hardGates?.dietConflictCap ?? 20
        return (flat, "full")
    }

    /// Collect fired caps and apply stacked min. Binding = tightest that limits weighted.
    static func applyCaps(weighted: Int, restrictions: [Restriction],
                          avoidHits: [String], nutrients: Nutrients,
                          rs: RulesetV4)
    -> (fired: [ScoreCap], binding: ScoreCap?, capped: Int) {
        var fired: [ScoreCap] = []

        for r in restrictions {
            guard let (value, intensity) = dietCapValue(for: r, nutrients: nutrients, rs: rs)
            else { continue }
            let sugarNote: String? = {
                if r.type.lowercased().contains("sugar"), let s = nutrients.sugar_g {
                    return String(format: "%.0f g of sugar", s)
                }
                if r.type.lowercased().contains("sodium"), let s = nutrients.sodium_mg {
                    return String(format: "%.0f mg of sodium", s)
                }
                return r.trigger
            }()
            fired.append(ScoreCap(
                id: "dietConflictCap",
                value: value,
                shortLabel: r.type.lowercased(),
                kind: "dietConflict",
                intensity: intensity,
                detail: {
                    let base = "Conflicts with your \(r.type.lowercased())."
                    if intensity == "full" {
                        return "\(base) Caps your score at \(value)."
                    }
                    if let note = sugarNote {
                        return "\(base) Limits your score (\(note))."
                    }
                    return "\(base) Limits your score."
                }()
            ))
        }

        let avoidCap = rs.hardGates?.avoidListCap ?? 49
        for hit in avoidHits {
            let isSeed = hit.lowercased().contains("seed")
            fired.append(ScoreCap(
                id: isSeed ? "seedOilCap" : "avoidListCap",
                value: avoidCap,
                shortLabel: hit.lowercased(),
                kind: "avoidList",
                intensity: "full",
                detail: "On your avoid list. Caps your score at \(avoidCap)."
            ))
        }

        guard !fired.isEmpty else { return ([], nil, weighted) }

        // effectiveCap = min(all firing caps)
        let effective = fired.map(\.value).min()!
        let capped = min(weighted, effective)
        // Binding = the minimum-value cap among those that actually limit the score.
        let binding: ScoreCap? = {
            guard weighted > effective else { return nil }
            return fired.filter { $0.value == effective }
                .sorted { $0.id < $1.id }
                .first
        }()
        return (fired, binding, capped)
    }

    /// Public helper for UI copy: avoid-list ceiling from the live ruleset.
    static func avoidListCapValue(rs: RulesetV4 = .bundled) -> Int {
        rs.hardGates?.avoidListCap ?? 49
    }

    /// Health-only base caps that limit Overall (and Your when stacked).
    /// - transFat: industrial TFA only (NOVA-4 numeric path, or partially-hydrogenated text)
    /// - freeSugarCeiling: caloric sweeteners / high sugar with low FVN (fruit sugar exempt)
    static func applyBaseCaps(base: Int, product p: Product, rs: RulesetV4)
    -> (fired: [ScoreCap], binding: ScoreCap?, capped: Int) {
        let p = applyingInferredFVN(to: p)
        var fired: [ScoreCap] = []

        if let gate = rs.hardGates?.transFat, firesIndustrialTransFat(p, rs: rs, gate: gate) {
            fired.append(ScoreCap(
                id: "transFatCap",
                value: gate.cap,
                shortLabel: "trans fat",
                kind: "transFat",
                intensity: "full",
                detail: "Contains industrial trans fat. Caps the overall score at \(gate.cap)."
            ))
        }

        if let gate = rs.hardGates?.freeSugarCeiling,
           isCaloricSweetener(p),
           !isNonNutritiveTableSweetener(p) {
            fired.append(ScoreCap(
                id: "freeSugarCeiling",
                value: gate.cap,
                shortLabel: "free sugar",
                kind: "freeSugar",
                intensity: "full",
                detail: "Caloric sweetener. Caps the overall score at \(gate.cap)."
            ))
        }

        if let gate = rs.hardGates?.nnsCeiling,
           route(p, ruleset: rs) == "unscored_sweetener",
           (p.nutrients.sugar_g ?? 0) < 10,
           isNonNutritiveTableSweetener(p) {
            // Dead path after V5.0.7: table NNS products are unscored, so this
            // ceiling never binds a dial. Kept for completeness if route changes.
            fired.append(ScoreCap(
                id: "nnsCeiling",
                value: gate.cap,
                shortLabel: "non-nutritive sweetener",
                kind: "nns",
                intensity: "full",
                detail: "Non-nutritive table sweetener. Caps the overall score at \(gate.cap)."
            ))
        }

        guard !fired.isEmpty else { return ([], nil, base) }
        let effective = fired.map(\.value).min()!
        let capped = min(base, effective)
        let binding: ScoreCap? = {
            guard base > effective else { return nil }
            return fired.filter { $0.value == effective }.sorted { $0.id < $1.id }.first
        }()
        return (fired, binding, capped)
    }

    /// Industrial TFA: text signal always; numeric needs NOVA 4 + threshold
    /// (ruminant profiles dairy_milk / yogurt_cheese / meat use > 2.0 g).
    private static func firesIndustrialTransFat(
        _ p: Product, rs: RulesetV4, gate: RulesetV4.HardGates.TransFatGate
    ) -> Bool {
        let text = (p.ingredientsText ?? "").lowercased()
        if text.range(of: #"partially hydrogenated|parcialmente hidrogenad"#,
                      options: .regularExpression) != nil {
            return true
        }
        guard let tf = p.nutrients.transFat_g, p.novaGroup == 4 else { return false }
        let profileId = route(p, ruleset: rs)
        let ruminant = ["dairy_milk", "yogurt_cheese", "meat"].contains(profileId)
        let threshold = ruminant ? 2.0 : gate.threshold
        return tf > threshold
    }

    /// Sugars / honeys / syrups category OR (sugar ≥ 50 g with FVN < 80).
    /// High-FVN dried fruit is exempt from the sugar≥50 numeric path.
    private static func isCaloricSweetener(_ p: Product) -> Bool {
        let tags = (p.categories ?? []).map { $0.lowercased() }
        let needles = ["sugars", "honeys", "syrups", "molasses", "sweeteners"]
        if tags.contains(where: { tag in needles.contains { tag.contains($0) } }) {
            return true
        }
        if let s = p.nutrients.sugar_g, s >= 50, (p.nutrients.fvn ?? 0) < 80 {
            return true
        }
        return false
    }

    /// Stevia / monk fruit / erythritol table products with sugar_g < 10.
    private static func isNonNutritiveTableSweetener(_ p: Product) -> Bool {
        let sugar = p.nutrients.sugar_g ?? 0
        guard sugar < 10 else { return false }
        let hay = ([p.name] + (p.categories ?? []) + (p.labels ?? [])
                   + [p.ingredientsText ?? ""]).joined(separator: " ").lowercased()
        let markers = ["stevia", "monk fruit", "monkfruit", "erythritol",
                       "e960", "e968", "e955", "sucralose", "aspartame", "e951"]
        return markers.contains { hay.contains($0) }
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
        case "S13": return f >= 0.5 ? ("rich in vitamins & minerals", true) : nil
        default:    return nil
        }
    }

    /// Most-specific-first router over normalized category tags. OFF category
    /// arrays include ancestors, so exact tag membership is enough.
    /// Defense in depth (V5.0.4): `whole_foods` only accepts NOVA ∈ {0,1,2} so
    /// processed derivatives that inherit ancestral tags (e.g. peanut butter →
    /// `nuts`) fall through to snacks/general instead of skipping S5.
    static func route(_ p: Product, ruleset rs: RulesetV4 = .bundled) -> String {
        let tags = Set(p.categories ?? [])
        let nova = p.novaGroup
        for entry in rs.router where tags.contains(entry.match) {
            if entry.profile == "whole_foods", !(nova == 0 || nova == 1 || nova == 2) {
                continue
            }
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
        case "S10": return s10(p, rs: rs)
        case "S12": return s12(p, variant: variant)
        case "S13": return s13(p, rs: rs)
        case "contaminantRisk":    return contaminantRisk(p, rs: rs)
        case "dairyProcessing":    return dairyProcessing(p, rs: rs)
        case "brewMaterial":       return brewMaterial(p, rs: rs)
        case "sweetenerType":      return kwLookup(haystack(p), rs.sweetenerType,
                                                   fallback: rs.sweetenerTypeDefault ?? 0.3)
        case "authenticity":       return authenticity(p, rs: rs)
        case "sweetenerProcessing": return kwLookup(haystack(p), rs.sweetenerProcessing,
                                                    fallback: rs.sweetenerProcessingDefault ?? 0.6)
        case "wholeGrain":         return wholeGrain(p, rs: rs)
        default:    return (0, false)   // unknown / removed rule id → earns nothing
        }
    }

    // MARK: Phase C category rules

    /// Searchable text for keyword rules: name + categories + labels + ingredients.
    private static func haystack(_ p: Product) -> String {
        ([p.name.lowercased(), p.ingredientsText?.lowercased() ?? ""]
         + (p.categories ?? []) + (p.labels ?? [])).joined(separator: " ")
    }

    /// Common plant-milk crop names used by S10 hero-share detection.
    private static let plantMilkCrops = [
        "coconut", "almond", "hemp", "cashew", "macadamia", "pea",
        "oat", "soy", "soya", "rice", "wheat", "corn",
    ]

    private static func s10(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        guard let hero = (p.ingredientShares ?? []).first(where: { share in
            plantMilkCrops.contains { share.name.contains($0) }
        })
        else { return (0.20, false) }
        // Declared percent wins; OFF's estimate is trusted at 75%.
        guard let pct = hero.percent ?? hero.percentEstimate.map({ $0 * 0.75 })
        else { return (0.20, false) }
        for step in rs.heroCredit ?? [[15, 1.0], [10, 0.8], [5, 0.5], [2, 0.2]]
        where step.count == 2 && pct >= step[0] {
            return (step[1], true)
        }
        return (0.0, true)
    }

    /// Rice arsenic pathway: rice → riceCap; all other crops neutral 1.0.
    private static func contaminantRisk(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        let cap = rs.contaminantRisk?.riceCap ?? 0.4
        let hay = haystack(p)
        if hay.contains("rice") { return (cap, true) }
        return (1.0, true)
    }

    private static func dairyProcessing(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        let tags = Set((p.categories ?? []) + (p.labels ?? []))
        for entry in rs.dairyProcessing ?? [] where tags.contains(entry.match) {
            return (entry.credit, true)
        }
        // Default is an assumption (fresh pasteurized), not evidence.
        return (rs.dairyProcessingDefault ?? 0.85, false)
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

    /// Qualitative within-category notes for unscored sweeteners (not a score).
    /// At most three plain-language lines derived from the legacy sweetener rules.
    static func sweetenerQualityNotes(_ p: Product, ruleset rs: RulesetV4 = .bundled) -> [String] {
        var notes: [String] = []

        let (typeF, _) = evaluate("sweetenerType", variant: nil, product: p, rs: rs)
        if let typeNote = sweetenerTypeNote(for: p, fraction: typeF, rs: rs) {
            notes.append(typeNote)
        }

        let (procF, _) = evaluate("sweetenerProcessing", variant: nil, product: p, rs: rs)
        if procF >= 0.95 {
            notes.append("Minimally processed")
        } else if procF <= 0.25 {
            notes.append("Refined")
        }

        let (authF, _) = evaluate("authenticity", variant: nil, product: p, rs: rs)
        if authF >= 0.95 {
            notes.append("Single-ingredient product")
        } else if authF <= 0.05 {
            notes.append("Blend")
        }

        return Array(notes.prefix(3))
    }

    private static func sweetenerTypeNote(for p: Product, fraction: Double, rs: RulesetV4) -> String? {
        let hay = haystack(p)
        for entry in rs.sweetenerType ?? [] where hay.contains(entry.kw) {
            switch entry.kw {
            case "raw honey":
                return "Raw honey — one of the less processed options"
            case "manuka":
                return "Manuka honey — one of the less processed options"
            case "maple":
                return "Maple syrup — one of the less processed options"
            case "stevia":
                return "Stevia — a non-nutritive option"
            case "monk fruit":
                return "Monk fruit — a non-nutritive option"
            case "honey":
                return "Honey — among the less refined options"
            case "coconut sugar":
                return "Coconut sugar — less refined than white sugar"
            case "turbinado", "demerara":
                return "Partially refined cane sugar"
            case "brown sugar":
                return "Brown sugar — still a refined sweetener"
            case "agave":
                return "Agave — a more concentrated sweetener"
            case "corn syrup":
                return "Corn syrup — highly processed"
            case "high fructose", "hfcs":
                return "High-fructose corn syrup"
            default:
                break
            }
        }
        if fraction >= 0.85 { return "One of the less processed sweetener options" }
        return nil
    }

    private static func wholeGrain(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        ((rs.wholeGrainKw ?? []).contains { haystack(p).contains($0) } ? 1.0 : 0.0, true)
    }

    // MARK: S1 — ingredient & additive risk

    private static func s1(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        // Whole-food bypass: NOVA 1–2 + no additives + no textSignals → clean,
        // even when ingredients_text is missing (single-ingredient produce).
        // Whole-food bypass: NOVA 1–2 + no additives + no textSignals → clean,
        // even when ingredients_text is missing (single-ingredient produce).
        let additivesEmpty = p.additives.isEmpty
        let textHit: Bool = {
            guard let text = p.ingredientsText?.lowercased() else { return false }
            return rs.textSignals.keys.contains { text.contains($0) }
        }()
        if (1...2).contains(p.novaGroup), additivesEmpty, !textHit {
            return (1.0, true)
        }

        guard p.additiveIngredientTextMissing != true, p.hasIngredientData else {
            return (0.20, false)
        }

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

    // MARK: S3 — added sugar (fvn-discounted fallback; drinks free-sugar + NNS floor)

    private static let nnsCodes: Set<String> = [
        "e950", "e951", "e954", "e955", "e957", "e959", "e960", "e961", "e962", "e969",
    ]
    private static let nnsTextMarkers = [
        "stevia", "sucralose", "aspartame", "acesulfame",
    ]

    private static func hasNonNutritiveSweetener(_ p: Product) -> Bool {
        let codes = Set(p.additives.compactMap(\.code))
        if !codes.isDisjoint(with: nnsCodes) { return true }
        let hay = ([p.ingredientsText ?? ""] + (p.labels ?? []) + [p.name])
            .joined(separator: " ").lowercased()
        return nnsTextMarkers.contains { hay.contains($0) }
    }

    private static func s3(_ p: Product, variant: String, rs: RulesetV4) -> (Double, Bool) {
        let thresholds = rs.s3Thresholds[variant] ?? rs.s3Thresholds["foods"]!
        let fvn = p.nutrients.fvn ?? 0
        let isDrinks = variant == "drinks"

        let result: (Double, Bool)
        if let added = p.nutrients.addedSugar_g {
            let effective: Double
            if isDrinks, fvn >= 80, let total = p.nutrients.sugar_g {
                // ≥80% juice: treat at least 70% of total sugar as free sugar.
                effective = max(added, total * 0.70)
            } else {
                effective = added
            }
            result = stepped(effective, thresholds: thresholds, unknownCredit: 0.25)
        } else if let total = p.nutrients.sugar_g {
            // Total-sugar fallback, discounted by fruit/veg/nuts content so
            // intrinsic fruit/dairy sugar isn't scored like a soda's.
            // Drinks: FVN discount capped at 30% (WHO free-sugar for juice).
            let discount: Double
            if isDrinks {
                discount = min(0.30, fvn / 100)
            } else {
                discount = min(1, fvn / 100)
            }
            let effective = total * (1 - discount)
            result = stepped(effective, thresholds: thresholds, unknownCredit: 0.25)
        } else {
            result = (0.25, false)
        }

        // Diet drinks: NNS floor so zero-sugar sodas don't score as Excellent.
        if isDrinks, hasNonNutritiveSweetener(p) {
            return (min(result.0, 0.30), result.1)
        }
        return result
    }

    // MARK: S12 — nutrient quality

    private static func s12(_ p: Product, variant: String? = nil) -> (Double, Bool) {
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
        let f: Double
        if variant == "produce" {
            f = 0.20 * protDens + 0.30 * fiber + 0.50 * fvn
        } else {
            f = 0.40 * protDens + 0.35 * fiber + 0.25 * fvn
        }
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

    /// Piecewise-linear through anchors f(t0)=1.0, f(t1)=0.60, f(t2)=0.30,
    /// f(t2·1.5)=0.0. Same signature / unknownCredit as the old step function.
    static func stepped(_ value: Double?, thresholds t: [Double],
                        unknownCredit: Double) -> (Double, Bool) {
        guard let v = value else { return (unknownCredit, false) }
        guard t.count == 3 else { return (unknownCredit, false) }
        let anchors: [(Double, Double)] = [
            (t[0], 1.0),
            (t[1], 0.60),
            (t[2], 0.30),
            (t[2] * 1.5, 0.0),
        ]
        if v <= anchors[0].0 { return (1.0, true) }
        if v >= anchors.last!.0 { return (0.0, true) }
        for i in 0..<(anchors.count - 1) {
            let (x0, y0) = anchors[i]
            let (x1, y1) = anchors[i + 1]
            if v <= x1 {
                let span = x1 - x0
                guard span > 0 else { return (y1, true) }
                let tFrac = (v - x0) / span
                return (y0 + (y1 - y0) * tFrac, true)
            }
        }
        return (0.0, true)
    }

    // MARK: - Overview generation payload

    struct OverviewMultiplierSource: Encodable, Equatable {
        let source: String       // "objective" | "goal" | "slider" | "preference"
        let selection: String
        let factor: Double
    }

    struct OverviewRuleInput: Encodable, Equatable {
        let rule: String
        let topic: String
        let weight: Double
        let fraction: Double
        let contribution: Double
        let multiplier: Double?
        /// Provenance of the final multiplier (pre-clamp factors). Empty/nil = none.
        let multiplierSources: [OverviewMultiplierSource]?
        let evidenceTier: String
        let driverKind: String

        init(rule: String, topic: String, weight: Double, fraction: Double,
             contribution: Double, multiplier: Double?,
             multiplierSources: [OverviewMultiplierSource]? = nil,
             evidenceTier: String, driverKind: String) {
            self.rule = rule
            self.topic = topic
            self.weight = weight
            self.fraction = fraction
            self.contribution = contribution
            self.multiplier = multiplier
            self.multiplierSources = multiplierSources
            self.evidenceTier = evidenceTier
            self.driverKind = driverKind
        }
    }

    struct OverviewContributorInput: Encodable, Equatable {
        let topic: String
        let contribution: Double
        let evidenceTier: String
        /// Potential loss = weight × (1 − fraction); used for negative ranking.
        var potentialLoss: Double? = nil
    }

    struct OverviewDeltaDriver: Encodable, Equatable {
        let topic: String
        let direction: String   // "up" | "down"
    }

    struct OverviewHardGate: Encodable, Equatable {
        let kind: String        // "dietConflict" | "avoidList"
        let detail: String
        let cappedTo: Int
        /// "full" | "partial" — partial means tapered (not slammed to minCap).
        let intensity: String
        let bindingCapId: String
        let shortLabel: String
    }

    struct OverviewFiredCap: Encodable, Equatable {
        let id: String
        let value: Int
        let shortLabel: String
        let kind: String
        let intensity: String?
    }

    /// Inputs for `/explain` and the deterministic template fallback.
    struct OverviewContext: Encodable, Equatable {
        let profileId: String
        let productName: String
        let objective: String
        let overall: Int
        let your: Int
        let band: String
        let confidence: Double
        let hasScoreableIngredientSignal: Bool
        let hasNutritionData: Bool
        let hasIngredientData: Bool
        let rules: [OverviewRuleInput]
        let topPositive: [OverviewContributorInput]
        let topNegative: [OverviewContributorInput]
        let nutrientLevels: [String]
        let deltaValue: Int
        let deltaDrivers: [OverviewDeltaDriver]
        let avoidMatches: [String]
        let detectedAdditives: [String]
        let novaGroup: Int?
        let hardGate: OverviewHardGate?
        let bindingCap: OverviewFiredCap?
        let firedCaps: [OverviewFiredCap]
        /// Overall health cap that limited the universal score (freeSugar / transFat / nns).
        let overallBindingCap: OverviewFiredCap?
        let overallFiredCaps: [OverviewFiredCap]
        let knownRuleIds: [String]
        /// Nonzero Your-Score nutrient nudge (build muscle / lose weight).
        let nutrientNudge: Int?
        let nutrientNudgeDriver: String?
    }

    /// Build the structured overview payload from the live v4 scoring path.
    static func overviewContext(for product: Product, profile: UserProfile,
                                ruleset rs: RulesetV4) -> OverviewContext? {
        let product = applyingInferredFVN(to: product)
        guard product.hasMinimumData else { return nil }
        let profileId = route(product, ruleset: rs)
        if profileId == "unsupported" || profileId == "unscored_sweetener" { return nil }
        guard let ruleList = rs.profiles[profileId] else { return nil }

        let multDetail = profile.personalizeScoring ? ruleMultiplierBreakdown(profile, rs: rs) : [:]
        var rules: [OverviewRuleInput] = []
        for pr in ruleList {
            let (f, had) = evaluate(pr.rule, variant: pr.variant, product: product, rs: rs)
            guard let display = rs.displayName(for: pr.rule) else {
                print("overview: missing displayName for rule \(pr.rule); excluded from prose payload")
                continue
            }
            let detail = multDetail[pr.rule]
            let sources = detail?.factors.map {
                OverviewMultiplierSource(source: $0.source, selection: $0.selection, factor: $0.factor)
            }
            rules.append(OverviewRuleInput(
                rule: pr.rule,
                topic: display,
                weight: pr.w,
                fraction: f,
                contribution: pr.w * f,
                multiplier: detail.map(\.product),
                multiplierSources: sources,
                evidenceTier: had ? "data" : "unknown-tier",
                driverKind: rs.isMerit(pr.rule) ? "merit" : "hygiene"
            ))
        }

        let totalW = ruleList.reduce(0) { $0 + $1.w }
        let backed: Double = {
            var sum = 0.0
            for pr in ruleList {
                let (_, had) = evaluate(pr.rule, variant: pr.variant, product: product, rs: rs)
                if had { sum += pr.w }
            }
            return sum
        }()
        let confidence = totalW > 0 ? backed / totalW : 0

        // Positives: merit rules only (never praise "hazard absent" hygiene rules).
        // Exclude S3/S4/S5 when the displayed nutrient badge is HIGH (V5.0.6).
        // Negatives: ranked by potential loss with materiality floor ≥ 2.0 pts.
        // A rule may appear in positives OR negatives, never both — keep the
        // side with the better (lower) rank; ties go to negatives (V5.0.4).
        func nutrientBadgeIsHigh(_ rule: String) -> Bool {
            let n = product.nutrients
            switch rule {
            case "S3": return n.sugar_g.map(NutrientLevels.sugar) == .high
            case "S4": return n.sodium_mg.map(NutrientLevels.sodium) == .high
            case "S5": return n.satFat_g.map(NutrientLevels.satFat) == .high
            default: return false
            }
        }
        let positiveRanked = rules
            .filter {
                $0.driverKind == "merit"
                    && $0.fraction >= 0.55
                    && !nutrientBadgeIsHigh($0.rule)
            }
            .sorted { $0.contribution > $1.contribution }

        let negativeRanked: [(OverviewRuleInput, Double)] = rules.compactMap { r in
            let m = profile.personalizeScoring ? (r.multiplier ?? 1.0) : 1.0
            let loss = r.weight * m * (1 - r.fraction)
            guard loss >= 2.0 else { return nil }
            return (r, loss)
        }
        .sorted { $0.1 > $1.1 }

        var posSide = Set<String>()
        var negSide = Set<String>()
        let posIndex = Dictionary(uniqueKeysWithValues:
            positiveRanked.enumerated().map { ($1.rule, $0) })
        let negIndex = Dictionary(uniqueKeysWithValues:
            negativeRanked.enumerated().map { ($1.0.rule, $0) })
        let allRules = Set(posIndex.keys).union(negIndex.keys)
        for rule in allRules {
            let pIdx = posIndex[rule]
            let nIdx = negIndex[rule]
            switch (pIdx, nIdx) {
            case (let p?, let n?):
                if p < n { posSide.insert(rule) }
                else { negSide.insert(rule) }   // tie → negative
            case (_?, nil): posSide.insert(rule)
            case (nil, _?): negSide.insert(rule)
            default: break
            }
        }

        let positives = positiveRanked
            .filter { posSide.contains($0.rule) }
            .prefix(3)
            .map { OverviewContributorInput(topic: $0.topic, contribution: $0.contribution,
                                          evidenceTier: $0.evidenceTier) }
        let negatives = negativeRanked
            .filter { negSide.contains($0.0.rule) }
            .prefix(3)
            .map { OverviewContributorInput(topic: $0.0.topic, contribution: $0.0.contribution,
                                          evidenceTier: $0.0.evidenceTier,
                                          potentialLoss: $0.1) }

        let baseMean: Double = {
            guard totalW > 0 else { return 0 }
            // Use full rule list contributions for mean (including unnamed rules).
            var earned = 0.0
            for pr in ruleList {
                let (f, _) = evaluate(pr.rule, variant: pr.variant, product: product, rs: rs)
                earned += pr.w * f
            }
            return earned / totalW
        }()

        let avoidMatches = avoidListHits(product, profile: profile, rs: rs)
        let activeRestrictions: [Restriction] = {
            if !product.restrictions.isEmpty { return product.restrictions }
            guard profile.autoFlagRestrictions else { return [] }
            return restrictionInputs(profile).compactMap { name in
                evalRestriction(name, product: product, ruleset: rs).map {
                    Restriction(type: $0.type, trigger: $0.trigger)
                }
            }
        }()

        // Preference caps for Your Score hardGate only — never mix overall
        // health caps into "also on your list" (honey freeSugar bug, V5.0.6).
        let prefFiredStored: [ScoreCap] = product.firedCaps ?? {
            let (fired, _, _) = applyCaps(
                weighted: 100,
                restrictions: activeRestrictions,
                avoidHits: avoidMatches,
                nutrients: product.nutrients,
                rs: rs
            )
            return fired
        }()
        let prefBinding = product.bindingCap

        let overallFiredPayload: [OverviewFiredCap] = {
            let fired = product.overallFiredCaps
                ?? applyBaseCaps(base: 100, product: product, rs: rs).fired
            return fired.map {
                OverviewFiredCap(id: $0.id, value: $0.value, shortLabel: $0.shortLabel,
                                 kind: $0.kind, intensity: $0.intensity)
            }
        }()
        let overallBindingPayload: OverviewFiredCap? = {
            let binding = product.overallBindingCap
                ?? applyBaseCaps(base: max(product.overallScore ?? 1, 1), product: product, rs: rs).binding
            return binding.map {
                OverviewFiredCap(id: $0.id, value: $0.value, shortLabel: $0.shortLabel,
                                 kind: $0.kind, intensity: $0.intensity)
            }
        }()

        let firedCapsPayload = prefFiredStored.map {
            OverviewFiredCap(id: $0.id, value: $0.value, shortLabel: $0.shortLabel,
                             kind: $0.kind, intensity: $0.intensity)
        }
        let bindingPayload = prefBinding.map {
            OverviewFiredCap(id: $0.id, value: $0.value, shortLabel: $0.shortLabel,
                             kind: $0.kind, intensity: $0.intensity)
        }

        let hardGate: OverviewHardGate? = {
            // Your Score preference binding only (dietConflict / avoidList).
            guard let b = prefBinding else { return nil }
            let intensity = b.intensity ?? "full"
            let others = prefFiredStored.filter { $0.id != b.id }.map(\.shortLabel)
            var detail: String
            if b.kind == "dietConflict" {
                if intensity == "partial", let sugar = product.nutrients.sugar_g {
                    detail = String(
                        format: "its %.0f g of sugar conflicts with your %@, which limits your score",
                        sugar, b.shortLabel)
                } else {
                    detail = "conflicts with your \(b.shortLabel), which caps Your Score at \(b.value)"
                }
            } else if b.kind == "avoidList" {
                detail = "contains \(b.shortLabel), which is on your avoid list and caps Your Score at \(b.value)"
            } else {
                detail = b.detail ?? "score capped at \(b.value)"
            }
            if !others.isEmpty {
                detail += " (also on your list: \(others.joined(separator: ", ")))"
            }
            return OverviewHardGate(
                kind: b.kind,
                detail: detail,
                cappedTo: b.value,
                intensity: intensity,
                bindingCapId: b.id,
                shortLabel: b.shortLabel
            )
        }()

        let deltaDrivers: [OverviewDeltaDriver] = {
            if let gate = hardGate {
                return [OverviewDeltaDriver(topic: gate.detail, direction: "down")]
            }
            guard profile.personalizeScoring else { return [] }
            var drivers: [OverviewDeltaDriver] = []
            let nudge = nutrientNudge(profile.objective, product.nutrients)
            if nudge != 0 {
                let topic: String
                switch profile.objective.lowercased() {
                case "lose weight":
                    topic = "slightly adjusted for calorie density given your weight-loss goal"
                case "build muscle":
                    topic = "slightly adjusted for protein density given your muscle-building goal"
                default:
                    topic = "slightly adjusted for your nutrition goal"
                }
                drivers.append(OverviewDeltaDriver(
                    topic: topic,
                    direction: nudge > 0 ? "up" : "down"
                ))
            }
            let scored = rules.compactMap { r -> (OverviewDeltaDriver, Double)? in
                let m = r.multiplier ?? 1
                guard abs(m - 1) > 0.01 else { return nil }
                let direction: String
                if r.fraction >= baseMean {
                    direction = m > 1 ? "up" : "down"
                } else {
                    direction = m > 1 ? "down" : "up"
                }
                let pressure = abs(m - 1) * r.weight * abs(r.fraction - baseMean)
                // Prefer preference-sourced phrasing when preference is among
                // the dominant factors on this rule (V5.0.6).
                let topic: String = {
                    let sources = r.multiplierSources ?? []
                    let prefs = sources.filter { $0.source == "preference" }
                    let prefStrength = prefs.map { abs($0.factor - 1) }.max() ?? 0
                    let otherStrength = sources
                        .filter { $0.source != "preference" }
                        .map { abs($0.factor - 1) }.max() ?? 0
                    if let top = prefs.max(by: { abs($0.factor - 1) < abs($1.factor - 1) }),
                       prefStrength + 1e-9 >= otherStrength {
                        return preferenceDriverPhrase(top.selection)
                    }
                    return r.topic
                }()
                return (OverviewDeltaDriver(topic: topic, direction: direction), pressure)
            }
            .sorted { $0.1 > $1.1 }
            drivers.append(contentsOf: scored.prefix(2).map(\.0))
            return Array(drivers.prefix(3))
        }()

        let nudgeVal = nutrientNudge(profile.objective, product.nutrients)
        let nudgeDriver: String? = {
            guard nudgeVal != 0 else { return nil }
            switch profile.objective.lowercased() {
            case "lose weight":
                return "slightly adjusted for calorie density given your weight-loss goal"
            case "build muscle":
                return "slightly adjusted for protein density given your muscle-building goal"
            default:
                return "slightly adjusted for your nutrition goal"
            }
        }()

        let additiveNames = product.additives.map(\.name)

        let overall = product.overallScore ?? 0
        let your = product.yourScore ?? overall
        return OverviewContext(
            profileId: profileId,
            productName: product.name,
            objective: profile.objective,
            overall: overall,
            your: your,
            band: rs.bandLabel(overall),
            confidence: confidence,
            hasScoreableIngredientSignal: product.hasScoreableIngredientSignal,
            hasNutritionData: product.hasNutritionData,
            hasIngredientData: product.hasIngredientData,
            rules: rules,
            topPositive: Array(positives),
            topNegative: Array(negatives),
            nutrientLevels: NutrientLevels.promptLines(product.nutrients),
            deltaValue: your - overall,
            deltaDrivers: deltaDrivers,
            avoidMatches: avoidMatches,
            detectedAdditives: additiveNames,
            novaGroup: product.hasKnownNova ? product.novaGroup : nil,
            hardGate: hardGate,
            bindingCap: bindingPayload,
            firedCaps: firedCapsPayload,
            overallBindingCap: overallBindingPayload,
            overallFiredCaps: overallFiredPayload,
            knownRuleIds: rs.allRuleIds,
            nutrientNudge: nudgeVal == 0 ? nil : nudgeVal,
            nutrientNudgeDriver: nudgeDriver
        )
    }

    /// Engine confidence + unknown-tier weight gate for the provisional banner.
    /// Independent of personalization — only rule evidence matters.
    static func isProvisionalScore(_ product: Product, ruleset rs: RulesetV4) -> Bool {
        let product = applyingInferredFVN(to: product)
        guard product.hasMinimumData else { return true }
        let profileId = route(product, ruleset: rs)
        if profileId == "unsupported" || profileId == "unscored_sweetener" { return false }
        guard let ruleList = rs.profiles[profileId] else { return true }
        var totalW = 0.0, backed = 0.0
        var heavyUnknown = false
        for pr in ruleList {
            let (_, had) = evaluate(pr.rule, variant: pr.variant, product: product, rs: rs)
            totalW += pr.w
            if had { backed += pr.w }
            else if pr.w >= 10 { heavyUnknown = true }
        }
        let confidence = totalW > 0 ? backed / totalW : 0
        return confidence < 0.80 || heavyUnknown
    }

    static func isProvisional(_ ctx: OverviewContext) -> Bool {
        if ctx.confidence < 0.80 { return true }
        return ctx.rules.contains { $0.weight >= 10 && $0.evidenceTier == "unknown-tier" }
    }
}

// MARK: - Debug score breakdown (DEBUG builds only)

#if DEBUG
extension ScoringEngineV4 {

    /// Full v5 score audit trail: router, per-rule fractions, multipliers,
    /// nutrient nudge, hard gates, and stored vs computed scores.
    /// (Swift type names remain `ScoringEngineV4` / `RulesetV4` for rename debt.)
    static func debugText(_ product: Product, for profile: UserProfile,
                          ruleset rs: RulesetV4) -> String {
        let fvnResolution = resolvedFVN(product)
        let product = applyingInferredFVN(to: product)
        let n = product.nutrients
        var lines: [String] = []

        func num(_ label: String, _ v: Double?) {
            lines.append("  \(label): \(v.map { String(format: "%.2f", $0) } ?? "—")")
        }

        lines.append("SCORING DEBUG — v5 rule engine")
        lines.append("Product: \(product.name) (\(product.id))")
        lines.append("Engine: \(engineVersion)")
        lines.append("Ruleset: \(rs.version)")
        lines.append("")

        lines.append("GATES")
        lines.append("  hasMinimumData: \(product.hasMinimumData)")
        lines.append("  hasNutritionData: \(product.hasNutritionData)")
        lines.append("  hasScoreableIngredientSignal: \(product.hasScoreableIngredientSignal)")
        let profileId = route(product, ruleset: rs)
        lines.append("  router → \(profileId)")
        if profileId == "unsupported" {
            lines.append("  outcome: unsupported (water / alcohol)")
            return lines.joined(separator: "\n")
        }
        if profileId == "unscored_sweetener" {
            lines.append("  outcome: unscored_sweetener")
            lines.append("")
            lines.append("AMONG SWEETENERS (relative quality — not a health score)")
            for note in sweetenerQualityNotes(product, ruleset: rs) {
                lines.append("  · \(note)")
            }
            if product.restrictions.isEmpty {
                lines.append("  restrictions: none")
            } else {
                lines.append("  restrictions: \(product.restrictions.map { "\($0.type) (\($0.trigger))" }.joined(separator: ", "))")
            }
            return lines.joined(separator: "\n")
        }
        guard product.hasMinimumData, let ruleList = rs.profiles[profileId] else {
            lines.append("  outcome: insufficientData")
            return lines.joined(separator: "\n")
        }
        lines.append("")

        lines.append("INPUTS (per 100g)")
        num("kcal", n.kcal)
        num("protein_g", n.protein_g)
        num("fiber_g", n.fiber_g)
        num("sugar_g", n.sugar_g)
        num("satFat_g", n.satFat_g)
        num("sodium_mg", n.sodium_mg)
        if let value = fvnResolution.value, let source = fvnResolution.inferredFrom {
            lines.append("  fvn: \(String(format: "%.0f", value)) (inferred: \(source))")
        } else {
            num("fvn", n.fvn)
        }
        lines.append("  nova_group: \(product.novaGroup)")
        lines.append("  categories: \((product.categories ?? []).joined(separator: ", "))")
        lines.append("")

        let results = ruleList.map { pr -> V4RuleResult in
            let (f, had) = evaluate(pr.rule, variant: pr.variant, product: product, rs: rs)
            return V4RuleResult(rule: pr.rule, weight: pr.w, fraction: f, hadData: had)
        }
        let totalW = results.reduce(0) { $0 + $1.weight }
        let earned = results.reduce(0) { $0 + $1.weight * $1.fraction }
        let backed = results.filter(\.hadData).reduce(0) { $0 + $1.weight }
        let overall = totalW > 0
            ? max(floorScore, Int((earned / totalW * 100).rounded()))
            : floorScore
        let confidence = totalW > 0 ? backed / totalW : 0

        lines.append("RULES (profile \(profileId), Σw=\(String(format: "%.0f", totalW)))")
        for r in results {
            let contrib = r.weight * r.fraction
            let data = r.hadData ? "data" : "unknown-tier"
            lines.append("  · \(r.rule): w \(String(format: "%.0f", r.weight)) × f \(String(format: "%.3f", r.fraction)) = \(String(format: "%.2f", contrib)) (\(data))")
        }
        lines.append("  confidence: \(String(format: "%.1f%%", confidence * 100))")
        let baseGate = applyBaseCaps(base: overall, product: product, rs: rs)
        let cappedOverall = baseGate.capped
        lines.append("  overall (base): \(overall)  [raw \(String(format: "%.2f", earned / max(totalW, 1) * 100))]")
        for c in baseGate.fired {
            let mark = baseGate.binding?.id == c.id ? " [binding]" : ""
            lines.append("  overall cap \(c.id): \(overall) → \(min(overall, c.value))\(mark)")
        }
        if baseGate.binding != nil {
            lines.append("  overall (capped): \(cappedOverall)")
        }
        lines.append("  band: \(rs.bandLabel(cappedOverall))")
        lines.append("")

        lines.append("PROFILE")
        lines.append("  objective: \(profile.objective)")
        lines.append("  personalizeScoring: \(profile.personalizeScoring)")
        lines.append("  autoFlagRestrictions: \(profile.autoFlagRestrictions)")
        if let goals = profile.healthGoals, !goals.isEmpty {
            lines.append("  healthGoals: \(goals.joined(separator: ", "))")
        }
        if let diet = profile.dietPattern { lines.append("  dietPattern: \(diet)") }
        if let avoid = profile.avoidList, !avoid.isEmpty {
            lines.append("  avoidList: \(avoid.joined(separator: ", "))")
        }
        lines.append("  restrictions: \(profile.restrictions.isEmpty ? "none" : profile.restrictions.joined(separator: ", "))")
        lines.append("")

        let restrictions = profile.autoFlagRestrictions
            ? restrictionInputs(profile).compactMap { name in
                evalRestriction(name, product: product, ruleset: rs).map {
                    Restriction(type: $0.type, trigger: $0.trigger)
                }
              }
            : []
        if !restrictions.isEmpty {
            lines.append("  active restrictions: \(restrictions.map { "\($0.type) (\($0.trigger))" }.joined(separator: ", "))")
        }

        guard profile.personalizeScoring else {
            lines.append("PERSONALIZATION OFF → yourScore = overall (\(overall))")
            lines.append("  stored overallScore: \(product.overallScore.map(String.init) ?? "—")")
            lines.append("  stored yourScore: \(product.yourScore.map(String.init) ?? "—")")
            return lines.joined(separator: "\n")
        }

        let multDetail = ruleMultiplierBreakdown(profile, rs: rs)
        let mult = multDetail.mapValues(\.product)
        if !multDetail.isEmpty {
            lines.append("MULTIPLIERS")
            for (rule, detail) in multDetail.sorted(by: { $0.key < $1.key })
            where abs(detail.product - 1) > 0.001 {
                let parts = detail.factors.map {
                    "×\(String(format: "%.2f", $0.factor)) (\($0.source))"
                }.joined(separator: " ")
                lines.append("  · \(rule): \(parts) → ×\(String(format: "%.2f", detail.product))")
            }
            lines.append("")
        }
        if !profile.preferences.isEmpty {
            lines.append("PREFERENCES: \(profile.preferences.joined(separator: ", "))")
            lines.append("  organic chip: \(showsOrganicChip(product: product, profile: profile) ? "yes" : "no")")
            lines.append("")
        }

        var yEarned = 0.0, yTotal = 0.0
        lines.append("YOUR SCORE — Σ(w·m·f) / Σ(w·m)")
        for r in results {
            let m = mult[r.rule] ?? 1.0
            let contrib = r.weight * m * r.fraction
            yEarned += contrib
            yTotal += r.weight * m
            if abs(m - 1) > 0.001 {
                lines.append("  · \(r.rule): w \(String(format: "%.0f", r.weight)) × m \(String(format: "%.2f", m)) × f \(String(format: "%.3f", r.fraction)) = \(String(format: "%.2f", contrib))")
            }
        }
        var your = yTotal > 0 ? max(floorScore, Int((yEarned / yTotal * 100).rounded())) : overall
        lines.append("  weighted raw: \(String(format: "%.2f", yEarned / max(yTotal, 1) * 100)) → \(your)")

        let nudge = nutrientNudge(profile.objective, n)
        if nudge != 0 {
            your = max(floorScore, min(100, your + nudge))
            lines.append("  nutrient nudge (\(profile.objective)): \(nudge > 0 ? "+" : "")\(nudge) → \(your)")
        }

        let avoidHits = avoidListHits(product, profile: profile, rs: rs)
        let (fired, binding, capped) = applyCaps(
            weighted: your, restrictions: restrictions, avoidHits: avoidHits,
            nutrients: product.nutrients, rs: rs)
        for c in fired {
            lines.append("  fired cap \(c.id) (\(c.shortLabel)): ≤\(c.value) [\(c.intensity ?? "full")]")
        }
        if let b = binding {
            lines.append("  bindingCap: \(b.id) ≤\(b.value) → \(capped)")
        } else if !fired.isEmpty {
            lines.append("  caps fired but did not bind (weighted \(your) ≤ effective \(fired.map(\.value).min()!))")
        }
        your = capped

        lines.append("  computed yourScore: \(your)")
        lines.append("  stored overallScore: \(product.overallScore.map(String.init) ?? "—")")
        lines.append("  stored yourScore: \(product.yourScore.map(String.init) ?? "—")")
        if let reason = product.overview {
            lines.append("  overview: \(reason.text)")
        }

        return lines.joined(separator: "\n")
    }
}
#endif
