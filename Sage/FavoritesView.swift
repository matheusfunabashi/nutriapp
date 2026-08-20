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

    var body: some View {
        List {
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
        .overlay {
            if store.favorites.isEmpty {
                ContentUnavailableView {
                    Label("No favorites yet", systemImage: "heart")
                } description: {
                    Text("Open any product and tap Add to favorites to keep it here.")
                } actions: {
                    if let onTapScan {
                        Button("Scan a product", action: onTapScan)
                            .buttonStyle(.borderedProminent)
                            .tint(store.accent)
                    }
                }
            }
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
