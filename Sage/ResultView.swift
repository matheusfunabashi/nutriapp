import SwiftUI

struct ResultView: View {
    @EnvironmentObject var store: AppStore
    let product: Product
    let fromScan: Bool
    let onBack: () -> Void
    let onCompare: () -> Void
    let onOpenMethodology: () -> Void

    var body: some View {
        let dark = store.darkMode
        ZStack {
            Theme.bg(dark).ignoresSafeArea()

            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        headerBlock(dark: dark)
                        allergenSection(dark: dark)
                        SectionTitle(title: "Breakdown", dark: dark)
                        gradesRow(dark: dark)
                        if product.transFats {
                            SeriousFlag().padding(.horizontal, 16).padding(.top, 8)
                        }
                        EyebrowLabel(text: "Per 100g / 100ml", dark: dark)
                        nutrientsCard(dark: dark).padding(.horizontal, 16)
                        EyebrowLabel(text: "Additives · \(product.additives.count)", dark: dark)
                        additivesCard(dark: dark).padding(.horizontal, 16)
                        detectedSection(dark: dark)
                        restrictionBanners(dark: dark)
                        disclaimer(dark: dark)
                        Spacer().frame(height: 140)
                    }
                    .frame(minWidth: geo.size.width, maxWidth: geo.size.width,
                           minHeight: geo.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            }
        }
    }

    private var isSaved: Bool {
        store.history.contains { $0.productId == product.id }
    }

    private var yourScoreIsWorstSignal: Bool {
        scoreTier(product.yourScore) == .bad
    }

    private func headerBlock(dark: Bool) -> some View {
        VStack(spacing: 8) {
            topBar(dark: dark)
            productHeader(dark: dark)
            VStack(spacing: 12) {
                scoreGapLine(dark: dark)
                aiAdviceSection(dark: dark)
                scoreComparisonCard(dark: dark)
                    .padding(.horizontal, 16)
                dataConfidenceLine(dark: dark)
            }
            .padding(.top, 14)
        }
        .padding(.bottom, 8)
    }

    private func topBar(dark: Bool) -> some View {
        HStack {
            CircleIconButton(systemName: "chevron.left", dark: dark,
                             accessibilityLabel: "Back", action: onBack)
            Spacer()
            if isSaved {
                Text("SAVED")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(1.6)
                    .foregroundColor(Theme.textSecondary(dark))
                    .accessibilityAddTraits(.isHeader)
            } else {
                Text("Sage")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.4)
                    .foregroundColor(Theme.textPrimary(dark))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            CircleIconButton(
                systemName: isSaved ? "bookmark.fill" : "bookmark",
                dark: dark,
                accessibilityLabel: isSaved ? "Saved to history" : "Not saved to history"
            )
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
    }

    private func productHeader(dark: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ProductThumb(glyph: product.glyph, score: product.yourScore, size: 64,
                         neutral: true, imageURL: product.imageURL)

            VStack(alignment: .leading, spacing: 2) {
                Text(product.brand.uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(1.2)
                    .foregroundColor(store.accent)
                Text(product.name)
                    .font(.system(size: 22, weight: .bold)).tracking(-0.5)
                    .foregroundColor(Theme.textPrimary(dark))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.9)
                Text(product.size)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.horizontal, 16)
    }

    /// Side-by-side dials: the universal Overall score next to the
    /// personalized "for you" score, with the compare action tucked below.
    private func scoreComparisonCard(dark: Bool) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                scorePanel(title: "OVERALL",
                           score: product.overallScore,
                           ringColor: scoreColor(product.overallScore),
                           emphasized: false, dark: dark)
                scorePanel(title: "YOUR SCORE",
                           score: product.yourScore,
                           ringColor: yourScoreIsWorstSignal ? Color.scoreBad
                                                             : scoreColor(product.yourScore),
                           emphasized: true, dark: dark)
            }
            compareButton(dark: dark)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.surface(dark))
        )
        .cardShadow(dark)
    }

    private func scorePanel(title: String, score: Int, ringColor: Color,
                            emphasized: Bool, dark: Bool) -> some View {
        let label = scoreLabel(score)
        let panelFill: Color = emphasized
            ? ringColor.opacity(dark ? 0.14 : 0.06)
            : (dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
        return VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .heavy)).tracking(1.2)
                .foregroundColor(Theme.textSecondary(dark))
            ScoreRing(score: score, size: 96, stroke: 7, dark: dark, ringColor: ringColor)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(ringColor))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18).padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(emphasized ? ringColor.opacity(0.35) : Color.clear, lineWidth: 1.5)
        )
        .overlay(alignment: .top) {
            if emphasized {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").font(.system(size: 8, weight: .bold))
                    Text("FOR YOU").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(store.accent))
                .offset(y: -9)
            }
        }
        .overlay(alignment: .topTrailing) {
            if emphasized {
                Button(action: onOpenMethodology) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textSecondary(dark))
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("How scoring works")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(score), \(label)")
    }

    /// Data Confidence (SCORING_V4.md §3.2): tells the user how much of the
    /// score is backed by real label data. High stays silent; Medium/Low get
    /// an honest caveat instead of silently punished data gaps.
    @ViewBuilder private func dataConfidenceLine(dark: Bool) -> some View {
        if product.dataConfidence != .high {
            HStack(spacing: 6) {
                Image(systemName: product.dataConfidence == .medium
                      ? "info.circle" : "exclamationmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text(product.dataConfidence == .medium
                     ? "Some label data is missing — the score may shift as data improves."
                     : "Limited label data — treat this score as provisional.")
                    .font(.system(size: 12))
                    .lineSpacing(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(Theme.textSecondary(dark))
            .padding(.horizontal, 20)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func scoreGapLine(dark: Bool) -> some View {
        if let gap = product.scoreGapReason {
            Text(gap)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary(dark))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .accessibilityLabel(gap)
        }
    }

    /// Overview body — hides text already shown in `scoreGapReason`.
    @ViewBuilder private func aiAdviceSection(dark: Bool) -> some View {
        if product.deltaReason != nil {
            let delta = product.yourScore - product.overallScore
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(store.accent)
                    Text("AI ADVICE")
                        .font(.system(size: 11, weight: .heavy)).tracking(1.3)
                        .foregroundColor(Theme.textSecondary(dark))
                    if delta != 0 {
                        let tint = delta < 0 ? Color.scoreBad : Color.scoreGood
                        Text(delta < 0 ? "\(delta)" : "+\(delta)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(tint))
                            .accessibilityLabel(deltaBadgeLabel(delta: delta) ?? "")
                    }
                    Spacer(minLength: 0)
                }
                if let body = product.overviewBodyText {
                    Text(body)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textPrimary(dark))
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
        }
    }

    private func deltaBadgeLabel(delta: Int) -> String? {
        guard delta != 0 else { return nil }
        let points = abs(delta)
        return delta < 0 ? "\(points) below overall" : "\(points) above overall"
    }

    private func compareButton(dark: Bool) -> some View {
        Button(action: onCompare) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                Text("Compare with another")
                    .font(.system(size: 14, weight: .semibold)).tracking(-0.2)
            }
            .foregroundColor(Theme.textPrimary(dark))
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.divider(dark), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compare with another product")
    }

    private func gradesRow(dark: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            NutriScoreCard(grade: product.nutriGrade, dark: dark)
            NovaCard(group: product.novaGroup, dark: dark)
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func nutrientsCard(dark: Bool) -> some View {
        let n = product.nutrients
        return CardView(dark: dark) {
            VStack(spacing: 0) {
                NutrientRow(label: "Sugar", value: "\(fmt(n.sugar_g ?? 0)) g",
                            tag: tagFromValue(n.sugar_g ?? 0, t1: 5, t2: 12.5, higherIsBetter: false),
                            divider: false, dark: dark)
                NutrientRow(label: "Sodium", value: "\(fmt(n.sodium_mg ?? 0)) mg",
                            tag: tagFromValue(n.sodium_mg ?? 0, t1: 120, t2: 400, higherIsBetter: false),
                            divider: true, dark: dark)
                NutrientRow(label: "Saturated fat", value: "\(fmt(n.satFat_g ?? 0)) g",
                            tag: tagFromValue(n.satFat_g ?? 0, t1: 1.5, t2: 5, higherIsBetter: false),
                            divider: true, dark: dark)
                NutrientRow(label: "Fiber", value: "\(fmt(n.fiber_g ?? 0)) g",
                            tag: tagFromValue(n.fiber_g ?? 0, t1: 3, t2: 6, higherIsBetter: true),
                            bonus: product.bonuses.contains("fiber"),
                            divider: true, dark: dark)
                NutrientRow(label: "Protein", value: "\(fmt(n.protein_g ?? 0)) g",
                            tag: tagFromValue(n.protein_g ?? 0, t1: 5, t2: 12, higherIsBetter: true),
                            bonus: product.bonuses.contains("protein"),
                            divider: true, dark: dark)
                NutrientRow(label: "Calcium", value: "\(fmt(n.calcium_mg ?? 0)) mg",
                            tag: tagFromValue(n.calcium_mg ?? 0, t1: 60, t2: 120, higherIsBetter: true),
                            bonus: product.bonuses.contains("calcium"),
                            divider: true, dark: dark)
            }
            .padding(.vertical, 4)
        }
    }

    private func additivesCard(dark: Bool) -> some View {
        CardView(dark: dark) {
            VStack(spacing: 0) {
                if product.additives.isEmpty {
                    HStack(spacing: 10) {
                        RiskDot(risk: .low)
                        Text("No additives detected")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.textPrimary(dark))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                } else {
                    SeverityBar(additives: product.additives, allowAlarmRed: !yourScoreIsWorstSignal)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .overlay(alignment: .bottom) {
                            Theme.divider(dark).frame(height: 0.5)
                        }
                    ForEach(Array(product.additives.enumerated()), id: \.element.id) { (i, a) in
                        AdditiveRow(additive: a, divider: i > 0, dark: dark,
                                    allowAlarmRed: !yourScoreIsWorstSignal)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func detectedSection(dark: Bool) -> some View {
        let show = product.caffeine_mg != nil || !product.sweeteners.isEmpty || product.seedOils
        return Group {
            if show {
                EyebrowLabel(text: "Detected", dark: dark)
                VStack(spacing: 6) {
                    if let mg = product.caffeine_mg {
                        InfoRow(emoji: "☕", label: "Contains caffeine",
                                detail: "\(fmt(mg)) mg per 100ml", dark: dark)
                    }
                    ForEach(product.sweeteners, id: \.self) { s in
                        InfoRow(emoji: "◈",
                                label: "Contains \(sweetenerLabel(s))",
                                detail: "Artificial / non-nutritive sweetener", dark: dark)
                    }
                    if product.seedOils {
                        InfoRow(emoji: "🌻", label: "Contains seed oils",
                                detail: "Informational, small score impact", dark: dark)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func restrictionBanners(dark: Bool) -> some View {
        let valid = product.restrictions.filter {
            ["vegan","vegetarian","pescatarian","low-sugar diet","low-sodium diet",
             "gluten-free","dairy-free"]
                .contains($0.type)
        }
        return Group {
            if !valid.isEmpty {
                VStack(spacing: 6) {
                    ForEach(valid) { r in
                        RestrictionBannerView(type: r.type, trigger: r.trigger, dark: dark)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }
        }
    }

    private func allergenSection(dark: Bool) -> some View {
        let userAllergies = store.user.allergies ?? []
        let warnings = AllergenMatcher.warnings(product: product, allergies: userAllergies)
        return Group {
            if !userAllergies.isEmpty {
                VStack(spacing: 8) {
                    ForEach(warnings) { w in
                        AllergenBanner(label: w.label, fromTag: w.fromTag, dark: dark)
                    }
                    AllergenDisclaimer(hasMatch: !warnings.isEmpty, dark: dark)
                }
                .padding(.horizontal, 16).padding(.bottom, 14)
            }
        }
    }

    private func disclaimer(dark: Bool) -> some View {
        Text("This is not professional advice. For specialized recommendation, seek a nutritionist.")
            .font(.system(size: 11))
            .multilineTextAlignment(.center)
            .foregroundColor(Theme.textSecondary(dark))
            .lineSpacing(2)
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
    }
}

// MARK: - Sub-components

struct NutriScoreCard: View {
    let grade: String
    let dark: Bool

    private let cardHeight: CGFloat = 100
    private var isKnown: Bool { ["A", "B", "C", "D", "E"].contains(grade.uppercased()) }

    var body: some View {
        if isKnown {
            knownBody
        } else {
            unknownBody
        }
    }

    private var knownBody: some View {
        let colors: [String: Color] = [
            "A": Color(hex: "1F8A5B"), "B": Color(hex: "7BA935"),
            "C": Color(hex: "D4A02D"), "D": Color(hex: "E07A26"),
            "E": Color(hex: "C9442B"),
        ]
        let g = grade.uppercased()
        let c = colors[g] ?? Color.neutralMuted
        return HStack(alignment: .center, spacing: 12) {
            Text(g)
                .font(.system(size: 28, weight: .heavy)).tracking(-1)
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c))
            VStack(alignment: .leading, spacing: 6) {
                Text("NUTRI-SCORE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                    .foregroundColor(Theme.textSecondary(dark))
                HStack(spacing: 2) {
                    ForEach(["A","B","C","D","E"], id: \.self) { letter in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(letter == g ? c
                                  : (dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)))
                            .frame(height: 4)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
    }

    private var unknownBody: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("?")
                .font(.system(size: 24, weight: .heavy)).tracking(-0.5)
                .foregroundColor(Theme.textSecondary(dark))
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                )
            VStack(alignment: .leading, spacing: 6) {
                Text("NUTRI-SCORE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                    .foregroundColor(Theme.textSecondary(dark))
                Text("Not rated")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textSecondary(dark))
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                            .frame(height: 4)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
        .accessibilityLabel("Nutri-Score not rated")
    }
}

struct NovaCard: View {
    let group: Int
    let dark: Bool

    private let cardHeight: CGFloat = 100
    private var isKnown: Bool { (1...4).contains(group) }

    var body: some View {
        if isKnown {
            knownBody
        } else {
            unknownBody
        }
    }

    private var knownBody: some View {
        let labels = [1: "Unprocessed", 2: "Culinary", 3: "Processed", 4: "Ultra-processed"]
        let colors: [Int: Color] = [
            1: Color(hex: "1F8A5B"), 2: Color(hex: "7BA935"),
            3: Color(hex: "D4A02D"), 4: Color(hex: "C9442B"),
        ]
        let c = colors[group] ?? Color.neutralMuted
        let labelColor = group >= 4 ? Color.cautionMuted : c
        return HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(1...4, id: \.self) { g in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(g <= group ? c
                              : (dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)))
                        .frame(width: 6, height: CGFloat(8 + g * 7))
                }
            }
            .frame(width: 52, height: 52, alignment: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text("PROCESSING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                    .foregroundColor(Theme.textSecondary(dark))
                Text("NOVA \(group)")
                    .font(.system(size: 13, weight: .heavy)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                Text(labels[group] ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
    }

    private var unknownBody: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(1...4, id: \.self) { g in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                        .frame(width: 6, height: CGFloat(8 + g * 7))
                }
            }
            .frame(width: 52, height: 52, alignment: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text("PROCESSING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                    .foregroundColor(Theme.textSecondary(dark))
                Text("Not rated")
                    .font(.system(size: 13, weight: .heavy)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                Text("Unknown")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.neutralMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
        .accessibilityLabel("NOVA processing not rated, unknown")
    }
}

struct NutrientRow: View {
    let label: String
    let value: String
    let tag: Tag?
    var bonus: Bool = false
    let divider: Bool
    let dark: Bool

    /// The word states the measured amount (Low/Mod/High); the tone says how
    /// that amount should feel for this nutrient — they must stay independent
    /// so "Fiber 0g" reads LOW (not a red HIGH) and "Protein 30g" reads a
    /// green HIGH (not LOW).
    struct Tag: Equatable {
        enum Tone { case good, mid, bad, neutral }
        let word: String
        let tone: Tone

        var fg: Color { switch tone {
            case .good:    return Color.scoreGood
            case .mid:     return Color.scoreOk
            case .bad:     return Color.scoreBad
            case .neutral: return Color.neutralMuted }
        }
        var bg: Color { fg.opacity(0.10) }
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
                if bonus {
                    Text("+ BOOST")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                        .foregroundColor(Color(hex: "1F8A5B"))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: "1F8A5B").opacity(0.12)))
                        .fixedSize()
                }
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .monospacedDigit().tracking(-0.2)
                .foregroundColor(Theme.textPrimary(dark))
                .fixedSize(horizontal: true, vertical: false)
            if let tag {
                Text(tag.word.uppercased())
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundColor(tag.fg)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(tag.bg))
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(alignment: .top) {
            if divider {
                Theme.divider(dark).frame(height: 0.5).padding(.horizontal, 8)
            }
        }
    }
}

struct AdditiveRow: View {
    let additive: Additive
    let divider: Bool
    let dark: Bool
    var allowAlarmRed: Bool = true

    private var riskFg: Color {
        if additive.risk == .high { return Color.scoreBad }
        return RiskStyle.fg(additive.risk)
    }

    private var riskBg: Color { riskFg.opacity(additive.risk == .high && allowAlarmRed ? 0.10 : 0.12) }

    var body: some View {
        HStack(spacing: 12) {
            RiskDot(risk: additive.risk, allowAlarmRed: allowAlarmRed)
            VStack(alignment: .leading, spacing: 2) {
                Text(additive.name)
                    .font(.system(size: 14, weight: .semibold)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = additive.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary(dark))
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Text(RiskStyle.label(additive.risk).uppercased())
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundColor(riskFg)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(riskBg))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .top) {
            if divider { Theme.divider(dark).frame(height: 0.5).padding(.horizontal, 8) }
        }
    }
}

struct SeverityBar: View {
    let additives: [Additive]
    var allowAlarmRed: Bool = true

    private func barColor(for risk: RiskLevel) -> Color {
        if risk == .high { return Color.scoreBad }
        return RiskStyle.fg(risk)
    }

    var body: some View {
        let total = max(additives.count, 1)
        let counts: [RiskLevel: Int] = additives.reduce(into: [:]) { dict, a in
            dict[a.risk, default: 0] += 1
        }
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach([RiskLevel.low, .moderate, .high], id: \.self) { r in
                        if let c = counts[r], c > 0 {
                            Rectangle()
                                .fill(barColor(for: r))
                                .frame(width: geo.size.width * CGFloat(c) / CGFloat(total))
                        }
                    }
                }
            }
            .frame(height: 6)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.04)))
            .clipShape(RoundedRectangle(cornerRadius: 3))

            HStack(spacing: 12) {
                ForEach([RiskLevel.low, .moderate, .high], id: \.self) { r in
                    HStack(spacing: 5) {
                        RiskDot(risk: r, size: 7, allowAlarmRed: allowAlarmRed)
                        Text("\(counts[r] ?? 0) \(RiskStyle.label(r).lowercased())")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(barColor(for: r))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RiskDot: View {
    let risk: RiskLevel
    var size: CGFloat = 10
    var allowAlarmRed: Bool = true

    private var color: Color {
        if risk == .high { return Color.scoreBad }
        return RiskStyle.fg(risk)
    }

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

struct InfoRow: View {
    let emoji: String
    let label: String
    let detail: String
    let dark: Bool
    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.04)))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13, weight: .heavy)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
    }
}

struct RestrictionBannerView: View {
    let type: String
    let trigger: String
    let dark: Bool
    var body: some View {
        let fg = Color.cautionMuted
        HStack(alignment: .top, spacing: 10) {
            Text("⚠️").font(.system(size: 14))
            VStack(alignment: .leading, spacing: 1) {
                Text("Contains \(trigger), flagged by your profile")
                    .font(.system(size: 13, weight: .heavy)).tracking(-0.1)
                    .foregroundColor(fg)
                Text(type.uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .foregroundColor(fg.opacity(0.85))
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(fg.opacity(dark ? 0.14 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(fg.opacity(0.18), lineWidth: 1)
        )
    }
}

struct SeriousFlag: View {
    var body: some View {
        let fg = Color.cautionMuted
        HStack(spacing: 12) {
            Text("!")
                .font(.system(size: 16, weight: .heavy))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(fg))
            VStack(alignment: .leading, spacing: 1) {
                Text("Contains trans fats")
                    .font(.system(size: 14, weight: .heavy)).tracking(-0.2)
                    .foregroundColor(fg)
                Text("The most heavily penalized input in your score.")
                    .font(.system(size: 11))
                    .foregroundColor(fg.opacity(0.85))
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(fg.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(fg.opacity(0.20), lineWidth: 1)
        )
    }
}

// MARK: - Allergen banners

struct AllergenBanner: View {
    let label: String
    let fromTag: Bool
    let dark: Bool
    var body: some View {
        let fg = Color.cautionMuted
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 18))
                .foregroundColor(fg)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(fromTag ? "Contains" : "May contain") \(label.lowercased())")
                    .font(.system(size: 14, weight: .heavy)).tracking(-0.2)
                    .foregroundColor(fg)
                Text(fromTag ? "Listed as an allergen for this product"
                             : "Detected in the ingredient list")
                    .font(.system(size: 11))
                    .foregroundColor(fg.opacity(0.85))
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(fg.opacity(dark ? 0.14 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(fg.opacity(0.20), lineWidth: 1)
        )
    }
}

struct AllergenDisclaimer: View {
    let hasMatch: Bool
    let dark: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary(dark))
            Text(hasMatch
                 ? "Always confirm on the product packaging — allergen data can be incomplete."
                 : "No declared allergens matched your profile, but data may be incomplete — always check the packaging.")
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary(dark))
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
        )
    }
}

// MARK: - Score gap copy (presentation; derived from deltaReason — no new model field)

extension Product {
    /// One-line explanation of why Your Score differs from Overall, when we can
    /// derive it from the existing rule-based / LLM `deltaReason` text.
    var scoreGapReason: String? {
        let delta = yourScore - overallScore
        guard delta != 0, let reason = deltaReason else { return nil }
        let text = reason.text

        if delta < 0 {
            if let detail = text.components(separatedBy: "Scores lower for you — ").last,
               detail != text {
                return "Lower for you: \(detail.trimmingCharacters(in: CharacterSet(charactersIn: ".")))"
            }
            if text.hasPrefix("Capped —") { return text }
            if let detail = text.components(separatedBy: "held back by ").last,
               detail != text {
                return "Lower for you: \(detail.trimmingCharacters(in: CharacterSet(charactersIn: ".")))"
            }
        } else if delta > 0 {
            if let detail = text.components(separatedBy: "Scores higher for you — ").last,
               detail != text {
                return "Higher for you: \(detail.trimmingCharacters(in: CharacterSet(charactersIn: ".")))"
            }
            if let detail = text.components(separatedBy: "main plus: ").last,
               detail != text {
                return "Higher for you: \(detail.trimmingCharacters(in: CharacterSet(charactersIn: ".")))"
            }
        }
        return nil
    }

    /// Non-redundant Overview body — strips content already shown in `scoreGapReason`.
    var overviewBodyText: String? {
        guard let reason = deltaReason else { return nil }
        let full = reason.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !full.isEmpty else { return nil }
        guard let gap = scoreGapReason else { return full }
        if full.caseInsensitiveCompare(gap) == .orderedSame { return nil }

        let gapDetail: String = {
            for prefix in ["Higher for you: ", "Lower for you: "] where gap.hasPrefix(prefix) {
                return String(gap.dropFirst(prefix.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }
            return gap
        }()

        var remainder = full
        let stripPrefixes = [
            "Scores higher for you — ",
            "Scores lower for you — ",
            "For your goal it's much like for everyone — the main plus: ",
            "For your goal it's much like for everyone — mainly held back by ",
        ]
        for prefix in stripPrefixes where remainder.hasPrefix(prefix) {
            remainder = String(remainder.dropFirst(prefix.count))
            break
        }
        remainder = remainder.trimmingCharacters(in: CharacterSet(charactersIn: ". "))

        if remainder.lowercased().hasPrefix(gapDetail.lowercased()) {
            remainder = String(remainder.dropFirst(gapDetail.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " .,—()"))
        }

        if remainder.hasPrefix("("), remainder.hasSuffix(")") { return remainder }

        remainder = remainder.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if remainder.count < 4 { return nil }
        if full.lowercased().contains(gapDetail.lowercased()) && remainder.isEmpty { return nil }
        return remainder.isEmpty ? nil : remainder
    }
}

// MARK: - Helpers

func fmt(_ v: Double) -> String {
    v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
}

func tagFromValue(_ v: Double, t1: Double, t2: Double, higherIsBetter: Bool) -> NutrientRow.Tag {
    if higherIsBetter {
        // Plenty of a beneficial nutrient is good news; little of it is
        // merely unremarkable (neutral), not an alarm.
        if v >= t2 { return .init(word: "High", tone: .good) }
        if v >= t1 { return .init(word: "Mod", tone: .mid) }
        return .init(word: "Low", tone: .neutral)
    } else {
        if v <= t1 { return .init(word: "Low", tone: .good) }
        if v <= t2 { return .init(word: "Mod", tone: .mid) }
        return .init(word: "High", tone: .bad)
    }
}

func sweetenerLabel(_ key: String) -> String {
    switch key {
    case "aspartame":     return "Aspartame"
    case "acesulfame K":  return "Acesulfame K"
    case "saccharin":     return "Saccharin"
    case "sucralose":     return "Sucralose"
    case "stevia":        return "Stevia"
    case "monk fruit":    return "Monk fruit"
    default:              return key
    }
}
