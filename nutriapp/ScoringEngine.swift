import Foundation

// MARK: - Scoring engine
//
// Two scores:
//   • Overall  — food-only, the same for everyone. Anchored on the official
//     Nutri-Score grade, then adjusted for NOVA processing, additives, and
//     trans fats.
//   • Your Score — Overall, then personalized by the user's objective and
//     preferences (swing up to ±35). Conflicting dietary restrictions hard-cap
//     the score and raise a warning banner.
//
// Both are deterministic and rule-based. The deltaReason text generated here is
// a rule-based placeholder; Phase 4 replaces it with a Claude-generated one.

enum ScoringEngine {

    // Tunables
    static let maxPersonalSwing = 35.0
    static let restrictionCap = 20

    /// Returns a copy of `product` with overallScore, yourScore, bonuses,
    /// restrictions, and deltaReason filled in for the given profile.
    static func score(_ product: Product, for profile: UserProfile) -> Product {
        var out = product
        let overall = computeOverall(product)
        out.overallScore = overall

        let result = computePersonal(product, profile: profile, overall: overall)
        out.yourScore = result.score
        out.bonuses = result.bonuses
        out.restrictions = result.restrictions
        out.deltaReason = result.reason
        return out
    }

    // MARK: Overall (food-only)

    static func computeOverall(_ p: Product) -> Int {
        var s = Double(gradeBase(p.nutriGrade) ?? nutrientBase(p.nutrients))

        // NOVA processing level.
        switch p.novaGroup {
        case 1:  s += 5
        case 2:  s += 2
        case 3:  s -= 4
        case 4:  s -= 8
        default: break
        }

        // Trans fats — the single most penalized input.
        if p.transFats { s -= 15 }

        // Additives, weighted by risk and capped.
        let high = p.additives.filter { $0.risk == .high }.count
        let moderate = p.additives.filter { $0.risk == .moderate }.count
        s -= min(Double(high) * 6 + Double(moderate) * 2, 20)

        return clampScore(s)
    }

    /// Nutri-Score grade → anchor score.
    private static func gradeBase(_ grade: String) -> Int? {
        switch grade.uppercased() {
        case "A": return 90
        case "B": return 75
        case "C": return 58
        case "D": return 40
        case "E": return 22
        default:  return nil
        }
    }

    /// Fallback anchor from raw nutrients when no Nutri-Score is available.
    private static func nutrientBase(_ n: Nutrients) -> Int {
        var s = 60.0
        if let sugar = n.sugar_g {
            if sugar > 22.5 { s -= 15 } else if sugar > 12.5 { s -= 8 }
            else if sugar > 5 { s -= 3 } else { s += 2 }
        }
        if let sodium = n.sodium_mg {
            if sodium > 600 { s -= 12 } else if sodium > 300 { s -= 6 }
            else if sodium > 120 { s -= 2 }
        }
        if let sat = n.satFat_g {
            if sat > 5 { s -= 10 } else if sat > 1.5 { s -= 4 }
        }
        if let fiber = n.fiber_g {
            if fiber >= 6 { s += 8 } else if fiber >= 3 { s += 4 }
        }
        if let protein = n.protein_g {
            if protein >= 12 { s += 8 } else if protein >= 5 { s += 4 }
        }
        return clampScore(s)
    }

    // MARK: Personalized (Your Score)

    struct PersonalResult {
        let score: Int
        let bonuses: [String]
        let restrictions: [Restriction]
        let reason: DeltaReason?
    }

    private struct Contribution {
        let value: Double          // signed point impact
        let text: String           // human explanation
    }

    static func computePersonal(_ p: Product, profile: UserProfile, overall: Int) -> PersonalResult {
        let n = p.nutrients
        let bonuses = nutrientBonuses(n)

        // Restriction conflicts (gated by the auto-flag toggle).
        var restrictions: [Restriction] = []
        if profile.autoFlagRestrictions {
            for r in profile.restrictions {
                if let hit = evalRestriction(r, product: p) {
                    restrictions.append(Restriction(type: hit.type, trigger: hit.trigger))
                }
            }
        }

        // If personalization is off, Your Score mirrors Overall.
        guard profile.personalizeScoring else {
            return PersonalResult(score: overall, bonuses: bonuses,
                                  restrictions: restrictions, reason: nil)
        }

        // Accumulate objective + preference contributions.
        var contributions: [Contribution] = []
        contributions += objectiveContributions(profile.objective, product: p)
        contributions += preferenceContributions(profile.preferences, product: p)

        let rawDelta = contributions.reduce(0) { $0 + $1.value }
        let pDelta = max(-maxPersonalSwing, min(maxPersonalSwing, rawDelta))
        var your = clampScore(Double(overall) + pDelta)

        // Restriction hard cap.
        let hardCapped = !restrictions.isEmpty
        if hardCapped { your = min(your, restrictionCap) }

        let reason = deltaReason(your: your, overall: overall,
                                 contributions: contributions,
                                 restriction: restrictions.first,
                                 hardCapped: hardCapped)

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

    // MARK: Objective weighting

    private static func objectiveContributions(_ objective: String, product p: Product) -> [Contribution] {
        let n = p.nutrients
        var c: [Contribution] = []
        let sugar = n.sugar_g, sodium = n.sodium_mg, sat = n.satFat_g
        let fiber = n.fiber_g, protein = n.protein_g
        let highRiskAdditives = p.additives.filter { $0.risk == .high }.count

        switch objective.lowercased() {
        case "build muscle":
            if let pr = protein, pr >= 12 { c.append(.init(value: 12, text: "High protein supports your muscle-building goal")) }
            else if let pr = protein, pr < 5 { c.append(.init(value: -6, text: "Low protein for a muscle-building goal")) }
            if let f = fiber, f >= 6 { c.append(.init(value: 4, text: "Good fiber content")) }

        case "lose weight":
            if let s = sugar, s > 12.5 { c.append(.init(value: -12, text: "High sugar works against weight loss")) }
            if let st = sat, st > 5 { c.append(.init(value: -8, text: "High saturated fat for a weight-loss goal")) }
            if let pr = protein, pr >= 12 { c.append(.init(value: 8, text: "High protein helps you stay full")) }
            if let f = fiber, f >= 6 { c.append(.init(value: 6, text: "High fiber helps you stay full")) }
            if p.novaGroup == 4 { c.append(.init(value: -5, text: "Ultra-processed")) }

        case "eat healthier":
            if p.novaGroup == 1 { c.append(.init(value: 10, text: "Whole, minimally processed food")) }
            if p.novaGroup == 4 { c.append(.init(value: -12, text: "Ultra-processed")) }
            if highRiskAdditives > 0 { c.append(.init(value: -8, text: "Contains higher-risk additives")) }
            if let f = fiber, f >= 6 { c.append(.init(value: 6, text: "High fiber")) }
            if let s = sugar, s > 12.5 { c.append(.init(value: -6, text: "High sugar")) }

        case "maintain":
            if let s = sugar, s > 22.5 { c.append(.init(value: -6, text: "Very high sugar")) }
            if let sd = sodium, sd > 600 { c.append(.init(value: -5, text: "Very high sodium")) }
            if let pr = protein, pr >= 12 { c.append(.init(value: 4, text: "Good protein")) }
            if let f = fiber, f >= 6 { c.append(.init(value: 4, text: "Good fiber")) }

        default:
            break
        }
        return c
    }

    // MARK: Preference weighting

    private static func preferenceContributions(_ preferences: [String], product p: Product) -> [Contribution] {
        let n = p.nutrients
        var c: [Contribution] = []
        let prefs = Set(preferences.map { $0.lowercased() })

        if prefs.contains("high protein") {
            if let pr = n.protein_g, pr >= 12 { c.append(.init(value: 8, text: "Matches your high-protein preference")) }
            else if let pr = n.protein_g, pr < 5 { c.append(.init(value: -5, text: "Low protein vs your preference")) }
        }
        if prefs.contains("low sugar") {
            if let s = n.sugar_g, s > 12.5 { c.append(.init(value: -8, text: "High sugar vs your low-sugar preference")) }
            else if let s = n.sugar_g, s <= 5 { c.append(.init(value: 3, text: "Low sugar, as you prefer")) }
        }
        if prefs.contains("low sodium") {
            if let s = n.sodium_mg, s > 400 { c.append(.init(value: -8, text: "High sodium vs your low-sodium preference")) }
            else if let s = n.sodium_mg, s <= 120 { c.append(.init(value: 3, text: "Low sodium, as you prefer")) }
        }
        if prefs.contains("low fat") {
            if let st = n.satFat_g, st > 5 { c.append(.init(value: -7, text: "High saturated fat vs your low-fat preference")) }
            else if let st = n.satFat_g, st <= 1.5 { c.append(.init(value: 2, text: "Low saturated fat")) }
        }
        if prefs.contains("high fiber") {
            if let f = n.fiber_g, f >= 6 { c.append(.init(value: 8, text: "High fiber, as you prefer")) }
            else if let f = n.fiber_g, f < 3 { c.append(.init(value: -3, text: "Low fiber vs your preference")) }
        }
        if prefs.contains("minimally processed") {
            if p.novaGroup == 4 { c.append(.init(value: -8, text: "Ultra-processed vs your preference")) }
            else if p.novaGroup == 1 { c.append(.init(value: 6, text: "Minimally processed, as you prefer")) }
        }
        return c
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

    // MARK: deltaReason (rule-based placeholder for Phase 4)

    private static func deltaReason(your: Int, overall: Int,
                                    contributions: [Contribution],
                                    restriction: Restriction?,
                                    hardCapped: Bool) -> DeltaReason? {
        if hardCapped, let r = restriction {
            return DeltaReason(tone: .negative,
                               text: "Capped — contains \(r.trigger), which conflicts with your \(r.type) restriction.")
        }
        let delta = your - overall
        guard abs(delta) >= 5 else { return nil }

        // Surface the single biggest driver.
        guard let top = contributions.max(by: { abs($0.value) < abs($1.value) }) else { return nil }
        return DeltaReason(tone: top.value >= 0 ? .positive : .negative, text: top.text)
    }

    // MARK: Helpers

    private static func clampScore(_ v: Double) -> Int {
        Int(max(0, min(100, v)).rounded())
    }
}
