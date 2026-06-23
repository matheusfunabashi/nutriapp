import SwiftUI
import UserNotifications

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
            OnboardingMarketingScreen(dark: dark, accent: store.accent)
        case .scores:
            OnboardingScoresScreen(dark: dark, accent: store.accent)
        case .alternatives:
            OnboardingAlternativesScreen(dark: dark, accent: store.accent)
        case .preferences:
            OnboardingPreferencesScreen(
                dark: dark, accent: store.accent,
                selection: $state.preferences
            )
        case .profile:
            OnboardingProfileScreen(
                dark: dark, accent: store.accent,
                ageRange: $state.ageRange,
                sex: $state.sex,
                lifeStage: $state.lifeStage
            )
        case .symptoms:
            OnboardingSymptomsScreen(
                dark: dark, accent: store.accent,
                selection: $state.symptoms
            )
        case .reviews:
            OnboardingReviewsScreen(dark: dark)
        case .notifications:
            OnboardingNotificationsScreen(dark: dark, accent: store.accent)
        case .loading:
            OnboardingLoadingScreen(
                dark: dark, accent: store.accent,
                onComplete: state.advance
            )
        case .results:
            OnboardingResultsScreen(
                accent: store.accent,
                preferences: state.preferences,
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

        case .preferences:
            return AnyView(
                OnboardingCTAButton(
                    title: "Continue",
                    dark: dark,
                    enabled: !state.preferences.isEmpty,
                    action: state.advance
                )
            )

        case .profile:
            return AnyView(
                OnboardingCTAButton(
                    title: "Continue",
                    dark: dark,
                    enabled: state.ageRange != nil && state.sex != nil,
                    action: state.advance
                )
            )

        case .reviews:
            return AnyView(VStack(spacing: 8) {
                OnboardingCTAButton(title: "Continue", dark: dark, action: state.advance)
                OnboardingGhostButton(title: "Maybe later", dark: dark, action: state.advance)
            })

        case .notifications:
            return AnyView(VStack(spacing: 8) {
                OnboardingCTAButton(
                    title: "Enable notifications",
                    dark: dark,
                    action: requestNotifications
                )
                OnboardingGhostButton(title: "Not now", dark: dark, action: state.advance)
            })

        case .marketing, .scores, .alternatives, .symptoms:
            return AnyView(
                OnboardingCTAButton(title: "Continue", dark: dark, action: state.advance)
            )
        }
    }

    // MARK: - Side effects

    private func requestNotifications() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                DispatchQueue.main.async { state.advance() }
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
