import SwiftUI

// MARK: - Verdict styling

extension KeyIngredients.Verdict {
    /// Good → score green, Fine → neutral gray, Limit → amber, Avoid → red.
    /// Same bands as the nutrient tags, so the page speaks one color language.
    var color: Color {
        switch self {
        case .good:    return Color.scoreGood
        case .neutral: return Color.neutralMuted
        case .limit:   return Color.scoreOk
        case .avoid:   return Color.scoreBad
        }
    }
}

// MARK: - Tally rows

/// The two-line verdict under the overview: how many real-food ingredients,
/// how many worth limiting. Scannable before the prose is readable.
struct IngredientTallyRows: View {
    let analysis: KeyIngredients.Analysis

    var body: some View {
        VStack(spacing: 0) {
            row(icon: "leaf", title: "Whole-food ingredients",
                count: analysis.goodCount,
                dot: analysis.goodCount > 0 ? Color.scoreGood : Color.neutralMuted)
            row(icon: "exclamationmark.triangle", title: "Worth limiting",
                count: analysis.watchCount,
                dot: analysis.watchCount == 0 ? Color.neutralMuted
                     : (analysis.hasAvoid ? Color.scoreBad : Color.scoreOk))
            Theme.hairline.frame(height: 0.5).padding(.horizontal, 20)
        }
    }

    private func row(icon: String, title: LocalizedStringKey, count: Int, dot: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.sageSemiBold(15))
                .foregroundColor(Theme.inkSecondary)
                .frame(width: 24)
            Text(title)
                .font(.sageSemiBold(16)).tracking(-0.2)
                .foregroundColor(Theme.ink)
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.sageSemiBold(16))
                .monospacedDigit()
                .foregroundColor(Theme.ink)
            Circle().fill(dot).frame(width: 10, height: 10)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .overlay(alignment: .top) {
            Theme.hairline.frame(height: 0.5).padding(.horizontal, 20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title) + Text(": \(count)"))
    }
}

// MARK: - Row

/// One key ingredient: name with the verdict word under it, colored dot and
/// chevron on the right. Tap → `IngredientDetailSheet`.
struct KeyIngredientRow: View {
    let item: KeyIngredients.Item

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.sageSemiBold(16)).tracking(-0.2)
                    .foregroundColor(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(item.verdict.label)
                    .font(.sageSemiBold(13))
                    .foregroundColor(item.verdict.color)
            }
            Spacer(minLength: 8)
            Circle().fill(item.verdict.color).frame(width: 10, height: 10)
            Image(systemName: "chevron.right")
                .font(.sageSemiBold(11))
                .foregroundColor(Theme.inkSecondary.opacity(0.6))
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            Theme.hairline.frame(height: 0.5).padding(.horizontal, 20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.verdict.label)")
        .accessibilityHint("Shows why")
    }
}

// MARK: - Detail sheet

/// Bottom sheet for one non-additive ingredient: verdict, "In this product"
/// (position, share, the reason for the verdict), then the knowledge-base
/// explainer and how Sage's four verdict words are defined.
struct IngredientDetailSheet: View {
    let item: KeyIngredients.Item
    /// Total tokens on the label, for "Ingredient 2 of 7".
    let total: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.name)
                            .font(.sageBold(24)).tracking(-0.5)
                            .foregroundColor(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Circle().fill(item.verdict.color).frame(width: 10, height: 10)
                            Text(item.verdict.label)
                                .font(.sageSemiBold(15))
                                .foregroundColor(item.verdict.color)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    inThisProduct

                    if let about = item.about, !about.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("About")
                                .font(.sageSemiBold(15))
                                .foregroundColor(Theme.ink)
                            Text(about)
                                .font(.sageRegular(15))
                                .foregroundColor(Theme.inkSecondary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("How Sage rates ingredients")
                            .font(.sageSemiBold(13))
                            .foregroundColor(Theme.ink)
                        Text("Good — a whole food. Fine — not a concern on its own. Limit — added sugar, refined fat or a sweetener the ruleset docks. Avoid — industrial trans fat or a high-risk additive. Verdicts come from the label and Sage's published ruleset, never from the product's marketing.")
                            .font(.sageRegular(13))
                            .foregroundColor(Theme.inkSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// The one panel on the sheet — product-specific facts.
    private var inThisProduct: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("In this product")
                .font(.sageSemiBold(15))
                .foregroundColor(Theme.ink)
            Text(positionLine)
                .font(.sageRegular(13))
                .monospacedDigit()
                .foregroundColor(Theme.inkSecondary)
            Text(item.reason)
                .font(.sageRegular(15))
                .foregroundColor(Theme.ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.fillQuiet)
        )
    }

    private var positionLine: String {
        let n = item.position + 1
        var parts = [String(localized: "Ingredient \(n) of \(total)")]
        if let share = item.share {
            let pct = share >= 10 ? String(format: "%.0f", share) : String(format: "%.1f", share)
            parts.append(item.shareIsDeclared ? String(localized: "\(pct)% declared")
                                              : String(localized: "~\(pct)% estimated"))
        } else if item.position == 0 {
            parts.append(String(localized: "listed first, so the largest share"))
        }
        return parts.joined(separator: " · ")
    }
}
