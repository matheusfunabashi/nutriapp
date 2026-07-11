import Foundation

// MARK: - Domain models

enum RiskLevel: String, Codable { case low, moderate, high, unrated }

struct Additive: Identifiable, Hashable, Codable {
    var id = UUID()
    let name: String
    let risk: RiskLevel
    /// Short justification, shown for higher-risk additives. nil when not applicable.
    var note: String? = nil
    /// Normalized E-number ("e150d") — scoring v4 looks tiers up by code.
    /// Optional for back-compat with snapshots saved before Phase B.
    var code: String? = nil
}

struct Restriction: Identifiable, Hashable, Codable {
    var id = UUID()
    let type: String
    let trigger: String
}

struct Nutrients: Hashable, Codable {
    var sugar_g: Double?
    var sodium_mg: Double?
    var satFat_g: Double?
    var fiber_g: Double?
    var protein_g: Double?
    var calcium_mg: Double?
    /// Energy in kcal per 100g (drives protein-density + calorie features in scoring v2).
    var kcal: Double? = nil
    /// Fruit/veg/nuts estimate 0–100 from ingredients (Nutri-Score field); discounts
    /// natural fruit/veg sugar and rewards whole-food content. Optional for back-compat.
    var fvn: Double? = nil
    /// Added sugars per 100g — mostly US labels; scoring v4's S3 prefers it and
    /// falls back to fvn-discounted total sugars. Optional for back-compat.
    var addedSugar_g: Double? = nil
}

/// One parsed ingredient with its declared or estimated recipe share.
/// Drives the v4 hero-ingredient rule (S10 — "the 2% almond problem").
struct IngredientShare: Hashable, Codable {
    /// Normalized OFF id without the language prefix, e.g. "oats".
    let name: String
    /// Declared on the pack (high trust).
    let percent: Double?
    /// OFF's heuristic estimate (v4 rules trust it at 75%).
    let percentEstimate: Double?
}

struct DeltaReason: Hashable, Codable {
    enum Tone: String, Codable { case positive, negative }
    let tone: Tone
    let text: String
}

struct Product: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let brand: String
    let size: String
    let glyph: String
    // Scores and their explanations are filled in by the ScoringEngine, so they're mutable.
    var overallScore: Int
    var yourScore: Int
    var deltaReason: DeltaReason?
    let nutriGrade: String
    let novaGroup: Int
    let nutrients: Nutrients
    var bonuses: [String]
    let transFats: Bool
    let caffeine_mg: Double?
    let sweeteners: [String]
    let seedOils: Bool
    let additives: [Additive]
    var restrictions: [Restriction]
    /// Normalized dietary signals from Open Food Facts (e.g. "non-vegan", "gluten",
    /// "milk"), used by the ScoringEngine to flag profile restrictions. Optional for
    /// backward-compatible decoding of older snapshots.
    var dietFlags: [String]? = nil
    /// Normalized Open Food Facts allergen tags (e.g. "milk", "peanuts"), used for
    /// deterministic allergen matching. Optional for backward-compatible decoding.
    var allergenTags: [String]? = nil
    /// Raw ingredient text from Open Food Facts, used as a fallback for allergen
    /// keyword matching. Optional for backward-compatible decoding.
    var ingredientsText: String? = nil
    /// Product photo URL (OFF front image, or Go-UPC via the backend fallback).
    /// nil = no image, a first-class state rendered as the glyph placeholder.
    /// Optional for backward-compatible decoding of older snapshots.
    var imageURL: String? = nil

    // MARK: Scoring-v4 data foundation (SCORING_V4.md §2) — all optional so
    // snapshots saved before Phase A keep decoding.

    /// Normalized label/certification tags (e.g. "organic", "fair-trade").
    /// Tier-1 signals: absence means "not claimed", never "unknown".
    var labels: [String]? = nil
    /// Normalized packaging materials (e.g. "glass", "pet", "aluminium").
    var packagingMaterials: [String]? = nil
    /// Normalized origin tags (e.g. "united-kingdom").
    var origins: [String]? = nil
    /// Parsed ingredients with recipe shares (S10 hero-ingredient rule).
    var ingredientShares: [IngredientShare]? = nil
    /// Environmental grade "a"–"e" (Eco-Score); nil when unknown/not applicable.
    var ecoGrade: String? = nil
    /// Raw serving size text (free-form; per-100g stays primary in scoring).
    var servingSize: String? = nil
    /// OFF's own 0–1 completeness estimate for this record.
    var completeness: Double? = nil
    /// When the OFF record last changed (staleness display: "updated X ago").
    var lastModified: Date? = nil
    /// Markets the product is sold in (sibling-inheritance guard, v4.1).
    var countries: [String]? = nil
    /// Normalized category tags (e.g. "beverages", "salty-snacks") — drives
    /// the v4 category router. Optional for back-compat.
    var categories: [String]? = nil
}

// MARK: - Data confidence (SCORING_V4.md §3.2–3.3)

enum DataConfidence: String, Codable {
    case high, medium, low
}

extension Product {
    var hasIngredientData: Bool {
        (ingredientsText?.isEmpty == false) || !(ingredientShares ?? []).isEmpty
    }

    var hasNutritionData: Bool {
        let n = nutrients
        return [n.kcal, n.sugar_g, n.satFat_g, n.sodium_mg, n.protein_g, n.fiber_g]
            .contains { $0 != nil }
    }

    /// Minimum data requirement: never score a product that has neither an
    /// ingredient list nor a nutrition table — show the insufficient-data
    /// state instead.
    var hasMinimumData: Bool { hasIngredientData || hasNutritionData }

    /// Provisional Phase-A confidence: a presence checklist over the signals
    /// scoring uses. Phase B replaces this with the rule-weight-backed version
    /// once the v4 engine lands; thresholds (0.8 / 0.5) already match the spec.
    var dataConfidenceScore: Double {
        let n = nutrients
        let core: [Double?] = [n.kcal, n.sugar_g, n.satFat_g, n.sodium_mg, n.protein_g, n.fiber_g]
        let nutritionFraction = Double(core.filter { $0 != nil }.count) / Double(core.count)

        var score = 0.0
        if hasIngredientData { score += 0.30 }
        score += 0.30 * nutritionFraction
        if (1...4).contains(novaGroup) { score += 0.15 }
        if !(packagingMaterials ?? []).isEmpty { score += 0.15 }
        if let g = ecoGrade, ("a"..."e").contains(g) { score += 0.05 }
        if !(origins ?? []).isEmpty { score += 0.05 }
        return score
    }

    var dataConfidence: DataConfidence {
        let s = dataConfidenceScore
        if s >= 0.8 { return .high }
        if s >= 0.5 { return .medium }
        return .low
    }
}

struct HistoryEntry: Identifiable, Hashable {
    let id = UUID()
    let productId: String
    let when: String
    let dateLabel: String

    var day: String { dateLabel.components(separatedBy: " · ").first ?? "" }
    var time: String { dateLabel.components(separatedBy: " · ").last ?? "" }
}

struct UserProfile: Codable {
    var name: String
    var handle: String
    var age: Int
    var sex: String
    var dob: String
    var heightIn: Int
    var weightLb: Int
    var goalWeightLb: Int
    var dailyStepGoal: Int
    var objective: String
    var restrictions: [String]
    var preferences: [String]
    /// Optional for backward-compatible decoding of profiles saved before allergens existed.
    var allergies: [String]? = nil
    var unitSystem: String
    var subscriptionStatus: String
    var subscriptionDaysLeft: Int
    var goalsCalories: Int
    var goalsProtein: Int
    var goalsCarbs: Int
    var goalsFat: Int
    var appearance: String
    var badgeCelebrations: Bool
    var liveActivity: Bool
    var autoFlagRestrictions: Bool
    var saveScansToHistory: Bool
    var personalizeScoring: Bool
    var appleHealth: Bool
}
