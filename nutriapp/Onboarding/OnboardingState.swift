import SwiftUI

// MARK: - Steps
//
// One enum case per screen, in display order. Driving the flow with a
// single rawValue keeps next/back trivial and lets us compute progress
// without bookkeeping.

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case marketing
    case scores
    case alternatives
    case preferences
    case profile
    case symptoms
    case reviews
    case notifications
    case loading
    case results

    var id: Int { rawValue }

    /// Welcome has no chrome; results uses its own dark layout.
    var showsChrome: Bool {
        switch self {
        case .welcome, .results: return false
        default: return true
        }
    }

    /// Progress 0…1 across the "chromed" portion of the flow.
    /// Welcome reports 0 (it doesn't show the bar anyway). The first
    /// chromed step shows ~10% so the bar is never empty.
    var progress: Double {
        guard rawValue > 0 else { return 0 }
        let total = Double(OnboardingStep.allCases.count - 1) // exclude welcome
        return Double(rawValue) / total
    }

    var allowsSkip: Bool { self == .symptoms }
}

// MARK: - Selectable models
//
// Each option exposes its own copy (title/subtitle/emoji) so the screen
// views stay thin and the strings live next to the data.

enum HealthPreference: String, CaseIterable, Identifiable, Codable {
    case lowSugar
    case noColors
    case noSeedOils
    case highProtein
    case noSweeteners
    case noPreservatives
    case glutenFree
    case minimallyProcessed

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .lowSugar:           return "🍬"
        case .noColors:           return "🎨"
        case .noSeedOils:         return "🌻"
        case .highProtein:        return "💪"
        case .noSweeteners:       return "🧪"
        case .noPreservatives:    return "🧫"
        case .glutenFree:         return "🌾"
        case .minimallyProcessed: return "🥦"
        }
    }

    var title: String {
        switch self {
        case .lowSugar:           return "Low added sugar"
        case .noColors:           return "No artificial colors"
        case .noSeedOils:         return "No seed oils"
        case .highProtein:        return "High protein"
        case .noSweeteners:       return "No sweeteners"
        case .noPreservatives:    return "No preservatives"
        case .glutenFree:         return "Gluten-free"
        case .minimallyProcessed: return "Minimally processed"
        }
    }

    var subtitle: String {
        switch self {
        case .lowSugar:           return "Flag hidden sugars"
        case .noColors:           return "Yellow 5, Red 40"
        case .noSeedOils:         return "Canola, soybean"
        case .highProtein:        return "> 10g per serving"
        case .noSweeteners:       return "Sucralose, aspartame"
        case .noPreservatives:    return "BHT, BHA, nitrates"
        case .glutenFree:         return "Wheat, barley, rye"
        case .minimallyProcessed: return "Low NOVA score"
        }
    }
}

enum AgeRange: String, CaseIterable, Identifiable, Codable {
    case age18to24, age25to34, age35to44, age45to54, age55plus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .age18to24: return "18–24"
        case .age25to34: return "25–34"
        case .age35to44: return "35–44"
        case .age45to54: return "45–54"
        case .age55plus: return "55+"
        }
    }

    /// Midpoint used to populate UserProfile.age.
    var representativeAge: Int {
        switch self {
        case .age18to24: return 21
        case .age25to34: return 30
        case .age35to44: return 40
        case .age45to54: return 50
        case .age55plus: return 60
        }
    }
}

enum BiologicalSex: String, CaseIterable, Identifiable, Codable {
    case female, male, other
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum LifeStage: String, CaseIterable, Identifiable, Codable {
    case none, pregnant, breastfeeding, condition

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:          return "None"
        case .pregnant:      return "Pregnant"
        case .breastfeeding: return "Breastfeeding"
        case .condition:     return "Managing a condition"
        }
    }
}

enum Symptom: String, CaseIterable, Identifiable, Codable {
    case lowEnergy, bloating, brainFog, poorSleep, skinIssues, weightGain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lowEnergy:  return "Low energy"
        case .bloating:   return "Bloating"
        case .brainFog:   return "Brain fog"
        case .poorSleep:  return "Poor sleep"
        case .skinIssues: return "Skin issues"
        case .weightGain: return "Weight gain"
        }
    }

    var emoji: String {
        switch self {
        case .lowEnergy:  return "🔋"
        case .bloating:   return "🎈"
        case .brainFog:   return "💭"
        case .poorSleep:  return "😴"
        case .skinIssues: return "🪞"
        case .weightGain: return "⚖️"
        }
    }
}

// MARK: - State container
//
// One ObservableObject owns the entire onboarding session. The
// individual screen views stay value-only and just read/write into it.

@MainActor
final class OnboardingState: ObservableObject {
    /// Which way the user is moving through the flow. Used by the
    /// coordinator to pick a direction-aware step transition so forward
    /// nav slides in from the trailing edge and back nav from the leading.
    enum Direction { case forward, back, none }

    @Published var step: OnboardingStep = .welcome
    @Published var direction: Direction = .none
    @Published var preferences: Set<HealthPreference> = []
    @Published var ageRange: AgeRange? = nil
    @Published var sex: BiologicalSex? = nil
    @Published var lifeStage: LifeStage = .none
    @Published var symptoms: Set<Symptom> = []

    func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        direction = .forward
        withAnimation(.easeInOut(duration: 0.32)) { step = next }
    }

    func goBack() {
        guard let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        direction = .back
        withAnimation(.easeInOut(duration: 0.28)) { step = prev }
    }

    /// Apply collected answers onto the persisted UserProfile so the
    /// rest of the app sees the user's preferences immediately.
    func apply(to user: inout UserProfile) {
        if !preferences.isEmpty {
            user.preferences = preferences.map(\.title)
        }
        if let ageRange { user.age = ageRange.representativeAge }
        if let sex { user.sex = sex.rawValue }

        // Life stage and symptoms aren't first-class profile fields, but
        // we surface them in restrictions so the scoring/UI can react.
        var restrictions = user.restrictions
        restrictions.removeAll(where: {
            LifeStage.allCases.map(\.label).contains($0) ||
            Symptom.allCases.map(\.title).contains($0)
        })
        if lifeStage != .none { restrictions.append(lifeStage.label) }
        restrictions.append(contentsOf: symptoms.map(\.title))
        user.restrictions = restrictions
    }
}
