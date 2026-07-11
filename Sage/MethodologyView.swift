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
                        .font(.sageBold(26)).tracking(-0.6)
                        .foregroundColor(Theme.textPrimary(dark))
                    Text("Every product gets an Overall score (10-100) from public nutrition data, plus a Your Score tuned to your profile.")
                        .font(.sageRegular(14))
                        .foregroundColor(Theme.textSecondary(dark))
                        .lineSpacing(2)
                }
                .padding(.horizontal, 24).padding(.bottom, 20)

                methodCard(
                    title: "Overall score",
                    body: "Starts every food at a neutral 50, adds points for protein density, fiber, and whole-food content (per 100g/ml), and subtracts for sugar, saturated fat, sodium, ultra-processing (NOVA), and risky additives. 100 = perfect food, 70 = good, 50 = neither good nor bad, 30 = bad for you, 10 = best avoided.",
                    dark: dark)
                methodCard(
                    title: "Your Score",
                    body: "Starts from Overall, then tunes it to your objective and preferences — e.g. protein-dense foods rise if you're building muscle; zero-calorie drinks rise a little if you're losing weight. Restriction conflicts cap it hard.",
                    dark: dark)
                methodCard(
                    title: "Tiers",
                    body: "80-100 Excellent · 60-79 Good · 40-59 OK · 10-39 Bad",
                    dark: dark)
                methodCard(
                    title: "Trans fats",
                    body: "Industrial trans fats have no safe intake level, so any amount triggers our heaviest flat penalty and a dedicated red flag.",
                    dark: dark)

                Spacer().frame(height: 60)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
    }

    private func methodCard(title: String, body: String, dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.sageBold(16)).tracking(-0.3)
                .foregroundColor(Theme.textPrimary(dark))
            Text(body)
                .font(.sageRegular(13))
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
                        .font(.sageBold(20)).tracking(-0.4)
                        .foregroundColor(Theme.textPrimary(dark))
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.sageBold(13))
                            .foregroundColor(Theme.textPrimary(dark))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(dark ? Color.white.opacity(0.08)
                                                              : Color.black.opacity(0.06)))
                    }.buttonStyle(.plain)
                }
                Text("Sage combines public nutrition data (per-100g nutrients, NOVA processing level, additive risk) into an Overall score, then tunes it to your goal and preferences to compute Your Score.")
                    .font(.sageRegular(14))
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
                    .font(.sageBold(22)).tracking(-0.5)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.textPrimary(dark))
                Text("Scores are a guide, not medical or professional nutrition advice. For specific dietary needs, please consult a registered dietitian or doctor.")
                    .font(.sageRegular(14))
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
