import SwiftUI

struct ScannerHomeView: View {
    @EnvironmentObject var store: AppStore
    let onTapScan: () -> Void
    let onTapHistory: () -> Void
    let onTapSearch: () -> Void
    let onOpenProduct: (String) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                wordmark
                // Split + stagger: greeting → search → scan → recent.
                StaggeredAppear(index: 0) { greeting() }
                StaggeredAppear(index: 1) {
                    searchEntry()
                        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
                }
                StaggeredAppear(index: 2) {
                    heroCard()
                        .padding(.horizontal, 16).padding(.bottom, 6)
                }
                StaggeredAppear(index: 3) { recentSection() }
            }
        }
        .sageScreenBackground()
        // The brand lockup is the title here, so the system bar would only add
        // an empty strip above it. Pushed screens still get their own bar.
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Mark and wordmark as one horizontal lockup, sitting directly on the
    /// background — a toolbar item would wrap it in the system's glass capsule
    /// and push it onto its own line above the title.
    private var wordmark: some View {
        HStack(spacing: 8) {
            SageMark(size: 26, color: store.accent)
            Text("Sage")
                .font(.sageSemiBold(22))
                .tracking(-0.6)
                .foregroundColor(Theme.ink)
        }
        .debugMenuTap()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Sage")
    }

    /// Name-free: onboarding no longer asks for one, so the profile default
    /// would leak a placeholder name the user never entered.
    private func greeting() -> some View {
        Text(timeGreeting)
            .font(.sageMedium(15))
            .foregroundColor(Theme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 4)
    }

    /// Device-local hour: 5–11 morning, 12–17 afternoon, else evening.
    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5...11:  return "Good morning"
        case 12...17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private func searchEntry() -> some View {
        Button(action: onTapSearch) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.inkSecondary)
                Text("Search a product or brand")
                    .font(.sageMedium(15))
                    .foregroundColor(Theme.inkSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card)
            )
            .cardShadow()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Search a product or brand")
    }

    private func heroCard() -> some View {
        Button(action: onTapScan) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scan a barcode")
                        .font(.sageBold(17))
                        .tracking(-0.4)
                        .foregroundColor(.white)
                    Text("Point your camera at any food barcode.")
                        .font(.sageRegular(13))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().fill(Color.white.opacity(0.2))
                    Image(systemName: "viewfinder")
                        .font(.sageBold(18))
                        .foregroundColor(.white)
                }
                .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [store.accent, Color(hex: "0C5A3B")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: store.accent.opacity(0.25), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Scan a barcode")
    }

    // MARK: Recent scans (display-time grouping)

    /// Collapses consecutive same-product history entries into one Home row.
    private struct HomeRecentGroup: Identifiable {
        var id: String { productId }
        let productId: String
        let latestScannedAt: Date
        let weekScanCount: Int
    }

    private func homeGroupedRecent(limit: Int = 5) -> [HomeRecentGroup] {
        let history = store.history
        guard !history.isEmpty else { return [] }
        var groups: [HomeRecentGroup] = []
        var idx = 0
        while idx < history.count && groups.count < limit {
            let pid = history[idx].productId
            let latest = history[idx].scannedAt
            idx += 1
            while idx < history.count && history[idx].productId == pid {
                idx += 1
            }
            groups.append(HomeRecentGroup(
                productId: pid,
                latestScannedAt: latest,
                weekScanCount: weekScanCount(for: pid, in: history)
            ))
        }
        return groups
    }

    private func weekScanCount(for productId: String, in history: [HistoryEntry]) -> Int {
        history.filter {
            $0.productId == productId &&
                Calendar.current.isDate($0.scannedAt, equalTo: .now, toGranularity: .weekOfYear)
        }.count
    }

    private func recentSubtitle(for group: HomeRecentGroup) -> String {
        if group.weekScanCount > 1 {
            return "Scanned \(group.weekScanCount)× this week"
        }
        return HistoryEntry.scannedAgoLabel(since: group.latestScannedAt)
    }

    private func recentSection() -> some View {
        let recent = homeGroupedRecent()
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent scans")
                    .font(.sageSemiBold(18))
                    .tracking(-0.4)
                    .foregroundColor(Theme.ink)
                Spacer()
                if !recent.isEmpty {
                    Button(action: onTapHistory) {
                        Text("See all")
                            .font(.sageMedium(13))
                            .foregroundColor(Theme.inkSecondary)
                            .padding(.vertical, 8).padding(.leading, 12)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("See all recent scans")
                }
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 10)

            if recent.isEmpty {
                VStack(spacing: 4) {
                    Text("No scans yet")
                        .font(.sageSemiBold(14))
                        .tracking(-0.2)
                        .foregroundColor(Theme.ink)
                    Text("Your scanned products will appear here.")
                        .font(.sageRegular(12))
                        .foregroundColor(Theme.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28).padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card)
                )
                .cardShadow()
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(recent) { group in
                        if let p = store.products[group.productId] {
                            RecentRow(product: p, subtitle: recentSubtitle(for: group)) {
                                onOpenProduct(p.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct RecentRow: View {
    let product: Product
    let subtitle: String
    let onTap: () -> Void

    var body: some View {
        let formatted = ProductNameFormatter.format(product)
        // Size is deliberately not shown: the row already carries brand, name
        // and score, and "350 g" was the least useful of the four at a glance.
        return Button(action: onTap) {
            HStack(spacing: 12) {
                ProductThumb(glyph: product.glyph, score: product.yourScore, size: 48,
                             imageURL: product.listImageURL,
                             processCutout: product.shouldProcessCutout)
                VStack(alignment: .leading, spacing: 1) {
                    if let brand = formatted.brand {
                        // `ProductNameFormatter` already canonicalizes casing
                        // ("COCA-COLA" → "Coca-Cola"); uppercasing it again
                        // threw that away.
                        Text(brand)
                            .font(.sageBold(11)).tracking(0.2)
                            .foregroundColor(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                    Text(formatted.name)
                        .font(.sageSemiBold(14))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.sageRegular(11))
                        .foregroundColor(Theme.inkSecondary)
                }
                Spacer(minLength: 8)
                CompactScoreRing(score: product.yourScore,
                                 isUnscored: product.isUnscored)
                Image(systemName: "chevron.right")
                    .font(.sageBold(12))
                    .foregroundColor(Theme.inkSecondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card)
            )
            .cardShadow()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(formatted.accessibilityLabel), \(subtitle)")
    }
}
