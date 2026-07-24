import SwiftUI

struct MethodologyView: View {
    @EnvironmentObject var store: AppStore
    let onBack: () -> Void

    private var bands: RulesetV4.Bands { RulesetV4.bundled.bands }

    var body: some View {
        let dark = store.darkMode
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                SubHeader(title: "How we score", onBack: onBack)
                    .foregroundColor(Theme.textPrimary(dark))

                VStack(alignment: .leading, spacing: 12) {
                    Text("A health score, not an ethics score")
                        .font(.sageBold(26)).tracking(-0.6)
                        .foregroundColor(Theme.textPrimary(dark))
                    Text("Sage measures health only. Packaging, certifications, animal welfare, and origin claims are out of the score unless they have a direct health pathway (for example brew-bag microplastics or arsenic risk in rice drinks).")
                        .font(.sageRegular(14))
                        .foregroundColor(Theme.textSecondary(dark))
                        .lineSpacing(2)
                }
                .padding(.horizontal, 24).padding(.bottom, 20)

                methodCard(
                    title: "How the number is built",
                    body: "Each product is routed to a category profile. Rules return a fraction from 0 to 1; the score is Σ(weight × fraction) / Σ(weight), floored at 10. Weights always sum to 100 for mental math and confidence. Your Score reweights rules for your goals, then may apply preference caps.",
                    dark: dark)
                methodCard(
                    title: "Bands",
                    body: "\(bands.excellent)–100 Excellent · \(bands.good)–\(bands.excellent - 1) Good · \(bands.ok)–\(bands.good - 1) OK · 10–\(bands.ok - 1) Bad. The same cut points drive dials, badges, and Overview labels.",
                    dark: dark)
                methodCard(
                    title: "Caps",
                    body: "Industrial trans fat (NOVA 4 or partially hydrogenated oil) caps Overall at 34. Free-sugar ceiling (34) still applies to foods with concentrated added sugar — candy in snacks, sugary drinks — but intrinsic dried-fruit sugar is exempt. Pure table sweeteners are not scored at all (see below), so the old NNS table-sweetener ceiling no longer applies to them. Your Score can be further limited by diet conflicts and avoid-list items; when several fire, the lowest wins.",
                    dark: dark)
                methodCard(
                    title: "Why sweeteners aren’t scored",
                    body: "This is essentially pure sugar, and no concentrated sugar is a health food. Sage doesn't score sweeteners, so a number here would only mislead.",
                    dark: dark)
                methodCard(
                    title: "Whole foods",
                    body: "Minimally processed produce (NOVA 1–2, no additives) gets a clean additive score even when the ingredient list is missing — single-ingredient foods often lack one. Fruits, vegetables, eggs, legumes, nuts, berries, and salads use a produce-focused nutrition blend.",
                    dark: dark)
                methodCard(
                    title: "Provisional scores",
                    body: "When too much of the weighted profile rests on missing evidence, we mark the score provisional. Missing data lowers confidence; it does not invent numbers.",
                    dark: dark)

                Spacer().frame(height: 60)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
    }

    private func methodCard(title: String, body: String, dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.sageBold(15)).tracking(-0.2)
                .foregroundColor(Theme.textPrimary(dark))
            Text(body)
                .font(.sageRegular(13))
                .foregroundColor(Theme.textSecondary(dark))
                .lineSpacing(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface(dark))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
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
                Text("Sage combines public nutrition data (per-100g nutrients, ingredient-derived processing level, additive risk) into an Overall score, then tunes it to your goal and preferences to compute Your Score.")
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
