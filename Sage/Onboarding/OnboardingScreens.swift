import SwiftUI

// MARK: - 1. Welcome

struct OnboardingWelcomeScreen: View {
    let accent: Color
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                HStack(spacing: 8) {
                    SageMark(size: 26, color: accent)
                    Text("Sage")
                        .font(.sageBold(22)).tracking(-0.6)
                        .foregroundColor(Theme.ink)
                }
                // 12pt above the safe-area inset — see OnboardingHeader.
                .padding(.top, 12)
                .padding(.bottom, 8)
            }

            Spacer().frame(height: 12)

            StaggeredAppear(index: 1) {
                OnboardingHeroImage(
                    assetName: OnboardingAssets.welcomeHero,
                    scale: 1.0,
                    horizontalPadding: 12
                )
                .frame(height: 320)
            }

            Spacer().frame(height: 36)

            StaggeredAppear(index: 2) {
                Text("Know exactly\nwhat's inside.")
                    .font(.sageBold(34)).tracking(-1)
                    .foregroundColor(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }

            StaggeredAppear(index: 3) {
                // Markdown bolds "your" without needing Text concatenation.
                Text("Scan any label. We translate every additive into plain language and score it for **your** body.")
                    .font(.sageRegular(15))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.inkSecondary)
                    .padding(.horizontal, 36)
                    .padding(.top, 10)
            }

            StaggeredAppear(index: 4) {
                statsRow.padding(.top, 22)
            }

            Spacer()

            StaggeredAppear(index: 5) {
                OnboardingCTAButton(title: "Get Started", action: onContinue)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            Spacer()
            stat(big: "4.9★", small: "App Store")
            Spacer()
            stat(big: "1.2M", small: "products")
            Spacer()
        }
        .padding(.horizontal, 36)
    }

    private func stat(big: String, small: String) -> some View {
        VStack(spacing: 2) {
            // Stat numbers benefit from tabular figures so the three columns
            // align even if the strings ever change (e.g. "500K+").
            Text(big)
                .font(.sageBold(18)).tracking(-0.4).monospacedDigit()
                .foregroundColor(Theme.ink)
            Text(small)
                .font(.sageRegular(12))
                .foregroundColor(Theme.inkSecondary)
        }
    }
}

// MARK: - 2. Marketing

struct OnboardingMarketingScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "What's marketed as\nhealthy often isn't",
                    subtitle: "Labels and marketing hide what's really in your food. “Natural,” “healthy,” and “lightly sweetened” aren't regulated."
                )
            }

            StaggeredAppear(index: 1) {
                OnboardingHeroImage(
                    assetName: OnboardingAssets.marketingHero,
                    scale: 1.0,
                    horizontalPadding: 12
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - 3. Two scores

// The pivot of the whole flow: this is the one thing Sage does that the
// competitors don't. It runs *after* the goals/avoids steps so the
// deduction rows can name the user's own picks — the difference between
// "we personalize scores" and "here is your personalization".

struct OnboardingScoresScreen: View {
    let accent: Color
    let goals: Set<String>
    let avoids: Set<String>

    /// Up to three deductions, phrased against what the user actually
    /// chose. Falls back to representative examples when they picked
    /// nothing (only reachable if goals were somehow skipped).
    private var deductions: [(delta: Int, ingredient: String, reason: String)] {
        var rows: [(Int, String, String)] = []

        // Avoid-list entries are the most legible: the user named the exact
        // ingredient, so we can show it being caught.
        for item in avoids.sorted().prefix(2) {
            rows.append((-12, "Contains \(item.lowercased())", "You asked us to flag this"))
        }

        // Goals re-weight rather than cap, so they read as softer nudges.
        for goal in goals.sorted() where rows.count < 3 {
            switch goal {
            case "Less sugar", "Blood sugar":
                rows.append((-9, "28g added sugar", "Weighs heavier when you care about sugar"))
            case "Less processed":
                rows.append((-8, "Ultra-processed", "Weighs heavier for cleaner labels"))
            case "More protein":
                rows.append((-5, "Low protein density", "Weighs heavier when you want protein"))
            case "Heart health", "Heart":
                rows.append((-7, "660mg sodium", "Weighs heavier for heart health"))
            case "Just keep it clean":
                rows.append((-6, "Long additive list", "Light nudge toward cleaner food"))
            case "Gut health":
                rows.append((-6, "Emulsifiers", "Weighs heavier for gut health"))
            case "Pregnancy":
                rows.append((-8, "Caffeine", "Tighter limit during pregnancy"))
            case "Young child":
                rows.append((-8, "Artificial colors", "Flagged for young children"))
            default:
                break
            }
        }

        if rows.isEmpty {
            rows = [(-8, "Contains Yellow 5", "You avoid dyes"),
                    (-6, "Sucralose", "Flagged for your goal"),
                    (-4, "Maltodextrin", "Affects blood sugar")]
        }
        return Array(rows.prefix(3)).map { (delta: $0.0, ingredient: $0.1, reason: $0.2) }
    }

    /// Your Score falls by the deductions we're showing, so the two dials
    /// and the rows underneath always add up.
    private var yourScore: Int { max(0, 72 + deductions.reduce(0) { $0 + $1.delta }) }

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "Two scores, not one",
                    subtitle: "Everyone sees the same Overall score. Only you see Your Score: the same product, re-scored against what you just told us."
                )
            }

            StaggeredAppear(index: 1) {
                HStack(spacing: 14) {
                    scoreCard(label: "OVERALL", score: 72, footnote: "What everyone sees",
                              highlighted: false)
                    Image(systemName: "arrow.right")
                        .font(.sageBold(14))
                        .foregroundColor(Theme.inkSecondary)
                    scoreCard(label: "YOUR SCORE", score: yourScore, footnote: "Tuned to you",
                              highlighted: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
            }

            StaggeredAppear(index: 2) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(deductions.enumerated()), id: \.offset) { _, row in
                        reasonRow(delta: row.delta,
                                  ingredient: row.ingredient,
                                  reason: row.reason)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.card)
                )
                .cardShadow()
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }

            Spacer()
        }
    }

    private func scoreCard(label: String, score: Int, footnote: String,
                            highlighted: Bool) -> some View {
        // Both cards carry a stroke — non-highlighted gets a hairline
        // neutral border so it doesn't read as visually lighter than the
        // highlighted "Your Score" card, which keeps its 2pt accent ring.
        let borderColor: Color = highlighted ? accent : Theme.hairline
        let borderWidth: CGFloat = highlighted ? 2 : 1

        return VStack(spacing: 12) {
            Text(label)
                .font(.sageBold(11)).tracking(1.4)
                .foregroundColor(highlighted ? accent : Theme.inkSecondary)

            // Shared ring — same component the product detail uses, so the
            // band colors here always match what a real scan will show.
            ScoreRing(score: score, size: 86, stroke: 8,
                      ringColor: highlighted ? nil : Color.gray.opacity(0.55))

            Text(footnote)
                .font(.sageRegular(11))
                .foregroundColor(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .cardShadow()
    }

    /// Deduction row: a red pill for the delta on the left, the ingredient
    /// on the right with a subtle "why" tag underneath.
    private func reasonRow(delta: Int, ingredient: String,
                            reason: String) -> some View {
        let red = Color.scoreBad
        return HStack(alignment: .top, spacing: 12) {
            Text("\(delta)")
                .font(.sageBold(13)).monospacedDigit()
                .foregroundColor(red)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(red.opacity(0.12)))

            VStack(alignment: .leading, spacing: 6) {
                Text(ingredient)
                    .font(.sageBold(14)).tracking(-0.2)
                    .foregroundColor(Theme.ink)
                Text(reason)
                    .font(.sageSemiBold(11))
                    .foregroundColor(Theme.inkSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.hairline))
            }
            Spacer(minLength: 0)
        }
    }

}

// MARK: - 4. Alternatives

struct OnboardingAlternativesScreen: View {
    struct Alternative: Identifiable {
        let id = UUID()
        /// Asset-catalog image name. If the image doesn't exist in the
        /// bundle yet, the card falls back to rendering `glyph`.
        let imageAsset: String
        /// Emoji fallback — used until `imageAsset` is added to
        /// `Assets.xcassets`, and on any future render error.
        let glyph: String
        let title: String
        let score: Int
    }

    let accent: Color

    private let items: [Alternative] = [
        .init(imageAsset: "alt-yogurt",          glyph: "🥛", title: "Greek Yogurt",    score: 96),
        .init(imageAsset: "alt-sparkling-water", glyph: "🫧", title: "Sparkling Water", score: 92),
        .init(imageAsset: "alt-nut-butter",      glyph: "🥜", title: "Peanut Butter",      score: 95),
        .init(imageAsset: "alt-protein-bar",     glyph: "🍫", title: "Protein Bars",    score: 84),
        .init(imageAsset: "alt-cooking-oil",     glyph: "🫒", title: "Cooking Oils",    score: 98),
        .init(imageAsset: "alt-crackers",        glyph: "🍪", title: "Crackers",        score: 81)
    ]

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "Discover the healthiest\nalternatives",
                    subtitle: "Instantly find the cleanest option in every category with scores ranked for you."
                )
            }

            StaggeredAppear(index: 1) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12),
                              GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(items) { item in
                        alternativeCard(item)
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer()
        }
    }

    /// Vertical card layout: title up top, score ring bottom-left,
    /// product image slot bottom-right. The image slot currently renders
    /// the category emoji at large size — swap for `AsyncImage` or a
    /// bundled asset when product art lands.
    private func alternativeCard(_ item: Alternative) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.sageBold(15)).tracking(-0.3)
                .foregroundColor(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
                .frame(maxHeight: 6)

            HStack(alignment: .center, spacing: 0) {
                ringBadge(score: item.score)
                Spacer(minLength: 0)
                imageSlot(item)
            }
            .offset(y: -6)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(height: 128, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.card)
        )
        .cardShadow()
    }

    /// Slot reserved for the product image. Tries the bundled illustration
    /// in `Assets.xcassets`; if that asset isn't present yet, gracefully
    /// falls back to the category emoji so the screen never shows a
    /// broken/missing-image box.
    ///
    /// No backing tile — the image (or emoji) sits directly on the card
    /// surface so it reads as a product, not a chip.
    private func imageSlot(_ item: Alternative) -> some View {
        Group {
            if UIImage(named: item.imageAsset) != nil {
                Image(item.imageAsset)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(item.glyph).font(.sageRegular(34))
            }
        }
        .frame(width: 70, height: 70)
    }

    private func ringBadge(score: Int) -> some View {
        ZStack {
            Circle().stroke(Theme.ringTrack, lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.sageBold(14)).monospacedDigit()
                .foregroundColor(accent)
        }
        .frame(width: 46, height: 46)
    }
}

// MARK: - 6d. Dietary restrictions + preferences
//
// Competitor-style 2-column pill grid (icon + label). Visually one "select
// your preferences" surface; under the hood each chip still writes into
// either `restrictions` (hard flags) or `preferences` (soft score nudges)
// so Profile › Dietary stays the source of truth later.

struct OnboardingDietaryRestrictionsScreen: View {
    let accent: Color
    @Binding var restrictions: Set<String>
    @Binding var preferences: Set<String>

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var selectionFingerprint: Int {
        restrictions.hashValue ^ preferences.hashValue
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                StaggeredAppear(index: 0) {
                    OnboardingTitle(
                        title: "Select your\npreferences",
                        subtitle: "Hard rules get flagged on every scan. Soft preferences only nudge Your Score."
                    )
                    .padding(.horizontal, 20)
                }

                StaggeredAppear(index: 1) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(DietaryOptions.onboardingChips) { chip in
                            preferencePill(chip)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }

                Spacer(minLength: 24)
            }
            .padding(.bottom, 16)
        }
        .sensoryFeedback(.selection, trigger: selectionFingerprint)
    }

    private func preferencePill(_ chip: DietaryOptions.Chip) -> some View {
        let selected = isSelected(chip)
        return Button {
            toggle(chip)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: chip.symbol)
                    .font(.sageSemiBold(13))
                    .foregroundStyle(selected ? accent : Theme.inkSecondary)
                    .frame(width: 18, alignment: .center)
                Text(chip.id)
                    .font(.sageSemiBold(13)).tracking(-0.2)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? accent.opacity(0.10) : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? accent : Color.black.opacity(0.08),
                            lineWidth: selected ? 1.5 : 1)
            )
            .cardShadow()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(chip.id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func isSelected(_ chip: DietaryOptions.Chip) -> Bool {
        switch chip.kind {
        case .restriction: return restrictions.contains(chip.id)
        case .preference:  return preferences.contains(chip.id)
        }
    }

    private func toggle(_ chip: DietaryOptions.Chip) {
        switch chip.kind {
        case .restriction:
            if restrictions.contains(chip.id) { restrictions.remove(chip.id) }
            else { restrictions.insert(chip.id) }
        case .preference:
            if preferences.contains(chip.id) { preferences.remove(chip.id) }
            else { preferences.insert(chip.id) }
        }
    }
}

// MARK: - 6e. Allergens
//
// Same 2-column pill grid as the preferences step. Labels stay in sync with
// `OnboardingAllergenOptions.presets` / Profile › Dietary.

struct OnboardingAllergensScreen: View {
    let accent: Color
    @Binding var allergies: [String]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                StaggeredAppear(index: 0) {
                    OnboardingTitle(
                        title: "Any allergies or\nintolerances?",
                        subtitle: "We'll warn you whenever a scanned product may contain these."
                    )
                    .padding(.horizontal, 20)
                }

                StaggeredAppear(index: 1) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(OnboardingAllergenOptions.chips) { chip in
                            allergenPill(chip)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }

                StaggeredAppear(index: 2) {
                    Label("Ingredient data can be incomplete, so always check the packaging.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.sageRegular(12))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }

                Spacer(minLength: 24)
            }
            .padding(.bottom, 16)
        }
        .sensoryFeedback(.selection, trigger: allergies)
    }

    private func allergenPill(_ chip: OnboardingAllergenOptions.Chip) -> some View {
        let selected = isSelected(chip.id)
        return Button {
            toggleAllergen(chip.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: chip.symbol)
                    .font(.sageSemiBold(13))
                    .foregroundStyle(selected ? accent : Theme.inkSecondary)
                    .frame(width: 18, alignment: .center)
                Text(chip.id)
                    .font(.sageSemiBold(13)).tracking(-0.2)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? accent.opacity(0.10) : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? accent : Color.black.opacity(0.08),
                            lineWidth: selected ? 1.5 : 1)
            )
            .cardShadow()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(chip.id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func isSelected(_ label: String) -> Bool {
        allergies.contains { $0.caseInsensitiveCompare(label) == .orderedSame }
    }

    private func toggleAllergen(_ label: String) {
        if let idx = allergies.firstIndex(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
            allergies.remove(at: idx)
        } else {
            allergies.append(label)
        }
    }
}

// MARK: - 7. Reviews

struct OnboardingReviewsScreen: View {
    struct Review: Identifiable {
        let id = UUID()
        let initial: String
        let name: String
        let location: String
        let body: String
        let color: Color
    }

    private let reviews: [Review] = [
        .init(initial: "F", name: "Felipe",   location: "Miami, FL",
              body: "\"I scanned my whole pantry and the scores were genuinely shocking. Threw out half my snacks.\"",
              color: Color(hex: "1F8A5B")),
        .init(initial: "E", name: "Enrico",  location: "Seattle, WA",
              body: "\"Finally an app that adjusts the score for pregnancy. Caught additives I'd never have spotted.\"",
              color: Color(hex: "6E5AC6")),
        .init(initial: "M", name: "Matthew", location: "Denver, CO",
              body: "\"The 'Your Score' vs overall thing is brilliant. It actually knows what I care about.\"",
              color: Color(hex: "C95A2B"))
    ]

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                VStack(spacing: 12) {
                    Text("Loved by clean eaters")
                        .font(.sageBold(28)).tracking(-0.7)
                        .foregroundColor(Theme.ink)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 8) {
                        Text("4.9")
                            .font(.sageBold(30)).monospacedDigit()
                            .foregroundColor(Theme.ink)
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.sageRegular(14))
                                    .foregroundColor(Color(hex: "D4A02D"))
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }

            VStack(spacing: 12) {
                ForEach(Array(reviews.enumerated()), id: \.element.id) { idx, r in
                    // Per-card stagger so the three reviews cascade in.
                    StaggeredAppear(index: idx + 1) { reviewCard(r) }
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
    }

    private func reviewCard(_ r: Review) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.sageRegular(12))
                        .foregroundColor(Color(hex: "D4A02D"))
                }
            }
            Text(r.body)
                .font(.sageRegular(14))
                .foregroundColor(Theme.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(r.color).frame(width: 30, height: 30)
                    Text(r.initial)
                        .font(.sageBold(13))
                        .foregroundColor(.white)
                }
                Text(r.name)
                    .font(.sageBold(13))
                    .foregroundColor(Theme.ink)
                Text("· \(r.location)")
                    .font(.sageRegular(12))
                    .foregroundColor(Theme.inkSecondary)
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card)
        )
        .cardShadow()
    }
}

// MARK: - 10. Loading

struct OnboardingLoadingScreen: View {
    let accent: Color
    let onComplete: () -> Void

    @State private var percent: Int = 0
    @State private var completedCount: Int = 0
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private let lines: [String] = [
        "Personalizing your scoring model",
        "Loading 1.2M product database",
        "Activating ingredient flags",
        "Calibrating Your Score"
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            StaggeredAppear(index: 0) {
                Text("\(percent)%")
                    .font(.sageBold(88)).monospacedDigit()
                    .foregroundColor(Theme.ink)
            }

            StaggeredAppear(index: 1) {
                Text("Building your Sage")
                    .font(.sageBold(18)).tracking(-0.3)
                    .foregroundColor(Theme.ink)
                    .padding(.top, 4)
            }

            StaggeredAppear(index: 2) {
                ProgressView(value: Double(percent), total: 100)
                    .progressViewStyle(.linear)
                    .tint(accent)
                    .animation(.linear(duration: 0.05), value: percent)
                    .padding(.horizontal, 32).padding(.top, 32)
                    .accessibilityLabel("Setup progress")
            }

            StaggeredAppear(index: 3) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        loadingRow(line: line, isComplete: idx < completedCount)
                    }
                }
                .padding(.horizontal, 32).padding(.top, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
            Spacer()
        }
        .onReceive(timer) { _ in tick() }
    }

    /// Cross-faded indicator: the empty ring and the filled check live in the
    /// same ZStack so toggling `isComplete` morphs them with a spring rather
    /// than snapping one out and the other in.
    private func loadingRow(line: String, isComplete: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Theme.inkSecondary.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                    .opacity(isComplete ? 0 : 1)
                    .scaleEffect(isComplete ? 0.7 : 1)
                ZStack {
                    Circle().fill(accent).frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.sageBold(11))
                        .foregroundColor(.white)
                }
                .opacity(isComplete ? 1 : 0)
                .scaleEffect(isComplete ? 1 : 0.6)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isComplete)

            Text(line)
                .font(.sageSemiBold(15))
                .foregroundColor(isComplete
                                 ? Theme.ink
                                 : Theme.inkSecondary)
                .animation(.easeOut(duration: 0.2), value: isComplete)
        }
    }

    private func tick() {
        guard percent < 100 else { return }
        percent += 1

        // Reveal check marks at 25/50/75/100.
        let target = min(lines.count, percent / 25 + (percent % 25 == 0 ? 0 : 1))
        if target > completedCount {
            withAnimation(.easeOut(duration: 0.2)) { completedCount = target }
        }

        if percent == 100 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                onComplete()
            }
        }
    }
}

// MARK: - 11. Results

struct OnboardingResultsScreen: View {
    let accent: Color
    let dietaryRestrictions: Set<String>
    let foodPreferences: Set<String>
    let healthGoals: Set<String>
    let avoidList: Set<String>
    let onStart: () -> Void

    private let bg = OnboardingInverted.background
    private let surface = OnboardingInverted.surface

    /// Pair each "watched" item with whether it's currently active for
    /// this user (we light up the ones they picked during onboarding).
    /// Act 1's goals and avoid-list lead, since those are the answers that
    /// actually drive Your Score.
    private var watchedItems: [(title: String, isOn: Bool)] {
        var rows: [(String, Bool)] = []

        for goal in healthGoals.sorted() {
            rows.append((goal, true))
        }
        for avoid in avoidList.sorted() {
            rows.append((avoid, true))
        }

        rows.append(contentsOf: [
            ("Low added sugar",
             dietaryRestrictions.contains("Low-sugar diet")),
            ("Low sodium",
             dietaryRestrictions.contains("Low-sodium diet")),
            ("High protein", foodPreferences.contains("High protein")),
            ("Gluten-free", dietaryRestrictions.contains("Gluten-free")),
            ("Minimally processed", foodPreferences.contains("Minimally processed")),
        ])

        // Anything already covered by an Act 1 pick would read as a
        // duplicate row, so drop the later generic version.
        var seen = Set<String>()
        return rows.compactMap { title, isOn in
            guard seen.insert(title.lowercased()).inserted else { return nil }
            return (title: title, isOn: isOn)
        }
    }

    /// Forward-looking close. Ends the flow on momentum rather than on a
    /// static number — the single most-copied idea from the competitor
    /// results screens.
    private let plan: [(week: String, title: String, blurb: String, symbol: String)] = [
        ("This week", "Just look",
         "Scan what's already in your kitchen. Nothing to change yet. You're building a baseline.",
         "play.circle.fill"),
        ("Week 2", "Start swapping",
         "Replace two or three staples with the better version of the same thing.",
         "arrow.triangle.swap"),
        ("Week 3", "Read on instinct",
         "You'll start clocking seed oils and dyes before you've opened the app.",
         "eye.fill"),
        ("Week 4", "It's just how you shop",
         "Cleaner picks stop feeling like work and start feeling like defaults.",
         "checkmark.seal.fill"),
    ]

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 16pt above the safe-area inset — the ScrollView and
                    // its ZStack parent both respect the inset, so this is
                    // the only gap we want under the Dynamic Island.
                    Spacer().frame(height: 16)

                    StaggeredAppear(index: 0) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Here's where you stand")
                                .font(.sageBold(28)).tracking(-0.6)
                                .foregroundColor(.white)
                            Text("Based on your goals, here's a rough sense of where a typical pantry starts — and where Sage users land after a few weeks.")
                                .font(.sageRegular(15))
                                .foregroundColor(Color.white.opacity(0.65))
                                .lineSpacing(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                    }

                    StaggeredAppear(index: 1) {
                        statsCard
                            .padding(.horizontal, 16).padding(.top, 20)
                    }

                    // The plan leads: it's the forward-looking half, and it
                    // reads better right after the score comparison than the
                    // settings-like checklist does.
                    StaggeredAppear(index: 2) {
                        Text("YOUR FIRST 30 DAYS")
                            .font(.sageBold(11)).tracking(1.4)
                            .foregroundColor(Color.white.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 10)
                    }

                    StaggeredAppear(index: 3) {
                        planCard.padding(.horizontal, 16)
                    }

                    StaggeredAppear(index: 4) {
                        Text("WE'LL WATCH FOR")
                            .font(.sageBold(11)).tracking(1.4)
                            .foregroundColor(Color.white.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 8)
                    }

                    StaggeredAppear(index: 5) {
                        VStack(spacing: 0) {
                            ForEach(Array(watchedItems.enumerated()), id: \.offset) { idx, item in
                                watchedRow(title: item.title, isOn: item.isOn)
                                if idx < watchedItems.count - 1 {
                                    Rectangle().fill(Color.white.opacity(0.06))
                                        .frame(height: 1)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer().frame(height: 100)
                }
            }

            VStack {
                Spacer()
                OnboardingCTAButton(title: "Start scanning", action: onStart)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36)
            }
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(plan.enumerated()), id: \.offset) { idx, step in
                HStack(alignment: .top, spacing: 14) {
                    // Connector rail: the dot marks the step, the line ties
                    // it to the next one so the four rows read as a path.
                    VStack(spacing: 0) {
                        Image(systemName: step.symbol)
                            .font(.sageSemiBold(13))
                            .foregroundColor(idx == 0 ? accent : Color.white.opacity(0.5))
                            .frame(width: 26, height: 26)
                            .background(
                                Circle().fill(idx == 0 ? accent.opacity(0.18)
                                                       : Color.white.opacity(0.06))
                            )
                        if idx < plan.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 1.5)
                                .frame(maxHeight: .infinity)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(step.week) · \(step.title)")
                            .font(.sageBold(14)).tracking(-0.2)
                            .foregroundColor(.white)
                        Text(step.blurb)
                            .font(.sageRegular(13))
                            .lineSpacing(2)
                            .foregroundColor(Color.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, idx < plan.count - 1 ? 18 : 0)

                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(surface)
        )
    }

    private var statsCard: some View {
        VStack(spacing: 14) {
            statRow(title: "Your pantry today", score: 53,
                    color: Color(hex: "D4A02D"))
            statRow(title: "Avg Sage user (30 days)", score: 88,
                    color: Color(hex: "3FBF7B"))
            Text("Illustrative estimate — not your actual pantry.")
                .font(.sageRegular(11))
                .foregroundColor(Color.white.opacity(0.40))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(surface)
        )
    }

    private func statRow(title: String, score: Int, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.sageBold(14))
                    .foregroundColor(.white)
                Spacer()
                HStack(spacing: 2) {
                    Text("\(score)")
                        .font(.sageBold(18)).monospacedDigit()
                        .foregroundColor(color)
                    Text("/100")
                        .font(.sageBold(12)).monospacedDigit()
                        .foregroundColor(color.opacity(0.6))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * CGFloat(score) / 100)
                }
            }
            .frame(height: 7)
        }
    }

    private func watchedRow(title: String, isOn: Bool) -> some View {
        HStack(spacing: 14) {
            // Static results screen, but keep the morph pattern consistent
            // with the rest of the onboarding so values flow smoothly if a
            // future iteration toggles them.
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 22, height: 22)
                    .opacity(isOn ? 0 : 1)
                ZStack {
                    Circle().fill(accent).frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.sageBold(11))
                        .foregroundColor(.white)
                }
                .opacity(isOn ? 1 : 0)
                .scaleEffect(isOn ? 1 : 0.7)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.7), value: isOn)

            Text(title)
                .font(isOn ? .sageBold(15) : .sageSemiBold(15))
                .foregroundColor(isOn ? .white : Color.white.opacity(0.55))
            Spacer()
            if isOn {
                Text("ON")
                    .font(.sageBold(11)).tracking(1.2)
                    .foregroundColor(accent)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.vertical, 16)
    }
}
