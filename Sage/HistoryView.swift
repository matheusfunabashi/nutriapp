import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    let onOpenProduct: (String) -> Void

    @State private var filter: Filter = .all
    @State private var confirmingClear = false

    enum Filter: String, CaseIterable { case all, good, bad }

    var body: some View {
        List {
            // Segmented control, not a hand-rolled chip row: it gets the
            // system's selection animation and VoiceOver treatment for free.
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Text(label(for: f)).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))

            ForEach(groupedDays, id: \.day) { entry in
                Section(entry.day.uppercased()) {
                    ForEach(entry.items) { h in
                        if let p = store.products[h.productId] {
                            HistoryRow(product: p, when: h.time) {
                                onOpenProduct(p.id)
                            }
                            // Swipe-to-delete is the platform gesture for a
                            // feed like this — no custom edit mode needed.
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    store.deleteHistory(h)
                                }
                            }
                        }
                    }
                }
            }

            if groupedDays.isEmpty {
                ContentUnavailableView(
                    filter == .all ? "Nothing here yet" : "No matches",
                    systemImage: "leaf",
                    description: Text(filter == .all
                                      ? "Scan a product to see it in your history."
                                      : "No scans match this filter yet.")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .sageListStyle()
        .navigationTitle("History")
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
            Button("Clear History", role: .destructive) { store.clearHistory() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your saved products are kept — only the history feed is cleared.")
        }
    }

    private func label(for f: Filter) -> String {
        switch f {
        case .all:  return "All (\(store.history.count))"
        case .good: return "Good (\(count { $0 >= 50 }))"
        case .bad:  return "Avoid (\(count { $0 < 50 }))"
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

private struct HistoryRow: View {
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
