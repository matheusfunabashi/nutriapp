import SwiftUI

struct SearchView: View {
    @EnvironmentObject var store: AppStore
    /// Called with the barcode of the tapped hit — ContentView runs the same
    /// lookup → score → /explain pipeline as a camera scan.
    let onSelect: (String) -> Void
    var onTapScan: (() -> Void)? = nil

    private enum Phase: Equatable {
        case idle          // under 2 chars typed
        case searching
        case results([BackendService.SearchHit])
        case empty         // OFF has no match → "Product not available."
        case failed
    }

    @State private var query: String = ""
    @State private var phase: Phase = .idle
    @State private var searchTask: Task<Void, Never>? = nil

    private let backend = BackendService()

    var body: some View {
        List {
            switch phase {
            case .idle:
                Section("Browse") {
                    ForEach(Self.categories, id: \.name) { category in
                        Button {
                            query = category.name
                        } label: {
                            HStack(spacing: 12) {
                                Text(category.emoji)
                                    .font(.sageRegular(20))
                                    .frame(width: 26)
                                Text(category.name)
                                    .font(.sageBold(15)).tracking(-0.2)
                                    .foregroundColor(Theme.ink)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Browse \(category.name)")
                    }
                }
            case .results(let hits):
                ForEach(hits) { hit in
                    SearchHitRow(hit: hit) { onSelect(hit.code) }
                }
            case .searching, .empty, .failed:
                EmptyView()
            }
        }
        .sageListStyle()
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        // The system search field: it lands in the navigation bar, brings its
        // own cancel button, scroll-to-dismiss, and keyboard handling.
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search by product or brand")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .scrollDismissesKeyboard(.immediately)
        .overlay { statusOverlay }
        .onChange(of: query) { _, newValue in scheduleSearch(for: newValue) }
    }

    @ViewBuilder private var statusOverlay: some View {
        switch phase {
        case .searching:
            ProgressView("Searching…")
                .tint(store.accent)
                .font(.sageRegular(13))
        case .empty:
            ContentUnavailableView {
                Label("No products found", systemImage: "magnifyingglass")
            } description: {
                Text("Try another name or brand — or scan the label instead.")
            } actions: {
                if let onTapScan {
                    Button("Scan a product", action: onTapScan)
                        .buttonStyle(.borderedProminent)
                        .tint(store.accent)
                }
            }
        case .failed:
            ContentUnavailableView {
                Label("Couldn't reach the catalog", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            }
        case .idle, .results:
            EmptyView()
        }
    }

    // MARK: Debounced typeahead

    /// Waits out a typing pause before hitting the backend, and cancels the
    /// in-flight request whenever another character arrives — only the latest
    /// query's results ever land.
    private func scheduleSearch(for raw: String) {
        searchTask?.cancel()
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            phase = .idle
            return
        }
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            phase = .searching
            do {
                let hits = try await backend.search(q)
                guard !Task.isCancelled else { return }
                phase = hits.isEmpty ? .empty : .results(hits)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed
            }
        }
    }

    // MARK: Browse categories (idle opener)

    /// Tapping a row drops its term into the search field, which fires the same
    /// debounced typeahead pipeline as manual typing. Kept in sync with
    /// `SageCategory.topRatedBrowse` — no Water / Coffee / etc., since those
    /// either can't score or aren't in Top Rated yet.
    private static let categories: [(emoji: String, name: String)] = [
        ("🥤", "Soda"),        ("🧃", "Juice"),
        ("🥛", "Milk"),        ("🥛", "Yogurt"),
        ("🧀", "Cheese"),      ("🍦", "Ice cream"),
        ("🥣", "Cereal"),      ("🍞", "Bread"),
        ("🍝", "Pasta"),       ("🍟", "Chips"),
        ("▣", "Snack bars"),  ("🍫", "Chocolate"),
    ]
}

// MARK: - Result row

private struct SearchHitRow: View {
    let hit: BackendService.SearchHit
    let onTap: () -> Void

    var body: some View {
        let formatted = ProductNameFormatter.format(
            productName: hit.name,
            brands: hit.brand.isEmpty ? nil : hit.brand,
            quantity: hit.quantity
        )
        return Button(action: onTap) {
            HStack(spacing: 12) {
                thumb
                VStack(alignment: .leading, spacing: 1) {
                    if let brand = formatted.brand {
                        Text(brand.uppercased())
                            .font(.sageBold(10)).tracking(1.2)
                            .foregroundColor(Theme.inkSecondary)
                    }
                    Text(formatted.name)
                        .font(.sageBold(14))
                        .foregroundColor(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let size = formatted.size {
                        Text(size)
                            .font(.sageRegular(11))
                            .foregroundColor(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.sageBold(12))
                    .foregroundColor(Theme.inkSecondary)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(formatted.accessibilityLabel)
        }
        .buttonStyle(.plain)
    }

    /// Prefer the OFF thumb already on the search hit — it's a small CDN URL
    /// that arrives with the typeahead payload. Falling back to `/images/{barcode}`
    /// only when OFF has no photo; that path is a Worker lazy-resolve and is
    /// too slow to fire for every row. No Vision cutout on 44pt tiles.
    private var thumb: some View {
        let offThumb = hit.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = (offThumb?.isEmpty == false ? offThumb : nil)
            ?? BackendService.productImageURL(barcode: hit.code)
        return ProductImageView(
            url: URL(string: urlString),
            style: .fixed(44),
            glyph: "🛒",
            processCutout: false
        )
    }
}
