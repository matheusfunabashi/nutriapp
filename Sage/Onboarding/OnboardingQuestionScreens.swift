import SwiftUI

// MARK: - Act 1 · Goals
//
// The first thing we ask, and the first thing that moves Your Score. Every
// option here is a real `UserProfile.healthGoals` value, so by the time the
// demo step runs the engine has something genuine to personalize against.
//
// Built as an inset-grouped `List` on the brand background: the system
// supplies row insets, separators and press highlights, and the beige
// survives via `.scrollContentBackground(.hidden)` (see `sageListStyle`).
// The title lives in the section header so it scrolls with the options and
// there's no dead band between the copy and the card.

struct OnboardingGoalsScreen: View {
    let accent: Color
    @Binding var selection: Set<String>

    var body: some View {
        List {
            Section {
                ForEach(OnboardingGoalOptions.all) { goal in
                    OnboardingChoiceRow(
                        symbol: goal.symbol,
                        title: goal.id,
                        subtitle: goal.blurb,
                        selected: selection.contains(goal.id),
                        accent: accent,
                        action: { toggle(goal.id) }
                    )
                }
            } header: {
                OnboardingTitle(
                    title: "What should Sage\nweigh for you?",
                    subtitle: "This is what makes Your Score yours. Pick everything that applies. You can change it later."
                )
                .onboardingListHeader()
            } footer: {
                Text("Sage always shows the same Overall score to everyone. Your Score is recalculated from these.")
                    .font(.sageRegular(12))
            }
        }
        .onboardingListStyle()
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}

// MARK: - Act 1 · Avoid list
//
// Second Your Score input. Unlike goals (which re-weight), anything picked
// here *caps* Your Score when detected — the sharpest, most legible form of
// personalization we can show off in the demo step.

struct OnboardingAvoidsScreen: View {
    let accent: Color
    @Binding var selection: Set<String>

    var body: some View {
        List {
            Section {
                ForEach(OnboardingAvoidOptions.all) { avoid in
                    OnboardingChoiceRow(
                        symbol: avoid.symbol,
                        title: avoid.id,
                        selected: selection.contains(avoid.id),
                        accent: accent,
                        action: { toggle(avoid.id) }
                    )
                }
            } header: {
                OnboardingTitle(
                    title: "Anything you want\nflagged on sight?",
                    subtitle: "Products containing these get capped and called out, no matter how good the rest of the label looks."
                )
                .onboardingListHeader()
            } footer: {
                Text("Skip this if you'd rather judge case by case.")
                    .font(.sageRegular(12))
            }
        }
        .onboardingListStyle()
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}

// MARK: - Act 3 · Attribution
//
// Marketing-only, and single-select, so tapping a row commits and advances
// in one gesture — no Continue button. Borrowed straight from the
// competitor flows, where the auto-advance is what makes them feel quick.

struct OnboardingAttributionScreen: View {
    let accent: Color
    @Binding var selection: String?
    let onPick: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(OnboardingAttributionOptions.all) { source in
                    OnboardingChoiceRow(
                        symbol: source.symbol,
                        title: source.id,
                        selected: selection == source.id,
                        showsChevron: true,
                        accent: accent,
                        action: { pick(source.id) }
                    )
                }
            } header: {
                OnboardingTitle(
                    title: "How did you hear\nabout Sage?",
                    subtitle: "Helps us know where to show up next."
                )
                .onboardingListHeader()
            }
        }
        .onboardingListStyle()
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func pick(_ id: String) {
        selection = id
        // Let the row's highlight land before the step slides away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: onPick)
    }
}
