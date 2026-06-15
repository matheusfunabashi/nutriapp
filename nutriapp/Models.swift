import Foundation

// MARK: - Domain models

enum RiskLevel: String, Codable { case low, moderate, high, unrated }

struct Additive: Identifiable, Hashable, Codable {
    var id = UUID()
    let name: String
    let risk: RiskLevel
    /// Short justification, shown for higher-risk additives. nil when not applicable.
    var note: String? = nil
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
