import SwiftUI
import SuperwallKit

enum Overlay: Identifiable, Hashable {
    case result(productId: String, fromScan: Bool)
    /// Product exists but fails the minimum-data requirement (no ingredient
    /// list AND no nutrition table) — never show a made-up score.
    case insufficientData(productId: String)
    /// A category Sage deliberately doesn't rate (water, alcoholic drinks).
    case unsupported(productId: String)
    case compare(aId: String, bId: String)
    case manual
    case methodology
    case personal
    case preferences
    case nutritionGoals
    case dietary
    /// Product search opened from the Home search field (not a tab).
    case search
    /// Best-scoring products in one Top Rated category (drill-in from the tab).
    case topRatedCategory(shelf: String)

    var id: String {
        switch self {
        case .result(let id, _):        return "result_\(id)"
        case .insufficientData(let id): return "insufficient_\(id)"
        case .unsupported(let id):      return "unsupported_\(id)"
        case .compare(let a, let b):    return "compare_\(a)_\(b)"
        case .manual:                return "manual"
        case .methodology:           return "methodology"
        case .personal:              return "personal"
        case .preferences:           return "preferences"
        case .nutritionGoals:        return "nutritionGoals"
        case .dietary:               return "dietary"
        case .search:                return "search"
        case .topRatedCategory(let s): return "topRated_\(s)"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var tab: AppTab = .home
    /// Last tab that actually has content. `.scan` is an action, not a page —
    /// we keep this so we can snap selection back when TabView briefly lands
    /// on the empty Scan slot (which otherwise shows a blank white screen).
    @State private var lastContentTab: AppTab = .home
    /// One navigation stack per tab — switching tabs preserves where you were,
    /// which is the behavior every other iOS app has.
    @State private var homePath: [Overlay] = []
    @State private var topRatedPath: [Overlay] = []
    @State private var pantryPath: [Overlay] = []
    @State private var youPath: [Overlay] = []

    @State private var showCamera = false
    @State private var showFirstLaunch = false
    @State private var firstScanSeen = false
    @State private var disclaimerFromScan = false
    @State private var pendingCompareA: Product? = nil
    @State private var showMethodModal = false
    @State private var isLookingUp = false
    @State private var lookupError: String? = nil
    /// Bumped on every completed scan so `sensoryFeedback` has an edge to fire on.
    @State private var scanFeedback: ScanOutcome? = nil
    /// Success haptic for non-scan milestones (search open, onboarding done).
    @State private var confirmTick = 0

    private enum ScanOutcome: Equatable { case found(String), failed }

    // First-launch onboarding: persisted across app relaunches so each user
    // sees the flow exactly once. Set to true the moment the user finishes
    // (or signs in from) the welcome flow.
    @AppStorage("sage.hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    /// Superwall gate — true only while the user holds the `pro` entitlement.
    /// Not persisted; Superwall re-checks entitlement on each launch, so a
    /// lapsed subscriber is re-gated.
    @State private var hasAccess = false
    /// Set once Superwall actually presents the paywall, so the fail-open
    /// timeout knows NOT to auto-unlock a user who's deciding on a live paywall.
    @State private var paywallShown = false

    private let backend = BackendService()

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingFlow {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasCompletedOnboarding = true
                    }
                    confirmTick &+= 1
                }
                .transition(.opacity)
            } else if hasAccess {
                mainContent
                    .transition(.opacity)
                    // Fire-and-forget ruleset refresh (SCORING_V4.md §11): never
                    // blocks anything; offline silently keeps the current tables.
                    .task {
                        RulesetStore.refreshInBackground(backend: backend)
                        AlternativesStore.refreshInBackground(backend: backend)
                    }
            } else {
                // Hard paywall gate: only `pro` subscribers get past this splash.
                // See `gateAccess()` — it presents the `app_access` paywall and
                // fails open on error/timeout so a Superwall outage can't brick the app.
                SplashView(accent: store.accent)
                    .task { gateAccess() }
            }
        }
        .sensoryFeedback(.success, trigger: confirmTick)
    }

    /// Superwall hard-paywall gate. Presents the `app_access` paywall and grants
    /// access only when the `pro` entitlement is confirmed — but FAILS OPEN if
    /// the paywall can't present (error) or nothing resolves in time (config
    /// never loaded, network hung), so a Superwall/network problem never traps
    /// the user on the splash. A paywall that *does* present disarms the timeout,
    /// so someone deciding on a live paywall is never let in for free.
    private func gateAccess() {
        let handler = PaywallPresentationHandler()
        // Paywall came up → the user must act on it; disarm the safety net.
        handler.onPresent { _ in self.paywallShown = true }
        // Couldn't present (network / product load / config error) → don't trap.
        handler.onError { _ in self.grantAccess() }
        // No audience match / holdout / placement missing → no paywall by design.
        handler.onSkip { _ in self.grantAccess() }

        Superwall.shared.register(placement: "app_access", handler: handler) {
            // Runs when the user holds `pro` — now, or the instant they purchase.
            self.grantAccess()
        }

        // Safety net: if 8s pass with no paywall on screen and still no access,
        // the request hung or config never loaded — fail open, don't brick.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if !self.hasAccess && !self.paywallShown { self.grantAccess() }
        }
    }

    private func grantAccess() {
        guard !hasAccess else { return }
        withAnimation(.easeInOut(duration: 0.3)) { hasAccess = true }
    }

    private var mainContent: some View {
        TabView(selection: $tab) {
            Tab(AppTab.home.label, systemImage: AppTab.home.icon, value: AppTab.home) {
                stack($homePath) {
                    ScannerHomeView(
                        onTapScan: { startScan() },
                        onTapHistory: { tab = .pantry },
                        onTapSearch: { push(.search) },
                        onOpenProduct: { id in openProduct(id) },
                        onTapTopRated: { tab = .topRated },
                        onTapPersonalize: { push(.dietary) },
                        onOpenCategory: { shelf in push(.topRatedCategory(shelf: shelf.rawValue)) }
                    )
                }
            }
            Tab(AppTab.topRated.label, systemImage: AppTab.topRated.icon, value: AppTab.topRated) {
                stack($topRatedPath) {
                    TopRatedCategoriesView(
                        onOpenCategory: { shelf in push(.topRatedCategory(shelf: shelf.rawValue)) }
                    )
                }
            }
            // Action slot, not a destination. Content is a safety net: if
            // TabView still shows this page (binding races / cover dismiss),
            // `onAppear` snaps back to the last real tab.
            Tab(AppTab.scan.label, systemImage: AppTab.scan.icon, value: AppTab.scan) {
                Color.clear
                    .ignoresSafeArea()
                    .onAppear { restoreContentTab() }
            }
            Tab(AppTab.pantry.label, systemImage: AppTab.pantry.icon, value: AppTab.pantry) {
                stack($pantryPath) {
                    PantryView(
                        onOpenProduct: { id in openProduct(id) },
                        onTapScan: { startScan() }
                    )
                }
            }
            Tab(AppTab.you.label, systemImage: AppTab.you.icon, value: AppTab.you) {
                stack($youPath) {
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
        }
        // Let TabView select `.scan`, then immediately bounce back — rejecting
        // the value in a custom Binding leaves the bar on Scan with a blank page.
        .onChange(of: tab) { _, newValue in
            guard newValue == .scan else {
                lastContentTab = newValue
                return
            }
            startScan()
            restoreContentTab()
        }
        .tint(store.accent)
        .fullScreenCover(isPresented: $showCamera) {
            ScanCameraView(
                onClose: { closeCamera() },
                onHistory: { closeCamera(); tab = .pantry },
                onScanComplete: { code in finishScan(barcode: code) }
            )
        }
        .sheet(isPresented: $showFirstLaunch, onDismiss: acknowledgeFirstLaunch) {
            DisclaimerSheet(onAcknowledge: { showFirstLaunch = false })
                .presentationDetents([.height(400)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMethodModal) {
            MethodologySheet(
                onDismiss: { showMethodModal = false },
                onLearnMore: { showMethodModal = false; push(.methodology) }
            )
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
        .alert("Couldn't find that product",
               isPresented: Binding(get: { lookupError != nil },
                                    set: { if !$0 { lookupError = nil } })) {
            Button("OK", role: .cancel) { lookupError = nil }
        } message: {
            Text(lookupError ?? "")
        }
        .overlay {
            if isLookingUp {
                LookupOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isLookingUp)
        // Scan success/failure, plus confirmTick for search open + onboarding done.
        .sensoryFeedback(trigger: scanFeedback) { _, outcome in
            switch outcome {
            case .found:  return .success
            case .failed: return .error
            case .none:   return nil
            }
        }
    }

    /// A tab's navigation stack. Every destination in the app resolves through
    /// the same `Overlay` enum, so all four stacks share one destination builder.
    private func stack<Root: View>(_ path: Binding<[Overlay]>,
                                   @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: path) {
            root()
                .navigationDestination(for: Overlay.self) { destination(for: $0) }
        }
    }

    /// Routes tab selection. Picking "Scan" is an action, not a destination —
    /// handled by `.onChange(of: tab)` so TabView never stays on the empty slot.
    private func restoreContentTab() {
        let restore = lastContentTab == .scan ? .home : lastContentTab
        // Async so we run after TabView finishes applying `.scan`; a same-runloop
        // write is ignored when the bar has already committed to the blank page.
        DispatchQueue.main.async {
            if tab == .scan {
                tab = restore
            }
        }
    }

    @ViewBuilder private func destination(for screen: Overlay) -> some View {
        switch screen {
        case .result(let id, let fromScan):
            if let p = store.products[id] {
                ResultView(
                    product: p,
                    fromScan: fromScan,
                    onCompare: { beginCompare(productId: id) },
                    onOpenMethodology: { showMethodModal = true },
                    onSelectAlternative: { alt in openAlternative(alt) },
                    onOpenShelf: { shelf in push(.topRatedCategory(shelf: shelf.rawValue)) }
                )
            } else {
                UnavailableView(title: "Couldn't open this product",
                                message: "It may have been removed from your library.")
            }
        case .insufficientData(let id):
            if let p = store.products[id] {
                InsufficientDataView(product: p)
            } else {
                UnavailableView(title: "Couldn't open this product",
                                message: "It may have been removed from your library.")
            }
        case .unsupported(let id):
            if let p = store.products[id] {
                UnsupportedView(product: p)
            } else {
                UnavailableView(title: "Couldn't open this product",
                                message: "It may have been removed from your library.")
            }
        case .compare(let aId, let bId):
            if let a = store.products[aId], let b = store.products[bId] {
                CompareView(a: a, b: b)
            } else {
                UnavailableView(title: "Couldn't open this comparison",
                                message: "One or both products are no longer available.")
            }
        case .topRatedCategory(let raw):
            if let shelf = SageCategory(rawValue: raw) {
                TopRatedListView(
                    shelf: shelf,
                    onOpenProduct: { product in openAlternative(product) },
                    onTapScan: { startScan() }
                )
            } else {
                UnavailableView(title: "Couldn't open this category",
                                message: "Try going back and picking another one.")
            }
        case .search:
            SearchView(
                onSelect: { code in openFromSearch(barcode: code) },
                onTapScan: { startScan() }
            )
        case .manual:         ManualEntryView()
        case .methodology:    MethodologyView()
        case .personal:       PersonalDetailsView()
        case .preferences:    PreferencesView()
        case .nutritionGoals: NutritionGoalsView()
        case .dietary:        DietaryView()
        }
    }

    /// The navigation stack belonging to the visible tab.
    private var activePath: Binding<[Overlay]> {
        switch tab {
        case .home, .scan: return $homePath
        case .topRated:    return $topRatedPath
        case .pantry:      return $pantryPath
        case .you:         return $youPath
        }
    }

    private func push(_ s: Overlay) { activePath.wrappedValue.append(s) }

    private func openProduct(_ id: String) {
        if case .result(let topId, _) = activePath.wrappedValue.last, topId == id { return }
        push(.result(productId: id, fromScan: false))
    }

    /// Opens a "better alternative" the user tapped. The candidate is already
    /// scored on-device, so we cache the snapshot and push its detail — no
    /// network round-trip.
    private func openAlternative(_ product: Product) {
        store.saveProduct(product)
        openProduct(product.id)
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

    /// Runs when the disclaimer sheet closes — by button or by swipe-down, so
    /// dismissing it still continues into the camera the user asked for.
    private func acknowledgeFirstLaunch() {
        guard disclaimerFromScan else { return }
        disclaimerFromScan = false
        showCamera = true
    }

    private func closeCamera() {
        showCamera = false
        pendingCompareA = nil
        // Cover dismiss can leave TabView parked on the empty Scan page.
        if tab == .scan { restoreContentTab() }
    }

    private func finishScan(barcode: String) {
        showCamera = false
        if tab == .scan { restoreContentTab() }
        let compareWith = pendingCompareA
        pendingCompareA = nil
        isLookingUp = true

        Task { @MainActor in
            do {
                let raw = try await backend.lookup(barcode: barcode)
                isLookingUp = false
                scanFeedback = .found(barcode)
                guard let product = scoreForDisplay(raw) else { return }
                if let a = compareWith {
                    store.saveProduct(product)
                    push(.compare(aId: a.id, bId: product.id))
                } else {
                    store.recordScan(product)
                    push(.result(productId: product.id, fromScan: true))
                }
                if !product.isUnscored {
                    store.requestOverview(for: product.id)
                }
                // Engagement-gated rating ask — no-ops until the user has
                // scanned enough, in a later session than the install one.
                ReviewPrompt.recordScan()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    ReviewPrompt.requestIfEarned()
                }
            } catch {
                isLookingUp = false
                scanFeedback = .failed
                lookupError = Self.lookupMessage(for: error, barcode: barcode)
            }
        }
    }

    /// Scores a freshly fetched product with the v4 engine and routes the
    /// non-scorable outcomes to their own screens. Returns the scored product
    /// for the caller to record/push, or nil when handled here.
    @MainActor private func scoreForDisplay(_ raw: Product) -> Product? {
        switch ScoringEngineV4.scoreProduct(raw, for: store.user, ruleset: RulesetStore.current) {
        case .scored(let p):
            return p
        case .unscored(let p, _):
            // Pure sweeteners etc.: open ResultView with data, no health score.
            return p
        case .insufficientData:
            presentInsufficientData(raw); return nil
        case .unsupported:
            presentUnsupported(raw); return nil
        }
    }

    /// Minimum-data requirement (SCORING_V4.md §3.3): the product exists but
    /// has neither an ingredient list nor a nutrition table, so no score can
    /// honestly be computed. Snapshot it (unscored) and show the data-gap state.
    private func presentInsufficientData(_ product: Product) {
        store.saveProduct(product)
        push(.insufficientData(productId: product.id))
    }

    /// Categories Sage deliberately doesn't rate (water, alcohol) — show the
    /// unsupported state rather than a misleading number.
    private func presentUnsupported(_ product: Product) {
        store.saveProduct(product)
        push(.unsupported(productId: product.id))
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
                guard let product = scoreForDisplay(raw) else { return }
                store.saveProduct(product)
                confirmTick &+= 1
                push(.result(productId: product.id, fromScan: false))
                if !product.isUnscored {
                    store.requestOverview(for: product.id)
                }
            } catch {
                isLookingUp = false
                lookupError = Self.lookupMessage(for: error, barcode: barcode)
            }
        }
    }

    private static func lookupMessage(for error: Error, barcode: String) -> String {
        guard let e = error as? BackendService.LookupError else {
            return "Something went wrong. Please try again."
        }
        switch e {
        case .notFound:
            return "Barcode \(barcode) isn't in the catalog yet — try searching by name, or enter it manually."
        case .unauthorized:
            return "Couldn't authenticate with the Sage server. Please update the app."
        case .network:
            return "Couldn't reach the catalog. Check your connection and try again."
        case .decoding:
            return "We found the product but couldn't read its data."
        }
    }

    private func beginCompare(productId: String) {
        pendingCompareA = store.products[productId]
        showCamera = true
    }
}

// MARK: - Empty / non-scorable states

/// Generic "we couldn't load this" destination. `ContentUnavailableView` is the
/// system component for exactly this, so it matches Mail, Files and Photos —
/// including its own Dynamic Type and VoiceOver handling.
struct UnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "questionmark.circle", description: Text(message))
            .sageScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Product identity block shared by the two non-scorable states.
private struct ProductIdentity: View {
    let product: Product
    @EnvironmentObject var store: AppStore

    var body: some View {
        let formatted = ProductNameFormatter.format(product)
        VStack(spacing: 14) {
            ProductThumb(glyph: product.glyph, score: 0,
                         neutral: true, imageURL: product.detailImageURL,
                         processCutout: product.shouldProcessCutout,
                         isDetail: true)
            VStack(spacing: 2) {
                if let brand = formatted.brand {
                    Text(brand.uppercased())
                        .font(.sageBold(11)).tracking(1.2)
                        .foregroundColor(store.accent)
                }
                Text(formatted.name)
                    .font(.sageBold(22)).tracking(-0.5)
                    .foregroundColor(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if let size = formatted.size {
                    Text(size)
                        .font(.sageRegular(13))
                        .foregroundColor(Theme.inkSecondary)
                }
            }
            .padding(.horizontal, 32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(formatted.accessibilityLabel)
        }
    }
}

// MARK: - Insufficient data state (SCORING_V4.md §3.3)

/// Shown when a product exists in the database but has neither an ingredient
/// list nor a nutrition table. "No data" is a first-class state — we never
/// render a score built purely from unknown-tier defaults.
struct InsufficientDataView: View {
    let product: Product
    @EnvironmentObject var store: AppStore

    private var knownNutrients: [(String, String)] {
        let n = product.nutrients
        var rows: [(String, String)] = []
        if let v = n.protein_g { rows.append(("Protein", "\(fmt(v)) g")) }
        if let v = n.kcal { rows.append(("Energy", "\(fmt(v)) kcal")) }
        if let v = n.sugar_g { rows.append(("Sugar", "\(fmt(v)) g")) }
        if let v = n.sodium_mg { rows.append(("Sodium", "\(fmt(v)) mg")) }
        if let v = n.satFat_g { rows.append(("Saturated fat", "\(fmt(v)) g")) }
        if let v = n.fiber_g { rows.append(("Fiber", "\(fmt(v)) g")) }
        if let v = n.calcium_mg { rows.append(("Calcium", "\(fmt(v)) mg")) }
        return rows
    }

    var body: some View {
        List {
            Section {
                ProductIdentity(product: product)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ContentUnavailableView {
                    Label("Not enough data to score", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("This listing isn't complete enough yet — Sage won't invent a score.")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if !knownNutrients.isEmpty {
                Section("Per 100g / 100ml") {
                    ForEach(knownNutrients, id: \.0) { row in
                        LabeledContent(row.0, value: row.1)
                            .font(.sageSemiBold(14))
                            .monospacedDigit()
                    }
                }
            }
        }
        .sageListStyle()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { SageToolbarTitle() }
    }
}

// MARK: - Unsupported category (SCORING_V4.md §7 launch decision)

/// Shown for categories Sage deliberately doesn't rate — bottled water and
/// alcoholic drinks. Honest "we don't score this" rather than a misleading
/// number for a category the model can't judge well.
struct UnsupportedView: View {
    let product: Product
    @EnvironmentObject var store: AppStore

    private var isAlcohol: Bool {
        let alcohol: Set = ["alcoholic-beverages", "beers", "wines", "spirits", "ciders"]
        return !Set(product.categories ?? []).isDisjoint(with: alcohol)
    }

    private var title: String {
        isAlcohol ? "We don't score alcohol" : "We don't score water"
    }

    private var symbol: String {
        isAlcohol ? "nosign" : "drop.fill"
    }

    private var reason: String {
        if isAlcohol {
            return "Alcohol's health impact isn't something a nutrition score can capture responsibly — so Sage leaves it unscored rather than invent a number."
        }
        return "Plain water isn't something a food score can judge fairly. Without lab data on minerals or contaminants, any number would be guesswork — so we'd rather show nothing than a misleading score."
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ProductIdentity(product: product)
                ContentUnavailableView(title, systemImage: symbol,
                                       description: Text(reason))
            }
            .padding(.top, 24)
        }
        .sageScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { SageToolbarTitle() }
    }
}

// MARK: - Scan lookup feedback

/// Compact branded spinner while `/lookup` runs. Soft veil + rotating accent
/// arc around the Sage mark — intentional motion only on this one wait.
struct LookupOverlay: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    private let ringSize: CGFloat = 72
    private let lineWidth: CGFloat = 3.5

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            Theme.background.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                if reduceMotion {
                    ProgressView()
                        .controlSize(.large)
                        .tint(store.accent)
                        .frame(width: ringSize, height: ringSize)
                } else {
                    ZStack {
                        Circle()
                            .stroke(Theme.ringTrack, lineWidth: lineWidth)
                            .frame(width: ringSize, height: ringSize)

                        Circle()
                            .trim(from: 0.08, to: 0.42)
                            .stroke(
                                store.accent,
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                            )
                            .frame(width: ringSize, height: ringSize)
                            .rotationEffect(.degrees(spinning ? 360 : 0))

                        SageMark(size: 28, color: store.accent)
                    }
                    .frame(width: ringSize, height: ringSize)
                }

                Text("Finding product…")
                    .font(.sageBold(14))
                    .foregroundColor(Theme.inkSecondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.card)
            )
            .cardShadow()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                spinning = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Finding product")
    }
}

// MARK: - Paywall / Manual (lightweight placeholders)

struct ManualEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore
    @State private var brand = ""
    @State private var name = ""

    var body: some View {
        Form {
            Section("Product") {
                TextField("Brand", text: $brand)
                TextField("Product name", text: $name)
            }
        }
        .sageListStyle()
        .navigationTitle("Manual Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { dismiss() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
