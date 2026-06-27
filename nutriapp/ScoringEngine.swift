import Foundation

// MARK: - Scoring engine (v2 — composite model)
//
// Two scores, both built from the same per-100g building blocks:
//   • Overall (Score 1) — goal-neutral, the same for everyone: Q − 0.5·P.
//   • Your Score (Score 2) — Overall plus a goal-specific Driver; the ONLY place
//     the user's objective changes the number. Conflicting dietary restrictions
//     hard-cap it to ≤20 and raise a warning banner.
//
// Penalty (P) and Quality (Q) are objective-independent. The Driver (D) and its
// weights vary by goal. All deterministic; the deltaReason text is a rule-based
// placeholder that Phase 4b replaces with an LLM-generated one.

enum ScoringEngine {

    static let restrictionCap = 20

    // MARK: Public API

    /// Returns a copy of `product` with both scores, bonuses, restrictions, and
    /// deltaReason filled in for the given profile.
    static func score(_ product: Product, for profile: UserProfile) -> Product {
        var out = product
        let b = Blocks(product)
        out.overallScore = clampScore(100 * (quality(b) - 0.5 * penalty(b)))
        let r = computePersonal(product, profile: profile, blocks: b, overall: out.overallScore)
        out.yourScore = r.score
        out.bonuses = r.bonuses
        out.restrictions = r.restrictions
        out.deltaReason = r.reason
        return out
    }

    /// Overall (Score 1) — goal-neutral.
    static func computeOverall(_ p: Product) -> Int {
        let b = Blocks(p)
        return clampScore(100 * (quality(b) - 0.5 * penalty(b)))
    }

    // MARK: Building blocks (each normalized 0–1)

    private struct Blocks {
        let protDensScore: Double   // protein per 100 kcal
        let lowEnergy: Double       // calorie lightness
        let fiberScore: Double
        let fvnScore: Double        // fruit/veg/nuts fraction
        let sugarPen: Double        // fvn discounts fruit/veg sugar
        let satPen: Double
        let sodiumPen: Double
        let procPen: Double         // NOVA processing

        init(_ p: Product) {
            let n = p.nutrients
            let fvn = n.fvn ?? 0

            // Guard: near-zero energy (water, diet soda) — no protein density, treat as light.
            if let kcal = n.kcal, kcal < 5 {
                protDensScore = 0
                lowEnergy = 1
            } else if let kcal = n.kcal, kcal > 0 {
                let protDens = (n.protein_g ?? 0) / (kcal / 100)
                protDensScore = min(1, protDens / 15)
                lowEnergy = max(0, min(1, (500 - kcal) / 450))
            } else {
                // kcal missing → neutral
                protDensScore = 0
                lowEnergy = 0.5
            }

            fiberScore = min(1, (n.fiber_g ?? 0) / 8)
            fvnScore = min(1, fvn / 100)
            sugarPen = min(1, (n.sugar_g ?? 0) * (1 - fvn / 100) / 25)
            satPen = min(1, (n.satFat_g ?? 0) / 10)
            sodiumPen = max(0, min(1, ((n.sodium_mg ?? 0) - 100) / 700))
            procPen = Self.procPen(p.novaGroup)
        }

        private static func procPen(_ nova: Int) -> Double {
            switch nova {
            case 1:  return 0.0
            case 2:  return 0.2
            case 3:  return 0.5
            case 4:  return 1.0
            default: return 0.5   // unknown processing → mid penalty
            }
        }
    }

    // MARK: Composites (goal-independent)

    private static func penalty(_ b: Blocks) -> Double {
        0.35 * b.procPen + 0.25 * b.sugarPen + 0.20 * b.satPen + 0.20 * b.sodiumPen
    }

    private static func quality(_ b: Blocks) -> Double {
        0.40 * b.protDensScore + 0.35 * b.fiberScore + 0.25 * (1 - b.procPen)
    }

    // MARK: Goal driver + weights (the only goal-dependent part — Score 2 only)

    private struct GoalWeights { let wd, wq, wp: Double }

    private static func driver(_ b: Blocks, objective: String) -> Double {
        switch objective.lowercased() {
        case "build muscle":
            return b.protDensScore
        case "lose weight":
            return 0.5 * b.protDensScore + 0.3 * b.lowEnergy + 0.2 * b.fiberScore
        case "eat healthier":
            return 0.40 * b.fiberScore + 0.35 * (1 - b.procPen) + 0.25 * b.fvnScore
        default: // maintain (goal-neutral → Score 2 == Score 1)
            return quality(b)
        }
    }

    private static func weights(_ objective: String) -> GoalWeights {
        switch objective.lowercased() {
        case "build muscle":  return GoalWeights(wd: 0.55, wq: 0.45, wp: 0.45)
        case "lose weight":   return GoalWeights(wd: 0.50, wq: 0.50, wp: 0.55)
        case "eat healthier": return GoalWeights(wd: 0.50, wq: 0.50, wp: 0.60)
        default:              return GoalWeights(wd: 0.50, wq: 0.50, wp: 0.50)
        }
    }

    private static func score2(_ b: Blocks, objective: String) -> Int {
        let w = weights(objective)
        return clampScore(100 * (w.wd * driver(b, objective: objective)
                                 + w.wq * quality(b)
                                 - w.wp * penalty(b)))
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

        var your = score2(b, objective: profile.objective)

        let hardCapped = !restrictions.isEmpty
        if hardCapped { your = min(your, restrictionCap) }

        let reason = deltaReason(objective: profile.objective, blocks: b,
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

    // MARK: deltaReason (rule-based placeholder for Phase 4b)

    private static func deltaReason(objective: String, blocks b: Blocks,
                                    your: Int, overall: Int,
                                    restriction: Restriction?, hardCapped: Bool) -> DeltaReason? {
        if hardCapped, let r = restriction {
            return DeltaReason(tone: .negative,
                               text: "Capped — contains \(r.trigger), which conflicts with your \(r.type) restriction.")
        }
        let delta = your - overall
        guard abs(delta) >= 5 else { return nil }
        let positive = delta > 0

        let text: String
        switch objective.lowercased() {
        case "build muscle":
            text = positive ? "High protein per calorie supports building muscle."
                            : "Low protein per calorie for a muscle-building goal."
        case "lose weight":
            if positive {
                text = b.lowEnergy >= 0.6 ? "Light and lower in calories for weight loss."
                                          : "Protein and fiber help you stay full."
            } else {
                text = b.sugarPen >= b.satPen ? "Sugar content works against your weight-loss goal."
                                              : "Higher in fat and calories for a weight-loss goal."
            }
        case "eat healthier":
            text = positive ? "Whole, minimally processed — good for eating healthier."
                            : "Highly processed with little whole-food content."
        default: // maintain — Score 2 ≈ Score 1, rarely reached
            text = positive ? "Slightly better than its overall rating for you."
                            : "Slightly below its overall rating for you."
        }
        return DeltaReason(tone: positive ? .positive : .negative, text: text)
    }

    // MARK: Helpers

    private static func clampScore(_ v: Double) -> Int {
        Int(max(0, min(100, v)).rounded())
    }
}
