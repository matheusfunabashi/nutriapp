import SwiftUI

struct MethodologyView: View {
    @EnvironmentObject var store: AppStore

    private var bands: RulesetV4.Bands { RulesetV4.bundled.bands }

    private var sections: [(title: String, body: String)] {
        [
            ("How the number is built",
             "Each product is routed to a category profile. Rules return a fraction from 0 to 1; the score is Σ(weight × fraction) / Σ(weight), floored at 10. Weights always sum to 100 for mental math and confidence. Your Score reweights rules for your goals, then may apply preference caps."),
            ("Bands",
             "\(bands.excellent)–100 Excellent · \(bands.good)–\(bands.excellent - 1) Good · \(bands.ok)–\(bands.good - 1) OK · 10–\(bands.ok - 1) Bad. The same cut points drive dials, badges, and Overview labels."),
            ("Caps",
             "Industrial trans fat (NOVA 4 or partially hydrogenated oil) caps Overall at 34. Free-sugar ceiling (34) still applies to foods with concentrated added sugar — candy in snacks, sugary drinks — but intrinsic dried-fruit sugar is exempt. Pure table sweeteners are not scored at all (see below), so the old NNS table-sweetener ceiling no longer applies to them. Your Score can be further limited by diet conflicts and avoid-list items; when several fire, the lowest wins."),
            ("Why sweeteners aren’t scored",
             "This is essentially pure sugar, and no concentrated sugar is a health food. Sage doesn't score sweeteners, so a number here would only mislead."),
            ("Whole foods",
             "Minimally processed produce (NOVA 1–2, no additives) gets a clean additive score even when the ingredient list is missing — single-ingredient foods often lack one. Fruits, vegetables, eggs, legumes, nuts, berries, and salads use a produce-focused nutrition blend."),
            ("Provisional scores",
             "When too much of the weighted profile rests on missing evidence, we mark the score provisional. Missing data lowers confidence; it does not invent numbers."),
        ]
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A health score, not an ethics score")
                        .font(.sageBold(22)).tracking(-0.5)
                        .foregroundColor(Theme.ink)
                    Text("Sage measures health only. Packaging, certifications, animal welfare, and origin claims are out of the score unless they have a direct health pathway (for example brew-bag microplastics or arsenic risk in rice drinks).")
                        .font(.sageRegular(14))
                        .foregroundColor(Theme.inkSecondary)
                        .lineSpacing(2)
                }
                .padding(.vertical, 6)
            }
            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    Text(section.body)
                        .font(.sageRegular(13))
                        .foregroundColor(Theme.inkSecondary)
                        .lineSpacing(2)
                }
            }
        }
        .sageListStyle()
        .navigationTitle("How we score")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Methodology sheet

/// The "how we score" primer, as a real sheet with a detent instead of a
/// hand-drawn dimming layer — so it gets the grabber, the swipe-to-dismiss,
/// and the system's own presentation animation.
struct MethodologySheet: View {
    @EnvironmentObject var store: AppStore
    let onDismiss: () -> Void
    let onLearnMore: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sage combines public nutrition data (per-100g nutrients, ingredient-derived processing level, additive risk) into an Overall score, then tunes it to your goal and preferences to compute Your Score.")
                    .font(.sageRegular(15))
                    .foregroundColor(Theme.inkSecondary)
                    .lineSpacing(3)
                Spacer()
                Button("Learn more", action: onLearnMore)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
            .sageScreenBackground()
            .navigationTitle("How we score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Got it", action: onDismiss)
                }
            }
        }
        .tint(store.accent)
    }
}

// MARK: - First-launch disclaimer

struct DisclaimerSheet: View {
    @EnvironmentObject var store: AppStore
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            SageMark(size: 44, color: store.accent)
            Text("Sage is informational, not advice")
                .font(.sageBold(22)).tracking(-0.5)
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.ink)
            Text("Scores are a guide, not medical or professional nutrition advice. For specific dietary needs, please consult a registered dietitian or doctor.")
                .font(.sageRegular(15))
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.inkSecondary)
                .lineSpacing(3)
            Spacer()
            Button("I understand", action: onAcknowledge)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(store.accent)
                .frame(maxWidth: .infinity)
        }
        .padding(28)
        .sageScreenBackground()
    }
}
