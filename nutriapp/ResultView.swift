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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                topBar(dark: dark)
                productHeader(dark: dark)
                dualScoreCard(dark: dark)
                    .padding(.horizontal, 16).padding(.bottom, 14)
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
        }
        .background(Theme.bg(dark).ignoresSafeArea())
    }

    private func topBar(dark: Bool) -> some View {
        HStack {
            CircleIconButton(systemName: "chevron.left", dark: dark, action: onBack)
            Spacer()
            Text(fromScan ? "SCANNED" : "SAVED")
                .font(.system(size: 13, weight: .heavy)).tracking(1.3)
                .foregroundColor(Theme.textSecondary(dark))
            Spacer()
            CircleIconButton(systemName: "bookmark", dark: dark)
        }
        .padding(.horizontal, 16).padding(.top, 60).padding(.bottom, 12)
    }

    private func productHeader(dark: Bool) -> some View {
        HStack(spacing: 16) {
            ProductThumb(glyph: product.glyph, score: product.yourScore, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(product.brand.uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(1.2)
                    .foregroundColor(store.accent)
                Text(product.name)
                    .font(.system(size: 22, weight: .bold)).tracking(-0.5)
                    .foregroundColor(Theme.textPrimary(dark))
                Text(product.size)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24).padding(.bottom, 16)
    }

    private func dualScoreCard(dark: Bool) -> some View {
        let delta = product.yourScore - product.overallScore
        let showDelta = abs(delta) >= 5 && product.deltaReason != nil
        let tone = product.deltaReason?.tone ?? (delta > 0 ? .positive : .negative)
        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    DualScoreCol(score: product.overallScore,
                                 label: "Overall", sublabel: "Universal score", dark: dark)
                    ZStack(alignment: .top) {
                        DualScoreCol(score: product.yourScore,
                                     label: "Your Score", sublabel: "Tuned to your profile",
                                     dark: dark, highlight: store.accent)
                        Text("★ FOR YOU")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Capsule().fill(store.accent))
                            .offset(y: -8)
                    }
                }
                if showDelta, let reason = product.deltaReason {
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(delta > 0 ? "+" : "")\(delta)")
                            .font(.system(size: 11, weight: .heavy))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(
                                Capsule().fill(tone == .positive ? Color(hex: "1F8A5B") : Color(hex: "C9442B"))
                            )
                        Text(reason.text)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textPrimary(dark))
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tone == .positive
                                  ? Color(hex: "1F8A5B").opacity(dark ? 0.14 : 0.08)
                                  : Color(hex: "C9442B").opacity(dark ? 0.14 : 0.07))
                    )
                    .padding(.top, 18)
                }
                Button(action: onCompare) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 14, weight: .bold))
                        Text("Compare with another")
                            .font(.system(size: 14, weight: .heavy)).tracking(-0.2)
                    }
                    .foregroundColor(Theme.textPrimary(dark))
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(dark ? Color.white.opacity(0.08) : Theme.bgLight)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
            .padding(.horizontal, 20).padding(.vertical, 24)

            Button(action: onOpenMethodology) {
                Text("ⓘ")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.textSecondary(dark))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(dark ? Color.white.opacity(0.06)
                                                    : Color.black.opacity(0.04)))
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
    }

    private func gradesRow(dark: Bool) -> some View {
        HStack(spacing: 8) {
            NutriScoreCard(grade: product.nutriGrade, dark: dark)
            NovaCard(group: product.novaGroup, dark: dark)
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func nutrientsCard(dark: Bool) -> some View {
        let n = product.nutrients
        return CardView(dark: dark) {
            VStack(spacing: 0) {
                if let v = n.sugar_g {
                    NutrientRow(label: "Sugar", value: "\(fmt(v)) g",
                                tag: tagFromValue(v, t1: 5, t2: 12.5, higherIsBetter: false),
                                divider: false, dark: dark)
                }
                if let v = n.sodium_mg {
                    NutrientRow(label: "Sodium", value: "\(fmt(v)) mg",
                                tag: tagFromValue(v, t1: 120, t2: 400, higherIsBetter: false),
                                divider: true, dark: dark)
                }
                if let v = n.satFat_g {
                    NutrientRow(label: "Saturated fat", value: "\(fmt(v)) g",
                                tag: tagFromValue(v, t1: 1.5, t2: 5, higherIsBetter: false),
                                divider: true, dark: dark)
                }
                if let v = n.fiber_g {
                    NutrientRow(label: "Fiber", value: "\(fmt(v)) g",
                                tag: tagFromValue(v, t1: 3, t2: 6, higherIsBetter: true),
                                bonus: product.bonuses.contains("fiber"),
                                divider: true, dark: dark)
                }
                if let v = n.protein_g {
                    NutrientRow(label: "Protein", value: "\(fmt(v)) g",
                                tag: tagFromValue(v, t1: 5, t2: 12, higherIsBetter: true),
                                bonus: product.bonuses.contains("protein"),
                                divider: true, dark: dark)
                }
                if let v = n.calcium_mg {
                    NutrientRow(label: "Calcium", value: "\(fmt(v)) mg",
                                tag: tagFromValue(v, t1: 60, t2: 120, higherIsBetter: true),
                                bonus: product.bonuses.contains("calcium"),
                                divider: true, dark: dark)
                }
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
                    SeverityBar(additives: product.additives)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .overlay(alignment: .bottom) {
                            Theme.divider(dark).frame(height: 0.5)
                        }
                    ForEach(Array(product.additives.enumerated()), id: \.element.id) { (i, a) in
                        AdditiveRow(additive: a, divider: i > 0, dark: dark)
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

struct DualScoreCol: View {
    let score: Int
    let label: String
    let sublabel: String
    let dark: Bool
    var highlight: Color? = nil
    var body: some View {
        let c = scoreColor(score)
        VStack(spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy)).tracking(1.4)
                .foregroundColor(Theme.textSecondary(dark))
            ScoreRing(score: score, size: 108, stroke: 9, dark: dark)
            Text(scoreLabel(score).uppercased())
                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(c))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18).padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(highlight != nil ? c.opacity(0.06)
                                       : (dark ? Color.white.opacity(0.03) : Color.black.opacity(0.025)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(highlight != nil ? c.opacity(0.33) : Color.clear, lineWidth: 1.5)
        )
    }
}

struct NutriScoreCard: View {
    let grade: String
    let dark: Bool
    var body: some View {
        let colors: [String: Color] = [
            "A": Color(hex: "1F8A5B"), "B": Color(hex: "7BA935"),
            "C": Color(hex: "D4A02D"), "D": Color(hex: "E07A26"),
            "E": Color(hex: "C9442B"),
        ]
        let c = colors[grade] ?? Color.gray
        return HStack(spacing: 12) {
            Text(grade)
                .font(.system(size: 28, weight: .heavy)).tracking(-1)
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c))
            VStack(alignment: .leading, spacing: 6) {
                Text("NUTRI-SCORE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                    .foregroundColor(Theme.textSecondary(dark))
                HStack(spacing: 2) {
                    ForEach(["A","B","C","D","E"], id: \.self) { g in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(g == grade ? c
                                  : (dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)))
                            .frame(height: 4)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
        .frame(maxWidth: .infinity)
    }
}

struct NovaCard: View {
    let group: Int
    let dark: Bool
    var body: some View {
        let labels = [1: "Unprocessed", 2: "Culinary", 3: "Processed", 4: "Ultra-processed"]
        let colors: [Int: Color] = [
            1: Color(hex: "1F8A5B"), 2: Color(hex: "7BA935"),
            3: Color(hex: "D4A02D"), 4: Color(hex: "C9442B"),
        ]
        let c = colors[group] ?? .gray
        return HStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(1...4, id: \.self) { g in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(g <= group ? c
                              : (dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)))
                        .frame(width: 6, height: CGFloat(8 + g * 7))
                }
            }
            .frame(height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("PROCESSING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                    .foregroundColor(Theme.textSecondary(dark))
                Text("NOVA \(group)")
                    .font(.system(size: 13, weight: .heavy)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                Text(labels[group] ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(c)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
        .frame(maxWidth: .infinity)
    }
}

struct NutrientRow: View {
    let label: String
    let value: String
    let tag: Tag
    var bonus: Bool = false
    let divider: Bool
    let dark: Bool

    enum Tag { case low, med, high, none
        var fg: Color { switch self {
            case .low:  return Color(hex: "1F8A5B")
            case .med:  return Color(hex: "D4A02D")
            case .high: return Color(hex: "C9442B")
            case .none: return .gray }
        }
        var bg: Color { fg.opacity(0.10) }
        var label: String { switch self {
            case .low: return "Low"; case .med: return "Mod"
            case .high: return "High"; case .none: return "" }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                if bonus {
                    Text("+ BOOST")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                        .foregroundColor(Color(hex: "1F8A5B"))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: "1F8A5B").opacity(0.12)))
                }
            }
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .monospacedDigit().tracking(-0.2)
                .foregroundColor(Theme.textPrimary(dark))
                .frame(minWidth: 56, alignment: .trailing)
            if tag != .none {
                Text(tag.label.uppercased())
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundColor(tag.fg)
                    .frame(minWidth: 52)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(tag.bg))
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
    var body: some View {
        HStack(spacing: 12) {
            RiskDot(risk: additive.risk)
            VStack(alignment: .leading, spacing: 2) {
                Text(additive.name)
                    .font(.system(size: 14, weight: .semibold)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
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
                .foregroundColor(RiskStyle.fg(additive.risk))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(RiskStyle.bg(additive.risk)))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .top) {
            if divider { Theme.divider(dark).frame(height: 0.5).padding(.horizontal, 8) }
        }
    }
}

struct SeverityBar: View {
    let additives: [Additive]
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
                                .fill(RiskStyle.fg(r))
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
                        RiskDot(risk: r, size: 7)
                        Text("\(counts[r] ?? 0) \(RiskStyle.label(r).lowercased())")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(RiskStyle.fg(r))
                    }
                }
            }
        }
    }
}

struct RiskDot: View {
    let risk: RiskLevel
    var size: CGFloat = 10
    var body: some View {
        Circle().fill(RiskStyle.fg(risk)).frame(width: size, height: size)
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
        let fg = dark ? Color(hex: "FF8B6E") : Color(hex: "A33B23")
        HStack(alignment: .top, spacing: 10) {
            Text("⚠️").font(.system(size: 14))
            VStack(alignment: .leading, spacing: 1) {
                Text("Contains \(trigger), flagged by your profile")
                    .font(.system(size: 13, weight: .heavy)).tracking(-0.1)
                    .foregroundColor(fg)
                Text(type.uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .foregroundColor(fg.opacity(0.8))
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "C9442B").opacity(dark ? 0.18 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "C9442B").opacity(0.22), lineWidth: 1)
        )
    }
}

struct SeriousFlag: View {
    var body: some View {
        let fg = Color(hex: "A33B23")
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
                .fill(Color(hex: "C9442B").opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: "C9442B").opacity(0.30), lineWidth: 1.5)
        )
    }
}

// MARK: - Helpers

func fmt(_ v: Double) -> String {
    v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
}

func tagFromValue(_ v: Double, t1: Double, t2: Double, higherIsBetter: Bool) -> NutrientRow.Tag {
    if higherIsBetter {
        if v >= t2 { return .low }
        if v >= t1 { return .med }
        return .high
    } else {
        if v <= t1 { return .low }
        if v <= t2 { return .med }
        return .high
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
