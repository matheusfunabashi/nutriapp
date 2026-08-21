import SwiftUI

/// The user-curated favorites shelf, newest first. Rows reuse `ProductRow` (the
/// same visual as History); swipe removes one, the toolbar menu clears all.
struct FavoritesView: View {
    @EnvironmentObject var store: AppStore
    let onOpenProduct: (String) -> Void
    var onTapScan: (() -> Void)? = nil

    @State private var confirmingClear = false
    /// Edges for `.sensoryFeedback` — bumped on remove and clear-all.
    @State private var removedTick = 0
    @State private var clearedTick = 0

    /// "Worth saving" starter rows for the empty shelf; resolved once.
    @State private var starterPicks: [Alternative] = []

    var body: some View {
        List {
            if store.favorites.isEmpty {
                Section {
                    StarterIntroCard(
                        symbol: "heart",
                        title: "Keep the ones you love",
                        message: "Tap the heart on any product page and it lands here — your shortlist for the next shop."
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                }
                if !starterPicks.isEmpty {
                    Section("WORTH SAVING") {
                        ForEach(starterPicks) { pick in
                            StarterProductRow(pick: pick, showsHeart: true) {
                                store.saveProduct(pick.product)
                                onOpenProduct(pick.product.id)
                            }
                        }
                    }
                }
            }

            ForEach(store.favorites) { fav in
                if let p = store.products[fav.productId] {
                    ProductRow(product: p, when: FavoriteEntry.addedAgoLabel(since: fav.addedAt)) {
                        onOpenProduct(p.id)
                    }
                    .swipeActions {
                        Button("Remove", systemImage: "heart.slash", role: .destructive) {
                            store.removeFavorite(fav)
                            removedTick &+= 1
                        }
                    }
                }
            }
        }
        .sageListStyle()
        .contentMargins(.top, store.favorites.isEmpty ? 0 : 16, for: .scrollContent)
        .task(id: store.favorites.isEmpty) {
            guard store.favorites.isEmpty, starterPicks.isEmpty else { return }
            starterPicks = StarterPicks.picks(for: store.user, limit: 3)
        }
        .toolbar {
            if !store.favorites.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Clear Favorites", systemImage: "trash", role: .destructive) {
                            confirmingClear = true
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        // Clearing the whole shelf can't be undone, so it goes through the
        // system's destructive confirmation rather than firing from the menu.
        .confirmationDialog("Remove all favorites?",
                            isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear Favorites", role: .destructive) {
                store.clearFavorites()
                clearedTick &+= 1
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Only your favorites shelf is cleared. Scan history and saved products are kept.")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: removedTick)
        .sensoryFeedback(.warning, trigger: clearedTick)
    }
}
