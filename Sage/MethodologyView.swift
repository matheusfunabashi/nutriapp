import SwiftUI

struct MethodologyView: View {
    @EnvironmentObject var store: AppStore
    let onBack: () -> Void

    var body: some View {
        let dark = store.darkMode
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                SubHeader(title: "How we score", onBack: onBack)
                    .foregroundColor(Theme.textPrimary(dark))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Two scores, one product")
                        .font(.system(size: 26, weight: .heavy)).tracking(-0.6)
                        .foregroundColor(Theme.textPrimary(dark))
                    Text("Every product gets an Overall score (0-100) from public nutrition data, plus a Your Score adjusted to your profile.")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary(dark))
                        .lineSpacing(2)
                }
                .padding(.horizontal, 24).padding(.bottom, 20)

                methodCard(
                    title: "Overall score",
                    body: "Combines Nutri-Score (per 100g/ml nutrients), NOVA classification (processing level), and additive risk into a 0-100 scale.",
                    dark: dark)
                methodCard(
                    title: "Your Score",
                    body: "Starts from Overall, then applies your objective, restrictions, and preferences. Restriction conflicts dock points; matching boosts (protein, fiber, calcium) bump it up.",
                    dark: dark)
                methodCard(
                    title: "Tiers",
                    body: "75-100 Excellent · 50-74 Good · 25-49 Poor · 0-24 Bad",
                    dark: dark)
                methodCard(
                    title: "Trans fats",
                    body: "Trans fats trigger our heaviest penalty. We surface them with a dedicated red flag.",
                    dark: dark)

                Spacer().frame(height: 60)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
    }

    private func methodCard(title: String, body: String, dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .heavy)).tracking(-0.3)
                .foregroundColor(Theme.textPrimary(dark))
            Text(body)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary(dark))
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
        .padding(.horizontal, 16).padding(.bottom, 10)
    }
}

// MARK: - Methodology modal

struct MethodologyModal: View {
    @EnvironmentObject var store: AppStore
    let onDismiss: () -> Void
    let onLearnMore: () -> Void

    var body: some View {
        let dark = store.darkMode
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("How we score")
                        .font(.system(size: 20, weight: .heavy)).tracking(-0.4)
                        .foregroundColor(Theme.textPrimary(dark))
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Theme.textPrimary(dark))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(dark ? Color.white.opacity(0.08)
                                                              : Color.black.opacity(0.06)))
                    }.buttonStyle(.plain)
                }
                Text("Sage combines public nutrition data (Nutri-Score, NOVA, additive risk) into an Overall score, then re-weights it against your profile to compute Your Score.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary(dark))
                    .lineSpacing(3)
                HStack(spacing: 10) {
                    PillButton(title: "Got it", variant: .secondary, dark: dark, fullWidth: true,
                               action: onDismiss)
                    PillButton(title: "Learn more", variant: .primary, dark: dark, fullWidth: true,
                               action: onLearnMore)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.bg(dark))
            )
            .padding(.horizontal, 16).padding(.bottom, 30)
            .transition(.move(edge: .bottom))
        }
    }
}

// MARK: - First-launch disclaimer

struct DisclaimerModal: View {
    @EnvironmentObject var store: AppStore
    let onAcknowledge: () -> Void

    var body: some View {
        let dark = store.darkMode
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 18) {
                SageMark(size: 44, color: store.accent)
                Text("Sage is informational, not advice")
                    .font(.system(size: 22, weight: .heavy)).tracking(-0.5)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.textPrimary(dark))
                Text("Scores are a guide, not medical or professional nutrition advice. For specific dietary needs, please consult a registered dietitian or doctor.")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.textSecondary(dark))
                    .lineSpacing(3)
                PillButton(title: "I understand", variant: .primary, dark: dark,
                           fullWidth: true, action: onAcknowledge)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.bg(dark))
            )
            .cardShadow(dark)
            .padding(.horizontal, 24)
        }
    }
}
