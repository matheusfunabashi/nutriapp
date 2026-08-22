import SwiftUI

struct ResultView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    let product: Product
    let fromScan: Bool
    let onCompare: () -> Void
    let onOpenMethodology: () -> Void
    /// Open a "better alternative" the user tapped. Defaulted so other call
    /// sites (previews/tests) compile unchanged.
    var onSelectAlternative: (Product) -> Void = { _ in }
    /// Open the Top Rated list for the scanned product's shelf ("See all").
    var onOpenShelf: (SageCategory) -> Void = { _ in }

    @State private var showLabelLegend = false
    @State private var selectedAdditive: ProductAdditive? = nil
    @State private var ingredientsExpanded = false
    /// Edge for `.sensoryFeedback` — bumped each time the favorite is toggled.
    @State private var favoriteTick = 0
    /// Computed once on appear (re-scoring candidates is cheap but not free, so
    /// it stays off the per-render path).
    @State private var alternativesOutcome: AlternativesOutcome = .noShelf
    /// True once the hero + title have scrolled under the nav bar; the bar
    /// then carries thumb · name · mini ring so the verdict never leaves the
    /// screen (Scout / App Store pattern).
    @State private var headerCollapsed = false
    @State private var overviewExpanded = true

    /// Offset (pt) past which the nav bar swaps to the compact product title —
    /// roughly the hero + title block height.
    private static let collapseThreshold: CGFloat = 300

    var body: some View {
        let dark = colorScheme == .dark
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    scrollableHeader(dark: dark)
                    allergenSection(dark: dark)
                    avoidFlagsSection(dark: dark)
                    betterOptionsSection(dark: dark)
                    processingSection(dark: dark)
                    if product.showsTransFatFlag {
                        SeriousFlag(
                            isHeaviestScorePenalty: TransFatAttribution.isHeaviestPenalty(in: product)
                        )
                        .padding(.horizontal, 16).padding(.top, 20)
                    }
                    nutritionSection(dark: dark)
                    additivesSection(dark: dark)
                    fullIngredientsSection(dark: dark)
                    detectedSection(dark: dark)
                    restrictionBanners(dark: dark)
                    disclaimer(dark: dark)
#if DEBUG
                    scoreDebugSection(dark: dark)
#endif
                }
                .frame(minWidth: geo.size.width, maxWidth: geo.size.width,
                       minHeight: geo.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .onScrollGeometryChange(for: Bool.self) { g in
                g.contentOffset.y + g.contentInsets.top > Self.collapseThreshold
            } action: { _, collapsed in
                withAnimation(.easeInOut(duration: 0.2)) { headerCollapsed = collapsed }
            }
        }
        .sageScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { toolbarTitle }
            ToolbarItem(placement: .topBarTrailing) { favoriteToolbarButton }
        }
        .onAppear {
            store.requestOverview(for: product.id)
        }
        .task(id: liveProduct.id) {
            // Re-scoring ~50 shelf candidates is cheap but not free; keep it
            // off the main thread so the header animates in untouched.
            let scanned = liveProduct
            let profile = store.user
            let ruleset = RulesetStore.current
            let shelfCandidates: [SageCategory: [AlternativeCandidate]] = {
                guard let shelf = SageCategory.shelf(for: scanned) else { return [:] }
                return [shelf: AlternativesStore.candidates(for: shelf)]
            }()
            let outcome = await Task.detached(priority: .userInitiated) {
                Alternatives.suggest(for: scanned,
                                     candidates: { shelfCandidates[$0] ?? [] },
                                     profile: profile, ruleset: ruleset)
            }.value
            alternativesOutcome = outcome
        }
        .sheet(isPresented: $showLabelLegend) {
            LabelLegendSheet(dark: dark)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedAdditive) { additive in
            AdditiveDetailSheet(additive: additive, dark: dark)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var liveProduct: Product {
        store.products[product.id] ?? product
    }

    private var yourScoreIsWorstSignal: Bool {
        guard let score = liveProduct.yourScore else { return false }
        return scoreTier(score) == .bad
    }

    /// "Better options" rail / already-top line (ALTERNATIVES_SPEC.md §5 / §7).
    ///
    /// A horizontal rail of compact cards — photo, score ring, name, one short
    /// reason — the same shape as the Home "Top picks" rail, so the product
    /// page stays calm. The list ranks on the axis the page emphasizes (Your
    /// Score when personalization is on).
    @ViewBuilder private func betterOptionsSection(dark: Bool) -> some View {
        let shelf = SageCategory.shelf(for: liveProduct)
        let shelfName = shelf?.displayName.lowercased() ?? "category"
        let canSeeAll = shelf.map { SageCategory.topRatedBrowse.contains($0) } ?? false
        switch alternativesOutcome {
        case .suggestions(let alternatives):
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Better options")
                        .font(.sageSemiBold(18))
                        .tracking(-0.4)
                        .foregroundColor(Theme.ink)
                    Spacer()
                    if canSeeAll, let shelf {
                        Button { onOpenShelf(shelf) } label: {
                            Text("See all")
                                .font(.sageMedium(13))
                                .foregroundColor(Theme.inkSecondary)
                                .padding(.vertical, 8).padding(.leading, 12)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("See all top rated \(shelfName)")
                    }
                }
                .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(alternatives) { alt in
                            AlternativeCard(alt: alt) { onSelectAlternative(alt.product) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8) // room for the card shadow
                }
                .scrollClipDisabled()
            }
        case .alreadyTopOfShelf:
            Button {
                if let shelf, canSeeAll { onOpenShelf(shelf) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.sageSemiBold(14))
                        .foregroundColor(Color.scoreGood)
                    Text("Among the best \(shelfName) we've scored")
                        .font(.sageSemiBold(13))
                        .foregroundColor(Theme.ink)
                    Spacer(minLength: 4)
                    if canSeeAll {
                        Image(systemName: "chevron.right")
                            .font(.sageBold(11))
                            .foregroundColor(Theme.inkSecondary)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .overlay(alignment: .top) { rowDivider }
                .overlay(alignment: .bottom) { rowDivider }
                .contentShape(Rectangle())
            }
            .buttonStyle(canSeeAll ? .pressable : .pressableStatic)
            .accessibilityLabel("Among the best \(shelfName) we've scored")
            .padding(.top, 20)
        case .noShelf, .unscored, .noBetterPeers:
            EmptyView()
        }
    }

    // MARK: Header
    //
    // One hero, and it's the product: a large pack shot, then name + brand on
    // the left and a single ring on the right — Your Score when the profile
    // personalizes anything, Overall otherwise. Overall and the delta live in
    // one caption line under the title; they are Sage's differentiator, but
    // they don't need two dials and three pills to say "+1".

    private func scrollableHeader(dark: Bool) -> some View {
        let p = liveProduct
        return VStack(spacing: 0) {
            productHero(dark: dark)
            titleBlock(dark: dark)
                .padding(.top, 12)
            if p.isUnscored {
                unscoredScoreCard(dark: dark, product: p)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            } else {
                scoreCaptionRow(dark: dark)
                    .padding(.top, 10)
                actionRow(dark: dark)
                    .padding(.top, 14)
                dataConfidenceLine(dark: dark)
                    .padding(.top, 10)
                overviewSection(dark: dark, product: p)
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 4)
    }

    /// The score the page leads with: Your Score when present, else Overall.
    private var primaryScore: Int? { liveProduct.yourScore ?? liveProduct.overallScore }

    private func productHero(dark: Bool) -> some View {
        let tint = primaryScore.map(scoreColor) ?? Theme.inkSecondary
        // No photo on record → a smaller, quieter tile; the glow only earns
        // its place behind a real pack shot.
        let hasPhoto = product.detailImageURL != nil
        return ZStack {
            // Soft tinted glow behind the pack shot — a background, not a
            // shadow, so it doesn't fight the one-card-shadow rule.
            if hasPhoto {
                Circle()
                    .fill(tint.opacity(dark ? 0.16 : 0.09))
                    .frame(width: 220, height: 220)
                    .blur(radius: 40)
            }
            ProductThumb(glyph: product.glyph, score: product.yourScore,
                         size: hasPhoto ? 176 : 120,
                         neutral: true, imageURL: product.detailImageURL,
                         fallbackImageURL: product.imageFallbackURL,
                         processCutout: product.shouldProcessCutout)
        }
        .frame(maxWidth: .infinity)
        .frame(height: hasPhoto ? 204 : 140)
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    private func titleBlock(dark: Bool) -> some View {
        let formatted = ProductNameFormatter.format(liveProduct)
        let showOrganic = !liveProduct.isUnscored
            && ScoringEngineV4.showsOrganicChip(product: liveProduct, profile: store.user)
        let meta = [formatted.brand, formatted.size]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(formatted.name)
                    .font(.sageBold(24)).tracking(-0.5)
                    .foregroundColor(Theme.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !meta.isEmpty || showOrganic {
                    HStack(spacing: 8) {
                        if !meta.isEmpty {
                            Text(meta)
                                .font(.sageRegular(15))
                                .foregroundColor(Theme.inkSecondary)
                                .lineLimit(2)
                        }
                        if showOrganic {
                            Text("Organic ✓")
                                .font(.sageSemiBold(11))
                                .foregroundColor(Theme.inkSecondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Theme.fillMuted))
                                .accessibilityLabel("Organic certified")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(formatted.accessibilityLabel)

            if !liveProduct.isUnscored, let score = primaryScore {
                heroRing(score: score, personalized: liveProduct.yourScore != nil)
            }
        }
        .padding(.horizontal, 20)
    }

    /// The one ring. "FOR YOU" above it only when the number is the
    /// personalized one; the tier word below always follows the number.
    private func heroRing(score: Int, personalized: Bool) -> some View {
        let color = scoreColor(score)
        return VStack(spacing: 6) {
            if personalized {
                Text("FOR YOU")
                    .font(.sageBold(10)).tracking(1.2)
                    .foregroundColor(store.accent)
            }
            ScoreRing(score: score, size: 84, stroke: 7, ringColor: color)
            Text(scoreLabel(score))
                .font(.sageSemiBold(14)).tracking(-0.2)
                .foregroundColor(color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(personalized ? "Your score" : "Score") \(score), \(scoreLabel(score))")
    }

    /// "Overall 93 · +1 for you" — the second number, demoted to a caption.
    /// A binding cap (diet / avoid list) rides along as a small chip.
    @ViewBuilder private func scoreCaptionRow(dark: Bool) -> some View {
        let p = liveProduct
        if let overall = p.overallScore, let your = p.yourScore {
            let delta = your - overall
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("Overall \(overall)")
                        .font(.sageMedium(14))
                        .monospacedDigit()
                        .foregroundColor(Theme.inkSecondary)
                    if delta != 0 {
                        Text("·")
                            .font(.sageMedium(14))
                            .foregroundColor(Theme.inkSecondary)
                        Text(delta > 0 ? "+\(delta) for you" : "\(delta) for you")
                            .font(.sageSemiBold(14))
                            .monospacedDigit()
                            .foregroundColor(delta > 0 ? Color.scoreGood : Color.scoreBad)
                    } else {
                        Text("· same for you")
                            .font(.sageMedium(14))
                            .foregroundColor(Theme.inkSecondary)
                    }
                }
                if let cap = p.bindingCap {
                    Text("Capped: \(cap.shortLabel)")
                        .font(.sageSemiBold(11))
                        .foregroundColor(Color.cautionMuted)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.cautionMuted.opacity(dark ? 0.18 : 0.12)))
                        .accessibilityLabel("Capped by \(cap.shortLabel)")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Overall \(overall). " + (deltaBadgeLabel(delta: delta) ?? "Same as overall"))
        }
    }

    /// Secondary actions as quiet capsules — Compare and "How we score" —
    /// instead of a full-width button inside the score card.
    private func actionRow(dark: Bool) -> some View {
        HStack(spacing: 8) {
            actionPill(icon: "arrow.left.arrow.right", title: "Compare",
                       accessibility: "Compare with another product", action: onCompare)
            actionPill(icon: "info.circle", title: "How we score",
                       accessibility: "How scoring works: multipliers reweight rules; caps are ceilings from your restrictions",
                       action: onOpenMethodology)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private func actionPill(icon: String, title: String, accessibility: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.sageSemiBold(12))
                Text(title)
                    .font(.sageSemiBold(13)).tracking(-0.1)
            }
            .foregroundColor(Theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Capsule().fill(Theme.fillMuted))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibility)
    }

    /// Nav-bar title: the brand lockup until the hero scrolls away, then
    /// thumb · name · mini ring.
    private var toolbarTitle: some View {
        let formatted = ProductNameFormatter.format(liveProduct)
        return ZStack {
            HStack(spacing: 8) {
                SageMark(size: 28, color: Theme.accent)
                Text("Sage")
                    .font(.sageBold(24)).tracking(-0.6)
                    .foregroundStyle(Theme.ink)
            }
            .opacity(headerCollapsed ? 0 : 1)
            .accessibilityHidden(headerCollapsed)

            HStack(spacing: 10) {
                ProductThumb(glyph: product.glyph, score: product.yourScore, size: 30,
                             neutral: true, imageURL: product.listImageURL,
                             fallbackImageURL: product.imageFallbackURL,
                             processCutout: product.shouldProcessCutout)
                Text(formatted.name)
                    .font(.sageSemiBold(15)).tracking(-0.2)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !liveProduct.isUnscored, let score = primaryScore {
                    MiniScoreRing(score: score, size: 32, stroke: 3)
                }
            }
            .opacity(headerCollapsed ? 1 : 0)
            .offset(y: headerCollapsed ? 0 : 6)
            .accessibilityHidden(!headerCollapsed)
        }
        .animation(.easeInOut(duration: 0.2), value: headerCollapsed)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(headerCollapsed ? formatted.accessibilityLabel : "Sage")
    }

    private func unscoredScoreCard(dark: Bool, product p: Product) -> some View {
        let notes = ScoringEngineV4.sweetenerQualityNotes(p, ruleset: RulesetStore.current)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Not scored")
                    .font(.sageBold(18)).tracking(-0.3)
                    .foregroundColor(Theme.ink)
                Text("This is essentially pure sugar, and no concentrated sugar is a health food. Sage doesn't score sweeteners, so a number here would only mislead.")
                    .font(.sageRegular(13))
                    .foregroundColor(Theme.inkSecondary)
                    .lineSpacing(2)
            }
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Among sweeteners")
                        .font(.sageBold(12)).tracking(0.4)
                        .foregroundColor(Theme.inkSecondary)
                    ForEach(notes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 8) {
                            Text("·")
                                .font(.sageBold(13))
                                .foregroundColor(Theme.inkSecondary)
                            Text(LocalizedStringKey(note))
                                .font(.sageRegular(13))
                                .foregroundColor(Theme.ink)
                        }
                    }
                    Text("Relative quality among sweeteners — not a health score.")
                        .font(.sageRegular(11))
                        .foregroundColor(Theme.inkSecondary)
                        .padding(.top, 2)
                }
            }
            compareButton(dark: dark)
            Button(action: onOpenMethodology) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.sageSemiBold(12))
                    Text("Why sweeteners aren’t scored")
                        .font(.sageSemiBold(12))
                }
                .foregroundColor(Theme.inkSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .fill(Theme.card)
        )
        .cardShadow()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Not scored"))
    }

    /// Engine confidence is the source of truth — additive undercount notes stay
    /// local to the Additives section and must not drive this banner.
    @ViewBuilder private func dataConfidenceLine(dark: Bool) -> some View {
        let provisional = ScoringEngineV4.isProvisionalScore(liveProduct,
                                                             ruleset: RulesetStore.current)
        if provisional {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                    .font(.sageSemiBold(12))
                Text("Limited label data — treat this score as provisional.")
                    .font(.sageRegular(12))
                    .lineSpacing(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(Theme.inkSecondary)
            .padding(.horizontal, 20)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func overviewSection(dark: Bool, product p: Product) -> some View {
        let generating = store.overviewGenerating.contains(p.id)
        let show = !p.isUnscored && (generating || p.overviewStale == true || p.overview != nil)
        if show {
            // Prose sits straight on the background (no card) under a
            // collapsible section header — the delta now lives in the score
            // caption, so the header carries no badge.
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { overviewExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Text("Overview")
                            .font(.sageSemiBold(18)).tracking(-0.4)
                            .foregroundColor(Theme.ink)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up")
                            .font(.sageSemiBold(12))
                            .foregroundColor(Theme.inkSecondary)
                            .rotationEffect(.degrees(overviewExpanded ? 0 : 180))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Overview")
                .accessibilityHint(overviewExpanded ? "Collapse" : "Expand")

                if overviewExpanded {
                    if generating || (p.overviewStale == true && p.overview == nil) {
                        Text("Generating overview…")
                            .font(.sageRegular(16))
                            .foregroundColor(Theme.inkSecondary)
                            .italic()
                    } else if let text = p.overview?.text {
                        Text(text)
                            .font(.sageRegular(16))
                            .foregroundColor(Theme.ink)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder private func avoidFlagsSection(dark: Bool) -> some View {
        let hits = ScoringEngineV4.avoidListHits(liveProduct, profile: store.user,
                                                 rs: RulesetStore.current)
        if !hits.isEmpty {
            VStack(spacing: 6) {
                ForEach(hits, id: \.self) { item in
                    let copy = avoidChipCopy(for: item)
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.sageSemiBold(12))
                            .foregroundColor(Color.scoreBad)
                        Text(copy)
                            .font(.sageSemiBold(13))
                            .foregroundColor(Theme.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(Color.scoreBad.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .stroke(Color.scoreBad.opacity(0.35), lineWidth: 1)
                    )
                    .accessibilityLabel(copy)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    /// Cite the binding avoid cap when it binds; otherwise "on your avoid list" only.
    /// Unscored products never mention caps — there is no score to ceiling.
    private func avoidChipCopy(for item: String) -> String {
        let titled = item.prefix(1).uppercased() + item.dropFirst().lowercased()
        if !liveProduct.isUnscored,
           let cap = liveProduct.bindingCap,
           cap.kind == "avoidList",
           cap.shortLabel == item.lowercased() {
            return "\(titled) — on your avoid list. Caps your score at \(cap.value)."
        }
        return "\(titled) — on your avoid list"
    }

    // MARK: Section chrome
    //
    // Sections sit straight on the background: one 18pt header (optionally
    // with a pill / count / caption on the right), rows separated by
    // hairlines. Cards are reserved for alerts (allergen, avoid-list, diet)
    // and the Better-options rail.

    private func sectionHeader<Trailing: View>(_ title: String, topPadding: CGFloat = 28,
                                               @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.sageSemiBold(18)).tracking(-0.4)
                .foregroundColor(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.top, topPadding).padding(.bottom, 10)
    }

    private func sectionHeader(_ title: String, topPadding: CGFloat = 28) -> some View {
        sectionHeader(title, topPadding: topPadding) { EmptyView() }
    }

    private var rowDivider: some View {
        Theme.hairline.frame(height: 0.5).padding(.horizontal, 20)
    }

    // MARK: Processing (NOVA) + Nutri-Score

    private static let novaShort = [
        1: "Minimally processed", 2: "Culinary ingredient",
        3: "Processed", 4: "Ultra-processed",
    ]
    private static let novaLong = [
        1: "Unprocessed or minimally processed",
        2: "Processed culinary ingredients",
        3: "Processed",
        4: "Ultra-processed",
    ]
    private static let novaExplainer = [
        1: "Whole foods, or foods altered only by cleaning, drying, freezing, pasteurizing or fermenting — nothing added that you wouldn't find in a kitchen.",
        2: "Oils, butter, sugar, salt, flours: ingredients pressed, refined or milled from whole foods, meant to cook with rather than eat on their own.",
        3: "A whole food plus a few culinary ingredients — canned vegetables, cheese, fresh bread, cured fish. Recognizable, usually short lists.",
        4: "Industrial formulations built from isolates, modified starches, hydrogenated fats, flavorings, emulsifiers and colors. Designed for shelf life and palatability; regular intake tracks with poorer health outcomes.",
    ]
    private static let novaFootnote =
        "NOVA grades processing, not nutrition — olive oil is NOVA 2 and a diet soda NOVA 4. Sage scores the processing evidence on the label, not the group number alone."

    /// NOVA / Nutri-Score palettes are external grading scales and keep their
    /// own colors (design.md), not theme tokens.
    private func novaColor(_ group: Int) -> Color {
        switch group {
        case 1:  return Color(hex: "1F8A5B")
        case 2:  return Color(hex: "7BA935")
        case 3:  return Color(hex: "D4A02D")
        default: return Color(hex: "C9442B")
        }
    }

    private func nutriColor(_ grade: String) -> Color {
        switch grade.uppercased() {
        case "A": return Color(hex: "1F8A5B")
        case "B": return Color(hex: "7BA935")
        case "C": return Color(hex: "D4A02D")
        case "D": return Color(hex: "E07A26")
        case "E": return Color(hex: "C9442B")
        default:  return Color.neutralMuted
        }
    }

    /// "Processing" header carrying the NOVA verdict as a tinted pill, a plain
    /// explainer for that group, and the Nutri-Score as one row beneath.
    @ViewBuilder private func processingSection(dark: Bool) -> some View {
        if showNovaCard || showNutriCard {
            VStack(alignment: .leading, spacing: 0) {
                if showNovaCard {
                    let g = product.novaGroup
                    let c = novaColor(g)
                    sectionHeader("Processing") {
                        Text("NOVA \(g) · \(Self.novaShort[g] ?? "")")
                            .font(.sageSemiBold(12)).tracking(-0.1)
                            .foregroundColor(c)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(c.opacity(dark ? 0.18 : 0.12)))
                            .accessibilityLabel("NOVA \(g), \(Self.novaLong[g] ?? "")")
                    }
                    Text(Self.novaExplainer[g] ?? "")
                        .font(.sageRegular(15))
                        .foregroundColor(Theme.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                    Text(Self.novaFootnote)
                        .font(.sageRegular(13))
                        .foregroundColor(Theme.inkSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                } else {
                    sectionHeader("Labels")
                }
                if showNutriCard {
                    nutriScoreRow(dark: dark)
                        .padding(.top, showNovaCard ? 16 : 0)
                }
            }
        }
    }

    private func nutriScoreRow(dark: Bool) -> some View {
        let g = product.nutriGrade.uppercased()
        let c = nutriColor(g)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nutri-Score")
                    .font(.sageSemiBold(15)).tracking(-0.2)
                    .foregroundColor(Theme.ink)
                Text("Front-of-pack nutrition grade, A to E")
                    .font(.sageRegular(12))
                    .foregroundColor(Theme.inkSecondary)
            }
            Spacer(minLength: 8)
            Text(g)
                .font(.sageBold(16))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).fill(c)
                )
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .overlay(alignment: .top) { rowDivider }
        .overlay(alignment: .bottom) { rowDivider }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nutri-Score \(g), nutrition grade")
    }

    // MARK: Nutrition

    private func nutritionSection(dark: Bool) -> some View {
        VStack(spacing: 0) {
            sectionHeader("Nutrition") {
                Button {
                    showLabelLegend = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Per 100 g / ml")
                            .font(.sageMedium(13))
                        Image(systemName: "info.circle")
                            .font(.sageSemiBold(13))
                    }
                    .foregroundColor(Theme.inkSecondary)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Values per 100 grams or millilitres. What the labels mean")
            }
            nutrientRows(dark: dark)
            rowDivider
        }
    }

    private func deltaBadgeLabel(delta: Int) -> String? {
        guard delta != 0 else { return nil }
        let points = abs(delta)
        return delta < 0 ? "\(points) below overall" : "\(points) above overall"
    }

    private func compareButton(dark: Bool) -> some View {
        Button(action: onCompare) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.sageSemiBold(14))
                Text("Compare with another")
                    .font(.sageSemiBold(14)).tracking(-0.2)
            }
            .foregroundColor(Theme.ink)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compare with another product")
    }

    /// Heart in the nav bar — where every B2C app keeps "save". Snapshots the
    /// live product so it stays openable from the Pantry even when it was
    /// opened from Search or Top Rated without ever being scanned.
    private var favoriteToolbarButton: some View {
        let saved = store.isFavorite(product.id)
        return Button {
            store.toggleFavorite(liveProduct)
            favoriteTick &+= 1
        } label: {
            Image(systemName: saved ? "heart.fill" : "heart")
                .font(.sageSemiBold(16))
                .foregroundStyle(saved ? Theme.accent : Theme.ink)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: favoriteTick)
        }
        .sensoryFeedback(.selection, trigger: favoriteTick)
        .accessibilityLabel(saved ? "Remove from favorites" : "Add to favorites")
    }

    /// Grades only render when the product actually carries them — a missing
    /// Nutri-Score or NOVA rating drops that card entirely rather than showing
    /// an "unknown" placeholder.
    private var showNutriCard: Bool {
        ["A", "B", "C", "D", "E"].contains(product.nutriGrade.uppercased())
    }
    private var showNovaCard: Bool { product.hasKnownNova }

    private func nutrientRows(dark: Bool) -> some View {
        let n = product.nutrients
        return VStack(spacing: 0) {
                // Levels come from NutrientLevels — the same source the
                // scoring factor labels and the LLM prompt read, so badge
                // and sentence can never disagree.
                nutrientRow(label: "Sugar", value: n.sugar_g, unit: "g",
                            level: n.sugar_g.map(NutrientLevels.sugar),
                            higherIsBetter: false, divider: true, dark: dark)
                nutrientRow(label: "Sodium", value: n.sodium_mg, unit: "mg",
                            level: n.sodium_mg.map(NutrientLevels.sodium),
                            higherIsBetter: false, divider: true, dark: dark)
                nutrientRow(label: "Saturated fat", value: n.satFat_g, unit: "g",
                            level: n.satFat_g.map(NutrientLevels.satFat),
                            higherIsBetter: false, divider: true, dark: dark)
                nutrientRow(label: "Fiber", value: n.fiber_g, unit: "g",
                            level: n.fiber_g.map(NutrientLevels.fiber),
                            higherIsBetter: true,
                            bonus: product.bonuses.contains("fiber"),
                            divider: true, dark: dark)
                nutrientRow(label: "Protein", value: n.protein_g, unit: "g",
                            level: n.protein_g.map(NutrientLevels.protein),
                            higherIsBetter: true,
                            bonus: product.bonuses.contains("protein"),
                            divider: true, dark: dark)
                // Micronutrient rows appear only when reported (most products
                // lack them); a dash-only row would just be noise.
                if n.calcium_mg != nil {
                    nutrientRow(label: "Calcium", value: n.calcium_mg, unit: "mg",
                                level: n.calcium_mg.map(NutrientLevels.calcium),
                                higherIsBetter: true,
                                bonus: product.bonuses.contains("calcium"),
                                divider: true, dark: dark)
                }
                if n.iron_mg != nil {
                    nutrientRow(label: "Iron", value: n.iron_mg, unit: "mg",
                                level: n.iron_mg.map(NutrientLevels.iron),
                                higherIsBetter: true,
                                bonus: product.bonuses.contains("iron"),
                                divider: true, dark: dark)
                }
                if n.potassium_mg != nil {
                    nutrientRow(label: "Potassium", value: n.potassium_mg, unit: "mg",
                                level: n.potassium_mg.map(NutrientLevels.potassium),
                                higherIsBetter: true,
                                bonus: product.bonuses.contains("potassium"),
                                divider: true, dark: dark)
                }
        }
    }

    private func nutrientRow(label: String, value: Double?, unit: String,
                             level: NutrientLevel?, higherIsBetter: Bool,
                             bonus: Bool = false, divider: Bool, dark: Bool) -> some View {
        let display = value.map { "\(fmt($0)) \(unit)" } ?? "—"
        let tag = level.map { nutrientTag($0, higherIsBetter: higherIsBetter) }
        return NutrientRow(label: label, value: display, tag: tag,
                           bonus: bonus, divider: divider, dark: dark,
                           horizontalPadding: 20)
    }

    private var additivesCountCaption: String? {
        if product.additiveIngredientTextMissing == true { return nil }
        let count = product.additives.count
        if product.additiveUndercountSuspected == true {
            return "\(count) · may be undercounted"
        }
        return count == 0 ? nil : "\(count) detected"
    }

    // MARK: Additives

    private func additivesSection(dark: Bool) -> some View {
        let sweeteners = IngredientIntegrity.sweetenerSystemMatches(
            ingredientsText: liveProduct.ingredientsText)
        return VStack(spacing: 0) {
            sectionHeader("Additives") {
                if let caption = additivesCountCaption {
                    Text(caption)
                        .font(.sageMedium(13))
                        .foregroundColor(Theme.inkSecondary)
                }
            }
            VStack(spacing: 0) {
                if product.additiveIngredientTextMissing == true {
                    HStack(spacing: 10) {
                        RiskDot(risk: .unrated)
                        Text("No ingredient data")
                            .font(.sageSemiBold(15))
                            .foregroundColor(Theme.inkSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .overlay(alignment: .top) { rowDivider }
                } else if product.additives.isEmpty && sweeteners.isEmpty {
                    HStack(spacing: 10) {
                        RiskDot(risk: .low)
                        Text("No additives detected")
                            .font(.sageSemiBold(15))
                            .foregroundColor(Theme.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .overlay(alignment: .top) { rowDivider }
                } else {
                    if !product.additives.isEmpty {
                        SeverityBar(additives: product.additives, allowAlarmRed: !yourScoreIsWorstSignal)
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .overlay(alignment: .top) { rowDivider }
                        ForEach(Array(product.additives.enumerated()), id: \.element.id) { (_, a) in
                            Button {
                                selectedAdditive = a
                            } label: {
                                AdditiveRow(additive: a, divider: true, dark: dark,
                                            allowAlarmRed: !yourScoreIsWorstSignal,
                                            horizontalPadding: 20)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !sweeteners.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .font(.sageSemiBold(14))
                                .foregroundColor(Theme.inkSecondary)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text("Sweetener system · \(sweeteners.count) detected")
                                        .font(.sageSemiBold(14))
                                        .foregroundColor(Theme.ink)
                                    Text("INFO")
                                        .font(.sageBold(10)).tracking(0.6)
                                        .foregroundColor(Theme.inkSecondary)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(
                                            Capsule().fill(Theme.inkSecondary.opacity(0.12))
                                        )
                                }
                                Text(sweeteners.map { $0.capitalized }.joined(separator: ", "))
                                    .font(.sageRegular(12))
                                    .foregroundColor(Theme.inkSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .overlay(alignment: .top) { rowDivider }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Sweetener system, \(sweeteners.count) detected: \(sweeteners.joined(separator: ", "))")
                    }
                }
            }
            rowDivider
        }
    }

    @ViewBuilder private func fullIngredientsSection(dark: Bool) -> some View {
        let raw = (liveProduct.ingredientsText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            let display = sentenceCasedIngredients(raw)
            let needles = avoidHighlightNeedles(for: liveProduct)
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        ingredientsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Full ingredients")
                            .font(.sageSemiBold(18)).tracking(-0.4)
                            .foregroundColor(Theme.ink)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.sageSemiBold(12))
                            .foregroundColor(Theme.inkSecondary)
                            .rotationEffect(.degrees(ingredientsExpanded ? 180 : 0))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28).padding(.bottom, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Full ingredients")
                .accessibilityHint(ingredientsExpanded ? "Collapse" : "Expand")

                if ingredientsExpanded {
                    highlightedIngredients(display, needles: needles, dark: dark)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private func sentenceCasedIngredients(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return String(first).uppercased() + trimmed.dropFirst().lowercased()
    }

    private func avoidHighlightNeedles(for product: Product) -> [String] {
        let hits = ScoringEngineV4.avoidListHits(product, profile: store.user,
                                                 rs: RulesetStore.current)
        guard !hits.isEmpty else { return [] }
        var needles: [String] = []
        let avoid = RulesetStore.current.avoidList
        for hit in hits {
            if let texts = avoid?[hit.lowercased()]?.text {
                needles.append(contentsOf: texts)
            }
            // Seed-oil crop names for parenthetical listings
            if hit.lowercased() == "seed oils" {
                needles.append(contentsOf: [
                    "rapeseed", "soybean", "soya", "canola", "sunflower",
                    "cottonseed", "grapeseed", "safflower", "corn oil",
                    "fully hydrogenated", "hydrogenated vegetable",
                ])
            }
        }
        return needles
    }

    private func highlightedIngredients(_ text: String, needles: [String], dark: Bool) -> some View {
        let attributed = highlightedAttributedString(text, needles: needles, dark: dark)
        return Text(attributed)
            .font(.sageRegular(15))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func highlightedAttributedString(_ text: String, needles: [String],
                                             dark: Bool) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = Theme.ink
        let lower = text.lowercased()
        for needle in needles {
            let n = needle.lowercased()
            guard !n.isEmpty else { continue }
            var searchStart = lower.startIndex
            while let range = lower.range(of: n, range: searchStart..<lower.endIndex) {
                if let attrStart = AttributedString.Index(range.lowerBound, within: result),
                   let attrEnd = AttributedString.Index(range.upperBound, within: result) {
                    result[attrStart..<attrEnd].backgroundColor = Color.scoreOk.opacity(0.28)
                }
                searchStart = range.upperBound
            }
        }
        return result
    }

    private func detectedSection(dark: Bool) -> some View {
        // A present caffeine field of 0 (common in OFF, e.g. Nutella) is not
        // "contains caffeine" — require a positive amount.
        let hasCaffeine = (product.caffeine_mg ?? 0) > 0
        let show = hasCaffeine || !product.sweeteners.isEmpty || product.seedOils
        // Solids are measured per 100 g, beverages per 100 ml.
        let isBeverage = (product.categories ?? []).contains {
            $0.contains("beverage") || $0.contains("drink")
        }
        return Group {
            if show {
                sectionHeader("Detected")
                VStack(spacing: 0) {
                    if hasCaffeine, let mg = product.caffeine_mg {
                        InfoRow(emoji: "☕", label: "Contains caffeine",
                                detail: "\(fmt(mg)) mg per \(isBeverage ? "100 ml" : "100 g")", dark: dark)
                    }
                    ForEach(product.sweeteners, id: \.self) { s in
                        InfoRow(emoji: "◈",
                                label: "Contains \(sweetenerLabel(s))",
                                detail: "Artificial / non-nutritive sweetener", dark: dark)
                    }
                    if product.seedOils {
                        let onAvoid = ScoringEngineV4.avoidListHits(
                            product, profile: store.user, rs: RulesetStore.current
                        ).contains { $0.lowercased().contains("seed") }
                        let detail: String = {
                            guard onAvoid else { return "Detected in ingredients" }
                            if !product.isUnscored,
                               let cap = product.bindingCap,
                               cap.kind == "avoidList",
                               cap.shortLabel.contains("seed") {
                                return "On your avoid list. Caps your score at \(cap.value)."
                            }
                            return "On your avoid list"
                        }()
                        InfoRow(
                            emoji: "🌻",
                            label: "Contains seed oils",
                            detail: detail,
                            dark: dark
                        )
                    }
                    rowDivider
                }
            }
        }
    }

    private func restrictionBanners(dark: Bool) -> some View {
        let valid = product.restrictions.filter {
            ["vegan","vegetarian","pescatarian","low-sugar diet","low-sodium diet",
             "gluten-free","dairy-free"]
                .contains($0.type)
        }
        let fired = product.firedCaps ?? []
        return Group {
            if !valid.isEmpty {
                VStack(spacing: 6) {
                    ForEach(valid) { r in
                        let capValue = fired.first {
                            $0.kind == "dietConflict" && $0.shortLabel == r.type.lowercased()
                        }?.value ?? RulesetStore.current.hardGates?.dietConflictCap ?? 20
                        RestrictionBannerView(
                            type: r.type, trigger: r.trigger,
                            capValue: capValue, dark: dark,
                            showCap: !liveProduct.isUnscored
                        )
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }
        }
    }

    private func allergenSection(dark: Bool) -> some View {
        let userAllergies = store.user.allergies ?? []
        let warnings = AllergenMatcher.warnings(product: product, allergies: userAllergies)
        return Group {
            if !userAllergies.isEmpty {
                VStack(spacing: 8) {
                    ForEach(warnings) { w in
                        AllergenBanner(label: w.label, fromTag: w.fromTag, dark: dark)
                    }
                    AllergenDisclaimer(hasMatch: !warnings.isEmpty, dark: dark)
                }
                .padding(.horizontal, 16).padding(.bottom, 14)
            }
        }
    }

    private func disclaimer(dark: Bool) -> some View {
        Text("This is not professional advice. For specialized recommendation, seek a nutritionist.")
            .font(.sageRegular(11))
            .multilineTextAlignment(.center)
            .foregroundColor(Theme.inkSecondary)
            .lineSpacing(2)
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
    }

#if DEBUG
    /// Human-readable provenance for the DEBUG caption (product.dataSource is
    /// the Worker's `_source`). nil = pure Open Food Facts.
    private var nutritionSourceLabel: String {
        switch product.dataSource {
        case "usda":     return "USDA (Open Food Facts had no record)"
        case "off+usda": return "USDA nutrition + Open Food Facts data"
        default:         return "Open Food Facts"
        }
    }

    private func scoreDebugSection(dark: Bool) -> some View {
        let breakdown = ScoringEngineV4.debugText(product, for: store.user,
                                                  ruleset: RulesetStore.current)
        return VStack(alignment: .leading, spacing: 8) {
            Text("SCORE DEBUG")
                .font(.sageBold(11)).tracking(1.2)
                .foregroundColor(Color(hex: ScoreBandColor.okMid))
            Text("Nutrition source: \(nutritionSourceLabel)")
                .font(.sageBold(11))
                .foregroundColor(Theme.ink)
            Text(breakdown)
                .font(.sageRegular(10))
                .monospacedDigit()
                .foregroundColor(Theme.inkSecondary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.fillQuiet)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .stroke(Color(hex: ScoreBandColor.okMid).opacity(0.35), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
#endif
}

// MARK: - Sub-components

struct NutrientRow: View {
    let label: String
    let value: String
    let tag: Tag?
    var bonus: Bool = false
    let divider: Bool
    let dark: Bool
    var horizontalPadding: CGFloat = 14

    /// The word states the measured amount (Low/Mod/High); the tone says how
    /// that amount should feel for this nutrient — they must stay independent
    /// so "Fiber 0g" reads LOW (not a red HIGH) and "Protein 30g" reads a
    /// green HIGH (not LOW).
    struct Tag: Equatable {
        enum Tone { case good, mid, bad, neutral }
        let word: String
        let tone: Tone

        var fg: Color { switch tone {
            case .good:    return Color.scoreGood
            case .mid:     return Color.scoreOk
            case .bad:     return Color.scoreBad
            case .neutral: return Color.neutralMuted }
        }
        var bg: Color { fg.opacity(0.10) }
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.sageSemiBold(14)).tracking(-0.2)
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
                if bonus {
                    Text("+ BOOST")
                        .font(.sageBold(10)).tracking(0.3)
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent.opacity(0.12)))
                        .fixedSize()
                }
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.sageBold(14))
                .monospacedDigit().tracking(-0.2)
                .foregroundColor(Theme.ink)
                .fixedSize(horizontal: true, vertical: false)
            if let tag {
                Text(tag.word.uppercased())
                    .font(.sageBold(10)).tracking(0.4)
                    .foregroundColor(tag.fg)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(tag.bg))
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, horizontalPadding).padding(.vertical, 12)
        .overlay(alignment: .top) {
            if divider {
                Theme.hairline.frame(height: 0.5)
                    .padding(.horizontal, horizontalPadding == 14 ? 8 : horizontalPadding)
            }
        }
    }
}

struct AdditiveRow: View {
    let additive: ProductAdditive
    let divider: Bool
    let dark: Bool
    var allowAlarmRed: Bool = true
    var horizontalPadding: CGFloat = 16

    private var riskFg: Color {
        if additive.risk == .high { return Color.scoreBad }
        return RiskStyle.fg(additive.risk)
    }

    private var riskBg: Color { riskFg.opacity(additive.risk == .high && allowAlarmRed ? 0.10 : 0.12) }

    var body: some View {
        HStack(spacing: 12) {
            RiskDot(risk: additive.risk, allowAlarmRed: allowAlarmRed)
            VStack(alignment: .leading, spacing: 2) {
                Text(additive.name)
                    .font(.sageSemiBold(14)).tracking(-0.2)
                    .foregroundColor(Theme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if let note = additive.note, !note.isEmpty {
                    Text(note)
                        .font(.sageRegular(11))
                        .foregroundColor(Theme.inkSecondary)
                        .lineSpacing(1)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            Text(RiskStyle.label(additive.risk))
                .font(.sageBold(10)).tracking(0.2)
                .foregroundColor(riskFg)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(riskBg))
            Image(systemName: "chevron.right")
                .font(.sageSemiBold(10))
                .foregroundColor(Theme.inkSecondary.opacity(0.6))
        }
        .padding(.horizontal, horizontalPadding).padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if divider {
                Theme.hairline.frame(height: 0.5)
                    .padding(.horizontal, horizontalPadding == 16 ? 8 : horizontalPadding)
            }
        }
        .accessibilityHint("Shows additive details")
    }
}

struct SeverityBar: View {
    let additives: [ProductAdditive]
    var allowAlarmRed: Bool = true

    private func barColor(for risk: RiskLevel) -> Color {
        if risk == .high { return Color.scoreBad }
        return RiskStyle.fg(risk)
    }

    /// Counts by risk; legend order always sums to the header (deduped) count.
    static func counts(for additives: [ProductAdditive]) -> [RiskLevel: Int] {
        additives.reduce(into: [:]) { dict, a in
            dict[a.risk, default: 0] += 1
        }
    }

    var body: some View {
        let total = max(additives.count, 1)
        let counts = Self.counts(for: additives)
        let order: [RiskLevel] = [.low, .moderate, .high, .unrated]
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(order, id: \.self) { r in
                        if let c = counts[r], c > 0 {
                            Rectangle()
                                .fill(barColor(for: r))
                                .frame(width: geo.size.width * CGFloat(c) / CGFloat(total))
                        }
                    }
                }
            }
            .frame(height: 6)
            .background(Capsule().fill(Theme.fillQuiet))
            .clipShape(Capsule())

            HStack(spacing: 10) {
                ForEach(order, id: \.self) { r in
                    HStack(spacing: 4) {
                        RiskDot(risk: r, size: 7, allowAlarmRed: allowAlarmRed)
                        Text("\(counts[r] ?? 0) \(RiskStyle.shortLabel(r))")
                            .font(.sageBold(11))
                            .foregroundColor(barColor(for: r))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(legendAccessibility(counts: counts, total: additives.count))
    }

    private func legendAccessibility(counts: [RiskLevel: Int], total: Int) -> String {
        let parts = [RiskLevel.low, .moderate, .high, .unrated].map {
            "\(counts[$0] ?? 0) \(RiskStyle.shortLabel($0))"
        }
        return "\(total) additives: " + parts.joined(separator: ", ")
    }
}

struct RiskDot: View {
    let risk: RiskLevel
    var size: CGFloat = 10
    var allowAlarmRed: Bool = true

    private var color: Color {
        if risk == .high { return Color.scoreBad }
        return RiskStyle.fg(risk)
    }

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

struct InfoRow: View {
    let emoji: String
    let label: String
    let detail: String
    let dark: Bool
    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.sageRegular(14))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).fill(Theme.fillQuiet))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.sageBold(13)).tracking(-0.2)
                    .foregroundColor(Theme.ink)
                Text(detail)
                    .font(.sageRegular(11))
                    .foregroundColor(Theme.inkSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .overlay(alignment: .top) {
            Theme.hairline.frame(height: 0.5).padding(.horizontal, 20)
        }
    }
}

struct RestrictionBannerView: View {
    let type: String
    let trigger: String
    var capValue: Int = 20
    let dark: Bool
    /// When false (unscored products), omit "Caps your score…" — there is no dial.
    var showCap: Bool = true
    var body: some View {
        let fg = Color.cautionMuted
        let headline: String = {
            if showCap {
                return "Conflicts with your \(type.lowercased()). Caps your score at \(capValue)."
            }
            return String(format: String(localized: "Conflicts with your %@."), type.lowercased())
        }()
        HStack(alignment: .top, spacing: 10) {
            Text("⚠️").font(.sageRegular(14))
            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.sageBold(13)).tracking(-0.1)
                    .foregroundColor(fg)
                Text(type.uppercased())
                    .font(.sageBold(11)).tracking(0.4)
                    .foregroundColor(fg.opacity(0.85))
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(fg.opacity(dark ? 0.14 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .stroke(fg.opacity(0.18), lineWidth: 1)
        )
        .accessibilityLabel("\(headline) Trigger: \(trigger).")
    }
}

/// Whether trans fat is actually the largest attributed score penalty.
/// V5 applies a base Overall cap when transFat_g > threshold — surface that.
enum TransFatAttribution {
    static func isHeaviestPenalty(in product: Product) -> Bool {
        guard product.showsTransFatFlag else { return false }
        if let cap = product.bindingCap, cap.kind == "transFat" { return true }
        if product.firedCaps?.contains(where: { $0.kind == "transFat" }) == true {
            return true
        }
        return false
    }
}

struct SeriousFlag: View {
    var isHeaviestScorePenalty: Bool = false

    var body: some View {
        let fg = Color.cautionMuted
        let subtitle = isHeaviestScorePenalty
            ? "Caps the overall score at 35 — industrial trans fat has no safe intake."
            : "Industrial trans fats have no safe intake level. Overall score capped at 34 when above 0.2 g/100 g."
        HStack(spacing: 12) {
            Text("!")
                .font(.sageBold(16))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).fill(fg))
            VStack(alignment: .leading, spacing: 1) {
                Text("Contains trans fats")
                    .font(.sageBold(14)).tracking(-0.2)
                    .foregroundColor(fg)
                Text(subtitle)
                    .font(.sageRegular(11))
                    .foregroundColor(fg.opacity(0.85))
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(fg.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(fg.opacity(0.20), lineWidth: 1)
        )
    }
}

// MARK: - Allergen banners

struct AllergenBanner: View {
    let label: String
    let fromTag: Bool
    let dark: Bool
    var body: some View {
        let fg = Color.cautionMuted
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.sageRegular(18))
                .foregroundColor(fg)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(fromTag ? "Contains" : "May contain") \(label.lowercased())")
                    .font(.sageBold(14)).tracking(-0.2)
                    .foregroundColor(fg)
                Text(fromTag ? "Listed as an allergen for this product"
                             : "Detected in the ingredient list")
                    .font(.sageRegular(11))
                    .foregroundColor(fg.opacity(0.85))
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(fg.opacity(dark ? 0.14 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(fg.opacity(0.20), lineWidth: 1)
        )
    }
}

struct AllergenDisclaimer: View {
    let hasMatch: Bool
    let dark: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.sageRegular(12))
                .foregroundColor(Theme.inkSecondary)
            Text(hasMatch
                 ? "Always confirm on the product packaging — allergen data can be incomplete."
                 : "No declared allergens matched your profile, but data may be incomplete — always check the packaging.")
                .font(.sageRegular(11))
                .foregroundColor(Theme.inkSecondary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.fillQuiet)
        )
    }
}

// MARK: - Helpers

func fmt(_ v: Double) -> String {
    v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
}

/// Maps a shared NutrientLevel to the badge. Plenty of a beneficial nutrient
/// is good news; little of it is merely unremarkable (neutral), not an alarm.
// Verdict words: the label states the *judgement*, not the raw amount (the
// amount is already the number next to it). This keeps word and colour in sync
// — green is always "Good", red always "High" (too much), grey always "Low"
// (a beneficial nutrient that's lacking) — so no word ever shows in two colours.
func nutrientTag(_ level: NutrientLevel, higherIsBetter: Bool) -> NutrientRow.Tag {
    if higherIsBetter {
        switch level {
        case .high:     return .init(word: "Good", tone: .good)
        case .moderate: return .init(word: "OK",   tone: .mid)
        case .low:      return .init(word: "Low",  tone: .neutral)
        }
    } else {
        switch level {
        case .low:      return .init(word: "Good", tone: .good)
        case .moderate: return .init(word: "OK",   tone: .mid)
        case .high:     return .init(word: "High", tone: .bad)
        }
    }
}

/// Bottom sheet with curated knowledge-base detail for one additive.
struct AdditiveDetailSheet: View {
    let additive: ProductAdditive
    let dark: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var kb: AdditiveKnowledgeBase.Entry? {
        additive.code.flatMap { AdditiveKnowledgeBase.entry(for: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(additive.name)
                                .font(.sageBold(20)).tracking(-0.3)
                                .foregroundColor(Theme.ink)
                            if let code = additive.code {
                                Text(code.uppercased())
                                    .font(.sageSemiBold(13))
                                    .foregroundColor(Theme.inkSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                        riskChip
                    }

                    if let kb {
                        section(title: "Function", body: kb.function.resolved())
                        section(title: "Overview", body: kb.detail.resolved())
                        section(title: "Why this rating",
                                body: tierExplanation(for: kb.risk))
                    } else {
                        section(title: "Overview",
                                body: "We haven't reviewed this additive yet. It stays unrated until we add a curated entry.")
                    }

                    if let detected = additive.detectedAs, !detected.isEmpty {
                        section(title: "Detected as",
                                body: detected.joined(separator: ", "))
                    }

                    if let sources = kb?.sources, !sources.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sources")
                                .font(.sageBold(13))
                                .foregroundColor(Theme.ink)
                            ForEach(sources, id: \.self) { urlString in
                                if let url = URL(string: urlString) {
                                    Button(urlString) { openURL(url) }
                                        .font(.sageRegular(12))
                                        .foregroundColor(Color.accentColor)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Additive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var riskChip: some View {
        let fg = additive.risk == .high ? Color.scoreBad : RiskStyle.fg(additive.risk)
        return Text(RiskStyle.label(additive.risk))
            .font(.sageBold(10)).tracking(0.2)
            .foregroundColor(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(fg.opacity(0.12)))
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.sageBold(13))
                .foregroundColor(Theme.ink)
            Text(body)
                .font(.sageRegular(14))
                .foregroundColor(Theme.inkSecondary)
                .lineSpacing(3)
        }
    }

    private func tierExplanation(for risk: RiskLevel) -> String {
        switch risk {
        case .low:
            return "Low risk means typical food-use levels are generally considered a low concern for the average person."
        case .moderate:
            return "Moderate risk means evidence or intake limits suggest a closer look, without treating this additive as a hard avoid for everyone."
        case .high:
            return "High risk means stronger caution from regulators or research (for example warnings, restrictions, or well-known concerns)."
        case .unrated:
            return "Unrated means Sage does not yet have a curated assessment for this code."
        }
    }
}

/// Bottom sheet explaining nutrient amount badges and additive risk chips.
struct LabelLegendSheet: View {
    let dark: Bool
    @Environment(\.dismiss) private var dismiss

    private let nutrientItems: [(word: String, fg: Color, meaning: String)] = [
        ("Good", Color.scoreGood,    "a healthy amount"),
        ("OK",   Color.scoreOk,      "middling"),
        ("High", Color.scoreBad,     "too much of something to limit"),
        ("Low",  Color.neutralMuted, "a beneficial nutrient is low"),
    ]

    private let riskItems: [(RiskLevel, String)] = [
        (.low, "generally recognized as lower concern"),
        (.moderate, "use with some caution"),
        (.high, "higher concern — limit when you can"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Nutrient amounts")
                            .font(.sageBold(15))
                            .foregroundColor(Theme.ink)
                        ForEach(nutrientItems, id: \.word) { item in
                            legendRow(word: item.word, fg: item.fg, meaning: item.meaning)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Additive risk")
                            .font(.sageBold(15))
                            .foregroundColor(Theme.ink)
                        ForEach(riskItems, id: \.0) { item in
                            legendRow(word: RiskStyle.label(item.0),
                                      fg: RiskStyle.fg(item.0),
                                      meaning: item.1)
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("What the labels mean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func legendRow(word: String, fg: Color, meaning: String) -> some View {
        HStack(spacing: 10) {
            Text(word)
                .font(.sageBold(10)).tracking(0.2)
                .foregroundColor(fg)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(fg.opacity(0.12)))
                .frame(minWidth: 72, alignment: .leading)
            Text(meaning)
                .font(.sageRegular(13))
                .foregroundColor(Theme.inkSecondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(word): \(meaning)")
    }
}

func sweetenerLabel(_ key: String) -> String {
    switch key {
    case "aspartame":     return "Aspartame"
    case "acesulfame K":  return "Acesulfame K"
    case "saccharin":     return "Saccharin"
    case "sucralose":     return "Sucralose"
    case "stevia":        return "Stevia"
    case "monk fruit":    return "Monk fruit"
    default:              return key
    }
}

// MARK: - Better-options card

/// One "Better options" card (ALTERNATIVES_SPEC.md §5): photo with the score
/// ring in the corner, name, and one short reason it beats the scanned product.
private struct AlternativeCard: View {
    let alt: Alternative
    let onTap: () -> Void

    var body: some View {
        let formatted = ProductNameFormatter.format(alt.product)
        let why = alt.reasons.first ?? "+\(alt.delta) for you"
        let title = [formatted.brand, formatted.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    ProductThumb(glyph: alt.product.glyph, score: alt.score, size: 96,
                                 neutral: true,
                                 imageURL: alt.product.listImageURL,
                                 fallbackImageURL: alt.product.imageFallbackURL,
                                 processCutout: alt.product.shouldProcessCutout)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                    ScoreRing(score: alt.score, size: 44, stroke: 4)
                        .background(Circle().fill(Theme.card).padding(-3))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.sageSemiBold(13)).tracking(-0.2)
                        .foregroundColor(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 34, alignment: .top)
                    Text(why)
                        .font(.sageSemiBold(11))
                        .foregroundColor(Color.scoreGood)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(width: 160, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card)
            )
            .cardShadow()
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(formatted.accessibilityLabel), scored \(alt.score), +\(alt.delta), \(why)")
    }
}
