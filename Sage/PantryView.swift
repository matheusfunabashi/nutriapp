import SwiftUI

/// The Pantry tab: a segmented switch between scan History and the user-curated
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
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

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
