import SwiftUI

// MARK: - 1. Welcome

struct OnboardingWelcomeScreen: View {
    let dark: Bool
    let accent: Color
    let onContinue: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                HStack(spacing: 8) {
                    SageMark(size: 26, color: accent)
                    Text("Sage")
                        .font(.system(size: 22, weight: .heavy)).tracking(-0.6)
                        .foregroundColor(Theme.textPrimary(dark))
                }
                .padding(.top, 60)
                .padding(.bottom, 8)
            }

            Spacer().frame(height: 20)

            StaggeredAppear(index: 1) {
                PhoneShowcase(dark: dark, accent: accent)
            }

            Spacer().frame(height: 28)

            StaggeredAppear(index: 2) {
                Text("Know exactly\nwhat's inside.")
                    .font(.system(size: 34, weight: .heavy)).tracking(-1)
                    .foregroundColor(Theme.textPrimary(dark))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            StaggeredAppear(index: 3) {
                // Markdown bolds "your" without needing Text concatenation.
                Text("Scan any label. We translate every additive into plain language and score it for **your** body.")
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.textSecondary(dark))
                    .padding(.horizontal, 36)
                    .padding(.top, 10)
            }

            StaggeredAppear(index: 4) {
                statsRow.padding(.top, 22)
            }

            Spacer()

            StaggeredAppear(index: 5) {
                VStack(spacing: 0) {
                    OnboardingCTAButton(title: "Get Started", dark: dark, action: onContinue)
                        .padding(.horizontal, 20)
                    Button(action: onSignIn) {
                        (Text("Already have an account? ")
                            .foregroundColor(Theme.textSecondary(dark))
                        + Text("Sign in").foregroundColor(Theme.textPrimary(dark)).fontWeight(.heavy))
                            .font(.system(size: 14))
                            .padding(.vertical, 10) // bigger tap surface
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat(big: "400K+", small: "scanners")
            Spacer()
            stat(big: "4.9★", small: "App Store")
            Spacer()
            stat(big: "1.2M", small: "products")
        }
        .padding(.horizontal, 36)
    }

    private func stat(big: String, small: String) -> some View {
        VStack(spacing: 2) {
            // Stat numbers benefit from tabular figures so the three columns
            // align even if the strings ever change (e.g. "500K+").
            Text(big)
                .font(.system(size: 18, weight: .heavy)).tracking(-0.4).monospacedDigit()
                .foregroundColor(Theme.textPrimary(dark))
            Text(small)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary(dark))
        }
    }
}

// MARK: - 2. Marketing

struct OnboardingMarketingScreen: View {
    let dark: Bool
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "What's marketed as\nhealthy often isn't",
                    subtitle: "Labels and marketing hide what's really in your food. “Natural,” “healthy,” and “lightly sweetened” aren't regulated.",
                    dark: dark
                )
            }

            Spacer()
            StaggeredAppear(index: 1) {
                PhoneShowcase(dark: dark, accent: accent)
            }
            Spacer()
        }
    }
}

// MARK: - 3. Two scores

struct OnboardingScoresScreen: View {
    let dark: Bool
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "Two scores, not one",
                    subtitle: "Everyone sees the same Overall score. But Sage also gives you Your Score — recalculated from your goals, age, and body.",
                    dark: dark
                )
            }

            StaggeredAppear(index: 1) {
                HStack(spacing: 14) {
                    scoreCard(label: "OVERALL", score: 72, footnote: "The public score",
                              highlighted: false)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(Theme.textSecondary(dark))
                    scoreCard(label: "YOUR SCORE", score: 58, footnote: "Tuned to you",
                              highlighted: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
            }

            StaggeredAppear(index: 2) {
                VStack(alignment: .leading, spacing: 12) {
                    reasonRow(delta: -8, text: "Contains Yellow 5 — you avoid dyes")
                    reasonRow(delta: -6, text: "Sucralose — flagged for your goals")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.surface(dark))
                )
                .cardShadow(dark)
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }

            Spacer()
        }
    }

    private func scoreCard(label: String, score: Int, footnote: String,
                            highlighted: Bool) -> some View {
        let ring = highlighted ? Color(hex: "D4A02D") : Color.gray.opacity(0.55)
        return VStack(spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .heavy)).tracking(1.4)
                .foregroundColor(highlighted ? accent : Theme.textSecondary(dark))

            ZStack {
                Circle()
                    .stroke(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                            lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(ring, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(.system(size: 28, weight: .heavy)).monospacedDigit()
                    .foregroundColor(Theme.textPrimary(dark))
            }
            .frame(width: 86, height: 86)

            Text(footnote)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary(dark))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(highlighted ? accent : Color.clear, lineWidth: 2)
        )
        .cardShadow(dark)
    }

    private func reasonRow(delta: Int, text: String) -> some View {
        HStack(spacing: 14) {
            Text("\(delta)")
                .font(.system(size: 15, weight: .heavy)).monospacedDigit()
                .foregroundColor(Color(hex: "C9442B"))
                .frame(width: 32, alignment: .leading)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textPrimary(dark))
            Spacer()
        }
    }
}

// MARK: - 4. Alternatives

struct OnboardingAlternativesScreen: View {
    struct Alternative: Identifiable {
        let id = UUID()
        let glyph: String
        let title: String
        let score: Int
    }

    let dark: Bool
    let accent: Color

    private let items: [Alternative] = [
        .init(glyph: "🥛", title: "Greek Yogurt", score: 96),
        .init(glyph: "🫧", title: "Sparkling Water", score: 92),
        .init(glyph: "🥜", title: "Nut Butter",     score: 95),
        .init(glyph: "🍫", title: "Protein Bars",   score: 84),
        .init(glyph: "🫒", title: "Cooking Oils",   score: 98),
        .init(glyph: "🍪", title: "Crackers",       score: 81)
    ]

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "Discover the healthiest\nalternatives",
                    subtitle: "Instantly find the cleanest option in every category — ranked for you.",
                    dark: dark
                )
            }

            StaggeredAppear(index: 1) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12),
                              GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            Text(item.glyph).font(.system(size: 22))
                            Text(item.title)
                                .font(.system(size: 14, weight: .heavy)).tracking(-0.2)
                                .foregroundColor(Theme.textPrimary(dark))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            miniRing(score: item.score)
                        }
                        .padding(.vertical, 14).padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Theme.surface(dark))
                        )
                        .cardShadow(dark)
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer()
        }
    }

    private func miniRing(score: Int) -> some View {
        ZStack {
            Circle()
                .stroke(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07),
                        lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                .foregroundColor(accent)
        }
        .frame(width: 38, height: 38)
    }
}

// MARK: - 5. Preferences (multi-select)

struct OnboardingPreferencesScreen: View {
    let dark: Bool
    let accent: Color
    @Binding var selection: Set<HealthPreference>

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "What matters most\nto you?",
                    subtitle: "We'll flag any ingredient that conflicts — and weight Your Score around these.",
                    dark: dark
                )
            }

            StaggeredAppear(index: 1) {
                OnboardingEyebrow(text: "Select all that apply", dark: dark)
                    .padding(.bottom, 10)
            }

            StaggeredAppear(index: 2) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12),
                              GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(HealthPreference.allCases) { pref in
                        OnboardingSelectionCard(
                            emoji: pref.emoji,
                            title: pref.title,
                            subtitle: pref.subtitle,
                            selected: selection.contains(pref),
                            dark: dark,
                            accent: accent,
                            action: { toggle(pref) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer()
        }
    }

    private func toggle(_ pref: HealthPreference) {
        if selection.contains(pref) { selection.remove(pref) }
        else                        { selection.insert(pref) }
    }
}

// MARK: - 6. Profile (age / sex / life stage)

struct OnboardingProfileScreen: View {
    let dark: Bool
    let accent: Color
    @Binding var ageRange: AgeRange?
    @Binding var sex: BiologicalSex?
    @Binding var lifeStage: LifeStage

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "Tell us about you",
                    subtitle: "Your Score adjusts for life stage and body — e.g. stricter limits during pregnancy.",
                    dark: dark
                )
            }

            VStack(alignment: .leading, spacing: 18) {
                StaggeredAppear(index: 1) {
                    section(eyebrow: "Age range") {
                        ChipFlowLayout(spacing: 8, runSpacing: 8) {
                            ForEach(AgeRange.allCases) { range in
                                OnboardingChip(
                                    label: range.label,
                                    selected: ageRange == range,
                                    dark: dark,
                                    accent: accent,
                                    action: { ageRange = range }
                                )
                            }
                        }
                    }
                }

                StaggeredAppear(index: 2) {
                    section(eyebrow: "Sex") {
                        ChipFlowLayout(spacing: 8, runSpacing: 8) {
                            ForEach(BiologicalSex.allCases) { s in
                                OnboardingChip(
                                    label: s.label,
                                    selected: sex == s,
                                    dark: dark,
                                    accent: accent,
                                    action: { sex = s }
                                )
                            }
                        }
                    }
                }

                StaggeredAppear(index: 3) {
                    section(eyebrow: "Life stage") {
                        ChipFlowLayout(spacing: 8, runSpacing: 8) {
                            ForEach(LifeStage.allCases) { stage in
                                OnboardingChip(
                                    label: stage.label,
                                    selected: lifeStage == stage,
                                    dark: dark,
                                    accent: accent,
                                    action: { lifeStage = stage }
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    @ViewBuilder
    private func section<Content: View>(eyebrow: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .heavy)).tracking(1.4)
                .foregroundColor(Theme.textSecondary(dark))
            content()
        }
    }
}

// MARK: - 7. Symptoms (multi-select, skippable)

struct OnboardingSymptomsScreen: View {
    let dark: Bool
    let accent: Color
    @Binding var selection: Set<Symptom>

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "What's holding you back?",
                    subtitle: "We'll prioritize ingredients linked to what you're feeling.",
                    dark: dark
                )
            }

            StaggeredAppear(index: 1) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12),
                              GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(Symptom.allCases) { s in
                        OnboardingSelectionCard(
                            emoji: s.emoji,
                            title: s.title,
                            subtitle: nil,
                            selected: selection.contains(s),
                            dark: dark,
                            accent: accent,
                            action: { toggle(s) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer()
        }
    }

    private func toggle(_ s: Symptom) {
        if selection.contains(s) { selection.remove(s) }
        else                     { selection.insert(s) }
    }
}

// MARK: - 8. Reviews

struct OnboardingReviewsScreen: View {
    struct Review: Identifiable {
        let id = UUID()
        let initial: String
        let name: String
        let location: String
        let body: String
        let color: Color
    }

    let dark: Bool

    private let reviews: [Review] = [
        .init(initial: "M", name: "Maya",   location: "Austin, TX",
              body: "\"I scanned my whole pantry and the scores were genuinely shocking. Threw out half my snacks.\"",
              color: Color(hex: "1F8A5B")),
        .init(initial: "P", name: "Priya",  location: "Seattle, WA",
              body: "\"Finally an app that adjusts the score for pregnancy. Caught additives I'd never have spotted.\"",
              color: Color(hex: "6E5AC6")),
        .init(initial: "J", name: "Jordan", location: "Denver, CO",
              body: "\"The 'Your Score' vs overall thing is brilliant — it actually knows what I care about.\"",
              color: Color(hex: "C95A2B"))
    ]

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                VStack(spacing: 12) {
                    Text("Loved by clean eaters")
                        .font(.system(size: 28, weight: .heavy)).tracking(-0.7)
                        .foregroundColor(Theme.textPrimary(dark))
                        .multilineTextAlignment(.center)

                    HStack(spacing: 8) {
                        Text("4.9")
                            .font(.system(size: 30, weight: .heavy)).monospacedDigit()
                            .foregroundColor(Theme.textPrimary(dark))
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: "D4A02D"))
                            }
                        }
                        Text("400,000+ ratings")
                            .font(.system(size: 12)).monospacedDigit()
                            .foregroundColor(Theme.textSecondary(dark))
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
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "D4A02D"))
                }
            }
            Text(r.body)
                .font(.system(size: 14))
                .foregroundColor(Theme.textPrimary(dark))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(r.color).frame(width: 30, height: 30)
                    Text(r.initial)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(.white)
                }
                Text(r.name)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(Theme.textPrimary(dark))
                Text("· \(r.location)")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary(dark))
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
    }
}

// MARK: - 9. Notifications

struct OnboardingNotificationsScreen: View {
    let dark: Bool
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "Stay ahead of what's\nin your food",
                    subtitle: "Get alerts on recalls, newly flagged ingredients, and when a product you scanned drops in score.",
                    dark: dark
                )
            }

            Spacer()

            VStack(spacing: 10) {
                StaggeredAppear(index: 1) {
                    notificationCard(icon: "exclamationmark.triangle.fill",
                                     iconColor: Color(hex: "D4A02D"),
                                     title: "Recall alert",
                                     subtitle: "A product you scanned was …")
                        .offset(x: -8)
                }
                StaggeredAppear(index: 2) {
                    notificationCard(icon: "doc.text",
                                     iconColor: Theme.textPrimary(dark),
                                     title: "Score dropped",
                                     subtitle: "Your granola bar fell to 41 …")
                }
                StaggeredAppear(index: 3) {
                    notificationCard(icon: "sparkles",
                                     iconColor: accent,
                                     title: "Cleaner swap found",
                                     subtitle: "We found a 96-rated alterna…")
                        .offset(x: -4)
                }
            }
            .padding(.horizontal, 36)

            Spacer().frame(height: 60)
            Spacer()
        }
    }

    private func notificationCard(icon: String, iconColor: Color,
                                   title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary(dark))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface(dark))
        )
        .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 4)
    }
}

// MARK: - 10. Loading

struct OnboardingLoadingScreen: View {
    let dark: Bool
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
                // contentTransition(.numericText) makes each digit roll instead
                // of swap, matching the skill's "tabular nums + contextual"
                // guidance. monospacedDigit keeps the column width steady.
                Text("\(percent)%")
                    .font(.system(size: 88, weight: .heavy)).monospacedDigit()
                    .foregroundColor(Theme.textPrimary(dark))
                    .contentTransition(.numericText(value: Double(percent)))
                    .animation(.linear(duration: 0.05), value: percent)
            }

            StaggeredAppear(index: 1) {
                Text("Building your Sage")
                    .font(.system(size: 18, weight: .heavy)).tracking(-0.3)
                    .foregroundColor(Theme.textPrimary(dark))
                    .padding(.top, 4)
            }

            StaggeredAppear(index: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        Capsule().fill(accent)
                            .frame(width: geo.size.width * CGFloat(percent) / 100)
                            .animation(.linear(duration: 0.05), value: percent)
                    }
                }
                .frame(height: 8)
                .padding(.horizontal, 32).padding(.top, 32)
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
                    .stroke(Theme.textSecondary(dark).opacity(0.4), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                    .opacity(isComplete ? 0 : 1)
                    .scaleEffect(isComplete ? 0.7 : 1)
                ZStack {
                    Circle().fill(accent).frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.white)
                }
                .opacity(isComplete ? 1 : 0)
                .scaleEffect(isComplete ? 1 : 0.6)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isComplete)

            Text(line)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isComplete
                                 ? Theme.textPrimary(dark)
                                 : Theme.textSecondary(dark))
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
    let preferences: Set<HealthPreference>
    let onStart: () -> Void

    private let bg = Color(hex: "0B2A1F")
    private let surface = Color(hex: "133A2C")

    /// Pair each "watched" item with whether it's currently active for
    /// this user (we light up the ones they explicitly selected).
    private var watchedItems: [(title: String, isOn: Bool)] {
        [
            ("Avoids artificial dyes", preferences.contains(.noColors)),
            ("Low added sugar",        preferences.contains(.lowSugar)),
            ("Avoids seed oils",       preferences.contains(.noSeedOils)),
            ("No artificial sweeteners", preferences.contains(.noSweeteners)),
            ("High protein",           preferences.contains(.highProtein)),
            ("Pregnancy-safe limits",  false)
        ]
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 70)

                    StaggeredAppear(index: 0) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Here's where you stand")
                                .font(.system(size: 28, weight: .heavy)).tracking(-0.6)
                                .foregroundColor(.white)
                            Text("Based on your goals, here's how your current pantry scores — and where Sage users land.")
                                .font(.system(size: 15))
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

                    StaggeredAppear(index: 2) {
                        Text("WE'LL WATCH FOR")
                            .font(.system(size: 11, weight: .heavy)).tracking(1.4)
                            .foregroundColor(Color.white.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 8)
                    }

                    StaggeredAppear(index: 3) {
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
                Button(action: onStart) {
                    Text("Start scanning")
                        .font(.system(size: 16, weight: .heavy)).tracking(-0.2)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Capsule().fill(Color.black))
                }
                .buttonStyle(.pressable)
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
    }

    private var statsCard: some View {
        VStack(spacing: 14) {
            statRow(title: "Your pantry today", score: 53,
                    color: Color(hex: "D4A02D"))
            statRow(title: "Avg Sage user (30 days)", score: 88,
                    color: Color(hex: "3FBF7B"))
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
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white)
                Spacer()
                HStack(spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 18, weight: .heavy)).monospacedDigit()
                        .foregroundColor(color)
                    Text("/100")
                        .font(.system(size: 12, weight: .heavy)).monospacedDigit()
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
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.white)
                }
                .opacity(isOn ? 1 : 0)
                .scaleEffect(isOn ? 1 : 0.7)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.7), value: isOn)

            Text(title)
                .font(.system(size: 15, weight: isOn ? .heavy : .semibold))
                .foregroundColor(isOn ? .white : Color.white.opacity(0.55))
            Spacer()
            if isOn {
                Text("ON")
                    .font(.system(size: 11, weight: .heavy)).tracking(1.2)
                    .foregroundColor(accent)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.vertical, 16)
    }
}
