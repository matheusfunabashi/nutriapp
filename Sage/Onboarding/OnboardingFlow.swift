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
//
// Flow shape (see `OnboardingStep`): motivation is collected in Act 1 so
// that the Your Score explainer in Act 2 and the live demo in Act 4 both
// have real personalization to show. Personal data comes last, and is
// skippable.

struct OnboardingFlow: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var state = OnboardingState()
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 0) {
                if state.step.showsChrome {
                    let skip: (() -> Void)? = state.step.allowsSkip
                        ? { state.advance() }
                        : nil
                    OnboardingHeader(
                        step: state.step,
                        onBack: { state.goBack() },
                        onSkip: skip
                    )
                }

                screenBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(state.step) // re-trigger transitions per step
                    .transition(stepTransition)

                if let footer {
                    footer.padding(.horizontal, 20).padding(.bottom, 36)
                }
            }
        }
        // The inverted steps are white-on-dark-green in both schemes, so the
        // status bar has to follow them. `preferredColorScheme` resolves at
        // the `WindowGroup`, so applying it here would be ignored — the
        // store carries the override up to the scene root instead.
        .onChange(of: state.step, initial: true) { _, step in
            store.schemeOverride = step.isInverted ? .dark : nil
        }
        .onDisappear { store.schemeOverride = nil }
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
    // The inverted steps carry the dark-green brand surface regardless of
    // color scheme; every other step uses the app's normal background.
    @ViewBuilder
    private var background: some View {
        if state.step.isInverted {
            OnboardingInverted.background
        } else {
            Theme.background
        }
    }

    // MARK: Screen bodies

    @ViewBuilder
    private var screenBody: some View {
        switch state.step {
        case .welcome:
            OnboardingWelcomeScreen(
                accent: store.accent,
                onContinue: state.advance
            )

        case .marketing:
            OnboardingMarketingScreen()

        case .goals:
            OnboardingGoalsScreen(accent: store.accent, selection: $state.healthGoals)

        case .avoids:
            OnboardingAvoidsScreen(accent: store.accent, selection: $state.avoidList)

        case .howItWorks:
            OnboardingHowItWorksScreen(accent: store.accent)

        case .pledge:
            OnboardingPledgeScreen(accent: store.accent)

        case .scores:
            OnboardingScoresScreen(accent: store.accent, goals: state.healthGoals,
                                   avoids: state.avoidList)

        case .alternatives:
            OnboardingAlternativesScreen(accent: store.accent)

        case .attribution:
            OnboardingAttributionScreen(
                accent: store.accent,
                selection: $state.acquisitionSource,
                onPick: state.advance
            )

        case .aboutYou:
            OnboardingAboutYouScreen(
                accent: store.accent,
                firstName: $state.firstName,
                sex: $state.sex
            )

        case .dietaryRestrictions:
            OnboardingDietaryRestrictionsScreen(
                accent: store.accent,
                restrictions: $state.dietaryRestrictions,
                preferences: $state.foodPreferences
            )

        case .allergens:
            OnboardingAllergensScreen(
                accent: store.accent,
                allergies: $state.selectedAllergens
            )

        case .demo:
            OnboardingDemoScreen(
                accent: store.accent,
                profile: state.previewProfile(basedOn: store.user),
                onContinue: state.advance
            )

        case .loading:
            OnboardingLoadingScreen(accent: store.accent, onComplete: state.advance)

        case .results:
            OnboardingResultsScreen(
                accent: store.accent,
                dietaryRestrictions: state.dietaryRestrictions,
                foodPreferences: state.foodPreferences,
                healthGoals: state.healthGoals,
                avoidList: state.avoidList,
                onStart: complete
            )
        }
    }

    // MARK: Footer (CTA + ghost)
    //
    // Screens that own their footer return nil here: welcome and results
    // have bespoke chrome, loading advances itself, the demo commits from
    // inside its reveal sheet, and attribution auto-advances on tap.
    private var footer: AnyView? {
        switch state.step {
        case .welcome, .loading, .results, .demo, .attribution:
            return nil

        case .goals:
            // The one step we gate: Your Score is the product, and it needs
            // at least one input to mean anything.
            return AnyView(
                OnboardingCTAButton(
                    title: "Continue",
                    enabled: !state.healthGoals.isEmpty,
                    action: state.advance
                )
            )

        case .howItWorks, .pledge:
            return AnyView(
                OnboardingCTAButton(title: "Continue", inverted: true,
                                    action: state.advance)
            )

        case .avoids, .marketing, .scores, .alternatives,
             .aboutYou, .dietaryRestrictions, .allergens:
            return AnyView(
                OnboardingCTAButton(title: "Continue", action: state.advance)
            )
        }
    }

    // MARK: - Side effects

    /// Persists the user's answers and finishes the flow.
    private func complete() {
        var u = store.user
        state.apply(to: &u)
        store.user = u
        // Results is an inverted step, so drop the override explicitly rather
        // than relying on `onDisappear` racing the swap to main content.
        store.schemeOverride = nil

        // Ship the marketing answer to D1 so we can see channel mix later.
        // Local profile already holds it; this is analytics-only and must not
        // block finishing onboarding if the network is down.
        if let source = state.acquisitionSource {
            let backend = BackendService()
            Task { await backend.reportAttribution(source: source) }
        }

        onFinish()
    }
}
