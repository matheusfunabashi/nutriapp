import Foundation

// MARK: - Scoring engine (v3 — anchored modifier model)
//
// Scale anchors: 100 perfect · 70 good · 50 neither good nor bad · 30 bad ·
// 10 shouldn't eat it. Scores are floored at 10 — never 0.
//
//   • Overall (Score 1) — goal-neutral, identical for everyone: start at a
//     neutral 50, add quality points (protein density, fiber, whole-food
//     content, low processing) and subtract penalty points (sugar, saturated
//     fat, sodium, ultra-processing, additive risk, trans fats).
//   • Your Score (Score 2) — Overall plus signed adjustments from the user's
//     objective and preferences, capped at ±20: personalization *tunes* the
//     universal number rather than replacing it, so a food that's bad for
//     everyone can still be a little better or worse for *you* (e.g. a
//     zero-calorie soda nudges up for weight loss). Conflicting dietary
//     restrictions hard-cap it to ≤20 and raise a warning banner.
//
// Missing nutrient inputs are excluded from both numerator and denominator —
// never treated as zero (healthy) or full credit.
//
// The same adjustment list drives the rule-based deltaReason placeholder and
// the signed "+/-" factors sent to the backend /explain prompt, so the LLM can
// never cite a factor the score didn't actually use.

enum ScoringEngine {

    static let floorScore = 10
    static let restrictionCap = 20
    static let maxAdjustment = 20.0

    // MARK: Public API

    /// Returns a copy of `product` with both scores, bonuses, restrictions, and
    /// deltaReason filled in for the given profile.
    static func score(_ product: Product, for profile: UserProfile) -> Product {
        var out = product
        let b = Blocks(product)
        out.overallScore = overall(b)
        let r = computePersonal(product, profile: profile, blocks: b, overall: out.overallScore)
        out.yourScore = r.score
        out.bonuses = r.bonuses
        out.restrictions = r.restrictions
        out.deltaReason = r.reason
        return out
    }

    /// Overall (Score 1) — goal-neutral.
    static func computeOverall(_ p: Product) -> Int {
        overall(Blocks(p))
    }

    /// Short signed drivers for the backend `/explain` prompt: "+ " prefixes
    /// what speaks for the product (for this user), "- " what speaks against
    /// it. Personal goal/preference adjustments come first, then the main
    /// overall drivers (deduped), so the LLM can explain the verdict even when
    /// the personalized delta is small — but never cites a fact the score
    /// didn't use. With personalization off, only the overall drivers are
    /// sent. Expects the *scored* product: a restriction conflict (hard-cap)
    /// is always the lead factor.
    static func signedFactors(_ product: Product, profile: UserProfile) -> [String] {
        let b = Blocks(product)
        let adjs = profile.personalizeScoring
            ? adjustments(b, objective: profile.objective, preferences: profile.preferences)
            : []
        var factors = merge(adjs, overallDrivers(b))
            .filter { abs($0.points) >= 1 }
            .sorted { abs($0.points) > abs($1.points) }
            .prefix(4)
            .map { ($0.points > 0 ? "+ " : "- ") + $0.label }
        if let r = product.restrictions.first {
            factors.insert("- conflicts with your \(r.type) restriction (\(r.trigger))", at: 0)
        }
        return factors
    }

    // MARK: Building blocks (each normalized 0–1; nil = unknown, excluded)

    private struct Blocks {
        let protDensScore: Double?   // protein per 100 kcal
        let absProteinScore: Double? // absolute protein per 100g
        let lowEnergy: Double?       // calorie lightness
        let fiberScore: Double?
        let fvnScore: Double?        // fruit/veg/nuts fraction
        let sugarPen: Double?        // fvn discounts fruit/veg sugar
        let satPen: Double?
        let sodiumPen: Double?
        let procPen: Double?         // NOVA processing; nil when nova unknown
        let upfPen: Double?          // ultra-processed share; nil when nova unknown
        let novaKnown: Bool
        let additivesPen: Double?    // risk-weighted additive load
        let transPen: Double         // 1 when trans fats present

        init(_ p: Product) {
            let n = p.nutrients

            // Guard: near-zero energy (water, diet soda) — no protein density, treat as light.
            if let kcal = n.kcal, kcal < 5 {
                protDensScore = 0
                lowEnergy = 1
            } else if let kcal = n.kcal, kcal > 0, let protein = n.protein_g {
                let protDens = protein / (kcal / 100)
                protDensScore = min(1, protDens / 15)
                lowEnergy = max(0, min(1, (500 - kcal) / 450))
            } else if let kcal = n.kcal, kcal > 0 {
                protDensScore = nil
                lowEnergy = max(0, min(1, (500 - kcal) / 450))
            } else {
                protDensScore = nil
                lowEnergy = nil
            }

            absProteinScore = n.protein_g.map { min(1, $0 / 25) }
            fiberScore = n.fiber_g.map { min(1, $0 / 8) }
            fvnScore = n.fvn.map { min(1, $0 / 100) }
            if let sugar = n.sugar_g {
                let fvn = n.fvn ?? 0
                sugarPen = min(1, sugar * (1 - fvn / 100) / 25)
            } else {
                sugarPen = nil
            }
            satPen = n.satFat_g.map { min(1, $0 / 10) }
            sodiumPen = n.sodium_mg.map { max(0, min(1, ($0 - 100) / 700)) }
            novaKnown = (1...4).contains(p.novaGroup)
            if novaKnown {
                let proc = Self.procPen(p.novaGroup)
                procPen = proc
                upfPen = max(0, (proc - 0.5) / 0.5)
            } else {
                procPen = nil
                upfPen = nil
            }

            if p.additiveIngredientTextMissing != true && p.hasIngredientData {
                let riskLoad = p.additives.reduce(0.0) { acc, a in
                    if let tier = a.tier {
                        return acc + AdditiveCatalog.penaltyWeight(for: tier)
                    }
                    switch a.risk {
                    case .high:     return acc + 1.5
                    case .moderate: return acc + 0.75
                    case .low, .unrated: return acc + 0.25
                    }
                }
                additivesPen = min(1, riskLoad / 5)
            } else {
                additivesPen = nil
            }
            transPen = p.transFats ? 1 : 0
        }

        private static func procPen(_ nova: Int) -> Double {
            switch nova {
            case 1:  return 0.0
            case 2:  return 0.2
            case 3:  return 0.5
            case 4:  return 1.0
            default: return 0.5
            }
        }
    }

    // MARK: Overall (Score 1) — 50 ± points (unknown terms omitted, not zeroed)

    private static func overall(_ b: Blocks) -> Int {
        var quality = 0.0
        if let v = b.protDensScore { quality += 14 * v }
        if let v = b.fiberScore { quality += 12 * v }
        if let v = b.fvnScore { quality += 14 * v }
        if b.novaKnown, let proc = b.procPen {
            quality += 10 * (1 - proc)
        }

        var penalty = 0.0
        if let v = b.sugarPen { penalty += 12 * v }
        if let v = b.satPen { penalty += 8 * v }
        if let v = b.sodiumPen { penalty += 8 * v }
        if b.novaKnown, let upf = b.upfPen { penalty += 6 * upf }
        if let v = b.additivesPen { penalty += 4 * v }
        penalty += 6 * b.transPen

        return clampScore(50 + quality - penalty)
    }

    // MARK: Personalization adjustments (the only goal/preference-dependent part)

    /// What a factor is about — used to dedupe personal adjustments against
    /// overall drivers when building the /explain factor list.
    private enum FactorKey {
        case protein, absProtein, energy, fiber, fvn, processing,
             sugar, satFat, sodium, additives, transFat
    }

    /// One signed nudge with a human-readable label, used for Your Score, the
    /// deltaReason placeholder, and the /explain factors.
    private struct Adjustment {
        let key: FactorKey
        let points: Double
        let label: String
    }

    private static func adjustments(_ b: Blocks, objective: String,
                                    preferences: [String]) -> [Adjustment] {
        var out: [Adjustment] = []
        func add(_ key: FactorKey, _ points: Double, _ label: String) {
            guard abs(points) >= 0.5 else { return }   // drop noise
            out.append(Adjustment(key: key, points: points, label: label))
        }

        switch objective.lowercased() {
        case "build muscle":
            if let dens = b.protDensScore {
                let pts = 12 * (dens - 0.35)
                add(.protein, pts, pts > 0 ? "high protein per calorie"
                                           : "low protein per calorie for a muscle goal")
            }
            if let abs = b.absProteinScore {
                add(.absProtein, 4 * abs, "protein-rich per 100g")
            }
            if let sp = b.sugarPen {
                add(.sugar, -4 * sp, "high sugar")
            }

        case "lose weight":
            if let low = b.lowEnergy, let sp = b.sugarPen {
                let sugarGate = max(0, 1 - 2 * sp)
                let energy = 10 * (low * sugarGate - 0.3)
                add(.energy, energy, energy > 0 ? "low calorie density" : "calorie-dense")
            }
            if let dens = b.protDensScore {
                add(.protein, 5 * dens, "protein that keeps you full")
            }
            if let fiber = b.fiberScore {
                add(.fiber, 4 * fiber, "filling fiber")
            }
            if let sp = b.sugarPen {
                add(.sugar, -8 * sp, "high sugar")
            }

        case "eat healthier":
            if let fvn = b.fvnScore {
                add(.fvn, 8 * fvn, "mostly whole fruits, vegetables, or nuts")
            }
            if let fiber = b.fiberScore {
                add(.fiber, 5 * fiber, "high fiber")
            }
            if b.novaKnown, let procPen = b.procPen, let upfPen = b.upfPen {
                let proc = 5 * ((1 - procPen) - upfPen)
                add(.processing, proc, processingLabel(b))
            }
            if let ap = b.additivesPen {
                add(.additives, -4 * ap, "contains riskier additives")
            }

        default: // maintain — goal-neutral, only preferences below apply
            break
        }

        // Preference nudges (smaller than goal drivers, all objectives).
        // "Organic" has no reliable signal in the data, so it never adjusts.
        let prefs = Set(preferences.map { $0.lowercased() })
        if prefs.contains("low sugar"), let sp = b.sugarPen {
            add(.sugar, -4 * sp, "high sugar (you prefer low sugar)")
        }
        if prefs.contains("low sodium"), let sp = b.sodiumPen {
            add(.sodium, -4 * sp, "high sodium (you prefer low sodium)")
        }
        if prefs.contains("low fat"), let sp = b.satPen {
            add(.satFat, -4 * sp, "high saturated fat (you prefer low fat)")
        }
        if prefs.contains("high protein"), let dens = b.protDensScore {
            add(.protein, 4 * dens, "protein-dense (your high-protein preference)")
        }
        if prefs.contains("high fiber"), let fiber = b.fiberScore {
            add(.fiber, 4 * fiber, "fiber-rich (your high-fiber preference)")
        }
        if prefs.contains("minimally processed"), b.novaKnown,
           let procPen = b.procPen, let upfPen = b.upfPen {
            let proc = 3 * ((1 - procPen) - upfPen)
            add(.processing, proc, proc > 0 ? processingLabel(b)
                                            : "ultra-processed (you prefer whole foods)")
        }
        return out
    }

    /// The main goal-neutral score drivers, labeled for the /explain prompt.
    /// Points mirror the overall formula's weights so sorting by magnitude
    /// surfaces what actually moved the number.
    private static func overallDrivers(_ b: Blocks) -> [Adjustment] {
        var out: [Adjustment] = []
        func add(_ key: FactorKey, _ points: Double, _ label: String) {
            guard abs(points) >= 0.5 else { return }
            out.append(Adjustment(key: key, points: points, label: label))
        }
        if let dens = b.protDensScore {
            add(.protein, 14 * dens, "high protein per calorie")
        }
        if let fiber = b.fiberScore {
            add(.fiber, 12 * fiber, "high fiber")
        }
        if let fvn = b.fvnScore {
            add(.fvn, 14 * fvn, "mostly whole fruits, vegetables, or nuts")
        }
        if b.novaKnown, let procPen = b.procPen, let upfPen = b.upfPen {
            add(.processing, 10 * (1 - procPen) - 6 * upfPen, processingLabel(b))
        }
        if let sp = b.sugarPen {
            add(.sugar, -12 * sp, "high sugar")
        }
        if let sat = b.satPen {
            add(.satFat, -8 * sat, "high saturated fat")
        }
        if let sod = b.sodiumPen {
            add(.sodium, -8 * sod, "high sodium")
        }
        if let ap = b.additivesPen {
            add(.additives, -4 * ap, "contains riskier additives")
        }
        if b.transPen > 0 {
            add(.transFat, -6 * b.transPen, "contains trans fats")
        }
        return out
    }

    /// Personal adjustments win over overall drivers on the same topic.
    private static func merge(_ adjustments: [Adjustment],
                              _ drivers: [Adjustment]) -> [Adjustment] {
        let covered = Set(adjustments.map(\.key))
        return adjustments + drivers.filter { !covered.contains($0.key) }
    }

    // "NOVA" never reaches users (US/UK audiences don't know the term) —
    // the signal is described plainly. Decision 2026-07-11.
    private static func processingLabel(_ b: Blocks) -> String {
        guard let proc = b.procPen else { return "processing unknown" }
        if proc <= 0.2 { return "minimally processed" }
        if proc < 1 { return "moderately processed" }
        return "ultra-processed"
    }

    // MARK: Personalized (Your Score)

    struct PersonalResult {
        let score: Int
        let bonuses: [String]
        let restrictions: [Restriction]
        let reason: DeltaReason?
    }

    private static func computePersonal(_ product: Product, profile: UserProfile,
                                        blocks b: Blocks, overall: Int) -> PersonalResult {
        let bonuses = nutrientBonuses(product.nutrients)

        // Restriction conflicts (gated by the auto-flag toggle).
        var restrictions: [Restriction] = []
        if profile.autoFlagRestrictions {
            for r in profile.restrictions {
                if let hit = evalRestriction(r, product: product) {
                    restrictions.append(Restriction(type: hit.type, trigger: hit.trigger))
                }
            }
        }

        // Personalization off → Your Score mirrors the goal-neutral Overall.
        guard profile.personalizeScoring else {
            return PersonalResult(score: overall, bonuses: bonuses,
                                  restrictions: restrictions, reason: nil)
        }

        let adjs = adjustments(b, objective: profile.objective,
                               preferences: profile.preferences)
        let delta = max(-maxAdjustment, min(maxAdjustment,
                                            adjs.reduce(0) { $0 + $1.points }))
        var your = clampScore(Double(overall) + delta)

        let hardCapped = !restrictions.isEmpty
        if hardCapped { your = min(your, restrictionCap) }

        let reason = deltaReason(adjustments: adjs, drivers: overallDrivers(b),
                                 your: your, overall: overall,
                                 restriction: restrictions.first, hardCapped: hardCapped)

        return PersonalResult(score: your, bonuses: bonuses,
                              restrictions: restrictions, reason: reason)
    }

    private static func nutrientBonuses(_ n: Nutrients) -> [String] {
        var b: [String] = []
        if let f = n.fiber_g, f >= 6 { b.append("fiber") }
        if let p = n.protein_g, p >= 12 { b.append("protein") }
        if let c = n.calcium_mg, c >= 120 { b.append("calcium") }
        return b
    }

    // MARK: Restriction evaluation

    private static func evalRestriction(_ name: String, product p: Product) -> (type: String, trigger: String)? {
        let flags = Set(p.dietFlags ?? [])
        let n = p.nutrients
        switch name.lowercased() {
        case "vegan":
            return flags.contains("non-vegan") ? ("vegan", "animal-derived ingredients") : nil
        case "vegetarian":
            return flags.contains("non-vegetarian") ? ("vegetarian", "meat or fish") : nil
        case "low-sugar diet":
            if let s = n.sugar_g, s > 12.5 { return ("low-sugar diet", "high sugar") }
            return nil
        case "low-sodium diet":
            if let s = n.sodium_mg, s > 400 { return ("low-sodium diet", "high sodium") }
            return nil
        case "gluten-free":
            return flags.contains("gluten") ? ("gluten-free", "gluten") : nil
        case "dairy-free":
            return flags.contains("milk") ? ("dairy-free", "milk") : nil
        default:
            return nil   // pescatarian and others: no reliable signal yet
        }
    }

    // MARK: deltaReason (rule-based placeholder; the LLM sentence replaces it)

    private static func deltaReason(adjustments: [Adjustment], drivers: [Adjustment],
                                    your: Int, overall: Int,
                                    restriction: Restriction?, hardCapped: Bool) -> DeltaReason? {
        if hardCapped, let r = restriction {
            return DeltaReason(tone: .negative,
                               text: "Capped — contains \(r.trigger), which conflicts with your \(r.type) restriction.")
        }
        let delta = your - overall

        // Meaningful delta: lead with the strongest same-signed adjustment.
        if abs(delta) >= 5,
           let top = adjustments
               .filter({ delta > 0 ? $0.points > 0 : $0.points < 0 })
               .max(by: { abs($0.points) < abs($1.points) }) {
            let text = delta > 0 ? "Scores higher for you — \(top.label)."
                                 : "Scores lower for you — \(top.label)."
            return DeltaReason(tone: delta > 0 ? .positive : .negative, text: text)
        }

        // Small delta: still explain the verdict, led by the strongest factor
        // overall. (The LLM sentence replaces this once /explain returns.)
        guard let top = merge(adjustments, drivers)
            .max(by: { abs($0.points) < abs($1.points) })
        else { return nil }
        let positive = top.points > 0
        let text = positive ? "For your goal it's much like for everyone — the main plus: \(top.label)."
                            : "For your goal it's much like for everyone — mainly held back by \(top.label)."
        return DeltaReason(tone: positive ? .positive : .negative, text: text)
    }

    // MARK: Helpers

    private static func clampScore(_ v: Double) -> Int {
        Int(max(Double(floorScore), min(100, v)).rounded())
    }
}

// MARK: - Debug score breakdown (DEBUG builds only)

#if DEBUG
extension ScoringEngine {

    struct DebugBreakdown {
        let text: String
    }

    /// Full v3 score audit trail: inputs, normalized blocks, weighted terms,
    /// overall math, and personalization steps.
    static func debugBreakdown(_ product: Product, for profile: UserProfile) -> DebugBreakdown {
        let b = Blocks(product)
        let n = product.nutrients
        var lines: [String] = []

        func num(_ label: String, _ v: Double?) {
            lines.append("  \(label): \(v.map { String(format: "%.2f", $0) } ?? "—")")
        }
        func block(_ label: String, _ v: Double?) {
            lines.append("  \(label): \(v.map { String(format: "%.3f", $0) } ?? "— excluded")")
        }
        func term(_ label: String, weight: Double, value: Double, sign: String = "+") {
            let pts = weight * value
            lines.append("  \(sign) \(label): \(String(format: "%.0f", weight)) × \(String(format: "%.3f", value)) = \(sign)\(String(format: "%.2f", pts))")
        }
        func skip(_ label: String, weight: Double) {
            lines.append("  · \(label): weight \(String(format: "%.0f", weight)) — skipped (no data)")
        }

        lines.append("SCORING DEBUG — v3 anchored modifier")
        lines.append("Product: \(product.name) (\(product.id))")
        lines.append("")

        lines.append("INPUTS (per 100g)")
        num("kcal", n.kcal)
        num("protein_g", n.protein_g)
        num("fiber_g", n.fiber_g)
        num("sugar_g", n.sugar_g)
        num("satFat_g", n.satFat_g)
        num("sodium_mg", n.sodium_mg)
        num("fvn", n.fvn)
        lines.append("  nova_group: \(product.novaGroup)\(b.novaKnown ? "" : " (unknown — processing excluded)")")
        lines.append("  transFats: \(product.transFats)")
        lines.append("  hasMinimumData: \(product.hasMinimumData)")
        lines.append("  hasNutritionData: \(product.hasNutritionData)")
        lines.append("  hasScoreableIngredientSignal: \(product.hasScoreableIngredientSignal)")
        lines.append("  hasIngredientData: \(product.hasIngredientData)")
        lines.append("  additiveIngredientTextMissing: \(product.additiveIngredientTextMissing ?? false)")
        if product.additives.isEmpty {
            lines.append("  additives: none")
        } else {
            lines.append("  additives (\(product.additives.count)):")
            for a in product.additives {
                let tier = a.tier.map { String(describing: $0) } ?? "—"
                let wt = a.tier.map { AdditiveCatalog.penaltyWeight(for: $0) }
                let wtStr = wt.map { String(format: "%.2f", $0) } ?? "—"
                lines.append("    · \(a.code ?? "?") \(a.name) tier=\(tier) wt=\(wtStr)")
            }
        }
        lines.append("")

        lines.append("NORMALIZED BLOCKS (0–1)")
        block("protDensScore", b.protDensScore)
        block("absProteinScore", b.absProteinScore)
        block("lowEnergy", b.lowEnergy)
        block("fiberScore", b.fiberScore)
        block("fvnScore", b.fvnScore)
        block("sugarPen", b.sugarPen)
        block("satPen", b.satPen)
        block("sodiumPen", b.sodiumPen)
        if let proc = b.procPen {
            lines.append("  procPen: \(String(format: "%.3f", proc))")
        } else {
            lines.append("  procPen: — excluded")
        }
        if let upf = b.upfPen {
            lines.append("  upfPen: \(String(format: "%.3f", upf))")
        } else {
            lines.append("  upfPen: — excluded")
        }
        block("additivesPen", b.additivesPen)
        lines.append("  transPen: \(String(format: "%.3f", b.transPen))")
        lines.append("")

        lines.append("OVERALL — quality (base 50)")
        var quality = 0.0
        if let v = b.protDensScore {
            term("protein density", weight: 14, value: v)
            quality += 14 * v
        } else { skip("protein density", weight: 14) }
        if let v = b.fiberScore {
            term("fiber", weight: 12, value: v)
            quality += 12 * v
        } else { skip("fiber", weight: 12) }
        if let v = b.fvnScore {
            term("fruit/veg/nuts", weight: 14, value: v)
            quality += 14 * v
        } else { skip("fruit/veg/nuts", weight: 14) }
        if b.novaKnown, let proc = b.procPen {
            let procQuality = 1 - proc
            term("low processing", weight: 10, value: procQuality)
            quality += 10 * procQuality
        } else {
            skip("low processing", weight: 10)
        }
        lines.append("  ⇒ quality subtotal: +\(String(format: "%.2f", quality))")
        lines.append("")

        lines.append("OVERALL — penalties")
        var penalty = 0.0
        if let v = b.sugarPen {
            term("sugar", weight: 12, value: v, sign: "−")
            penalty += 12 * v
        } else { skip("sugar", weight: 12) }
        if let v = b.satPen {
            term("saturated fat", weight: 8, value: v, sign: "−")
            penalty += 8 * v
        } else { skip("saturated fat", weight: 8) }
        if let v = b.sodiumPen {
            term("sodium", weight: 8, value: v, sign: "−")
            penalty += 8 * v
        } else { skip("sodium", weight: 8) }
        if b.novaKnown, let upf = b.upfPen {
            term("ultra-processing", weight: 6, value: upf, sign: "−")
            penalty += 6 * upf
        } else {
            skip("ultra-processing", weight: 6)
        }
        if let v = b.additivesPen {
            term("additives", weight: 4, value: v, sign: "−")
            penalty += 4 * v
        } else { skip("additives", weight: 4) }
        if b.transPen > 0 {
            term("trans fats", weight: 6, value: b.transPen, sign: "−")
        } else {
            lines.append("  − trans fats: 6 × 0.000 = −0.00")
        }
        penalty += 6 * b.transPen
        lines.append("  ⇒ penalty subtotal: −\(String(format: "%.2f", penalty))")
        lines.append("")

        let rawOverall = 50 + quality - penalty
        let overall = clampScore(rawOverall)
        lines.append("OVERALL SCORE")
        lines.append("  50 + \(String(format: "%.2f", quality)) − \(String(format: "%.2f", penalty)) = \(String(format: "%.2f", rawOverall))")
        lines.append("  clamped [\(floorScore)…100] → \(overall)")
        lines.append("  stored overallScore: \(product.overallScore)")
        lines.append("")

        lines.append("YOUR SCORE — profile")
        lines.append("  objective: \(profile.objective)")
        lines.append("  preferences: \(profile.preferences.isEmpty ? "none" : profile.preferences.joined(separator: ", "))")
        lines.append("  personalizeScoring: \(profile.personalizeScoring)")
        lines.append("  autoFlagRestrictions: \(profile.autoFlagRestrictions)")
        lines.append("  restrictions: \(profile.restrictions.isEmpty ? "none" : profile.restrictions.joined(separator: ", "))")
        lines.append("")

        let restrictions: [Restriction] = {
            guard profile.autoFlagRestrictions else { return [] }
            return profile.restrictions.compactMap { r in
                guard let hit = evalRestriction(r, product: product) else { return nil }
                return Restriction(type: hit.type, trigger: hit.trigger)
            }
        }()

        if !profile.personalizeScoring {
            lines.append("  personalization OFF → yourScore = overall (\(overall))")
        } else {
            let adjs = adjustments(b, objective: profile.objective,
                                   preferences: profile.preferences)
            lines.append("PERSONAL ADJUSTMENTS (cap ±\(Int(maxAdjustment)))")
            if adjs.isEmpty {
                lines.append("  (none above noise threshold)")
            } else {
                for a in adjs {
                    let sign = a.points >= 0 ? "+" : ""
                    lines.append("  \(sign)\(String(format: "%.2f", a.points)) — \(a.label)")
                }
            }
            let rawDelta = adjs.reduce(0) { $0 + $1.points }
            let delta = max(-maxAdjustment, min(maxAdjustment, rawDelta))
            if abs(rawDelta - delta) > 0.01 {
                lines.append("  raw delta \(String(format: "%.2f", rawDelta)) → capped \(String(format: "%.2f", delta))")
            } else {
                lines.append("  delta: \(String(format: "%+.2f", delta))")
            }
            var your = clampScore(Double(overall) + delta)
            lines.append("  \(overall) \(String(format: "%+.2f", delta)) = \(String(format: "%.2f", Double(overall) + delta)) → clamped \(your)")
            if !restrictions.isEmpty {
                let capped = min(your, restrictionCap)
                lines.append("  restriction hard-cap ≤\(restrictionCap): \(your) → \(capped)")
                your = capped
            }
            lines.append("  stored yourScore: \(product.yourScore) (computed \(your))")
        }

        if !restrictions.isEmpty && profile.personalizeScoring {
            // already handled above
        } else if !restrictions.isEmpty {
            lines.append("  active restrictions: \(restrictions.map { "\($0.type) (\($0.trigger))" }.joined(separator: ", "))")
        }

        return DebugBreakdown(text: lines.joined(separator: "\n"))
    }
}
#endif
