import SwiftUI

enum Overlay: Identifiable, Hashable {
    case result(productId: String, fromScan: Bool)
    /// Product exists but fails the minimum-data requirement (no ingredient
    /// list AND no nutrition table) — never show a made-up score.
    case insufficientData(productId: String)
    /// A category Sage deliberately doesn't rate (water, alcoholic drinks).
    case unsupported(productId: String)
    case compare(aId: String, bId: String)
    case paywall
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
        case .paywall:               return "paywall"
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

    private enum ScanOutcome: Equatable { case found(String), failed }

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
                .task {
                    RulesetStore.refreshInBackground(backend: backend)
                    AlternativesStore.refreshInBackground(backend: backend)
                }
        }
    }

    private var mainContent: some View {
        TabView(selection: tabSelection) {
            Tab(AppTab.home.label, systemImage: AppTab.home.icon, value: AppTab.home) {
                stack($homePath) {
                    ScannerHomeView(
                        onTapScan: { startScan() },
                        onTapHistory: { tab = .pantry },
                        onTapSearch: { push(.search) },
                        onOpenProduct: { id in openProduct(id) }
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
            // Not a destination — selecting it opens the camera and the
            // previously selected tab stays put (see `tabSelection`).
            Tab(AppTab.scan.label, systemImage: AppTab.scan.icon, value: AppTab.scan) {
                Color.clear
            }
            Tab(AppTab.pantry.label, systemImage: AppTab.pantry.icon, value: AppTab.pantry) {
                stack($pantryPath) {
                    HistoryView(onOpenProduct: { id in openProduct(id) })
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
        .alert("Couldn't load that product",
               isPresented: Binding(get: { lookupError != nil },
                                    set: { if !$0 { lookupError = nil } })) {
            Button("OK", role: .cancel) { lookupError = nil }
        } message: {
            Text(lookupError ?? "")
        }
        .overlay {
            if isLookingUp { LookupOverlay().transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.2), value: isLookingUp)
        // Scan result lands as a tap; a miss buzzes. This is the one moment in
        // the app that should be felt, not just seen.
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

    /// Routes tab selection. Picking "Scan" is an action, not a destination:
    /// it opens the camera and leaves the current tab selected.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { tab },
            set: { newValue in
                guard newValue != .scan else { startScan(); return }
                tab = newValue
            }
        )
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
                    onSelectAlternative: { alt in openAlternative(alt) }
                )
            } else {
                UnavailableView(title: "Product unavailable",
                                message: "This product couldn't be loaded.")
            }
        case .insufficientData(let id):
            if let p = store.products[id] {
                InsufficientDataView(product: p)
            } else {
                UnavailableView(title: "Product unavailable",
                                message: "This product couldn't be loaded.")
            }
        case .unsupported(let id):
            if let p = store.products[id] {
                UnsupportedView(product: p)
            } else {
                UnavailableView(title: "Product unavailable",
                                message: "This product couldn't be loaded.")
            }
        case .compare(let aId, let bId):
            if let a = store.products[aId], let b = store.products[bId] {
                CompareView(a: a, b: b)
            } else {
                UnavailableView(title: "Comparison unavailable",
                                message: "One or both products couldn't be loaded.")
            }
        case .topRatedCategory(let raw):
            if let shelf = SageCategory(rawValue: raw) {
                TopRatedListView(shelf: shelf,
                                 onOpenProduct: { product in openAlternative(product) })
            } else {
                UnavailableView(title: "Category unavailable",
                                message: "This category couldn't be loaded.")
            }
        case .search:
            SearchView(onSelect: { code in openFromSearch(barcode: code) })
        case .paywall:        PaywallView()
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
        case .notFound: return "No match for barcode \(barcode). It may not be in the database yet — try manual entry."
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
                ContentUnavailableView(
                    "Not enough data to score",
                    systemImage: "chart.bar.xaxis",
                    description: Text("This product isn't fully catalogued yet.")
                )
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

struct LookupOverlay: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            ProgressView("Looking up product…")
                .progressViewStyle(.circular)
                .tint(store.accent)
                .font(.sageBold(14))
                .padding(28)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Looking up product")
    }
}

// MARK: - Paywall / Manual (lightweight placeholders)

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [store.accent, Color.black.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "crown.fill").font(.system(size: 56)).foregroundColor(.yellow)
                Text("Sage Premium").font(.sageBold(32)).foregroundColor(.white)
                Text("Unlimited scans, AI ingredient analysis, and personalized insights.")
                    .font(.sageRegular(15))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 30)
                Spacer()
                Button("Start free trial") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundStyle(Theme.inkLight)
                Button("Restore purchase") { dismiss() }
                    .font(.sageSemiBold(13))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

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
