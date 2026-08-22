import SwiftUI

struct ScannerHomeView: View {
    @EnvironmentObject var store: AppStore
    let onTapScan: () -> Void
    let onTapHistory: () -> Void
    let onTapSearch: () -> Void
    let onOpenProduct: (String) -> Void
    /// First-run starter section hooks (Top Rated tab / Personalize screen).
    var onTapTopRated: (() -> Void)? = nil
    var onTapPersonalize: (() -> Void)? = nil
    /// Browse rail → one Top Rated shelf.
    var onOpenCategory: ((SageCategory) -> Void)? = nil

    /// Goal-aware starter picks, resolved once; shown until the first scan.
    @State private var starterPicks: [Alternative] = []

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
                    pantryScoreHero()
                        .padding(.horizontal, 16).padding(.bottom, 6)
                }
                StaggeredAppear(index: 3) { browseRail() }
                StaggeredAppear(index: 4) {
                    if hasRealScans {
                        recentSection()
                    } else {
                        starterSection()
                    }
                }
            }
        }
        .sageScreenBackground()
        .task(id: store.user.healthGoals) {
            // Only worth scoring while there's no history to show instead.
            guard !hasRealScans else { return }
            starterPicks = StarterPicks.picks(for: store.user, limit: 6)
        }
        // The brand lockup is the title here, so the system bar would only add
        // an empty strip above it. Pushed screens still get their own bar.
        .toolbar(.hidden, for: .navigationBar)
    }

    /// History minus the onboarding demo scan the flow seeds — one demo row
    /// under "Recent scans" would read as thin, so Home keeps the starter
    /// section until the user has scanned something of their own.
    private var hasRealScans: Bool {
        let demoId = OnboardingDemoProduct.candidate?.barcode
        return store.history.contains { $0.productId != demoId }
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

    /// Uses the first name when the user shared one; otherwise a time-of-day
    /// greeting only — never a placeholder like "Jamie".
    private func greeting() -> some View {
        let name = store.user.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = name.isEmpty ? timeGreeting : "\(timeGreeting), \(name)"
        return Text(text)
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
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.card)
            )
            .cardShadow()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Search a product or brand")
    }

    // MARK: Pantry Score hero
    //
    // The one personal number on Home — the average Your Score of what the
    // user has actually scanned — so the screen has a reason to be revisited
    // (Duolingo's streak, Oasis's "Your Score"). Never shows a 0: until three
    // scored scans exist it's a progress ring toward unlocking, which keeps the
    // scan CTA purposeful instead of generic.

    private static let unlockCount = 3
    /// Recent window the score is averaged over — a pantry, not a lifetime.
    private static let scoreWindow = 20

    /// Real scans only (the onboarding demo seed is excluded), newest first,
    /// paired with their Your Score when the product is scored.
    private var scoredScans: [(entry: HistoryEntry, score: Int)] {
        let demoId = OnboardingDemoProduct.candidate?.barcode
        return store.history.compactMap { h in
            guard h.productId != demoId,
                  let s = store.products[h.productId]?.yourScore else { return nil }
            return (h, s)
        }
    }

    private var pantryScore: Int? {
        let recent = scoredScans.prefix(Self.scoreWindow)
        guard recent.count >= Self.unlockCount else { return nil }
        return Int((Double(recent.reduce(0) { $0 + $1.score }) / Double(recent.count)).rounded())
    }

    /// This week's average minus the prior week's; nil until both have ≥2 scans.
    private var weeklyTrend: Int? {
        let now = Date.now
        guard let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now),
              let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now) else { return nil }
        let thisWeek = scoredScans.filter { $0.entry.scannedAt >= weekAgo }
        let lastWeek = scoredScans.filter { $0.entry.scannedAt >= twoWeeksAgo && $0.entry.scannedAt < weekAgo }
        guard thisWeek.count >= 2, lastWeek.count >= 2 else { return nil }
        let a = Double(thisWeek.reduce(0) { $0 + $1.score }) / Double(thisWeek.count)
        let b = Double(lastWeek.reduce(0) { $0 + $1.score }) / Double(lastWeek.count)
        return Int((a - b).rounded())
    }

    private func pantryScoreHero() -> some View {
        let scanned = min(scoredScans.count, Self.unlockCount)
        return VStack(spacing: 14) {
            HStack(spacing: 16) {
                if let score = pantryScore {
                    ScoreRing(score: score, size: 84, stroke: 8)
                } else {
                    unlockRing(progress: scanned)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("PANTRY SCORE")
                        .font(.sageBold(11)).tracking(1.4)
                        .foregroundColor(Theme.inkSecondary)
                    if let score = pantryScore {
                        Text(scoreLabel(score))
                            .font(.sageBold(20)).tracking(-0.4)
                            .foregroundColor(Theme.ink)
                        Text(trendLine(score: score))
                            .font(.sageRegular(13))
                            .foregroundColor(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(scanned == 0 ? "Unlock your score" : "\(Self.unlockCount - scanned) to go")
                            .font(.sageBold(20)).tracking(-0.4)
                            .foregroundColor(Theme.ink)
                        Text("Scan \(Self.unlockCount) products and Sage averages how your pantry scores for you.")
                            .font(.sageRegular(13))
                            .foregroundColor(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            Button(action: onTapScan) {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                        .font(.sageBold(15))
                    Text("Scan a product")
                        .font(.sageBold(15)).tracking(-0.2)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(store.accent))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Scan a product barcode")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).fill(Theme.card)
        )
        .cardShadow()
        .accessibilityElement(children: .contain)
    }

    /// Progress toward the first Pantry Score — accent arc over the track,
    /// "n/3" in the middle. Same geometry as `ScoreRing` so the swap at
    /// unlock doesn't shift the layout.
    private func unlockRing(progress: Int) -> some View {
        ZStack {
            Circle().stroke(Theme.ringTrack, lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(progress) / CGFloat(Self.unlockCount))
                .stroke(store.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            Text("\(progress)/\(Self.unlockCount)")
                .font(.sageFixedBold(16)).monospacedDigit()
                .foregroundColor(Theme.ink)
        }
        .frame(width: 84, height: 84)
        .accessibilityLabel("\(progress) of \(Self.unlockCount) scans toward your Pantry Score")
    }

    private func trendLine(score: Int) -> String {
        let n = min(scoredScans.count, Self.scoreWindow)
        let base = "Across your last \(n) scans"
        guard let t = weeklyTrend, t != 0 else { return base + "." }
        return base + " · \(t > 0 ? "up" : "down") \(abs(t)) this week."
    }

    // MARK: Browse rail
    //
    // A browse path on Home (the Top Rated tab stays the deep version):
    // pack-shot chips for every shelf, tap → that shelf's ranked list.

    private func browseRail() -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Browse top rated")
                    .font(.sageSemiBold(18))
                    .tracking(-0.4)
                    .foregroundColor(Theme.ink)
                Spacer()
                if let onTapTopRated {
                    Button(action: onTapTopRated) {
                        Text("See all")
                            .font(.sageMedium(13))
                            .foregroundColor(Theme.inkSecondary)
                            .padding(.vertical, 8).padding(.leading, 12)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("See all top rated categories")
                }
            }
            .padding(.horizontal, 24).padding(.top, 14)

            // Photos as the UI: the pack shot floats on the background with the
            // shelf name under it — no capsule, no card (App Store / Scout
            // "Rankings" pattern). The shot is the affordance.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(SageCategory.topRatedBrowse) { category in
                        Button {
                            onOpenCategory?(category)
                        } label: {
                            VStack(spacing: 8) {
                                Group {
                                    if let asset = category.bundledTopRatedHeroAsset {
                                        Image(asset).resizable().scaledToFit()
                                    } else {
                                        Text(category.emoji).font(.sageRegular(32))
                                    }
                                }
                                .frame(width: 76, height: 76)
                                Text(category.displayName)
                                    .font(.sageSemiBold(13)).tracking(-0.2)
                                    .foregroundColor(Theme.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .frame(width: 84)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Top rated \(category.displayName)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 4)
            }
        }
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

            if !recent.isEmpty {
                // Big pack shots with the ring in the corner — the product is
                // the row. Same rail shape as Top picks / Better options.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(recent) { group in
                            if let p = store.products[group.productId] {
                                RecentScanTile(product: p, subtitle: recentSubtitle(for: group)) {
                                    onOpenProduct(p.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: First-run starter content (before the first scan)
    //
    // "Recent scans" has nothing to show on day one, and a card that says so is
    // a placeholder for content that doesn't exist yet. Instead the slot holds
    // real, goal-personalized products the user can open right now, plus the
    // watchlist they just set up — the section hands over to Recent scans the
    // moment history exists.

    private func starterSection() -> some View {
        let watch = StarterPicks.watchlist(for: store.user)
        let personalized = !(store.user.healthGoals ?? []).isEmpty
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(personalized ? "Top picks for you" : "Top picks to start with")
                    .font(.sageSemiBold(18))
                    .tracking(-0.4)
                    .foregroundColor(Theme.ink)
                Spacer()
                if let onTapTopRated {
                    Button(action: onTapTopRated) {
                        Text("See all")
                            .font(.sageMedium(13))
                            .foregroundColor(Theme.inkSecondary)
                            .padding(.vertical, 8).padding(.leading, 12)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("See all top rated")
                }
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 10)

            if starterPicks.isEmpty {
                // Scoring is near-instant, but never flash an empty rail.
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(Theme.fillQuiet)
                            .frame(width: 148, height: 176)
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(starterPicks) { pick in
                            StarterPickCard(pick: pick) {
                                store.saveProduct(pick.product)
                                onOpenProduct(pick.product.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8) // room for the card shadow
                }
                .scrollClipDisabled()
            }

            if !watch.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SAGE IS WATCHING FOR")
                        .font(.sageBold(11)).tracking(1.4)
                        .foregroundColor(Theme.inkSecondary)
                        .padding(.horizontal, 24)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(watch, id: \.self) { item in
                                SageChip(title: item, selected: false) {
                                    onTapPersonalize?()
                                }
                            }
                            if let onTapPersonalize {
                                Button(action: onTapPersonalize) {
                                    Label("Edit", systemImage: "slider.horizontal.3")
                                        .font(.sageSemiBold(13))
                                        .foregroundStyle(store.accent)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 14)
            }
        }
    }
}

private struct RecentScanTile: View {
    let product: Product
    let subtitle: String
    let onTap: () -> Void

    var body: some View {
        let formatted = ProductNameFormatter.format(product)
        return Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    ProductThumb(glyph: product.glyph, score: product.yourScore, size: 128,
                                 neutral: true,
                                 imageURL: product.listImageURL,
                                 fallbackImageURL: product.imageFallbackURL,
                                 processCutout: product.shouldProcessCutout)
                    CompactScoreRing(score: product.yourScore, isUnscored: product.isUnscored)
                        .background(Circle().fill(Theme.background).padding(-3))
                        .offset(x: 8, y: 8)
                }
                .padding(.trailing, 8).padding(.bottom, 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatted.name)
                        .font(.sageSemiBold(14)).tracking(-0.2)
                        .foregroundColor(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.sageRegular(12))
                        .foregroundColor(Theme.inkSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 136, alignment: .leading)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(formatted.accessibilityLabel), \(subtitle)")
    }
}
