import SwiftUI

enum Overlay: Identifiable, Hashable {
    case result(productId: String, fromScan: Bool)
    /// Product exists but fails the minimum-data requirement (no ingredient
    /// list AND no nutrition table) — never show a made-up score.
    case insufficientData(productId: String)
    case compare(aId: String, bId: String)
    case paywall
    case manual
    case methodology
    case personal
    case preferences
    case nutritionGoals
    case dietary

    var id: String {
        switch self {
        case .result(let id, _):        return "result_\(id)"
        case .insufficientData(let id): return "insufficient_\(id)"
        case .compare(let a, let b):    return "compare_\(a)_\(b)"
        case .paywall:               return "paywall"
        case .manual:                return "manual"
        case .methodology:           return "methodology"
        case .personal:              return "personal"
        case .preferences:           return "preferences"
        case .nutritionGoals:        return "nutritionGoals"
        case .dietary:               return "dietary"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    @State private var tab: AppTab = .home
    @State private var stack: [Overlay] = []
    @State private var showCamera = false
    @State private var showFirstLaunch = false
    @State private var firstScanSeen = false
    @State private var disclaimerFromScan = false
    @State private var pendingCompareA: Product? = nil
    @State private var showMethodModal = false
    @State private var isLookingUp = false
    @State private var lookupError: String? = nil

    // First-launch onboarding: persisted across app relaunches so each user
    // sees the flow exactly once. Set to true the moment the user finishes
    // (or signs in from) the welcome flow.
    @AppStorage("sage.hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    private let backend = BackendService()

    var body: some View {
        if !hasCompletedOnboarding {
            OnboardingFlow {
                withAnimation(.easeInOut(duration: 0.3)) {
                    hasCompletedOnboarding = true
                }
            }
            .transition(.opacity)
        } else {
            mainContent
                .transition(.opacity)
                // Fire-and-forget ruleset refresh (SCORING_V4.md §11): never
                // blocks anything; offline silently keeps the current tables.
                .task { RulesetStore.refreshInBackground(backend: backend) }
        }
    }

    private var mainContent: some View {
        ZStack {
            // Keep tab content alive under overlays so Search (and other tabs)
            // retain their state when the user taps back from a product page.
            tabContent
                .ignoresSafeArea(.keyboard)

            if !stack.isEmpty {
                Theme.bg(store.darkMode).ignoresSafeArea()
                if let screen = stack.last {
                    overlayView(for: screen)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.bg(store.darkMode).ignoresSafeArea())
                        .clipped()
                        .id(screen.id)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            if !showCamera && stack.isEmpty && !showFirstLaunch {
                VStack {
                    Spacer()
                    TabBar(tab: $tab, onScan: startScan)
                }
                .zIndex(50)
            }

            if showCamera {
                ScanCameraView(
                    onClose: { closeCamera() },
                    onHistory: { closeCamera(); tab = .pantry },
                    onScanComplete: { code in finishScan(barcode: code) }
                )
                .zIndex(60)
                .transition(.move(edge: .bottom))
            }

            if isLookingUp {
                LookupOverlay()
                    .zIndex(95)
                    .transition(.opacity)
            }

            if let err = lookupError {
                ErrorToast(message: err) { lookupError = nil }
                    .zIndex(96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showMethodModal {
                MethodologyModal(
                    onDismiss: { showMethodModal = false },
                    onLearnMore: { showMethodModal = false; push(.methodology) }
                )
                .zIndex(85)
            }

            if showFirstLaunch {
                DisclaimerModal(onAcknowledge: { acknowledgeFirstLaunch() })
                    .zIndex(90)
            }
        }
        .background(Theme.bg(store.darkMode).ignoresSafeArea())
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: stack)
        .animation(.easeOut(duration: 0.3), value: showCamera)
        .animation(.easeOut(duration: 0.2), value: showFirstLaunch)
        .animation(.easeOut(duration: 0.2), value: showMethodModal)
        .animation(.easeOut(duration: 0.2), value: isLookingUp)
        .animation(.easeOut(duration: 0.2), value: lookupError)
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .home:
            ScannerHomeView(
                onTapScan: { startScan() },
                onTapHistory: { tab = .pantry },
                onTapSearch: { tab = .search },
                onOpenProduct: { id in openProduct(id) }
            )
        case .pantry:
            HistoryView(onOpenProduct: { id in openProduct(id) })
        case .search:
            SearchView(onSelect: { code in openFromSearch(barcode: code) })
        case .you:
            ProfileView(
                onOpenPersonal: { push(.personal) },
                onOpenPreferences: { push(.preferences) },
                onOpenNutritionGoals: { push(.nutritionGoals) },
                onOpenDietary: { push(.dietary) },
                onOpenMethodology: { push(.methodology) },
                onOpenDisclaimer: { showFirstLaunch = true }
            )
        }
    }

    @ViewBuilder private func overlayView(for screen: Overlay) -> some View {
        switch screen {
        case .result(let id, let fromScan):
            if let p = store.products[id] {
                ResultView(
                    product: p,
                    fromScan: fromScan,
                    onBack: dismissOverlay,
                    onCompare: { beginCompare(productId: id) },
                    onOpenMethodology: { showMethodModal = true }
                )
            } else {
                OverlayFallbackView(
                    title: "Product unavailable",
                    message: "This product couldn't be loaded.",
                    onBack: dismissOverlay
                )
            }
        case .insufficientData(let id):
            if let p = store.products[id] {
                InsufficientDataView(product: p, onBack: dismissOverlay)
            } else {
                OverlayFallbackView(
                    title: "Product unavailable",
                    message: "This product couldn't be loaded.",
                    onBack: dismissOverlay
                )
            }
        case .compare(let aId, let bId):
            if let a = store.products[aId], let b = store.products[bId] {
                CompareView(a: a, b: b, onBack: dismissOverlay)
            } else {
                OverlayFallbackView(
                    title: "Comparison unavailable",
                    message: "One or both products couldn't be loaded.",
                    onBack: dismissOverlay
                )
            }
        case .paywall:        PaywallView(onDismiss: dismissOverlay)
        case .manual:         ManualEntryView(onCancel: dismissOverlay, onSubmit: dismissOverlay)
        case .methodology:    MethodologyView(onBack: dismissOverlay)
        case .personal:       PersonalDetailsView(onBack: dismissOverlay)
        case .preferences:    PreferencesView(onBack: dismissOverlay)
        case .nutritionGoals: NutritionGoalsView(onBack: dismissOverlay)
        case .dietary:        DietaryView(onBack: dismissOverlay)
        }
    }

    private func push(_ s: Overlay) { stack.append(s) }

    /// Pops the overlay stack and clears any modal that would block the back button.
    private func dismissOverlay() {
        showMethodModal = false
        guard !stack.isEmpty else { return }
        _ = stack.popLast()
    }

    private func pop() { dismissOverlay() }
    private func reset() { stack.removeAll() }

    private func openProduct(_ id: String) {
        if case .result(let topId, _) = stack.last, topId == id { return }
        push(.result(productId: id, fromScan: false))
    }

    private func startScan() {
        if !firstScanSeen {
            firstScanSeen = true
            disclaimerFromScan = true
            showFirstLaunch = true
            return
        }
        showCamera = true
    }

    private func acknowledgeFirstLaunch() {
        showFirstLaunch = false
        if disclaimerFromScan {
            disclaimerFromScan = false
            showCamera = true
        }
    }

    private func closeCamera() {
        showCamera = false
        pendingCompareA = nil
    }

    private func finishScan(barcode: String) {
        showCamera = false
        let compareWith = pendingCompareA
        pendingCompareA = nil
        isLookingUp = true

        Task { @MainActor in
            do {
                let raw = try await backend.lookup(barcode: barcode)
                isLookingUp = false
                guard raw.hasMinimumData else {
                    presentInsufficientData(raw)
                    return
                }
                let product = ScoringEngine.score(raw, for: store.user)
                if let a = compareWith {
                    store.saveProduct(product)
                    push(.compare(aId: a.id, bId: product.id))
                } else {
                    store.recordScan(product)
                    push(.result(productId: product.id, fromScan: true))
                }
                fetchExplanation(for: product)
            } catch {
                isLookingUp = false
                lookupError = Self.lookupMessage(for: error, barcode: barcode)
            }
        }
    }

    /// Minimum-data requirement (SCORING_V4.md §3.3): the product exists but
    /// has neither an ingredient list nor a nutrition table, so no score can
    /// honestly be computed. Snapshot it (unscored) and show the data-gap
    /// state instead of a result page.
    private func presentInsufficientData(_ product: Product) {
        store.saveProduct(product)
        push(.insufficientData(productId: product.id))
    }

    /// A search selection runs the same pipeline as a scan (/lookup → score →
    /// result page → async /explain); it just skips the camera and doesn't
    /// enter scan history.
    private func openFromSearch(barcode: String) {
        isLookingUp = true
        Task { @MainActor in
            do {
                let raw = try await backend.lookup(barcode: barcode)
                isLookingUp = false
                guard raw.hasMinimumData else {
                    presentInsufficientData(raw)
                    return
                }
                let product = ScoringEngine.score(raw, for: store.user)
                store.saveProduct(product)
                push(.result(productId: product.id, fromScan: false))
                fetchExplanation(for: product)
            } catch {
                isLookingUp = false
                lookupError = Self.lookupMessage(for: error, barcode: barcode)
            }
        }
    }

    /// Fires `/explain` after the result is already on screen and swaps the
    /// rule-based deltaReason for the LLM sentence when it arrives. Every scan
    /// gets one — capped and personalization-off included; the class-bucket
    /// cache (hash covers objective, preferences, restrictions, and toggles)
    /// keeps repeat cost at zero.
    private func fetchExplanation(for product: Product) {
        let classHash = ScoreClass(store.user).hash
        let payload = BackendService.ExplainPayload(
            barcode: product.id,
            classHash: classHash,
            productName: product.name,
            objective: store.user.objective,
            overall: product.overallScore,
            your: product.yourScore,
            factors: ScoringEngine.signedFactors(product, profile: store.user)
        )
        guard !payload.factors.isEmpty else { return }   // data-poor product
        Task { @MainActor in
            guard let text = await backend.explain(payload) else { return }
            // Drop a stale reply: the profile class changed mid-flight, or the
            // product was rescored/removed while we waited.
            guard ScoreClass(store.user).hash == classHash,
                  var current = store.products[product.id],
                  current.yourScore == product.yourScore else { return }
            let delta = product.yourScore - product.overallScore
            let tone: DeltaReason.Tone = delta > 0 ? .positive
                : delta < 0 ? .negative
                : (payload.factors.first?.hasPrefix("+") == true ? .positive : .negative)
            current.deltaReason = DeltaReason(tone: tone, text: text)
            store.saveProduct(current)
        }
    }

    private static func lookupMessage(for error: Error, barcode: String) -> String {
        guard let e = error as? BackendService.LookupError else {
            return "Something went wrong. Please try again."
        }
        switch e {
        case .notFound: return "No match for barcode \(barcode). It may not be in the database yet — try manual entry."
        case .dailyLimitReached: return "You've used today's free scan. Upgrade to Premium for unlimited scans."
        case .unauthorized: return "Couldn't authenticate with the Sage server. Please update the app."
        case .network:  return "Network error. Check your connection and try again."
        case .decoding: return "We found the product but couldn't read its data."
        }
    }

    private func beginCompare(productId: String) {
        pendingCompareA = store.products[productId]
        showCamera = true
    }
}

// MARK: - Overlay fallback (missing product data — still needs a working back button)

struct OverlayFallbackView: View {
    let title: String
    let message: String
    let onBack: () -> Void
    @EnvironmentObject var store: AppStore

    var body: some View {
        let dark = store.darkMode
        ZStack {
            Theme.bg(dark).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    CircleIconButton(systemName: "chevron.left", dark: dark,
                                     accessibilityLabel: "Back", action: onBack)
                    Spacer()
                    Text("Sage")
                        .font(.sageBold(18)).tracking(-0.4)
                        .foregroundColor(Theme.textPrimary(dark))
                    Spacer()
                    Color.clear.frame(width: 42, height: 42)
                }
                .padding(.horizontal, 16).padding(.top, 8)

                Spacer()
                VStack(spacing: 8) {
                    Text(title)
                        .font(.sageBold(18))
                        .foregroundColor(Theme.textPrimary(dark))
                    Text(message)
                        .font(.sageRegular(13))
                        .foregroundColor(Theme.textSecondary(dark))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Insufficient data state (SCORING_V4.md §3.3)

/// Shown when a product exists in the database but has neither an ingredient
/// list nor a nutrition table. "No data" is a first-class state — we never
/// render a score built purely from unknown-tier defaults.
struct InsufficientDataView: View {
    let product: Product
    let onBack: () -> Void
    @EnvironmentObject var store: AppStore

    private var hasKnownNutrients: Bool {
        let n = product.nutrients
        return [n.sugar_g, n.sodium_mg, n.satFat_g, n.fiber_g, n.protein_g,
                n.calcium_mg, n.kcal].contains { $0 != nil }
    }

    var body: some View {
        let dark = store.darkMode
        ZStack {
            Theme.bg(dark).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    CircleIconButton(systemName: "chevron.left", dark: dark,
                                     accessibilityLabel: "Back", action: onBack)
                    Spacer()
                    Text("Sage")
                        .font(.sageBold(18)).tracking(-0.4)
                        .foregroundColor(Theme.textPrimary(dark))
                    Spacer()
                    // Balances the back button so the title stays centered.
                    Color.clear.frame(width: 42, height: 42)
                }
                .padding(.horizontal, 16).padding(.top, 8)

                Spacer()

                VStack(spacing: 14) {
                    ProductThumb(glyph: product.glyph, score: 0, size: 84,
                                 neutral: true, imageURL: product.imageURL)
                    VStack(spacing: 2) {
                        if !product.brand.isEmpty {
                            Text(product.brand.uppercased())
                                .font(.sageBold(11)).tracking(1.2)
                                .foregroundColor(store.accent)
                        }
                        Text(product.name)
                            .font(.sageBold(22)).tracking(-0.5)
                            .foregroundColor(Theme.textPrimary(dark))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                    .padding(.horizontal, 32)

                    VStack(spacing: 8) {
                        Text("Not enough data to score")
                            .font(.sageBold(16))
                            .foregroundColor(Theme.textPrimary(dark))
                        Text("This product isn't fully catalogued yet.")
                            .font(.sageRegular(13))
                            .foregroundColor(Theme.textSecondary(dark))
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .padding(.horizontal, 36)
                    }
                    .padding(.top, 8)

                    if hasKnownNutrients {
                        VStack(spacing: 0) {
                            EyebrowLabel(text: "Per 100g / 100ml", dark: dark)
                            insufficientNutrientsCard(dark: dark)
                                .padding(.horizontal, 16)
                        }
                        .padding(.top, 12)
                    }
                }

                Spacer()
                Spacer()
            }
        }
    }

    private func insufficientNutrientsCard(dark: Bool) -> some View {
        let n = product.nutrients
        var rows: [(String, String)] = []
        if let v = n.protein_g { rows.append(("Protein", "\(fmt(v)) g")) }
        if let v = n.kcal { rows.append(("Energy", "\(fmt(v)) kcal")) }
        if let v = n.sugar_g { rows.append(("Sugar", "\(fmt(v)) g")) }
        if let v = n.sodium_mg { rows.append(("Sodium", "\(fmt(v)) mg")) }
        if let v = n.satFat_g { rows.append(("Saturated fat", "\(fmt(v)) g")) }
        if let v = n.fiber_g { rows.append(("Fiber", "\(fmt(v)) g")) }
        if let v = n.calcium_mg { rows.append(("Calcium", "\(fmt(v)) mg")) }

        return CardView(dark: dark) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    HStack {
                        Text(row.0)
                            .font(.sageSemiBold(14))
                            .foregroundColor(Theme.textPrimary(dark))
                        Spacer()
                        Text(row.1)
                            .font(.sageBold(14))
                            .monospacedDigit()
                            .foregroundColor(Theme.textPrimary(dark))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .overlay(alignment: .top) {
                        if i > 0 {
                            Theme.divider(dark).frame(height: 0.5).padding(.horizontal, 8)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Scan lookup feedback

struct LookupOverlay: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        let dark = store.darkMode
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(store.accent)
                    .scaleEffect(1.3)
                Text("Looking up product…")
                    .font(.sageBold(14)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface(dark))
            )
            .cardShadow(dark)
        }
    }
}

struct ErrorToast: View {
    let message: String
    let onDismiss: () -> Void
    @EnvironmentObject var store: AppStore

    var body: some View {
        let dark = store.darkMode
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(hex: "D4A02D"))
                    .font(.sageRegular(16))
                Text(message)
                    .font(.sageSemiBold(13))
                    .foregroundColor(Theme.textPrimary(dark))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.sageBold(11))
                        .foregroundColor(Theme.textSecondary(dark))
                        .padding(6)
                        .background(Circle().fill(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
            )
            .cardShadow(dark)
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            onDismiss()
        }
    }
}

// MARK: - Paywall / Manual (lightweight placeholders)

struct PaywallView: View {
    let onDismiss: () -> Void
    @EnvironmentObject var store: AppStore
    var body: some View {
        let dark = store.darkMode
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [store.accent, Color.black.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                }.padding(.horizontal, 16).padding(.top, 60)
                Spacer().frame(height: 60)
                Image(systemName: "crown.fill").font(.system(size: 56)).foregroundColor(.yellow)
                Text("Sage Premium").font(.sageBold(32)).foregroundColor(.white)
                Text("Unlimited scans, AI ingredient analysis, and personalized insights.")
                    .font(.sageRegular(15))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 30)
                Spacer()
                PillButton(title: "Start free trial", variant: .primary, dark: dark,
                           fullWidth: true, action: onDismiss)
                    .padding(.horizontal, 20)
                Button("Restore purchase", action: onDismiss)
                    .font(.sageSemiBold(13))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 60)
            }
        }
    }
}

struct ManualEntryView: View {
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @EnvironmentObject var store: AppStore
    @State private var brand = ""
    @State private var name = ""
    var body: some View {
        let dark = store.darkMode
        ZStack {
            Theme.bg(dark).ignoresSafeArea()
            VStack(spacing: 14) {
                HStack {
                    Button("Cancel", action: onCancel).foregroundColor(Theme.textPrimary(dark))
                    Spacer()
                    Text("Manual Entry").font(.sageBold(16))
                        .foregroundColor(Theme.textPrimary(dark))
                    Spacer()
                    Button("Save", action: onSubmit)
                        .foregroundColor(store.accent).fontWeight(.bold)
                }.padding(.horizontal, 20).padding(.top, 60)
                VStack(spacing: 10) {
                    TextField("Brand", text: $brand)
                    Divider()
                    TextField("Product name", text: $name)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface(dark)))
                .padding(.horizontal, 16)
                Spacer()
            }
        }
    }
}

