import SwiftUI

// MARK: - Top Rated (TOPRATED_SPEC.md)

/// Category grid: Sage categories. Water and coffee have no data (TOPRATED_SPEC
/// §2) and are shown greyed out and disabled.
struct TopRatedCategoriesView: View {
    @EnvironmentObject var store: AppStore
    let onOpenCategory: (SageCategory) -> Void

    var body: some View {
        List {
            Section {
                ForEach(SageCategory.allCases) { category in
                    row(category)
                }
            } footer: {
                Text("The best-scoring products in each category.")
            }
        }
        .sageListStyle()
        .navigationTitle("Top Rated")
    }

    @ViewBuilder private func row(_ category: SageCategory) -> some View {
        let enabled = category.hasTopRated
        Button { onOpenCategory(category) } label: {
            HStack(spacing: 12) {
                Text(category.emoji)
                    .font(.sageRegular(22))
                    .opacity(enabled ? 1 : 0.45)
                Text(category.displayName)
                    .font(.sageBold(15)).tracking(-0.2)
                    .foregroundColor(enabled ? Theme.ink : Theme.inkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if enabled {
                    Image(systemName: "chevron.right")
                        .font(.sageBold(12))
                        .foregroundColor(Theme.inkSecondary)
                } else {
                    Text("Not rated")
                        .font(.sageRegular(12))
                        .foregroundColor(Theme.inkSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    let onOpenProduct: (Product) -> Void

    @State private var items: [Alternative] = []
    @State private var loaded = false

    var body: some View {
        List {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                TopRatedRow(rank: idx + 1, alt: item) {
                    onOpenProduct(item.product)
                }
            }
        }
        .sageListStyle()
        .overlay {
            if items.isEmpty {
                if loaded {
                    ContentUnavailableView("No rated products yet",
                                           systemImage: "trophy",
                                           description: Text("Nothing in this category has enough data to rank."))
                } else {
                    ProgressView().tint(store.accent)
                }
            }
        }
        .navigationTitle(shelf.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
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
    let onTap: () -> Void

    var body: some View {
        let formatted = ProductNameFormatter.format(alt.product)
        return Button(action: onTap) {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.sageBold(15)).monospacedDigit()
                    .foregroundColor(Theme.inkSecondary)
                    .frame(width: 22, alignment: .center)
                ProductThumb(glyph: alt.product.glyph, score: alt.score, size: 56,
                             imageURL: alt.product.listImageURL,
                             processCutout: alt.product.shouldProcessCutout)
                VStack(alignment: .leading, spacing: 1) {
                    if let brand = formatted.brand {
                        Text(brand.uppercased())
                            .font(.sageBold(10)).tracking(1.2)
                            .foregroundColor(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                    Text(formatted.name)
                        .font(.sageBold(14)).tracking(-0.2)
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                    if let size = formatted.size {
                        Text(size)
                            .font(.sageRegular(11))
                            .foregroundColor(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                YourScorePill(score: alt.score, isUnscored: false)
                Image(systemName: "chevron.right")
                    .font(.sageBold(12))
                    .foregroundColor(Theme.inkSecondary)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Number \(rank), \(formatted.accessibilityLabel)")
        }
        .buttonStyle(.plain)
    }
}
