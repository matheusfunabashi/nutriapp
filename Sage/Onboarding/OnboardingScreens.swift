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
                // 12pt above the safe-area inset — see OnboardingHeader.
                .padding(.top, 12)
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

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "What's marketed as\nhealthy often isn't",
                    subtitle: "Labels and marketing hide what's really in your food. “Natural,” “healthy,” and “lightly sweetened” aren't regulated.",
                    dark: dark
                )
            }

            StaggeredAppear(index: 1) {
                OnboardingHeroImage(
                    assetName: OnboardingAssets.marketingHero,
                    dark: dark,
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

struct OnboardingScoresScreen: View {
    let dark: Bool
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "Two scores, not one",
                    subtitle: "Everyone sees the same Overall score. But Sage also gives you Your Score, recalculated from your goals, age, and body.",
                    dark: dark
                )
            }

            StaggeredAppear(index: 1) {
                HStack(spacing: 14) {
                    scoreCard(label: "OVERALL", score: 72, footnote: "The overall score",
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
                VStack(alignment: .leading, spacing: 14) {
                    reasonRow(delta: -8,
                              ingredient: "Contains Yellow 5",
                              reason: "You avoid dyes")
                    reasonRow(delta: -6,
                              ingredient: "Sucralose",
                              reason: "Flagged for your goal")
                    // Third row keeps the card balanced — two rows left a
                    // lot of vertical air below the second item.
                    reasonRow(delta: -4,
                              ingredient: "Maltodextrin",
                              reason: "Affects blood sugar")
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
        // Both cards now carry a stroke — non-highlighted gets a hairline
        // neutral border so it doesn't read as visually lighter than the
        // highlighted "Your Score" card, which keeps its 2pt accent ring.
        let borderColor: Color = highlighted
            ? accent
            : (dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
        let borderWidth: CGFloat = highlighted ? 2 : 1

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
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .cardShadow(dark)
    }

    /// Deduction row: a red pill for the delta on the left, the ingredient
    /// on the right with a subtle "why" tag underneath.
    private func reasonRow(delta: Int, ingredient: String,
                            reason: String) -> some View {
        let red = Color(hex: "C9442B")
        return HStack(alignment: .top, spacing: 12) {
            Text("\(delta)")
                .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                .foregroundColor(red)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(red.opacity(0.12)))

            VStack(alignment: .leading, spacing: 6) {
                Text(ingredient)
                    .font(.system(size: 14, weight: .heavy)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                Text(reason)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textSecondary(dark))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(
                        Capsule().fill(dark ? Color.white.opacity(0.06)
                                              : Color.black.opacity(0.05))
                    )
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

    let dark: Bool
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
                    subtitle: "Instantly find the cleanest option in every category with scores ranked for you.",
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
                .font(.system(size: 15, weight: .heavy)).tracking(-0.3)
                .foregroundColor(Theme.textPrimary(dark))
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
                .fill(Theme.surface(dark))
        )
        .cardShadow(dark)
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
                Text(item.glyph).font(.system(size: 34))
            }
        }
        .frame(width: 70, height: 70)
    }

    private func ringBadge(score: Int) -> some View {
        ZStack {
            Circle()
                .stroke(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07),
                        lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.system(size: 14, weight: .heavy)).monospacedDigit()
                .foregroundColor(accent)
        }
        .frame(width: 46, height: 46)
    }
}

// MARK: - 6a. Profile · Name
//
// First of the three split "Tell us about you" screens. Single text
// field with the keyboard auto-presented so users land typing.

struct OnboardingNameScreen: View {
    let dark: Bool
    @Binding var firstName: String

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTitle(
                title: "What should we\ncall you?",
                subtitle: "This is how Sage will address you in the app.",
                dark: dark
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("FIRST NAME")
                    .font(.system(size: 11, weight: .heavy)).tracking(1.4)
                    .foregroundColor(Theme.textSecondary(dark))

                TextField("", text: $firstName)
                    .focused($focused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.textPrimary(dark))
                    .padding(.horizontal, 14).padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.surface(dark))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(focused ? OnboardingBrandGreen
                                            : Color.black.opacity(0.08),
                                    lineWidth: focused ? 1.5 : 1)
                    )
                    .animation(.easeOut(duration: 0.18), value: focused)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .onAppear {
            // Wait for the step slide to finish before raising the keyboard —
            // avoids layout + animation fighting on first paint.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                focused = true
            }
        }
    }
}

// MARK: - 6b. Profile · Body stats
//
// Height + weight via native wheel pickers, with a single toggle that
// converts both readings in-place between imperial and metric so the
// numbers always reflect the active unit.

struct OnboardingBodyStatsScreen: View {
    let dark: Bool
    @Binding var useImperial: Bool
    @Binding var heightFt: Int
    @Binding var heightIn: Int
    @Binding var heightCm: Int
    @Binding var weightLb: Int
    @Binding var weightKg: Int

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "Your body stats",
                    subtitle: "Used to adjust serving sizes and nutrient limits for you.",
                    dark: dark
                )
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    StaggeredAppear(index: 1) { unitsCard }
                    StaggeredAppear(index: 2) { heightCard }
                    StaggeredAppear(index: 3) { weightCard }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Units toggle

    private var unitsCard: some View {
        HStack {
            Text("Imperial units")
                .font(.system(size: 15, weight: .heavy)).tracking(-0.2)
                .foregroundColor(Theme.textPrimary(dark))
            Spacer()
            Toggle("", isOn: Binding(
                get: { useImperial },
                set: { toggleUnits(to: $0) }
            ))
            .labelsHidden()
            .tint(OnboardingBrandGreen)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(cardBackground)
    }

    // MARK: Height

    private var heightCard: some View {
        sectionCard(label: "HEIGHT") {
            if useImperial {
                HStack(spacing: 0) {
                    pickerColumn(label: "FT", selection: $heightFt, range: 3...8)
                    pickerColumn(label: "IN", selection: $heightIn, range: 0...11)
                }
                .frame(height: 130)
            } else {
                pickerColumn(label: "CM", selection: $heightCm, range: 90...250)
                    .frame(height: 130)
            }
        }
    }

    // MARK: Weight

    private var weightCard: some View {
        sectionCard(label: "WEIGHT") {
            if useImperial {
                pickerColumn(label: "LB", selection: $weightLb, range: 50...500)
                    .frame(height: 130)
            } else {
                pickerColumn(label: "KG", selection: $weightKg, range: 25...250)
                    .frame(height: 130)
            }
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    private func sectionCard<C: View>(label: String,
                                       @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .heavy)).tracking(1.4)
                .foregroundColor(Theme.textSecondary(dark))
                .padding(.leading, 4)
            content()
                .frame(maxWidth: .infinity)
                .background(cardBackground)
        }
    }

    @ViewBuilder
    private func pickerColumn(label: String, selection: Binding<Int>,
                               range: ClosedRange<Int>) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(1.4)
                .foregroundColor(Theme.textSecondary(dark))
                .padding(.top, 10)
            Picker(label, selection: selection) {
                ForEach(range, id: \.self) { v in
                    Text("\(v)")
                        .font(.system(size: 22, weight: .heavy))
                        .monospacedDigit()
                        .tag(v)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped() // wheels render outside their bounds on some sizes
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.surface(dark))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
    }

    // MARK: Unit conversion
    //
    // Recomputes the *other* unit's reading whenever the toggle flips
    // so both stored values stay aligned and the wheels always show
    // the equivalent figure.

    private func toggleUnits(to imperial: Bool) {
        guard imperial != useImperial else { return }
        if imperial {
            // metric → imperial
            let totalInches = Int((Double(heightCm) / 2.54).rounded())
            heightFt = max(3, min(8, totalInches / 12))
            heightIn = max(0, min(11, totalInches % 12))
            weightLb = max(50, min(500, Int((Double(weightKg) * 2.20462).rounded())))
        } else {
            // imperial → metric
            heightCm = max(90, min(250,
                Int((Double(heightFt * 12 + heightIn) * 2.54).rounded())
            ))
            weightKg = max(25, min(250, Int((Double(weightLb) / 2.20462).rounded())))
        }
        useImperial = imperial
    }
}

// MARK: - 6c. Profile · Personal details
//
// DOB (3 tappable mini-cards opening wheel-picker sheets), gender
// segmented control, and a multi-select life-stage pill grid where
// "None" is mutually exclusive with the rest.

struct OnboardingPersonalDetailsScreen: View {
    let dark: Bool
    @Binding var dobMonth: Int
    @Binding var dobDay: Int
    @Binding var dobYear: Int
    @Binding var sex: BiologicalSex?
    @Binding var lifeStages: Set<LifeStage>

    @State private var pickerField: DOBField? = nil

    enum DOBField: String, Identifiable {
        case month, day, year
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "A bit more\nabout you",
                    subtitle: "Helps us personalize your score more accurately.",
                    dark: dark
                )
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    StaggeredAppear(index: 1) { dobSection }
                    StaggeredAppear(index: 2) { genderSection }
                    StaggeredAppear(index: 3) { lifeStageSection }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .sheet(item: $pickerField) { field in
            dobPickerSheet(field)
        }
    }

    // MARK: DOB

    private var dobSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DATE OF BIRTH")
                .font(.system(size: 11, weight: .heavy)).tracking(1.4)
                .foregroundColor(Theme.textSecondary(dark))

            HStack(spacing: 10) {
                dobCard(label: "Month",
                        value: monthLabel(dobMonth),
                        field: .month)
                dobCard(label: "Day",
                        value: String(format: "%02d", dobDay),
                        field: .day)
                dobCard(label: "Year",
                        value: "\(dobYear)",
                        field: .year)
            }
        }
    }

    private func dobCard(label: String, value: String, field: DOBField) -> some View {
        Button {
            pickerField = field
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .heavy)).tracking(1.0)
                    .foregroundColor(Theme.textSecondary(dark))
                Text(value)
                    .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                    .foregroundColor(Theme.textPrimary(dark))
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.surface(dark))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
    }

    @ViewBuilder
    private func dobPickerSheet(_ field: DOBField) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { pickerField = nil }
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(OnboardingBrandGreen)
                    .padding(.horizontal, 20).padding(.vertical, 14)
            }
            switch field {
            case .month:
                Picker("Month", selection: $dobMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text(monthLabel(m)).tag(m)
                    }
                }
                .pickerStyle(.wheel)
            case .day:
                Picker("Day", selection: $dobDay) {
                    ForEach(1...daysInMonth(dobMonth, year: dobYear), id: \.self) { d in
                        Text("\(d)").tag(d)
                    }
                }
                .pickerStyle(.wheel)
            case .year:
                // Clamp years so the wheel doesn't go decades into the
                // future or the 1800s. 13 years old is the floor.
                let currentYear = Calendar(identifier: .gregorian)
                    .component(.year, from: Date())
                Picker("Year", selection: $dobYear) {
                    ForEach((currentYear - 100)...(currentYear - 13), id: \.self) { y in
                        Text("\(String(y))").tag(y)
                    }
                }
                .pickerStyle(.wheel)
            }
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    private func monthLabel(_ m: Int) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.shortMonthSymbols[max(0, min(11, m - 1))]
    }

    private func daysInMonth(_ month: Int, year: Int) -> Int {
        var c = DateComponents(); c.year = year; c.month = month
        let cal = Calendar(identifier: .gregorian)
        guard let date = cal.date(from: c),
              let range = cal.range(of: .day, in: .month, for: date) else { return 31 }
        return range.count
    }

    // MARK: Gender — custom 3-button segmented control

    private var genderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GENDER")
                .font(.system(size: 11, weight: .heavy)).tracking(1.4)
                .foregroundColor(Theme.textSecondary(dark))

            HStack(spacing: 6) {
                ForEach(BiologicalSex.allCases) { option in
                    genderButton(option)
                }
            }
            .padding(4)
            .background(
                Capsule().fill(Theme.surface(dark))
            )
            .overlay(
                Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func genderButton(_ option: BiologicalSex) -> some View {
        let isSelected = sex == option
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                sex = option
            }
        } label: {
            Text(option.label)
                .font(.system(size: 14, weight: .heavy)).tracking(-0.2)
                .foregroundColor(isSelected ? .white : Theme.textPrimary(dark))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(isSelected ? OnboardingBrandGreen : Color.clear)
                )
        }
        .buttonStyle(.pressable)
    }

    // MARK: Life stage — multi-select with "None" as mutex

    private var lifeStageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LIFE STAGE")
                .font(.system(size: 11, weight: .heavy)).tracking(1.4)
                .foregroundColor(Theme.textSecondary(dark))

            ChipFlowLayout(spacing: 8, runSpacing: 8) {
                ForEach(LifeStage.allCases) { stage in
                    OnboardingChip(
                        label: stage.label,
                        selected: lifeStages.contains(stage),
                        dark: dark,
                        accent: OnboardingBrandGreen,
                        action: { toggleLifeStage(stage) }
                    )
                }
            }
        }
    }

    /// Tapping `.none` clears every other selection and selects only None.
    /// Tapping anything else drops `.none` first, then toggles. Empty set
    /// means the user hasn't picked a life stage (including None).
    private func toggleLifeStage(_ stage: LifeStage) {
        if stage == .none {
            lifeStages = [.none]
            return
        }
        lifeStages.remove(.none)
        if lifeStages.contains(stage) {
            lifeStages.remove(stage)
        } else {
            lifeStages.insert(stage)
        }
    }
}

// MARK: - 6d. Dietary restrictions (hard rules + soft preferences)

struct OnboardingDietaryRestrictionsScreen: View {
    let dark: Bool
    @Binding var restrictions: Set<String>
    @Binding var preferences: Set<String>

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "Any dietary\nrestrictions?",
                    subtitle: "We'll flag conflicts on every scan.",
                    dark: dark
                )
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    StaggeredAppear(index: 1) {
                        section(
                            title: "Restrictions",
                            description: "Hard rules — flagged as warnings on every scan."
                        ) {
                            pillWrap(items: DietaryOptions.restrictions, selection: $restrictions)
                        }
                    }

                    Rectangle()
                        .fill(Theme.divider(dark))
                        .frame(height: 1)
                        .padding(.horizontal, 4)

                    StaggeredAppear(index: 2) {
                        section(
                            title: "Preferences",
                            description: "Soft signals — nudge your score, no warnings."
                        ) {
                            pillWrap(items: DietaryOptions.preferences, selection: $preferences)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private func section<C: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy)).tracking(1.4)
                .foregroundColor(Theme.textPrimary(dark))
            Text(description)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary(dark))
                .lineSpacing(2)
            content()
        }
    }

    private func pillWrap(items: [String], selection: Binding<Set<String>>) -> some View {
        ChipFlowLayout(spacing: 8, runSpacing: 8) {
            ForEach(items, id: \.self) { item in
                OnboardingDietPill(
                    label: item,
                    selected: selection.wrappedValue.contains(item),
                    dark: dark,
                    action: { toggle(item, in: selection) }
                )
            }
        }
    }

    private func toggle(_ value: String, in selection: Binding<Set<String>>) {
        if selection.wrappedValue.contains(value) {
            selection.wrappedValue.remove(value)
        } else {
            selection.wrappedValue.insert(value)
        }
    }
}

// MARK: - 6e. Allergens (grid + custom entry)

struct OnboardingAllergensScreen: View {
    let dark: Bool
    @Binding var allergies: [String]

    @State private var customInput = ""
    @FocusState private var customFocused: Bool

    private var presetLabels: [String] { OnboardingAllergenOptions.presets }

    private var customAllergies: [String] {
        let presets = Set(presetLabels.map { $0.lowercased() })
        return allergies.filter { !presets.contains($0.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingTitle(
                    title: "Any allergies or\nintolerances?",
                    subtitle: "We'll warn you whenever a scanned product may contain these.",
                    dark: dark
                )
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    StaggeredAppear(index: 1) {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                            ],
                            spacing: 10
                        ) {
                            ForEach(presetLabels, id: \.self) { label in
                                OnboardingAllergenCell(
                                    label: label,
                                    selected: isSelected(label),
                                    dark: dark,
                                    action: { toggleAllergen(label) }
                                )
                            }
                        }
                    }

                    StaggeredAppear(index: 2) { addAllergyRow }

                    if !customAllergies.isEmpty {
                        StaggeredAppear(index: 3) {
                            ChipFlowLayout(spacing: 8, runSpacing: 8) {
                                ForEach(customAllergies, id: \.self) { label in
                                    customPill(label)
                                }
                            }
                        }
                    }

                    StaggeredAppear(index: 4) { disclaimer }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var addAllergyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.square")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Theme.textSecondary(dark))
            TextField("Add another allergy", text: $customInput)
                .focused($customFocused)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textPrimary(dark))
                .submitLabel(.done)
                .onSubmit { addCustomAllergy() }
            if !customInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Add", action: addCustomAllergy)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(OnboardingBrandGreen)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundColor(Color.black.opacity(0.12))
        )
        .onTapGesture { customFocused = true }
    }

    private func customPill(_ label: String) -> some View {
        Button { removeAllergy(label) } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 12, weight: .heavy)).tracking(-0.1)
                    .foregroundColor(OnboardingBrandGreen)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(OnboardingBrandGreen)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(OnboardingBrandGreen.opacity(0.10)))
            .overlay(Capsule().stroke(OnboardingBrandGreen, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text("Data may be incomplete — always check the packaging.")
                .font(.system(size: 11))
                .lineSpacing(2)
                .multilineTextAlignment(.center)
        }
        .foregroundColor(Theme.textSecondary(dark))
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func isSelected(_ label: String) -> Bool {
        allergies.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame })
    }

    private func toggleAllergen(_ label: String) {
        if let idx = allergies.firstIndex(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
            allergies.remove(at: idx)
        } else {
            allergies.append(label)
        }
    }

    private func addCustomAllergy() {
        let trimmed = customInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !allergies.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            allergies.append(trimmed)
        }
        customInput = ""
        customFocused = false
    }

    private func removeAllergy(_ label: String) {
        allergies.removeAll { $0.caseInsensitiveCompare(label) == .orderedSame }
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

    let dark: Bool

    private let reviews: [Review] = [
        .init(initial: "F", name: "Felipe",   location: "Miami, FL",
              body: "\"I scanned my whole pantry and the scores were genuinely shocking. Threw out half my snacks.\"",
              color: Color(hex: "1F8A5B")),
        .init(initial: "E", name: "Enrico",  location: "Seattle, WA",
              body: "\"Finally an app that adjusts the score for pregnancy. Caught additives I'd never have spotted.\"",
              color: Color(hex: "6E5AC6")),
        .init(initial: "M", name: "Matthew", location: "Denver, CO",
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
    let dietaryRestrictions: Set<String>
    let foodPreferences: Set<String>
    let lifeStages: Set<LifeStage>
    let onStart: () -> Void

    private let bg = Color(hex: "0B2A1F")
    private let surface = Color(hex: "133A2C")

    /// Pair each "watched" item with whether it's currently active for
    /// this user (we light up the ones they picked during onboarding).
    private var watchedItems: [(title: String, isOn: Bool)] {
        [
            ("Low added sugar",
             foodPreferences.contains("Low sugar") || dietaryRestrictions.contains("Low-sugar diet")),
            ("Low sodium",
             foodPreferences.contains("Low sodium") || dietaryRestrictions.contains("Low-sodium diet")),
            ("High protein", foodPreferences.contains("High protein")),
            ("Gluten-free", dietaryRestrictions.contains("Gluten-free")),
            ("Minimally processed", foodPreferences.contains("Minimally processed")),
            ("Pregnancy-safe limits", lifeStages.contains(.pregnant)),
        ]
    }

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
