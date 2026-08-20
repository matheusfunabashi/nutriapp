import SwiftUI

// MARK: - Steps
//
// One enum case per screen, in display order. Driving the flow with a
// single rawValue keeps next/back trivial and lets us compute progress
// without bookkeeping.

enum OnboardingStep: Int, CaseIterable, Identifiable {
    // Act 1 — hook. The problem lands first, then motivation is collected
    // before any friction, so every later screen can be framed as a
    // consequence of the user's own answers.
    case welcome
    case marketing           // "What's marketed as healthy often isn't"
    case goals               // "What should Sage weigh for you?" → healthGoals
    case avoids              // "Anything you want flagged?"      → avoidList

    // Act 2 — the argument. Ends on the two-score explainer, which is now
    // captioned with the picks made in Act 1.
    case howItWorks          // inverted: Scan → Your Score → Swap
    case pledge              // inverted: no brand ever pays for a score
    case scores              // the Your Score differentiator
    case alternatives

    // Act 3 — the asks.
    case attribution         // "How did you hear about Sage?"
    case aboutYou            // optional name + sex
    case dietaryRestrictions
    case allergens

    // Act 4 — payoff.
    case demo                // a real product, scored live against their answers
    case loading
    case results

    var id: Int { rawValue }

    /// Welcome has no chrome; results uses its own dark layout. The demo
    /// hides the bar too — it reads as a product moment, not a wizard step.
    var showsChrome: Bool {
        switch self {
        case .welcome, .results: return false
        default: return true
        }
    }

    /// Progress 0…1 across the "chromed" portion of the flow.
    /// Welcome reports 0 (it doesn't show the bar anyway). The first
    /// chromed step shows ~6% so the bar is never empty.
    var progress: Double {
        guard rawValue > 0 else { return 0 }
        let total = Double(OnboardingStep.allCases.count - 1) // exclude welcome
        return Double(rawValue) / total
    }

    /// Steps whose answers are genuinely optional get a Skip in the toolbar.
    var allowsSkip: Bool {
        switch self {
        case .avoids, .attribution, .aboutYou, .dietaryRestrictions, .allergens:
            return true
        default:
            return false
        }
    }

    /// Inverted (dark green) steps. These keep white-on-green chrome
    /// regardless of the active color scheme.
    var isInverted: Bool {
        switch self {
        case .howItWorks, .pledge, .results: return true
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
    /// Soft nudges only — sugar/sodium hard rules live under Restrictions
    /// ("Low-sugar diet" / "Low-sodium diet"), not duplicated here.
    static let preferences = [
        "Low fat", "High protein", "High fiber", "Organic", "Minimally processed",
    ]

    /// Unified chip grid for the onboarding preferences step. Labels must
    /// stay in sync with `restrictions` / `preferences` above (and DietaryView).
    struct Chip: Identifiable {
        enum Kind { case restriction, preference }
        let id: String
        let symbol: String
        let kind: Kind
    }

    static let onboardingChips: [Chip] = [
        .init(id: "Vegan",                symbol: "leaf.fill",              kind: .restriction),
        .init(id: "Vegetarian",           symbol: "carrot.fill",            kind: .restriction),
        .init(id: "Pescatarian",          symbol: "fish.fill",              kind: .restriction),
        .init(id: "High protein",         symbol: "bolt.fill",              kind: .preference),
        .init(id: "Gluten-free",          symbol: "nosign",                 kind: .restriction),
        .init(id: "Dairy-free",           symbol: "cup.and.saucer.fill",    kind: .restriction),
        .init(id: "Low-sugar diet",       symbol: "cube.fill",              kind: .restriction),
        .init(id: "Low-sodium diet",      symbol: "drop.fill",              kind: .restriction),
        .init(id: "Low fat",              symbol: "chart.bar.fill",         kind: .preference),
        .init(id: "High fiber",           symbol: "circle.hexagongrid.fill", kind: .preference),
        .init(id: "Organic",              symbol: "leaf.circle.fill",       kind: .preference),
        .init(id: "Minimally processed",  symbol: "sparkles",               kind: .preference),
    ]
}

enum OnboardingAllergenOptions {
    static let presets = [
        "Milk", "Eggs", "Peanuts", "Tree nuts", "Soy",
        "Wheat / gluten", "Fish", "Shellfish", "Sesame", "Mustard",
    ]

    struct Chip: Identifiable {
        let id: String
        let symbol: String
    }

    /// Same labels as `presets`, with icons for the onboarding pill grid.
    static let chips: [Chip] = [
        .init(id: "Milk",           symbol: "cup.and.saucer.fill"),
        .init(id: "Eggs",           symbol: "oval.fill"),
        .init(id: "Peanuts",        symbol: "circle.hexagongrid.fill"),
        .init(id: "Tree nuts",      symbol: "leaf.fill"),
        .init(id: "Soy",            symbol: "leaf.circle"),
        .init(id: "Wheat / gluten", symbol: "nosign"),
        .init(id: "Fish",           symbol: "fish.fill"),
        .init(id: "Shellfish",      symbol: "fork.knife"),
        .init(id: "Sesame",         symbol: "circle.dotted"),
        .init(id: "Mustard",        symbol: "flame.fill"),
    ]
}

// MARK: - Your Score inputs
//
// These two lists are the only onboarding answers that actually move Your
// Score, so their labels must match `DietaryView`'s vocabulary exactly —
// ScoringV4 looks goals and avoid-list entries up by string. Adding a nice-
// sounding option here that isn't in the ruleset would silently do nothing.

enum OnboardingGoalOptions {
    struct Goal: Identifiable {
        /// Stored in `UserProfile.healthGoals` — must match a `multipliers.goal`
        /// key in the ruleset (lookup is case-insensitive).
        let id: String
        let symbol: String
        let blurb: String
    }

    /// Broad priorities for first-run. Clinical / life-stage goals
    /// (Pregnancy, Young child, Gut health) live only in Personalize.
    static let all: [Goal] = [
        .init(id: "Less sugar", symbol: "cube.fill",
              blurb: "Added sugars and sweet drinks weigh heavier"),
        .init(id: "Less processed", symbol: "leaf.fill",
              blurb: "Ultra-processed foods and long additive lists weigh heavier"),
        .init(id: "More protein", symbol: "flame.fill",
              blurb: "Protein density weighs heavier"),
        .init(id: "Heart health", symbol: "heart.fill",
              blurb: "Sodium and saturated fat weigh heavier"),
        .init(id: "Just keep it clean", symbol: "checkmark.seal.fill",
              blurb: "A light nudge toward cleaner labels — no strong specialty focus"),
    ]
}

enum OnboardingAvoidOptions {
    struct Avoid: Identifiable {
        /// Must match `DietaryView.avoids` / `UserProfile.avoidList`.
        let id: String
        let symbol: String
    }

    static let all: [Avoid] = [
        .init(id: "Seed oils",         symbol: "drop.fill"),
        .init(id: "HFCS",              symbol: "cube.fill"),
        .init(id: "Sucralose",         symbol: "sparkles"),
        .init(id: "Aspartame",         symbol: "flask.fill"),
        .init(id: "Artificial colors", symbol: "paintpalette.fill"),
        .init(id: "Carrageenan",       symbol: "waveform.path"),
        .init(id: "Palm oil",          symbol: "tree.fill"),
        .init(id: "Titanium dioxide",  symbol: "circle.hexagongrid.fill"),
        .init(id: "Added phosphates",  symbol: "bolt.fill"),
        .init(id: "Caffeine",          symbol: "cup.and.saucer.fill"),
    ]
}

// MARK: - Attribution
//
// Marketing-only; never read by scoring. Stored verbatim on
// `UserProfile.acquisitionSource`.

enum OnboardingAttributionOptions {
    struct Source: Identifiable {
        let id: String
        let symbol: String
    }

    static let all: [Source] = [
        .init(id: "TikTok",         symbol: "music.note"),
        .init(id: "Instagram",      symbol: "camera.fill"),
        .init(id: "From a friend",  symbol: "person.2.fill"),
        .init(id: "App Store",      symbol: "magnifyingglass"),
        .init(id: "Other",          symbol: "ellipsis"),
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

    /// Dietary hard rules + soft score signals from the restrictions screen.
    @Published var dietaryRestrictions: Set<String> = []
    @Published var foodPreferences: Set<String> = []
    @Published var selectedAllergens: [String] = []

    // MARK: - Your Score inputs (Act 1)
    //
    // Collected before anything else, so by the time the demo step runs the
    // engine has real personalization to apply and the Overall/Your Score
    // split lands on the user's own answers rather than a canned number.

    @Published var healthGoals: Set<String> = []
    @Published var avoidList: Set<String> = []

    /// Marketing attribution (Act 3). Nil when skipped.
    @Published var acquisitionSource: String? = nil

    /// Optional identity (Act 3). Empty / nil when skipped — never fall back
    /// to a fake placeholder name like "Jamie Rivera".
    @Published var firstName: String = ""
    @Published var sex: BiologicalSex? = nil

    /// A profile carrying *only* what's been answered so far. The demo step
    /// scores against this so the reveal reflects the real ruleset rather
    /// than a hand-written delta.
    ///
    /// The personalization fields are cleared before applying: `AppStore`
    /// seeds `user` from `MockData.user`, which ships with a low-sugar
    /// restriction and high-protein/low-sodium preferences. Inheriting those
    /// would make the reveal cite reasons the user never chose — the one
    /// thing this screen cannot afford to get wrong.
    func previewProfile(basedOn base: UserProfile) -> UserProfile {
        var p = base
        p.restrictions = []
        p.preferences = []
        p.healthGoals = []
        p.avoidList = []
        p.allergies = nil
        p.personalizeScoring = true
        apply(to: &p)
        return p
    }

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

        let trimmedName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Always write — an empty/skipped answer must not leave a seeded
        // placeholder like "Jamie Rivera" on the profile.
        user.name = trimmedName
        user.sex = sex?.rawValue ?? ""

        if !dietaryRestrictions.isEmpty {
            user.restrictions = Array(dietaryRestrictions)
        }

        if !selectedAllergens.isEmpty {
            user.allergies = selectedAllergens
        }

        // Your Score inputs. Written only when non-empty so a skipped step
        // leaves any previously-saved value alone rather than clearing it.
        if !healthGoals.isEmpty {
            user.healthGoals = Array(healthGoals)
        }
        if !avoidList.isEmpty {
            user.avoidList = Array(avoidList)
        }
        if let acquisitionSource {
            user.acquisitionSource = acquisitionSource
        }
    }
}
