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
        guard p.hasIngredientData else { return (0.20, false) }

        var penalties: [Double] = []
        var gumsCounted = 0
        for code in p.additives.compactMap(\.code) {
            guard let tier = rs.additiveTiers[code],
                  let fraction = rs.tierFractions[tier] else { continue }
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
}
