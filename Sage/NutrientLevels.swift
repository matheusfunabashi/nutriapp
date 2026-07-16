import Foundation

/// Single source of truth for the LOW / MOD / HIGH nutrient badges
/// (per 100g/ml). The Breakdown badges, the scoring factor labels, and the
/// levels sent to the LLM all read from here — so the UI and the AI advice
/// can never disagree about what "high sugar" means.
enum NutrientLevel: String {
    case low, moderate, high

    /// The word used in factor labels and the /explain prompt.
    var word: String { self == .moderate ? "moderate" : rawValue }
}

enum NutrientLevels {
    // (t1, t2): ≤ t1 low · ≤ t2 moderate · above high — identical to the
    // badge thresholds the Breakdown card has always displayed.
    static func sugar(_ g: Double) -> NutrientLevel { level(g, 5, 12.5) }
    static func sodium(_ mg: Double) -> NutrientLevel { level(mg, 120, 400) }
    static func satFat(_ g: Double) -> NutrientLevel { level(g, 1.5, 5) }
    static func fiber(_ g: Double) -> NutrientLevel { level(g, 3, 6) }
    static func protein(_ g: Double) -> NutrientLevel { level(g, 5, 12) }
    static func calcium(_ mg: Double) -> NutrientLevel { level(mg, 60, 120) }
    // Beneficial micronutrients (per 100g). MOD ≈ 10% DV, HIGH ≈ 25% DV —
    // the "good source" / "excellent source" convention.
    static func iron(_ mg: Double) -> NutrientLevel { level(mg, 2, 4.5) }
    static func potassium(_ mg: Double) -> NutrientLevel { level(mg, 300, 700) }

    private static func level(_ v: Double, _ t1: Double, _ t2: Double) -> NutrientLevel {
        if v <= t1 { return .low }
        if v <= t2 { return .moderate }
        return .high
    }

    /// Ground-truth lines for the /explain prompt, e.g. "sugar: high (14g)".
    /// The backend instructs the model to never contradict these — the badge
    /// the user sees and the sentence they read must agree.
    static func promptLines(_ n: Nutrients) -> [String] {
        var lines: [String] = []
        if let v = n.sugar_g { lines.append("sugar: \(sugar(v).word) (\(fmtNum(v))g)") }
        if let v = n.sodium_mg { lines.append("sodium: \(sodium(v).word) (\(fmtNum(v))mg)") }
        if let v = n.satFat_g { lines.append("saturated fat: \(satFat(v).word) (\(fmtNum(v))g)") }
        if let v = n.fiber_g { lines.append("fiber: \(fiber(v).word) (\(fmtNum(v))g)") }
        if let v = n.protein_g { lines.append("protein: \(protein(v).word) (\(fmtNum(v))g)") }
        if let v = n.iron_mg { lines.append("iron: \(iron(v).word) (\(fmtNum(v))mg)") }
        if let v = n.potassium_mg { lines.append("potassium: \(potassium(v).word) (\(fmtNum(v))mg)") }
        return lines
    }

    private static func fmtNum(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}
