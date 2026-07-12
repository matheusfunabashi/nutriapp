import SwiftUI

struct CompareView: View {
    @EnvironmentObject var store: AppStore
    let a: Product
    let b: Product
    let onBack: () -> Void

    var body: some View {
        let dark = store.darkMode
        let delta = b.yourScore - a.yourScore
        let tie = abs(delta) <= 3
        let winner: String? = tie ? nil : (delta > 0 ? "b" : "a")

        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar(dark: dark)
                title(dark: dark, tie: tie, winner: winner, delta: delta)
                HStack(spacing: 8) {
                    CompareCol(product: a, isWinner: winner == "a", tie: tie, dark: dark)
                    CompareCol(product: b, isWinner: winner == "b", tie: tie, dark: dark)
                }
                .padding(.horizontal, 16).padding(.top, 12)
                SectionTitle(title: "Nutrients", subtitle: "Per 100g / 100ml", dark: dark)
                nutrientsCompare(dark: dark)
                SectionTitle(title: "Additives",
                             subtitle: "\(a.additives.count) vs \(b.additives.count)", dark: dark)
                additivesCompare(dark: dark)
                disclaimer(dark: dark)
                Spacer().frame(height: 120)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
    }

    private func topBar(dark: Bool) -> some View {
        HStack {
            CircleIconButton(systemName: "chevron.left", dark: dark, action: onBack)
            Spacer()
            Text("COMPARE")
                .font(.sageBold(13)).tracking(1.3)
                .foregroundColor(Theme.textSecondary(dark))
            Spacer()
            Color.clear.frame(width: 42, height: 42)
        }
        .padding(.horizontal, 16).padding(.top, 60).padding(.bottom, 12)
    }

    private func title(dark: Bool, tie: Bool, winner: String?, delta: Int) -> some View {
        let summary: String = {
            if tie { return "These are roughly equivalent for your profile." }
            let winName = (winner == "a" ? a : b).name
            let diff = abs(delta)
            return "\(winName) is +\(diff) better for you."
        }()
        return VStack(alignment: .leading, spacing: 4) {
            Text(tie ? "It's a tie" : "Better choice")
                .font(.sageBold(26)).tracking(-0.6)
                .foregroundColor(Theme.textPrimary(dark))
            Text(summary)
                .font(.sageRegular(14))
                .foregroundColor(Theme.textSecondary(dark))
                .lineSpacing(2)
        }
        .padding(.horizontal, 24).padding(.bottom, 2)
    }

    private func nutrientsCompare(dark: Bool) -> some View {
        CardView(dark: dark) {
            VStack(spacing: 0) {
                CompareRow(label: "Sugar",
                           av: a.nutrients.sugar_g, bv: b.nutrients.sugar_g,
                           unit: "g", higherIsBetter: false, divider: false, dark: dark)
                CompareRow(label: "Sodium",
                           av: a.nutrients.sodium_mg, bv: b.nutrients.sodium_mg,
                           unit: "mg", higherIsBetter: false, divider: true, dark: dark)
                CompareRow(label: "Sat fat",
                           av: a.nutrients.satFat_g, bv: b.nutrients.satFat_g,
                           unit: "g", higherIsBetter: false, divider: true, dark: dark)
                CompareRow(label: "Fiber",
                           av: a.nutrients.fiber_g, bv: b.nutrients.fiber_g,
                           unit: "g", higherIsBetter: true, divider: true, dark: dark)
                CompareRow(label: "Protein",
                           av: a.nutrients.protein_g, bv: b.nutrients.protein_g,
                           unit: "g", higherIsBetter: true, divider: true, dark: dark)
                CompareRow(label: "Calcium",
                           av: a.nutrients.calcium_mg, bv: b.nutrients.calcium_mg,
                           unit: "mg", higherIsBetter: true, divider: true, dark: dark)
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 16)
    }

    private func additivesCompare(dark: Bool) -> some View {
        HStack(spacing: 8) {
            AdditivesCol(product: a, dark: dark)
            AdditivesCol(product: b, dark: dark)
        }
        .padding(.horizontal, 16)
    }

    private func disclaimer(dark: Bool) -> some View {
        Text("This is not professional advice. For specialized recommendation, seek a nutritionist.")
            .font(.sageRegular(11))
            .multilineTextAlignment(.center)
            .foregroundColor(Theme.textSecondary(dark))
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
            .frame(maxWidth: .infinity)
    }
}

struct CompareCol: View {
    let product: Product
    let isWinner: Bool
    let tie: Bool
    let dark: Bool
    var body: some View {
        let c = scoreColor(product.yourScore)
        VStack(alignment: .leading, spacing: 10) {
            if isWinner {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.sageBold(9))
                        .foregroundColor(.white)
                    Text("BETTER")
                        .font(.sageBold(10)).tracking(1)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(c))
                .offset(y: -22)
                .padding(.bottom, -22)
            }
            ProductThumb(glyph: product.glyph, score: product.yourScore, size: 60,
                         imageURL: product.imageURL)
            Text(product.brand.uppercased())
                .font(.sageBold(10)).tracking(1.2)
                .foregroundColor(Theme.textSecondary(dark))
            Text(product.name)
                .font(.sageBold(14)).tracking(-0.2)
                .lineLimit(2)
                .foregroundColor(Theme.textPrimary(dark))
                .frame(minHeight: 34, alignment: .top)
            Text(product.size)
                .font(.sageRegular(11))
                .foregroundColor(Theme.textSecondary(dark))

            if !product.restrictions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(product.restrictions) { r in
                        HStack(spacing: 5) {
                            Text("⚠️").font(.sageRegular(10))
                            Text(r.trigger)
                                .font(.sageBold(10))
                                .foregroundColor(Color(hex: "C9442B"))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Color(hex: "C9442B").opacity(0.08))
                        .cornerRadius(8)
                    }
                }
            }

            Divider().background(Theme.divider(dark)).padding(.top, 4)

            ScoreLine(label: "Your", score: product.yourScore, prominent: true, dark: dark)
            ScoreLine(label: "Overall", score: product.overallScore, prominent: false, dark: dark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isWinner ? c : Color.clear, lineWidth: 2)
        )
        .cardShadow(dark)
    }
}

struct ScoreLine: View {
    let label: String
    let score: Int
    let prominent: Bool
    let dark: Bool
    var body: some View {
        let c = scoreColor(score)
        HStack {
            Text(label.uppercased())
                .font(.sageBold(10)).tracking(1.2)
                .foregroundColor(Theme.textSecondary(dark))
            Spacer()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(score)")
                    .font(.sageBold(prominent ? 24 : 16))
                    .monospacedDigit().tracking(-0.6)
                    .foregroundColor(c)
                Text(scoreLabel(score).uppercased())
                    .font(.sageBold(9)).tracking(0.4)
                    .foregroundColor(c)
            }
        }
    }
}

struct CompareRow: View {
    let label: String
    let av: Double?
    let bv: Double?
    let unit: String
    let higherIsBetter: Bool
    let divider: Bool
    let dark: Bool
    var body: some View {
        let aN = av ?? 0
        let bN = bv ?? 0
        let valid = av != nil && bv != nil
        let aWins: Bool = valid ? (higherIsBetter ? aN > bN : aN < bN) : false
        let bWins: Bool = valid ? (higherIsBetter ? bN > aN : bN < aN) : false
        return HStack(spacing: 8) {
            ValueCell(value: av.map { "\(fmt($0)) \(unit)" } ?? ",", winner: aWins, align: .leading, dark: dark)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(label.uppercased())
                .font(.sageBold(11)).tracking(0.5)
                .foregroundColor(Theme.textSecondary(dark))
                .frame(maxWidth: .infinity, alignment: .center)
            ValueCell(value: bv.map { "\(fmt($0)) \(unit)" } ?? ",", winner: bWins, align: .trailing, dark: dark)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(alignment: .top) {
            if divider { Theme.divider(dark).frame(height: 0.5).padding(.horizontal, 8) }
        }
    }
}

struct ValueCell: View {
    let value: String
    let winner: Bool
    let align: HorizontalAlignment
    let dark: Bool
    var body: some View {
        HStack(spacing: 6) {
            if align == .leading && winner { winnerMark }
            Text(value)
                .font(.sageBold(15))
                .monospacedDigit().tracking(-0.3)
                .foregroundColor(Theme.textPrimary(dark))
            if align == .trailing && winner { winnerMark }
        }
    }
    private var winnerMark: some View {
        ZStack {
            Circle().fill(Color(hex: "1F8A5B")).frame(width: 16, height: 16)
            Image(systemName: "checkmark")
                .font(.sageBold(9))
                .foregroundColor(.white)
        }
    }
}

struct AdditivesCol: View {
    let product: Product
    let dark: Bool
    var body: some View {
        let sorted = product.additives.sorted { rank($0.risk) > rank($1.risk) }
        return VStack(alignment: .leading, spacing: 4) {
            if sorted.isEmpty {
                VStack(spacing: 6) {
                    Circle().fill(Color(hex: "1F8A5B")).frame(width: 8, height: 8)
                    Text("No additives")
                        .font(.sageBold(11))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Theme.textPrimary(dark))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { (i, a) in
                    HStack(spacing: 7) {
                        Circle().fill(RiskStyle.fg(a.risk)).frame(width: 7, height: 7)
                        Text(a.name)
                            .font(.sageSemiBold(11))
                            .lineLimit(1)
                            .foregroundColor(Theme.textPrimary(dark))
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 4)
                    .overlay(alignment: .top) {
                        if i > 0 { Theme.divider(dark).frame(height: 0.5) }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
    }
    private func rank(_ r: RiskLevel) -> Int {
        switch r {
        case .low: return 0; case .moderate: return 1
        case .high: return 2; case .unrated: return -1
        }
    }
}
