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
    case profileName     // "What should we call you?"
    case profileBody     // "Your body stats"
    case profileDetails  // "A bit more about you" (DOB / gender / life stage)
    case dietaryRestrictions // "Any dietary restrictions?"
    case allergens             // "Any allergies or intolerances?"
    case reviews
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

    /// Skip lives in the header row for dietary and allergen steps.
    /// Profile name/body/details use a ghost Skip under the CTA instead.
    var allowsSkip: Bool {
        switch self {
        case .dietaryRestrictions, .allergens: return true
        default: return false
        }
    }
}

// MARK: - Dietary & allergen option lists
//
// String labels match `DietaryView` / `UserProfile` so onboarding writes
// the same values the profile screen and scoring engine expect.

enum DietaryOptions {
    static let restrictions = [
        "Vegan", "Vegetarian", "Pescatarian", "Low-sugar diet",
        "Low-sodium diet", "Gluten-free", "Dairy-free",
    ]
    static let preferences = [
        "Low sugar", "Low sodium", "Low fat",
        "High protein", "High fiber", "Organic", "Minimally processed",
    ]
}

enum OnboardingAllergenOptions {
    static let presets = [
        "Milk", "Eggs", "Peanuts", "Tree nuts", "Soy",
        "Wheat / gluten", "Fish", "Shellfish", "Sesame", "Mustard",
    ]
}

// MARK: - Selectable models
//
// Each option exposes its own copy (title/subtitle/emoji) so the screen
// views stay thin and the strings live next to the data.

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

    // MARK: - Profile (split across 3 screens)
    //
    // Body stats are stored in *both* imperial and metric: the units
    // toggle on the body-stats screen converts between them in-place
    // so the user never sees stale numbers.

    /// Screen 1
    @Published var firstName: String = ""

    /// Screen 2
    @Published var useImperial: Bool = true
    @Published var heightFt: Int = 5
    @Published var heightIn: Int = 7
    @Published var heightCm: Int = 170
    @Published var weightLb: Int = 147
    @Published var weightKg: Int = 67

    /// Screen 3
    @Published var dobMonth: Int = 1
    @Published var dobDay: Int = 1
    @Published var dobYear: Int = 1995
    @Published var sex: BiologicalSex? = nil
    @Published var lifeStages: Set<LifeStage> = []

    /// Dietary hard rules + soft score signals from the restrictions screen.
    @Published var dietaryRestrictions: Set<String> = []
    @Published var foodPreferences: Set<String> = []
    @Published var selectedAllergens: [String] = []

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
        if !foodPreferences.isEmpty {
            user.preferences = Array(foodPreferences)
        }

        // Name — leave the existing value alone if the user skipped.
        let trimmedName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            user.name = trimmedName
        }

        // Body stats — always store in imperial in the profile (its
        // canonical unit). Convert from metric only when the user
        // finished the flow with the metric toggle on.
        user.heightIn = useImperial ? (heightFt * 12 + heightIn)
                                    : Int((Double(heightCm) / 2.54).rounded())
        user.weightLb = useImperial ? weightLb
                                    : Int((Double(weightKg) * 2.20462).rounded())
        user.unitSystem = useImperial ? "Imperial" : "Metric"

        // DOB — formatted MM/dd/yyyy with the locale-agnostic en_US_POSIX
        // formatter so we don't accidentally pull region order.
        let comps = DateComponents(year: dobYear, month: dobMonth, day: dobDay)
        if let dobDate = Calendar(identifier: .gregorian).date(from: comps) {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "MM/dd/yyyy"
            user.dob = fmt.string(from: dobDate)

            let years = Calendar(identifier: .gregorian)
                .dateComponents([.year], from: dobDate, to: Date()).year ?? 0
            user.age = max(0, years)
        }

        if let sex { user.sex = sex.rawValue }

        // Dietary hard rules + life stage share `restrictions`.
        var restrictions = Array(dietaryRestrictions)
        for stage in lifeStages where stage != .none {
            restrictions.append(stage.label)
        }
        if !restrictions.isEmpty {
            user.restrictions = restrictions
        }

        if !selectedAllergens.isEmpty {
            user.allergies = selectedAllergens
        }
    }
}
