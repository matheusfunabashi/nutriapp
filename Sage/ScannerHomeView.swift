import SwiftUI

struct ScannerHomeView: View {
    @EnvironmentObject var store: AppStore
    let onTapScan: () -> Void
    let onTapHistory: () -> Void
    let onTapSearch: () -> Void
    let onOpenProduct: (String) -> Void

    var body: some View {
        let dark = store.darkMode
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header(dark: dark)
                // Split + stagger: greeting → search → scan → recent.
                StaggeredAppear(index: 0) { greeting(dark: dark) }
                StaggeredAppear(index: 1) {
                    searchEntry(dark: dark)
                        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
                }
                StaggeredAppear(index: 2) {
                    heroCard(dark: dark)
                        .padding(.horizontal, 16).padding(.bottom, 6)
                }
                StaggeredAppear(index: 3) { recentSection(dark: dark) }
                Spacer().frame(height: 120)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
    }

    private func header(dark: Bool) -> some View {
        HStack {
            HStack(spacing: 8) {
                SageMark(size: 26, color: store.accent)
                Text("Sage")
                    .font(.sageSemiBold(22))
                    .tracking(-0.6)
                    .foregroundColor(Theme.textPrimary(dark))
            }
            .debugMenuTap()
            Spacer()
            Button(action: onTapHistory) {
                ZStack {
                    Circle().fill(dark ? Color.white.opacity(0.08) : Color.white)
                    Image(systemName: "list.bullet")
                        .foregroundColor(Theme.textPrimary(dark))
                        .font(.sageSemiBold(15))
                }
                .frame(width: 38, height: 38)
                .cardShadow(dark)
                .minHitArea(44) // visible 38pt; tap target lifts to 44 (WCAG)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Scan history")
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)
    }

    private func greeting(dark: Bool) -> some View {
        Text("\(timeGreeting), \(store.user.name)")
            .font(.sageMedium(15))
            .foregroundColor(Theme.textSecondary(dark))
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

    private func searchEntry(dark: Bool) -> some View {
        Button(action: onTapSearch) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textSecondary(dark))
                Text("Search a product or brand")
                    .font(.sageMedium(15))
                    .foregroundColor(Theme.textSecondary(dark))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface(dark))
            )
            .cardShadow(dark)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Search a product or brand")
    }

    private func heroCard(dark: Bool) -> some View {
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

    private func recentSection(dark: Bool) -> some View {
        let recent = homeGroupedRecent()
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent scans")
                    .font(.sageSemiBold(18))
                    .tracking(-0.4)
                    .foregroundColor(Theme.textPrimary(dark))
                Spacer()
                if !recent.isEmpty {
                    Button(action: onTapHistory) {
                        Text("See all")
                            .font(.sageMedium(13))
                            .foregroundColor(Theme.textSecondary(dark))
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
                        .foregroundColor(Theme.textPrimary(dark))
                    Text("Your scanned products will appear here.")
                        .font(.sageRegular(12))
                        .foregroundColor(Theme.textSecondary(dark))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28).padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
                )
                .cardShadow(dark)
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(recent) { group in
                        if let p = store.products[group.productId] {
                            RecentRow(product: p, subtitle: recentSubtitle(for: group), dark: dark) {
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
    let dark: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ProductThumb(glyph: product.glyph, score: product.yourScore, size: 48,
                             imageURL: product.imageURL)
                VStack(alignment: .leading, spacing: 1) {
                    Text(product.name)
                        .font(.sageSemiBold(14))
                        .foregroundColor(Theme.textPrimary(dark))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.sageRegular(11))
                        .foregroundColor(Theme.textSecondary(dark))
                }
                Spacer(minLength: 8)
                CompactScoreRing(score: product.yourScore, dark: dark)
                Image(systemName: "chevron.right")
                    .font(.sageBold(12))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
            )
            .cardShadow(dark)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(product.name), \(subtitle)")
    }
}

struct ScanBrackets: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: 4, y: 18)); p.addLine(to: CGPoint(x: 4, y: 8))
                p.addQuadCurve(to: CGPoint(x: 8, y: 4), control: CGPoint(x: 4, y: 4))
                p.addLine(to: CGPoint(x: 18, y: 4))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: w - 4, y: 18)); p.addLine(to: CGPoint(x: w - 4, y: 8))
                p.addQuadCurve(to: CGPoint(x: w - 8, y: 4), control: CGPoint(x: w - 4, y: 4))
                p.addLine(to: CGPoint(x: w - 18, y: 4))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: 4, y: h - 18)); p.addLine(to: CGPoint(x: 4, y: h - 8))
                p.addQuadCurve(to: CGPoint(x: 8, y: h - 4), control: CGPoint(x: 4, y: h - 4))
                p.addLine(to: CGPoint(x: 18, y: h - 4))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: w - 4, y: h - 18)); p.addLine(to: CGPoint(x: w - 4, y: h - 8))
                p.addQuadCurve(to: CGPoint(x: w - 8, y: h - 4), control: CGPoint(x: w - 4, y: h - 4))
                p.addLine(to: CGPoint(x: w - 18, y: h - 4))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}
