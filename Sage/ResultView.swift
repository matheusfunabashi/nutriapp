import SwiftUI

struct ResultView: View {
    @EnvironmentObject var store: AppStore
    let product: Product
    let fromScan: Bool
    let onBack: () -> Void
    let onCompare: () -> Void
    let onOpenMethodology: () -> Void
    /// Open a "better alternative" the user tapped. Defaulted so other call
    /// sites (previews/tests) compile unchanged.
    var onSelectAlternative: (Product) -> Void = { _ in }

    @State private var showLabelLegend = false
    @State private var selectedAdditive: ProductAdditive? = nil
    @State private var ingredientsExpanded = false
    /// Computed once on appear (re-scoring candidates is cheap but not free, so
    /// it stays off the per-render path).
    @State private var alternatives: [Alternative] = []

    var body: some View {
        let dark = store.darkMode
        VStack(spacing: 0) {
            topBar(dark: dark)
                .background(Theme.bg(dark))

            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        scrollableHeader(dark: dark)
                        allergenSection(dark: dark)
                        avoidFlagsSection(dark: dark)
                        betterOptionsSection(dark: dark)
                        if showNutriCard || showNovaCard {
                            SectionTitle(title: "Breakdown", dark: dark)
                            gradesRow(dark: dark)
                        }
                        if product.showsTransFatFlag {
                            SeriousFlag(
                                isHeaviestScorePenalty: TransFatAttribution.isHeaviestPenalty(in: product)
                            )
                            .padding(.horizontal, 16).padding(.top, 8)
                        }
                        nutrientsHeader(dark: dark)
                        nutrientsCard(dark: dark).padding(.horizontal, 16)
                        EyebrowLabel(text: additivesEyebrow(dark: dark), dark: dark)
                        additivesCard(dark: dark).padding(.horizontal, 16)
                        fullIngredientsSection(dark: dark)
                        detectedSection(dark: dark)
                        restrictionBanners(dark: dark)
                        disclaimer(dark: dark)
#if DEBUG
                        scoreDebugSection(dark: dark)
#endif
                        Spacer().frame(height: 140)
                    }
                    .frame(minWidth: geo.size.width, maxWidth: geo.size.width,
                           minHeight: geo.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
        .onAppear {
            store.requestOverview(for: product.id)
            alternatives = Alternatives.suggest(for: liveProduct, profile: store.user)
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

    /// "Better options": up to three same-shelf products that beat this one on
    /// Overall (ALTERNATIVES_SPEC.md). Hidden when the product has no shelf,
    /// is unscored, or nothing scores meaningfully higher.
    @ViewBuilder private func betterOptionsSection(dark: Bool) -> some View {
        if !alternatives.isEmpty {
            let baseline = liveProduct.overallScore ?? 0
            SectionTitle(title: "Better options", dark: dark)
            VStack(spacing: 0) {
                ForEach(Array(alternatives.enumerated()), id: \.element.id) { idx, alt in
                    AlternativeRow(alt: alt, delta: alt.score - baseline,
                                   divider: idx > 0, dark: dark) {
                        onSelectAlternative(alt.product)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.surface(dark))
            )
            .cardShadow(dark)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func scrollableHeader(dark: Bool) -> some View {
        let p = liveProduct
        return VStack(spacing: 8) {
            productHeader(dark: dark)
            VStack(spacing: 12) {
                if p.isUnscored {
                    unscoredScoreCard(dark: dark, product: p)
                        .padding(.horizontal, 16)
                } else {
                    overviewSection(dark: dark, product: p)
                    scoreComparisonCard(dark: dark)
                        .padding(.horizontal, 16)
                    dataConfidenceLine(dark: dark)
                }
            }
            .padding(.top, 14)
        }
        .padding(.bottom, 8)
    }

    private func topBar(dark: Bool) -> some View {
        ZStack {
            HStack {
                CircleIconButton(systemName: "chevron.left", dark: dark,
                                 accessibilityLabel: "Back", action: onBack)
                Spacer()
            }
            HStack(spacing: 8) {
                SageMark(size: 26, color: store.accent)
                Text("Sage")
                    .font(.sageSemiBold(22))
                    .tracking(-0.6)
                    .foregroundColor(Theme.textPrimary(dark))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("Sage")
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
    }

    private var productTitle: String {
        let brand = product.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brand.isEmpty else { return name }
        if name.lowercased().hasPrefix(brand.lowercased()) { return name }
        return "\(brand.localizedCapitalized) \(name)"
    }

    private func productHeader(dark: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ProductThumb(glyph: product.glyph, score: product.yourScore,
                         neutral: true, imageURL: product.detailImageURL,
                         processCutout: product.shouldProcessCutout,
                         isDetail: true)

            VStack(alignment: .leading, spacing: 2) {
                Text(productTitle)
                    .font(.sageBold(22)).tracking(-0.5)
                    .foregroundColor(Theme.textPrimary(dark))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.9)
                Text(product.size)
                    .font(.sageRegular(13))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.horizontal, 16)
    }

    /// Side-by-side dials for scored products, or the single "Not scored" card
    /// for pure sweeteners (no dials / tier / Organic chip).
    private func scoreComparisonCard(dark: Bool) -> some View {
        let showOrganic = ScoringEngineV4.showsOrganicChip(product: liveProduct,
                                                           profile: store.user)
        return VStack(spacing: 12) {
            if showOrganic {
                Text("Organic ✓")
                    .font(.sageSemiBold(11))
                    .foregroundColor(Theme.textSecondary(dark))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(
                        Capsule().fill(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    )
                    .accessibilityLabel("Organic certified")
            }
            HStack(alignment: .top, spacing: 12) {
                scorePanel(title: "OVERALL",
                           score: liveProduct.overallScore ?? 0,
                           ringColor: scoreColor(liveProduct.overallScore ?? 0),
                           emphasized: false, dark: dark)
                scorePanel(title: "YOUR SCORE",
                           score: liveProduct.yourScore ?? 0,
                           ringColor: yourScoreIsWorstSignal ? Color.scoreBad
                                                             : scoreColor(liveProduct.yourScore ?? 0),
                           emphasized: true, dark: dark,
                           bindingCap: liveProduct.bindingCap)
            }
            compareButton(dark: dark)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.surface(dark))
        )
        .cardShadow(dark)
    }

    private func unscoredScoreCard(dark: Bool, product p: Product) -> some View {
        let notes = ScoringEngineV4.sweetenerQualityNotes(p, ruleset: RulesetStore.current)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Not scored")
                    .font(.sageBold(18)).tracking(-0.3)
                    .foregroundColor(Theme.textPrimary(dark))
                Text("This is essentially pure sugar, and no concentrated sugar is a health food. Sage doesn't score sweeteners, so a number here would only mislead.")
                    .font(.sageRegular(13))
                    .foregroundColor(Theme.textSecondary(dark))
                    .lineSpacing(2)
            }
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Among sweeteners")
                        .font(.sageBold(12)).tracking(0.4)
                        .foregroundColor(Theme.textSecondary(dark))
                    ForEach(notes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 8) {
                            Text("·")
                                .font(.sageBold(13))
                                .foregroundColor(Theme.textSecondary(dark))
                            Text(LocalizedStringKey(note))
                                .font(.sageRegular(13))
                                .foregroundColor(Theme.textPrimary(dark))
                        }
                    }
                    Text("Relative quality among sweeteners — not a health score.")
                        .font(.sageRegular(11))
                        .foregroundColor(Theme.textSecondary(dark))
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
                .foregroundColor(Theme.textSecondary(dark))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.surface(dark))
        )
        .cardShadow(dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Not scored"))
    }

    private func scorePanel(title: String, score: Int, ringColor: Color,
                            emphasized: Bool, dark: Bool,
                            bindingCap: ScoreCap? = nil) -> some View {
        let label = scoreLabel(score)
        let panelFill: Color = emphasized
            ? ringColor.opacity(dark ? 0.14 : 0.06)
            : (dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
        return VStack(spacing: 12) {
            Text(title)
                .font(.sageBold(11)).tracking(1.2)
                .foregroundColor(Theme.textSecondary(dark))
            ScoreRing(score: score, size: 96, stroke: 7, dark: dark, ringColor: ringColor)
            Text(label.uppercased())
                .font(.sageBold(11)).tracking(0.6)
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(ringColor))
            if emphasized, let cap = bindingCap {
                Text("Capped: \(cap.shortLabel)")
                    .font(.sageSemiBold(10))
                    .foregroundColor(Color.cautionMuted)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.cautionMuted.opacity(dark ? 0.18 : 0.12))
                    )
                    .accessibilityLabel("Capped by \(cap.shortLabel)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18).padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(emphasized ? ringColor.opacity(0.35) : Color.clear, lineWidth: 1.5)
        )
        .overlay(alignment: .top) {
            if emphasized {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").font(.system(size: 8, weight: .bold))
                    Text("FOR YOU").font(.sageBold(9)).tracking(0.8)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(store.accent))
                .offset(y: -9)
            }
        }
        .overlay(alignment: .topTrailing) {
            if emphasized {
                Button(action: onOpenMethodology) {
                    Image(systemName: "info.circle")
                        .font(.sageSemiBold(13))
                        .foregroundColor(Theme.textSecondary(dark))
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("How scoring works: multipliers reweight rules; caps are ceilings from your restrictions")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(score), \(label)")
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
            .foregroundColor(Theme.textSecondary(dark))
            .padding(.horizontal, 20)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func overviewSection(dark: Bool, product p: Product) -> some View {
        let generating = store.overviewGenerating.contains(p.id)
        let show = !p.isUnscored && (generating || p.overviewStale == true || p.overview != nil)
        if show {
            let overall = p.overallScore ?? 0
            let your = p.yourScore ?? overall
            let delta = your - overall
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.sageBold(12))
                        .foregroundColor(store.accent)
                    Text("Overview")
                        .font(.sageBold(12)).tracking(-0.1)
                        .foregroundColor(Theme.textSecondary(dark))
                    if delta != 0 {
                        let tint = delta < 0 ? Color.scoreBad : Color.scoreGood
                        Text(delta < 0 ? "\(delta)" : "+\(delta)")
                            .font(.sageBold(10))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(tint))
                            .accessibilityLabel(deltaBadgeLabel(delta: delta) ?? "")
                    }
                    Spacer(minLength: 0)
                }
                if generating || (p.overviewStale == true && p.overview == nil) {
                    Text("Generating overview…")
                        .font(.sageRegular(13))
                        .foregroundColor(Theme.textSecondary(dark))
                        .italic()
                } else if let text = p.overview?.text {
                    Text(text)
                        .font(.sageRegular(13))
                        .foregroundColor(Theme.textPrimary(dark))
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.surface(dark))
            )
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Overview")
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
                            .foregroundColor(Theme.textPrimary(dark))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.scoreBad.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
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

    private func nutrientsHeader(dark: Bool) -> some View {
        HStack(spacing: 6) {
            Text("Per 100 g / 100 ml")
                .font(.sageBold(12)).tracking(-0.1)
                .foregroundColor(Theme.textSecondary(dark))
            Button {
                showLabelLegend = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.sageSemiBold(13))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("What the labels mean")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14).padding(.bottom, 6)
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
            .foregroundColor(Theme.textPrimary(dark))
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.divider(dark), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compare with another product")
    }

    /// Grades only render when the product actually carries them — a missing
    /// Nutri-Score or NOVA rating drops that card entirely rather than showing
    /// an "unknown" placeholder.
    private var showNutriCard: Bool {
        ["A", "B", "C", "D", "E"].contains(product.nutriGrade.uppercased())
    }
    private var showNovaCard: Bool { product.hasKnownNova }

    private func gradesRow(dark: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if showNutriCard {
                NutriScoreCard(grade: product.nutriGrade, dark: dark)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            if showNovaCard {
                NovaCard(group: product.novaGroup, dark: dark)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func nutrientsCard(dark: Bool) -> some View {
        let n = product.nutrients
        return CardView(dark: dark) {
            VStack(spacing: 0) {
                // Levels come from NutrientLevels — the same source the
                // scoring factor labels and the LLM prompt read, so badge
                // and sentence can never disagree.
                nutrientRow(label: "Sugar", value: n.sugar_g, unit: "g",
                            level: n.sugar_g.map(NutrientLevels.sugar),
                            higherIsBetter: false, divider: false, dark: dark)
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
            .padding(.vertical, 4)
        }
    }

    private func nutrientRow(label: String, value: Double?, unit: String,
                             level: NutrientLevel?, higherIsBetter: Bool,
                             bonus: Bool = false, divider: Bool, dark: Bool) -> some View {
        let display = value.map { "\(fmt($0)) \(unit)" } ?? "—"
        let tag = level.map { nutrientTag($0, higherIsBetter: higherIsBetter) }
        return NutrientRow(label: label, value: display, tag: tag,
                           bonus: bonus, divider: divider, dark: dark)
    }

    private func additivesEyebrow(dark: Bool) -> String {
        if product.additiveIngredientTextMissing == true { return "Additives" }
        let count = product.additives.count
        if product.additiveUndercountSuspected == true {
            return "Additives · \(count) (may be undercounted)"
        }
        return "Additives · \(count)"
    }

    private func additivesCard(dark: Bool) -> some View {
        CardView(dark: dark) {
            VStack(spacing: 0) {
                if product.additiveIngredientTextMissing == true {
                    HStack(spacing: 10) {
                        RiskDot(risk: .unrated)
                        Text("No ingredient data")
                            .font(.sageSemiBold(14))
                            .foregroundColor(Theme.textSecondary(dark))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                } else if product.additives.isEmpty {
                    HStack(spacing: 10) {
                        RiskDot(risk: .low)
                        Text("No additives detected")
                            .font(.sageSemiBold(14))
                            .foregroundColor(Theme.textPrimary(dark))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                } else {
                    SeverityBar(additives: product.additives, allowAlarmRed: !yourScoreIsWorstSignal)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .overlay(alignment: .bottom) {
                            Theme.divider(dark).frame(height: 0.5)
                        }
                    ForEach(Array(product.additives.enumerated()), id: \.element.id) { (i, a) in
                        Button {
                            selectedAdditive = a
                        } label: {
                            AdditiveRow(additive: a, divider: i > 0, dark: dark,
                                        allowAlarmRed: !yourScoreIsWorstSignal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
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
                            .font(.sageBold(12)).tracking(-0.1)
                            .foregroundColor(Theme.textSecondary(dark))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.sageSemiBold(11))
                            .foregroundColor(Theme.textSecondary(dark))
                            .rotationEffect(.degrees(ingredientsExpanded ? 180 : 0))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14).padding(.bottom, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Full ingredients")
                .accessibilityHint(ingredientsExpanded ? "Collapse" : "Expand")

                if ingredientsExpanded {
                    highlightedIngredients(display, needles: needles, dark: dark)
                        .padding(.horizontal, 16)
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
            .font(.sageRegular(13))
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.surface(dark))
            )
    }

    private func highlightedAttributedString(_ text: String, needles: [String],
                                             dark: Bool) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = Theme.textPrimary(dark)
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
                EyebrowLabel(text: "Detected", dark: dark)
                VStack(spacing: 6) {
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
                }
                .padding(.horizontal, 16)
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
            .foregroundColor(Theme.textSecondary(dark))
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
                .foregroundColor(Color(hex: "D4A02D"))
            Text("Nutrition source: \(nutritionSourceLabel)")
                .font(.sageBold(11))
                .foregroundColor(Theme.textPrimary(dark))
            Text(breakdown)
                .font(.sageRegular(10))
                .monospacedDigit()
                .foregroundColor(Theme.textSecondary(dark))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(hex: "D4A02D").opacity(0.35), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
#endif
}

// MARK: - Sub-components

/// Shared height for the side-by-side Breakdown grade cards.
private let breakdownCardHeight: CGFloat = 108

struct NutriScoreCard: View {
    let grade: String
    let dark: Bool

    private var isKnown: Bool { ["A", "B", "C", "D", "E"].contains(grade.uppercased()) }

    var body: some View {
        if isKnown {
            knownBody
        } else {
            unknownBody
        }
    }

    private var knownBody: some View {
        let colors: [String: Color] = [
            "A": Color(hex: "1F8A5B"), "B": Color(hex: "7BA935"),
            "C": Color(hex: "D4A02D"), "D": Color(hex: "E07A26"),
            "E": Color(hex: "C9442B"),
        ]
        let g = grade.uppercased()
        let c = colors[g] ?? Color.neutralMuted
        return HStack(alignment: .center, spacing: 12) {
            Text(g)
                .font(.sageBold(28)).tracking(-1)
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c))
            VStack(alignment: .leading, spacing: 3) {
                Text("Nutri-Score \(g)")
                    .font(.sageBold(13)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                Text("Nutrition grade")
                    .font(.sageSemiBold(11))
                    .foregroundColor(c)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .frame(height: breakdownCardHeight)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
        .accessibilityLabel("Nutri-Score \(g), nutrition grade")
    }

    private var unknownBody: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("?")
                .font(.sageBold(24)).tracking(-0.5)
                .foregroundColor(Theme.textSecondary(dark))
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("Nutri-Score")
                    .font(.sageBold(13)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                Text("Not rated")
                    .font(.sageSemiBold(11))
                    .foregroundColor(Color.neutralMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .frame(height: breakdownCardHeight)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
        .accessibilityLabel("Nutri-Score not rated")
    }
}

struct NovaCard: View {
    let group: Int
    let dark: Bool

    private var isKnown: Bool { (1...4).contains(group) }

    var body: some View {
        if isKnown {
            knownBody
        } else {
            unknownBody
        }
    }

    private var knownBody: some View {
        let labels = [
            1: "Unprocessed or minimally processed",
            2: "Processed culinary ingredients",
            3: "Processed",
            4: "Ultra-processed",
        ]
        let colors: [Int: Color] = [
            1: Color(hex: "1F8A5B"), 2: Color(hex: "7BA935"),
            3: Color(hex: "D4A02D"), 4: Color(hex: "C9442B"),
        ]
        let c = colors[group] ?? Color.neutralMuted
        let labelColor = group >= 4 ? Color.cautionMuted : c
        return HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(1...4, id: \.self) { g in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(g <= group ? c
                              : (dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)))
                        .frame(width: 6, height: CGFloat(8 + g * 7))
                }
            }
            .frame(width: 52, height: 52, alignment: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text("NOVA \(group)")
                    .font(.sageBold(13)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                Text(labels[group] ?? "")
                    .font(.sageSemiBold(11))
                    .foregroundColor(labelColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .frame(height: breakdownCardHeight)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
        .accessibilityLabel("NOVA \(group), \(labels[group] ?? "")")
    }

    private var unknownBody: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(1...4, id: \.self) { g in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                        .frame(width: 6, height: CGFloat(8 + g * 7))
                }
            }
            .frame(width: 52, height: 52, alignment: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text("NOVA")
                    .font(.sageBold(13)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                Text("Not rated")
                    .font(.sageSemiBold(11))
                    .foregroundColor(Color.neutralMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .frame(height: breakdownCardHeight)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
        .accessibilityLabel("NOVA not rated")
    }
}

struct NutrientRow: View {
    let label: String
    let value: String
    let tag: Tag?
    var bonus: Bool = false
    let divider: Bool
    let dark: Bool

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
            HStack(spacing: 7) {
                Text(label)
                    .font(.sageSemiBold(14)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
                if bonus {
                    Text("+ BOOST")
                        .font(.sageBold(10)).tracking(0.3)
                        .foregroundColor(Color(hex: "1F8A5B"))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: "1F8A5B").opacity(0.12)))
                        .fixedSize()
                }
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.sageBold(14))
                .monospacedDigit().tracking(-0.2)
                .foregroundColor(Theme.textPrimary(dark))
                .fixedSize(horizontal: true, vertical: false)
            if let tag {
                Text(tag.word.uppercased())
                    .font(.sageBold(10)).tracking(0.4)
                    .foregroundColor(tag.fg)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(tag.bg))
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(alignment: .top) {
            if divider {
                Theme.divider(dark).frame(height: 0.5).padding(.horizontal, 8)
            }
        }
    }
}

struct AdditiveRow: View {
    let additive: ProductAdditive
    let divider: Bool
    let dark: Bool
    var allowAlarmRed: Bool = true

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
                    .foregroundColor(Theme.textPrimary(dark))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if let note = additive.note, !note.isEmpty {
                    Text(note)
                        .font(.sageRegular(11))
                        .foregroundColor(Theme.textSecondary(dark))
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
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(riskBg))
            Image(systemName: "chevron.right")
                .font(.sageSemiBold(10))
                .foregroundColor(Theme.textSecondary(dark).opacity(0.6))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if divider { Theme.divider(dark).frame(height: 0.5).padding(.horizontal, 8) }
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
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.04)))
            .clipShape(RoundedRectangle(cornerRadius: 3))

            HStack(spacing: 10) {
                ForEach(order, id: \.self) { r in
                    HStack(spacing: 5) {
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
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.04)))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.sageBold(13)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                Text(detail)
                    .font(.sageRegular(11))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(fg.opacity(dark ? 0.14 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                .background(RoundedRectangle(cornerRadius: 10).fill(fg))
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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(fg.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(fg.opacity(dark ? 0.14 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                .foregroundColor(Theme.textSecondary(dark))
            Text(hasMatch
                 ? "Always confirm on the product packaging — allergen data can be incomplete."
                 : "No declared allergens matched your profile, but data may be incomplete — always check the packaging.")
                .font(.sageRegular(11))
                .foregroundColor(Theme.textSecondary(dark))
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
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
                                .foregroundColor(Theme.textPrimary(dark))
                            if let code = additive.code {
                                Text(code.uppercased())
                                    .font(.sageSemiBold(13))
                                    .foregroundColor(Theme.textSecondary(dark))
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
                                .foregroundColor(Theme.textPrimary(dark))
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
            .background(Theme.bg(dark).ignoresSafeArea())
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
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(fg.opacity(0.12)))
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.sageBold(13))
                .foregroundColor(Theme.textPrimary(dark))
            Text(body)
                .font(.sageRegular(14))
                .foregroundColor(Theme.textSecondary(dark))
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
                            .foregroundColor(Theme.textPrimary(dark))
                        ForEach(nutrientItems, id: \.word) { item in
                            legendRow(word: item.word, fg: item.fg, meaning: item.meaning)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Additive risk")
                            .font(.sageBold(15))
                            .foregroundColor(Theme.textPrimary(dark))
                        ForEach(riskItems, id: \.0) { item in
                            legendRow(word: RiskStyle.label(item.0),
                                      fg: RiskStyle.fg(item.0),
                                      meaning: item.1)
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.bg(dark).ignoresSafeArea())
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
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(fg.opacity(0.12)))
                .frame(minWidth: 72, alignment: .leading)
            Text(meaning)
                .font(.sageRegular(13))
                .foregroundColor(Theme.textSecondary(dark))
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

// MARK: - Better-options row

/// One "Better options" card (ALTERNATIVES_SPEC.md §5) — mirrors HistoryRow, with
/// a green "+N vs. this" delta instead of a timestamp.
private struct AlternativeRow: View {
    let alt: Alternative
    let delta: Int
    let divider: Bool
    let dark: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ProductThumb(glyph: alt.product.glyph, score: alt.score, size: 56,
                             imageURL: alt.product.listImageURL,
                             processCutout: alt.product.shouldProcessCutout)
                VStack(alignment: .leading, spacing: 1) {
                    if !alt.product.brand.isEmpty {
                        Text(alt.product.brand.uppercased())
                            .font(.sageBold(10)).tracking(1.2)
                            .foregroundColor(Theme.textSecondary(dark))
                            .lineLimit(1)
                    }
                    Text(alt.product.name)
                        .font(.sageBold(14)).tracking(-0.2)
                        .foregroundColor(Theme.textPrimary(dark))
                        .lineLimit(1)
                    Text("+\(delta) vs. this")
                        .font(.sageBold(11))
                        .foregroundColor(Color.scoreGood)
                }
                Spacer(minLength: 8)
                YourScorePill(score: alt.score, isUnscored: false)
                Image(systemName: "chevron.right")
                    .font(.sageBold(12))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .overlay(alignment: .top) {
                if divider {
                    Theme.divider(dark).frame(height: 0.5).padding(.horizontal, 12)
                }
            }
        }
        .buttonStyle(.pressable)
    }
}
