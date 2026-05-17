import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    let onOpenProduct: (String) -> Void

    @State private var filter: Filter = .all

    enum Filter: String { case all, good, bad }

    var body: some View {
        let dark = store.darkMode
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textSecondary(dark))
                    Text("History")
                        .font(.system(size: 32, weight: .heavy)).tracking(-1)
                        .foregroundColor(Theme.textPrimary(dark))
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(filterItems, id: \.id) { f in
                            FilterChip(label: f.label, count: f.count,
                                       active: filter == f.id, dark: dark) {
                                filter = f.id
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }

                ForEach(groupedDays, id: \.day) { entry in
                    Text(entry.day.uppercased())
                        .font(.system(size: 11, weight: .heavy)).tracking(1.4)
                        .foregroundColor(Theme.textSecondary(dark))
                        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)

                    CardView(dark: dark) {
                        VStack(spacing: 0) {
                            ForEach(Array(entry.items.enumerated()), id: \.element.id) { (i, h) in
                                if let p = store.products[h.productId] {
                                    HistoryRow(product: p, when: h.time,
                                               divider: i > 0, dark: dark) {
                                        onOpenProduct(p.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if groupedDays.isEmpty { EmptyHistory(dark: dark) }
                Spacer().frame(height: 120)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
    }

    private var filtered: [HistoryEntry] {
        store.history.filter { h in
            guard let p = store.products[h.productId] else { return false }
            switch filter {
            case .all: return true
            case .good: return p.yourScore >= 50
            case .bad: return p.yourScore < 50
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

    private var filterItems: [(id: Filter, label: String, count: Int)] {
        let goodCount = store.history.filter {
            (store.products[$0.productId]?.yourScore ?? 0) >= 50
        }.count
        let badCount = store.history.filter {
            (store.products[$0.productId]?.yourScore ?? 0) < 50
        }.count
        return [
            (.all,  "All",           store.history.count),
            (.good, "Good for you",  goodCount),
            (.bad,  "Avoid",         badCount),
        ]
    }
}

private struct FilterChip: View {
    let label: String
    let count: Int
    let active: Bool
    let dark: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: .heavy)).tracking(-0.1)
                Text("\(count)")
                    .font(.system(size: 11, weight: .heavy))
                    .opacity(active ? 0.7 : 0.5)
                    .monospacedDigit()
            }
            .foregroundColor(active ? (dark ? .black : .white)
                              : Theme.textPrimary(dark))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(
                Capsule().fill(
                    active ? (dark ? Color.white : Color.black)
                           : (dark ? Color.white.opacity(0.06) : Color.white)
                )
            )
            .cardShadow(!active && !dark)
        }
        .buttonStyle(.plain)
    }
}

private struct HistoryRow: View {
    let product: Product
    let when: String
    let divider: Bool
    let dark: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ProductThumb(glyph: product.glyph, score: product.yourScore, size: 48)
                VStack(alignment: .leading, spacing: 1) {
                    Text(product.brand.uppercased())
                        .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                        .foregroundColor(Theme.textSecondary(dark))
                    Text(product.name)
                        .font(.system(size: 14, weight: .heavy)).tracking(-0.2)
                        .foregroundColor(Theme.textPrimary(dark))
                        .lineLimit(1)
                    Text(when)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary(dark))
                }
                Spacer(minLength: 8)
                YourScorePill(score: product.yourScore)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .overlay(alignment: .top) {
                if divider {
                    Theme.divider(dark).frame(height: 0.5).padding(.horizontal, 12)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyHistory: View {
    let dark: Bool
    var body: some View {
        VStack(spacing: 8) {
            Text("🌱").font(.system(size: 32))
            Text("Nothing here yet")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.textPrimary(dark))
            Text("Scan a product to see it in your history.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary(dark))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 60)
    }
}
