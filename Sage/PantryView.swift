import SwiftUI

/// The Pantry tab: an underline-tab switch between scan History and the user-curated
/// Favorites shelf. Both children are self-contained lists; this container owns
/// only the mode toggle and the shared "Pantry" title. Each child contributes
/// its own trailing toolbar menu (clear history / clear favorites).
struct PantryView: View {
    let onOpenProduct: (String) -> Void
    var onTapScan: (() -> Void)? = nil

    @State private var mode: Mode = .history

    enum Mode: String, CaseIterable {
        case history = "History"
        case favorites = "Favorites"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Underline tabs, not a segmented control — the mode switch is the
            // screen's primary navigation, and two pills stacked on top of the
            // filter pills below read as a form, not a feed.
            SageUnderlineTabs(items: Mode.allCases, title: \.rawValue, selection: $mode)
                .padding(.top, 4)

            switch mode {
            case .history:
                HistoryView(onOpenProduct: onOpenProduct, onTapScan: onTapScan)
            case .favorites:
                FavoritesView(onOpenProduct: onOpenProduct, onTapScan: onTapScan)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Pantry")
        .navigationBarTitleDisplayMode(.inline)
    }
}
