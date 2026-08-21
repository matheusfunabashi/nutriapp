import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    let onOpenProduct: (String) -> Void
    var onTapScan: (() -> Void)? = nil

    @State private var filter: Filter = .all
    @State private var confirmingClear = false
    /// Edges for `.sensoryFeedback` — bumped on clear-all and swipe-delete.
    @State private var clearedTick = 0
    @State private var deletedTick = 0

    enum Filter: String, CaseIterable { case all, good, bad }

    /// Goal-aware starter rows for the empty state; resolved once.
    @State private var starterPicks: [Alternative] = []

    var body: some View {
        VStack(spacing: 0) {
            // Filter chips (capsules with counts) — a secondary filter under the
            // underline tabs, the way Airbnb / Uber Eats do it. Lives outside
            // the List so it shares the tabs' 20pt gutter instead of inheriting
            // the inset-grouped section margin (which differs by iOS version).
            // Hidden until there's something to filter — "All 0 · Good 0" reads
            // as dead controls.
            if !store.history.isEmpty {
            HStack(spacing: 8) {
                ForEach(Filter.allCases, id: \.self) { f in
                    SageChip(title: title(for: f), count: count(for: f), selected: filter == f) {
                        withAnimation(.easeOut(duration: 0.2)) { filter = f }
                    }
                }
            }
            // Centered, like the tab labels and the empty state above/below it.
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .sensoryFeedback(.selection, trigger: filter)
            }

            historyList
        }
        .background(Theme.background.ignoresSafeArea())
        .task(id: store.history.isEmpty) {
            guard store.history.isEmpty, starterPicks.isEmpty else { return }
            starterPicks = StarterPicks.picks(for: store.user, limit: 3)
        }
    }

    private var historyList: some View {
        List {
            if store.history.isEmpty {
                // First-run: a compact, top-anchored intro that says what this
                // screen becomes, then real products to open right now —
                // content pulls the eye, not whitespace.
                Section {
                    StarterIntroCard(
                        symbol: "clock.arrow.circlepath",
                        title: "Your scans will line up here",
                        message: "Every product you scan lands in this feed, grouped by day, with its score — so you can see how your pantry is trending.",
                        cta: onTapScan.map { ("Scan a product", $0) }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                }
                if !starterPicks.isEmpty {
                    Section("MEANWHILE, WORTH A LOOK") {
                        ForEach(starterPicks) { pick in
                            StarterProductRow(pick: pick) {
                                store.saveProduct(pick.product)
                                onOpenProduct(pick.product.id)
                            }
                        }
                    }
                }
            }

            ForEach(groupedDays, id: \.day) { entry in
                Section(entry.day.uppercased()) {
                    ForEach(entry.items) { h in
                        if let p = store.products[h.productId] {
                            ProductRow(product: p, when: h.time) {
                                onOpenProduct(p.id)
                            }
                            // Swipe-to-delete is the platform gesture for a
                            // feed like this — no custom edit mode needed.
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    store.deleteHistory(h)
                                    deletedTick &+= 1
                                }
                            }
                        }
                    }
                }
            }
        }
        .sageListStyle()
        .contentMargins(.top, store.history.isEmpty ? 0 : 16, for: .scrollContent)
        .overlay {
            // Only the *filtered*-empty case keeps a system empty view; the
            // first-run case is handled by the starter rows above.
            if !store.history.isEmpty && groupedDays.isEmpty {
                ContentUnavailableView {
                    Label("Nothing in this filter", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Try All, or scan something new.")
                } actions: {
                    Button("Show all") { filter = .all }
                        .buttonStyle(.borderedProminent)
                        .tint(store.accent)
                }
            }
        }
        .toolbar {
            if !store.history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Clear History", systemImage: "trash", role: .destructive) {
                            confirmingClear = true
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        // Clearing every scan can't be undone, so it goes through the system's
        // destructive confirmation rather than firing straight from the menu.
        .confirmationDialog("Clear all scan history?",
                            isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                store.clearHistory()
                clearedTick &+= 1
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your saved products are kept — only the history feed is cleared.")
        }
        .sensoryFeedback(.warning, trigger: clearedTick)
        .sensoryFeedback(.impact(weight: .light), trigger: deletedTick)
    }

    private func title(for f: Filter) -> String {
        switch f {
        case .all:  return "All"
        case .good: return "Good"
        case .bad:  return "Avoid"
        }
    }

    private func count(for f: Filter) -> Int {
        switch f {
        case .all:  return store.history.count
        case .good: return count { $0 >= 50 }
        case .bad:  return count { $0 < 50 }
        }
    }

    private func count(_ predicate: (Int) -> Bool) -> Int {
        store.history.filter {
            guard let s = store.products[$0.productId]?.yourScore else { return false }
            return predicate(s)
        }.count
    }

    private var filtered: [HistoryEntry] {
        store.history.filter { h in
            guard let p = store.products[h.productId] else { return false }
            switch filter {
            case .all: return true
            case .good: return (p.yourScore ?? -1) >= 50
            case .bad: return p.yourScore.map { $0 < 50 } ?? false
            }
        }
    }

    private var groupedDays: [(day: String, items: [HistoryEntry])] {
        var order: [String] = []
        var groups: [String: [HistoryEntry]] = [:]
        for h in filtered {
            if groups[h.day] == nil { order.append(h.day) }
            groups[h.day, default: []].append(h)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }
}

/// A tappable product row (thumbnail, brand/name, meta subtitle, score pill).
/// Shared by the History and Favorites lists.
struct ProductRow: View {
    let product: Product
    let when: String
    let onTap: () -> Void

    var body: some View {
        let formatted = ProductNameFormatter.format(product)
        let meta = [formatted.size, when].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return Button(action: onTap) {
            HStack(spacing: 12) {
                ProductThumb(glyph: product.glyph, score: product.yourScore, size: 56,
                             imageURL: product.listImageURL,
                             processCutout: product.shouldProcessCutout)
                VStack(alignment: .leading, spacing: 1) {
                    if let brand = formatted.brand {
                        Text(brand.uppercased())
                            .font(.sageBold(10)).tracking(1.2)
                            .foregroundColor(Theme.inkSecondary)
                    }
                    Text(formatted.name)
                        .font(.sageBold(14)).tracking(-0.2)
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                    Text(meta)
                        .font(.sageRegular(11))
                        .monospacedDigit()
                        .foregroundColor(Theme.inkSecondary)
                }
                Spacer(minLength: 8)
                YourScorePill(score: product.yourScore, isUnscored: product.isUnscored)
                Image(systemName: "chevron.right")
                    .font(.sageBold(12))
                    .foregroundColor(Theme.inkSecondary)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(formatted.accessibilityLabel), \(when)")
        }
        .buttonStyle(.plain)
    }
}
