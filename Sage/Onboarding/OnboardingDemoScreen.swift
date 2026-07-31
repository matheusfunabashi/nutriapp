import SwiftUI

// MARK: - Act 4 · Live demo
//
// The payoff screen, and the only one that proves rather than claims. The
// user guesses a score, then sees the real engine's answer — Overall next
// to Your Score, with the gap attributed to the goals and avoid-list items
// they picked back in Act 1.
//
// Nothing here is hardcoded. The demo product is a candidate JSON blob run
// through `Alternatives.scored`, which is the exact path a real scan takes
// (`OpenFoodFactsService.mapCandidate` → `ScoringEngineV4.scoreProduct`),
// and the swap comes from `Alternatives.suggest` over the bundled shelves.
// That means it works offline, and it can never drift from the shipping
// ruleset — if scoring changes, this screen changes with it.

// MARK: Demo fixture

enum OnboardingDemoProduct {
    /// Real OFF product — Bear Naked Vanilla Almond Crisp
    /// (`0856416000710`). Markets as a clean whole-grain granola; the live
    /// engine still finds plenty to personalize on (added sugar for Blood
    /// sugar, fiber for Heart, NOVA 4 on Overall). Encoded as the same
    /// `AlternativeCandidate` JSON the bundled shelves use so offline
    /// scoring stays identical to a real scan.
    ///
    /// Snapshot of https://world.openfoodfacts.org/api/v2/product/0856416000710.json
    /// — keep the pack-shot asset in sync if the OFF front image rotates.
    private static let candidateJSON = """
    {
      "barcode": "0856416000710",
      "name": "Vanilla Almond Crisp",
      "brand": "Bear Naked",
      "image_url": "https://images.openfoodfacts.org/images/products/085/641/600/0710/front_en.71.400.jpg",
      "ingredients_text": "whole grain oats, brown rice syrup, almonds, dried cane syrup, oat bran, brown rice, natural flavors, ground flax seeds",
      "additives_tags": [],
      "nova_group": 4,
      "nutriscore_grade": "c",
      "categories_tags": [
        "en:plant-based-foods-and-beverages",
        "en:plant-based-foods",
        "en:breakfasts",
        "en:cereals-and-potatoes",
        "en:cereals-and-their-products",
        "en:breakfast-cereals",
        "en:mueslis"
      ],
      "labels_tags": ["en:no-gmos", "en:non-gmo-project"],
      "nutriments": {
        "energy-kcal_100g": 400,
        "sugars_100g": 13.46,
        "added-sugars_100g": 13.46,
        "sodium_100g": 0.288,
        "saturated-fat_100g": 1.92,
        "fiber_100g": 9.62,
        "proteins_100g": 11.54,
        "fruits-vegetables-nuts-estimate-from-ingredients_100g": 10.94
      }
    }
    """

    /// Decoded once — the JSON is a compile-time constant, so a failure here
    /// is a programmer error, not a runtime condition.
    static let candidate: AlternativeCandidate? = {
        guard let data = candidateJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AlternativeCandidate.self, from: data)
    }()

    /// Bundled OFF front image (`onboarding-demo-product` imageset). Falls
    /// back to the neutral bowl glyph if the asset is missing.
    static let imageAsset = "onboarding-demo-product"

    /// Scores the fixture against the profile built from the user's answers.
    @MainActor
    static func scored(for profile: UserProfile) -> Product? {
        guard let candidate else { return nil }
        return Alternatives.scored(candidate, profile: profile,
                                   ruleset: RulesetStore.current)?.product
    }
}

// MARK: Screen

struct OnboardingDemoScreen: View {
    let accent: Color
    /// Profile assembled from everything answered so far.
    let profile: UserProfile
    let onContinue: () -> Void

    @State private var product: Product?
    @State private var guess: Guess?
    @State private var showReveal = false

    enum Guess: String, CaseIterable, Identifiable {
        case clean, middling, avoid
        var id: String { rawValue }

        var label: String {
            switch self {
            case .clean:    return "Pretty clean"
            case .middling: return "Somewhere in the middle"
            case .avoid:    return "I'd avoid it"
            }
        }
        var symbol: String {
            switch self {
            case .clean:    return "checkmark.seal"
            case .middling: return "minus.circle"
            case .avoid:    return "exclamationmark.triangle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "Your turn",
                    subtitle: "Whole grain oats. Almonds. Non-GMO. How do you think it scores?"
                )
            }

            StaggeredAppear(index: 1) { productCard }

            StaggeredAppear(index: 2) {
                VStack(spacing: 10) {
                    ForEach(Guess.allCases) { option in
                        guessButton(option)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }

            Spacer()
        }
        .task {
            // Scoring reads the bundled ruleset; do it once when the step
            // appears rather than on every body evaluation.
            if product == nil {
                product = OnboardingDemoProduct.scored(for: profile)
            }
        }
        .sheet(isPresented: $showReveal) {
            if let product {
                OnboardingDemoRevealSheet(
                    product: product,
                    profile: profile,
                    accent: accent,
                    guess: guess,
                    onContinue: {
                        showReveal = false
                        onContinue()
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: showReveal)
    }

    private var productCard: some View {
        HStack(spacing: 14) {
            packShot
            VStack(alignment: .leading, spacing: 4) {
                Text(OnboardingDemoProduct.candidate?.brand ?? "Bear Naked")
                    .font(.sageSemiBold(12)).tracking(0.4)
                    .foregroundStyle(Theme.inkSecondary)
                Text(OnboardingDemoProduct.candidate?.name ?? "Vanilla Almond Crisp")
                    .font(.sageBold(17)).tracking(-0.3)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card)
        )
        .cardShadow()
        .padding(.horizontal, 20)
    }

    /// Bundled pack shot when the imageset exists, neutral glyph tile when it
    /// doesn't, so the screen looks finished either way.
    @ViewBuilder
    private var packShot: some View {
        if UIImage(named: OnboardingDemoProduct.imageAsset) != nil {
            Image(OnboardingDemoProduct.imageAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
        } else {
            ProductThumb(glyph: "🥣", score: nil, size: 64, neutral: true)
        }
    }

    private func guessButton(_ option: Guess) -> some View {
        Button {
            guess = option
            // Let the selection register before the sheet takes over.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showReveal = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.symbol)
                    .font(.sageSemiBold(15))
                    .foregroundStyle(accent)
                    .frame(width: 24)
                Text(option.label)
                    .font(.sageBold(15)).tracking(-0.2)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(guess == option ? accent : Color.black.opacity(0.08),
                            lineWidth: guess == option ? 2 : 1)
            )
        }
        .buttonStyle(.pressable)
        .disabled(product == nil)
        .opacity(product == nil ? 0.5 : 1)
    }
}

// MARK: Reveal sheet

/// The actual argument for Your Score: two numbers side by side, then the
/// reasons the personal one is lower, drawn from the caps and restrictions
/// the engine actually fired.
struct OnboardingDemoRevealSheet: View {
    let product: Product
    let profile: UserProfile
    let accent: Color
    let guess: OnboardingDemoScreen.Guess?
    let onContinue: () -> Void

    @State private var swap: Alternative?
    /// Prefetched so the button never has to score the cereal shelf on tap —
    /// that work was freezing the first press and making it feel like the
    /// button needed several clicks before anything appeared.
    @State private var pendingSwap: Alternative?
    @State private var swapReady = false

    private var overall: Int { product.overallScore ?? 0 }
    private var yours: Int { product.yourScore ?? overall }
    private var delta: Int { yours - overall }

    /// Which of the three honest outcomes we're in. Your Score genuinely can
    /// land above Overall — a low-sodium, low-saturated-fat product scores
    /// *better* for someone who picked the heart goal — and pretending
    /// otherwise would make the demo a lie the app later contradicts.
    private enum Verdict { case worse, level, better }
    private var verdict: Verdict {
        if delta <= -4 { return .worse }
        if delta >= 3 { return .better }
        return .level
    }

    /// Why Your Score differs, in the engine's own words. Prefers the caps
    /// that actually bound the score, then any fired restrictions, then the
    /// generic signed factors.
    private var reasons: [String] {
        var out: [String] = []
        if let binding = product.bindingCap {
            out.append("Capped at \(binding.value), because you asked us to flag \(binding.shortLabel).")
        }
        for cap in product.firedCaps ?? [] where cap.id != product.bindingCap?.id {
            out.append("Flagged: \(cap.shortLabel).")
        }
        for r in product.restrictions {
            out.append("Conflicts with your \(r.type) restriction (\(r.trigger)).")
        }
        if out.isEmpty {
            // No cap fired, so explain the shift with the drivers that moved
            // it — positive ones when the score went up.
            let wanted = verdict == .better ? "+ " : "- "
            out = ScoringEngine.signedFactors(product, profile: profile)
                .filter { $0.hasPrefix(wanted) }
                .map { String($0.dropFirst(2)).capitalizedFirst }
        }
        return Array(out.prefix(4))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                dials.padding(.top, 22)

                if !reasons.isEmpty {
                    reasonsCard.padding(.top, 24)
                }

                swapSection.padding(.top, 24)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 100)
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTAButton(title: "Got it", action: onContinue)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 20)
                .background(.regularMaterial)
        }
        .task {
            guard !swapReady else { return }
            pendingSwap = Self.bestSwap(for: product, profile: profile)
            swapReady = true
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(verdictLine)
                .font(.sageBold(24)).tracking(-0.6)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(subheadline)
                .font(.sageRegular(14))
                .lineSpacing(2)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
    }

    /// Reacts to the guess without ever telling the user they were wrong —
    /// the surprise should land on the product, not on them. When Your Score
    /// came out at or above Overall the copy has to change too, or the
    /// screen would imply a problem the numbers don't show.
    private var verdictLine: String {
        switch verdict {
        case .worse:
            return guess == .avoid ? "Good instincts." : "Not for you, it isn't."
        case .better:
            return "Better for you than it looks."
        case .level:
            return "This one clears your bar."
        }
    }

    private var subheadline: String {
        switch verdict {
        case .worse:
            return "Same granola. Same label. \(abs(delta)) points lower once we score it against what you told us."
        case .better:
            return "It lines up with what you're optimizing for, so it scores higher for you than it does in general."
        case .level:
            return "Nothing you flagged turned up in it, so your score tracks the general one."
        }
    }

    private var dials: some View {
        HStack(spacing: 14) {
            dial(label: "OVERALL", score: overall,
                 caption: "What everyone sees",
                 highlighted: false)
            dial(label: "YOUR SCORE", score: yours,
                 caption: delta == 0 ? "Tuned to you"
                                     : "\(delta > 0 ? "+" : "")\(delta) for you",
                 highlighted: true)
        }
    }

    private func dial(label: String, score: Int, caption: String,
                      highlighted: Bool) -> some View {
        VStack(spacing: 12) {
            Text(label)
                .font(.sageBold(11)).tracking(1.4)
                .foregroundStyle(highlighted ? accent : Theme.inkSecondary)

            ScoreRing(score: score, size: 92, stroke: 8,
                      ringColor: highlighted ? nil : Color.gray.opacity(0.55))

            Text(caption)
                .font(.sageSemiBold(11))
                .foregroundStyle(deltaColor(highlighted: highlighted))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(highlighted ? accent : Color.black.opacity(0.08),
                        lineWidth: highlighted ? 2 : 1)
        )
        .cardShadow()
    }

    private func deltaColor(highlighted: Bool) -> Color {
        guard highlighted, delta != 0 else { return Theme.inkSecondary }
        return delta < 0 ? Color.scoreBad : Color.scoreGood
    }

    private var reasonsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verdict == .better ? "WHY YOURS IS HIGHER" : "WHY YOURS IS DIFFERENT")
                .font(.sageBold(11)).tracking(1.4)
                .foregroundStyle(Theme.inkSecondary)

            ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: verdict == .better
                          ? "plus.circle.fill" : "minus.circle.fill")
                        .font(.sageRegular(13))
                        .foregroundStyle(verdict == .better ? Color.scoreGood : Color.scoreBad)
                    Text(reason)
                        .font(.sageRegular(14))
                        .lineSpacing(2)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card)
        )
        .cardShadow()
    }

    @ViewBuilder
    private var swapSection: some View {
        if let swap {
            VStack(alignment: .leading, spacing: 12) {
                Text("A BETTER ONE, SAME SHELF")
                    .font(.sageBold(11)).tracking(1.4)
                    .foregroundStyle(Theme.inkSecondary)

                HStack(spacing: 14) {
                    ProductThumb(glyph: "🥣", score: nil, size: 54, neutral: true,
                                 imageURL: swap.product.imageURL)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(swap.product.brand)
                            .font(.sageSemiBold(11)).tracking(0.4)
                            .foregroundStyle(Theme.inkSecondary)
                        Text(swap.product.name)
                            .font(.sageBold(15)).tracking(-0.2)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 2) {
                        Text("\(swap.score)")
                            .font(.sageBold(22)).monospacedDigit()
                            .foregroundStyle(Color.scoreGood)
                        Text("+\(swap.score - overall)")
                            .font(.sageBold(11)).monospacedDigit()
                            .foregroundStyle(Color.scoreGood)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card)
                )
                .cardShadow()
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if !swapReady {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if pendingSwap != nil {
            Button("Show me a better one", action: revealSwap)
                .font(.sageBold(15))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent.opacity(0.10))
                )
                .buttonStyle(.pressable)
        }
        // No pending swap → shelf can't beat this product; omit the button
        // rather than inventing one (same rule as the live Alternatives row).
    }

    /// Instant reveal — the heavy `Alternatives.suggest` work already ran in
    /// `.task`, so a single tap always shows the card.
    private func revealSwap() {
        guard let pendingSwap else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            swap = pendingSwap
        }
    }

    /// Pulls a real alternative off the bundled shelf, or nil when nothing
    /// clears the +10 margin.
    private static func bestSwap(for product: Product, profile: UserProfile) -> Alternative? {
        if case .suggestions(let list) = Alternatives.suggest(for: product, profile: profile) {
            return list.first
        }
        return nil
    }
}

private extension String {
    /// Sentence-cases an engine factor string ("high added sugar" → "High…").
    var capitalizedFirst: String {
        guard let f = first else { return self }
        return String(f).uppercased() + dropFirst()
    }
}
