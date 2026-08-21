import SwiftUI

// MARK: - Top Rated (TOPRATED_SPEC.md)

/// Two-up category grid over `SageCategory.topRatedBrowse` — hero pack shot
/// when the asset exists, emoji tile otherwise. Water / coffee (unscored) and
/// energy drinks (nothing rates well) are excluded from the list itself.
struct TopRatedCategoriesView: View {
    @EnvironmentObject var store: AppStore
    let onOpenCategory: (SageCategory) -> Void

    /// Live pack shot for shelves with no bundled hero asset: the shelf's #1
    /// product, resolved lazily per card. Emoji was the old fallback, but five
    /// emoji tiles in a grid of real product photos read as unfinished — now
    /// the emoji only shows while the photo loads (or offline).
    @State private var heroProducts: [SageCategory: Product] = [:]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(SageCategory.topRatedBrowse) { category in
                    categoryCard(category)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Top Rated")
    }

    private func categoryCard(_ category: SageCategory) -> some View {
        Button { onOpenCategory(category) } label: {
            HStack(spacing: 8) {
                Text(category.displayName)
                    .font(.sageBold(15)).tracking(-0.2)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if let asset = category.bundledTopRatedHeroAsset {
                        Image(asset)
                            .resizable()
                            .scaledToFit()
                    } else if let hero = heroProducts[category] {
                        ProductThumb(glyph: category.emoji, score: nil, size: 56,
                                     imageURL: hero.listImageURL,
                                     fallbackImageURL: hero.imageFallbackURL,
                                     processCutout: hero.shouldProcessCutout)
                    } else {
                        Text(category.emoji)
                            .font(.sageRegular(32))
                    }
                }
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.card)
            )
            .cardShadow()
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Top rated \(category.displayName)")
        .task(id: category.id) {
            guard category.bundledTopRatedHeroAsset == nil,
                  heroProducts[category] == nil else { return }
            // Highest-ranked product that actually has a photo — a top pick
            // with no image slot would put the barcode fallback on the tile.
            let ranked = TopRated.items(for: category, profile: store.user)
            if let hero = ranked.first(where: { $0.product.listImageURL != nil })
                ?? ranked.first {
                heroProducts[category] = hero.product
            }
        }
    }
}

/// The best-scoring products in one category (ranked 1…10, Overall). Candidates
/// are re-scored on-device so the numbers match a fresh scan (§4).
struct TopRatedListView: View {
    @EnvironmentObject var store: AppStore
    let shelf: SageCategory
    let onOpenProduct: (Product) -> Void
    var onTapScan: (() -> Void)? = nil

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
                    ContentUnavailableView {
                        Label("Nothing to rank yet", systemImage: "trophy")
                    } description: {
                        Text("This category doesn't have enough scored products yet.")
                    } actions: {
                        if let onTapScan {
                            Button("Scan a product", action: onTapScan)
                                .buttonStyle(.borderedProminent)
                                .tint(store.accent)
                        }
                    }
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
                             fallbackImageURL: alt.product.imageFallbackURL,
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
                        // Two lines: "Organic Whole M…" truncations made
                        // half the ranked names unreadable.
                        .lineLimit(2)
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
