import Foundation

// MARK: - Domain models

enum RiskLevel: String { case low, moderate, high }

struct Additive: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let risk: RiskLevel
}

struct Restriction: Identifiable, Hashable {
    let id = UUID()
    let type: String
    let trigger: String
}

struct Nutrients: Hashable {
    var sugar_g: Double?
    var sodium_mg: Double?
    var satFat_g: Double?
    var fiber_g: Double?
    var protein_g: Double?
    var calcium_mg: Double?
}

struct DeltaReason: Hashable {
    enum Tone { case positive, negative }
    let tone: Tone
    let text: String
}

struct Product: Identifiable, Hashable {
    let id: String
    let name: String
    let brand: String
    let size: String
    let glyph: String
    let overallScore: Int
    let yourScore: Int
    let deltaReason: DeltaReason?
    let nutriGrade: String
    let novaGroup: Int
    let nutrients: Nutrients
    let bonuses: [String]
    let transFats: Bool
    let caffeine_mg: Double?
    let sweeteners: [String]
    let seedOils: Bool
    let additives: [Additive]
    let restrictions: [Restriction]
}

struct HistoryEntry: Identifiable, Hashable {
    let id = UUID()
    let productId: String
    let when: String
    let dateLabel: String

    var day: String { dateLabel.components(separatedBy: " · ").first ?? "" }
    var time: String { dateLabel.components(separatedBy: " · ").last ?? "" }
}

struct UserProfile {
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
