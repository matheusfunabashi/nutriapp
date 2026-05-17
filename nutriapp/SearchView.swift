import SwiftUI

struct SearchView: View {
    @EnvironmentObject var store: AppStore
    let onOpenProduct: (String) -> Void

    @State private var query: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        let dark = store.darkMode
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Search")
                    .font(.system(size: 34, weight: .heavy)).tracking(-1)
                    .foregroundColor(Theme.textPrimary(dark))
                    .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 8)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Theme.textSecondary(dark))
                    TextField("Search by product or brand", text: $query)
                        .focused($focused)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.textPrimary(dark))
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button {
                            query = ""; focused = true
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Theme.textPrimary(dark))
                                .padding(5)
                                .background(Circle().fill(dark ? Color.white.opacity(0.12)
                                                                 : Color.black.opacity(0.08)))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface(dark))
                )
                .cardShadow(dark)
                .padding(.horizontal, 16).padding(.top, 12)

                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    if !recent.isEmpty { resultsSection(title: "Recent", items: recent, dark: dark) }
                    resultsSection(title: "Popular", items: popular, dark: dark)
                } else {
                    let count = filtered.count
                    Text("\(count) result\(count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textSecondary(dark))
                        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)
                    if filtered.isEmpty { noMatches(dark: dark) }
                    else { listCard(items: filtered, dark: dark) }
                }
                Spacer().frame(height: 140)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
    }

    private var filtered: [Product] {
        let q = query.lowercased()
        return Array(store.products.values).filter {
            $0.name.lowercased().contains(q) || $0.brand.lowercased().contains(q)
        }.sorted { $0.name < $1.name }
    }
    private var recent: [Product] {
        Array(store.history.prefix(4)).compactMap { store.products[$0.productId] }
    }
    private var popular: [Product] {
        ["yogurt","cereal","cola","cokeZero"].compactMap { store.products[$0] }
    }

    private func resultsSection(title: String, items: [Product], dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textSecondary(dark))
                .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)
            listCard(items: items, dark: dark)
        }
    }

    private func listCard(items: [Product], dark: Bool) -> some View {
        CardView(dark: dark) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { (i, p) in
                    SearchRow(product: p, divider: i > 0, dark: dark) {
                        onOpenProduct(p.id)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func noMatches(dark: Bool) -> some View {
        CardView(dark: dark) {
            VStack(spacing: 4) {
                Text("No matches")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(Theme.textPrimary(dark))
                Text("Try a different brand or product name.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40).padding(.horizontal, 24)
        }
        .padding(.horizontal, 16)
    }
}

private struct SearchRow: View {
    let product: Product
    let divider: Bool
    let dark: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                let s = product.yourScore
                Text("\(s)")
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .tracking(-0.3)
                    .foregroundColor(scoreColor(s))
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(scoreColor(s).opacity(0.10))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(product.brand.uppercased())
                        .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                        .foregroundColor(Theme.textSecondary(dark))
                    Text(product.name)
                        .font(.system(size: 14, weight: .heavy)).tracking(-0.2)
                        .foregroundColor(Theme.textPrimary(dark))
                        .lineLimit(1)
                }
                Spacer()
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
