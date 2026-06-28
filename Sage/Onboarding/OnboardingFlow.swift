import SwiftUI

// MARK: - OnboardingFlow
//
// Top-level coordinator for the first-launch onboarding. It owns the
// session state and decides, per step:
//   • whether to draw the chromed header (back/progress/skip)
//   • which screen body to render
//   • how to render the footer (CTA + optional ghost button)
//
// Individual screens stay value-typed and unaware of navigation —
// they receive bindings/closures and nothing else.

struct OnboardingFlow: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var state = OnboardingState()
    @State private var awaitingReviewPrompt = false
    let onFinish: () -> Void

    var body: some View {
        let dark = store.darkMode

        ZStack {
            background(dark: dark).ignoresSafeArea()

            VStack(spacing: 0) {
                if state.step.showsChrome {
                    let skip: (() -> Void)? = state.step.allowsSkip
                        ? { state.advance() }
                        : nil
                    OnboardingHeader(
                        step: state.step,
                        dark: dark,
                        onBack: { state.goBack() },
                        onSkip: skip
                    )
                }

                screenBody(dark: dark)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(state.step) // re-trigger transitions per step
                    .transition(stepTransition)

                if let footer = footer(dark: dark) {
                    footer.padding(.horizontal, 20).padding(.bottom, 36)
                }
            }
        }
    }

    // MARK: Step transition
    //
    // Direction-aware slide+fade. Forward nav inserts from the trailing
    // edge and removes toward the leading; back nav mirrors it. Keeps
    // the wizard feeling spatial without ever feeling backwards.
    private var stepTransition: AnyTransition {
        switch state.direction {
        case .back:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal:   .move(edge: .trailing).combined(with: .opacity)
            )
        case .forward, .none:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            )
        }
    }

    // MARK: Background
    //
    // The results step is dark themed regardless of color scheme; every
    // other step uses the app's normal background.
    @ViewBuilder
    private func background(dark: Bool) -> some View {
        if state.step == .results {
            Color(hex: "0B2A1F")
        } else {
            Theme.bg(dark)
        }
    }

    // MARK: Screen bodies

    @ViewBuilder
    private func screenBody(dark: Bool) -> some View {
        switch state.step {
        case .welcome:
            OnboardingWelcomeScreen(
                dark: dark, accent: store.accent,
                onContinue: state.advance,
                onSignIn: complete  // placeholder until auth lands
            )
        case .marketing:
            OnboardingMarketingScreen(dark: dark)
        case .scores:
            OnboardingScoresScreen(dark: dark, accent: store.accent)
        case .alternatives:
            OnboardingAlternativesScreen(dark: dark, accent: store.accent)
        case .profileName:
            OnboardingNameScreen(
                dark: dark,
                firstName: $state.firstName
            )
        case .profileBody:
            OnboardingBodyStatsScreen(
                dark: dark,
                useImperial: $state.useImperial,
                heightFt: $state.heightFt,
                heightIn: $state.heightIn,
                heightCm: $state.heightCm,
                weightLb: $state.weightLb,
                weightKg: $state.weightKg
            )
        case .profileDetails:
            OnboardingPersonalDetailsScreen(
                dark: dark,
                dobMonth: $state.dobMonth,
                dobDay: $state.dobDay,
                dobYear: $state.dobYear,
                sex: $state.sex,
                lifeStages: $state.lifeStages
            )
        case .dietaryRestrictions:
            OnboardingDietaryRestrictionsScreen(
                dark: dark,
                restrictions: $state.dietaryRestrictions,
                preferences: $state.foodPreferences
            )
        case .allergens:
            OnboardingAllergensScreen(
                dark: dark,
                allergies: $state.selectedAllergens
            )
        case .reviews:
            OnboardingReviewsScreen(dark: dark)
        case .loading:
            OnboardingLoadingScreen(
                dark: dark, accent: store.accent,
                onComplete: state.advance
            )
        case .results:
            OnboardingResultsScreen(
                accent: store.accent,
                dietaryRestrictions: state.dietaryRestrictions,
                foodPreferences: state.foodPreferences,
                lifeStages: state.lifeStages,
                onStart: complete
            )
        }
    }

    // MARK: Footer (CTA + ghost)
    //
    // The welcome / loading / results screens render their own footers
    // because their copy and chrome are bespoke. Everything else uses
    // the standard "Continue" pill + optional secondary ghost.
    private func footer(dark: Bool) -> AnyView? {
        switch state.step {
        case .welcome, .loading, .results:
            return nil

        case .profileName:
            // Name + Skip. CTA enabled once anything is typed; Skip
            // simply advances without saving.
            return AnyView(VStack(spacing: 8) {
                OnboardingCTAButton(
                    title: "Continue",
                    dark: dark,
                    enabled: !state.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: state.advance
                )
                OnboardingGhostButton(title: "Skip", dark: dark, action: state.advance)
            })

        case .profileBody:
            // Body stats default to sensible values, so CTA is always
            // enabled. Skip is offered for users who'd rather not say.
            return AnyView(VStack(spacing: 8) {
                OnboardingCTAButton(title: "Continue", dark: dark, action: state.advance)
                OnboardingGhostButton(title: "Skip", dark: dark, action: state.advance)
            })

        case .profileDetails:
            // CTA enabled once a gender is picked (DOB and life stage
            // both default to valid values). Skip bypasses entirely.
            return AnyView(VStack(spacing: 8) {
                OnboardingCTAButton(
                    title: "Continue",
                    dark: dark,
                    enabled: state.sex != nil,
                    action: state.advance
                )
                OnboardingGhostButton(title: "Skip", dark: dark, action: state.advance)
            })

        case .dietaryRestrictions, .allergens:
            // Selection is optional — Skip lives in the header row.
            return AnyView(
                OnboardingCTAButton(title: "Continue", dark: dark, action: state.advance)
            )

        case .reviews:
            return AnyView(VStack(spacing: 8) {
                OnboardingCTAButton(
                    title: "Continue",
                    dark: dark,
                    enabled: !awaitingReviewPrompt,
                    action: requestReviewThenAdvance
                )
                OnboardingGhostButton(title: "Maybe later", dark: dark, action: state.advance)
            })

        case .marketing, .scores, .alternatives:
            return AnyView(
                OnboardingCTAButton(title: "Continue", dark: dark, action: state.advance)
            )
        }
    }

    // MARK: - Side effects

    private func requestReviewThenAdvance() {
        guard !awaitingReviewPrompt else { return }
        awaitingReviewPrompt = true
        ReviewPromptPresenter.requestThenContinue {
            awaitingReviewPrompt = false
            state.advance()
        }
    }

    /// Persists the user's answers and finishes the flow.
    private func complete() {
        var u = store.user
        state.apply(to: &u)
        store.user = u
        onFinish()
    }
}
