import SwiftUI

// MARK: - Top Rated (TOPRATED_SPEC.md)

/// Category grid: the 14 Sage categories. The two with no data (water,
/// coffee — §2) are shown greyed out and disabled.
struct TopRatedCategoriesView: View {
    @EnvironmentObject var store: AppStore
    let onOpenCategory: (SageCategory) -> Void

    private let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let dark = store.darkMode
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                StaggeredAppear(index: 0) {
                    Text("Top Rated")
                        .font(.sageBold(34)).tracking(-1)
                        .foregroundColor(Theme.textPrimary(dark))
                        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
                }
                StaggeredAppear(index: 1) {
                    Text("The best-scoring products in each category.")
                        .font(.sageRegular(14))
                        .foregroundColor(Theme.textSecondary(dark))
                        .padding(.horizontal, 24).padding(.bottom, 14)
                }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(SageCategory.allCases) { category in
                        tile(category, dark: dark)
                    }
                }
                .padding(.horizontal, 16)
                Spacer().frame(height: 120)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
    }

    @ViewBuilder private func tile(_ category: SageCategory, dark: Bool) -> some View {
        let enabled = category.hasTopRated
        Button { onOpenCategory(category) } label: {
            HStack(spacing: 10) {
                Text(category.emoji).font(.sageRegular(22)).opacity(enabled ? 1 : 0.45)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayName)
                        .font(.sageBold(15)).tracking(-0.2)
                        .foregroundColor(enabled ? Theme.textPrimary(dark) : Theme.textSecondary(dark))
                        .lineLimit(1)
                    if !enabled {
                        Text("Not rated")
                            .font(.sageRegular(11))
                            .foregroundColor(Theme.textSecondary(dark))
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 14).padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
            )
            .cardShadow(dark)
            .opacity(enabled ? 1 : 0.6)
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .accessibilityLabel(enabled ? "Top rated \(category.displayName)"
                                    : "\(category.displayName), not rated")
    }
}

/// The best-scoring products in one category (ranked 1…20, Overall). Candidates
/// are re-scored on-device so the numbers match a fresh scan (§4).
struct TopRatedListView: View {
    @EnvironmentObject var store: AppStore
    let shelf: SageCategory
    let onBack: () -> Void
    let onOpenProduct: (Product) -> Void

    @State private var items: [Alternative] = []
    @State private var loaded = false

    var body: some View {
        let dark = store.darkMode
        VStack(spacing: 0) {
            SubHeader(title: shelf.displayName, onBack: onBack)
            ScrollView(showsIndicators: false) {
                if items.isEmpty {
                    Text(loaded ? "No rated products yet." : "Loading…")
                        .font(.sageRegular(14))
                        .foregroundColor(Theme.textSecondary(dark))
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            TopRatedRow(rank: idx + 1, alt: item, divider: idx > 0, dark: dark) {
                                onOpenProduct(item.product)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface(dark))
                    )
                    .cardShadow(dark)
                    .padding(.horizontal, 16)
                }
                Spacer().frame(height: 120)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
        .onAppear {
            guard !loaded else { return }
            items = TopRated.items(for: shelf, profile: store.user)
            loaded = true
        }
    }
}

/// One ranked Top Rated row — rank number + thumb + name + score pill.
private struct TopRatedRow: View {
    let rank: Int
    let alt: Alternative
    let divider: Bool
    let dark: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.sageBold(15)).monospacedDigit()
                    .foregroundColor(Theme.textSecondary(dark))
                    .frame(width: 22, alignment: .center)
                ProductThumb(glyph: alt.product.glyph, score: alt.score, size: 56,
                             imageURL: alt.product.listImageURL,
                             processCutout: alt.product.shouldProcessCutout)
                VStack(alignment: .leading, spacing: 1) {
                    if !alt.product.brand.isEmpty {
                        Text(alt.product.brand.uppercased())
                            .font(.sageBold(10)).tracking(1.2)
                            .foregroundColor(Theme.textSecondary(dark))
                            .lineLimit(1)
                    }
                    Text(alt.product.name)
                        .font(.sageBold(14)).tracking(-0.2)
                        .foregroundColor(Theme.textPrimary(dark))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                YourScorePill(score: alt.score, isUnscored: false)
                Image(systemName: "chevron.right")
                    .font(.sageBold(12))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .overlay(alignment: .top) {
                if divider {
                    Theme.divider(dark).frame(height: 0.5).padding(.horizontal, 12)
                }
            }
        }
        .buttonStyle(.pressable)
    }
}
