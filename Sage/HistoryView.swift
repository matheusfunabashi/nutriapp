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
                StaggeredAppear(index: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Library")
                            .font(.sageSemiBold(13))
                            .foregroundColor(Theme.textSecondary(dark))
                        Text("History")
                            .font(.sageBold(32)).tracking(-1)
                            .foregroundColor(Theme.textPrimary(dark))
                    }
                    // 12pt above the system safe-area; ContentView's
                    // tabContent isn't ignoring it, so this is the only
                    // breathing room we need below the Dynamic Island.
                    .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
                }

                StaggeredAppear(index: 1) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(filterItems, id: \.id) { f in
                                FilterChip(label: f.label, count: f.count,
                                           active: filter == f.id, dark: dark) {
                                    // Spring keeps the chip transition interruptible
                                    // if the user flicks between filters.
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        filter = f.id
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                }

                ForEach(Array(groupedDays.enumerated()), id: \.element.day) { (gIdx, entry) in
                    // Stagger each day group so multi-day pantries reveal in
                    // sequence rather than as one block.
                    StaggeredAppear(index: gIdx + 2) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.day.uppercased())
                                .font(.sageBold(11)).tracking(1.4)
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
                    }
                }

                if groupedDays.isEmpty {
                    StaggeredAppear(index: 2) { EmptyHistory(dark: dark) }
                }
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

    private var filterItems: [(id: Filter, label: String, count: Int)] {
        let goodCount = store.history.filter {
            guard let s = store.products[$0.productId]?.yourScore else { return false }
            return s >= 50
        }.count
        let badCount = store.history.filter {
            guard let s = store.products[$0.productId]?.yourScore else { return false }
            return s < 50
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
                    .font(.sageBold(13)).tracking(-0.1)
                Text("\(count)")
                    .font(.sageBold(11))
                    .opacity(active ? 0.7 : 0.5)
                    .monospacedDigit() // counts can shift as scans pile up
                    .contentTransition(.numericText()) // smooth count updates
            }
            .foregroundColor(active ? (dark ? .black : .white)
                              : Theme.textPrimary(dark))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(
                Capsule().fill(
                    active ? (dark ? Color.white : Color.black)
                           : (dark ? Color.white.opacity(0.06) : Color.white)
                )
            )
            .cardShadow(!active && !dark)
            .minHitArea(40) // chips are slim — keep thumb target healthy
        }
        .buttonStyle(.pressable)
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
                ProductThumb(glyph: product.glyph, score: product.yourScore, size: 48,
                             imageURL: product.imageURL)
                VStack(alignment: .leading, spacing: 1) {
                    Text(product.brand.uppercased())
                        .font(.sageBold(10)).tracking(1.2)
                        .foregroundColor(Theme.textSecondary(dark))
                    Text(product.name)
                        .font(.sageBold(14)).tracking(-0.2)
                        .foregroundColor(Theme.textPrimary(dark))
                        .lineLimit(1)
                    Text(when)
                        .font(.sageRegular(11))
                        .monospacedDigit() // align times across rows
                        .foregroundColor(Theme.textSecondary(dark))
                }
                Spacer(minLength: 8)
                YourScorePill(score: product.yourScore, isUnscored: product.isUnscored)
                Image(systemName: "chevron.right")
                    .font(.sageBold(12))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .overlay(alignment: .top) {
                if divider {
                    // Dividers stay as borders (layout separation, not depth)
                    // per the skill's "shadows over borders" exception.
                    Theme.divider(dark).frame(height: 0.5).padding(.horizontal, 12)
                }
            }
        }
        .buttonStyle(.pressable)
    }
}

private struct EmptyHistory: View {
    let dark: Bool
    var body: some View {
        VStack(spacing: 8) {
            Text("🌱").font(.sageRegular(32))
            Text("Nothing here yet")
                .font(.sageBold(16))
                .foregroundColor(Theme.textPrimary(dark))
            Text("Scan a product to see it in your history.")
                .font(.sageRegular(13))
                .foregroundColor(Theme.textSecondary(dark))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 60)
    }
}
