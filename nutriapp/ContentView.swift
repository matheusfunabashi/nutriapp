import SwiftUI

enum Overlay: Identifiable, Hashable {
    case result(productId: String, fromScan: Bool)
    case compare(aId: String, bId: String)
    case paywall
    case manual
    case onboarding
    case methodology
    case personal
    case preferences
    case nutritionGoals
    case dietary

    var id: String {
        switch self {
        case .result(let id, _):     return "result_\(id)"
        case .compare(let a, let b): return "compare_\(a)_\(b)"
        case .paywall:               return "paywall"
        case .manual:                return "manual"
        case .onboarding:            return "onboarding"
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

    @State private var tab: AppTab = .scanner
    @State private var stack: [Overlay] = []
    @State private var showCamera = false
    @State private var showFirstLaunch = false
    @State private var firstScanSeen = false
    @State private var disclaimerFromScan = false
    @State private var pendingCompareA: Product? = nil
    @State private var showMethodModal = false
    @State private var isLookingUp = false
    @State private var lookupError: String? = nil

    private let foodFacts = OpenFoodFactsService()

    var body: some View {
        ZStack {
            tabContent
                .ignoresSafeArea(.keyboard)

            ForEach(Array(stack.enumerated()), id: \.offset) { (i, screen) in
                overlayView(for: screen)
                    .zIndex(Double(30 + i))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if !showCamera && stack.isEmpty && !showFirstLaunch {
                VStack {
                    Spacer()
                    TabBar(tab: $tab)
                }
                .zIndex(50)
            }

            if showCamera {
                ScanCameraView(
                    onClose: { closeCamera() },
                    onHistory: { closeCamera(); tab = .history },
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
        case .scanner:
            ScannerHomeView(
                onTapScan: { startScan() },
                onTapHistory: { tab = .history },
                onOpenProduct: { id in openProduct(id) }
            )
        case .history:
            HistoryView(onOpenProduct: { id in openProduct(id) })
        case .search:
            SearchView(onOpenProduct: { id in openProduct(id) })
        case .profile:
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
                    onBack: pop,
                    onCompare: { beginCompare(productId: id) },
                    onOpenMethodology: { showMethodModal = true }
                )
            }
        case .compare(let aId, let bId):
            if let a = store.products[aId], let b = store.products[bId] {
                CompareView(a: a, b: b, onBack: pop)
            }
        case .paywall:        PaywallView(onDismiss: pop)
        case .manual:         ManualEntryView(onCancel: pop, onSubmit: pop)
        case .onboarding:     OnboardingView(onFinish: pop)
        case .methodology:    MethodologyView(onBack: pop)
        case .personal:       PersonalDetailsView(onBack: pop)
        case .preferences:    PreferencesView(onBack: pop)
        case .nutritionGoals: NutritionGoalsView(onBack: pop)
        case .dietary:        DietaryView(onBack: pop)
        }
    }

    private func push(_ s: Overlay) { stack.append(s) }
    private func pop() { _ = stack.popLast() }
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
                let raw = try await foodFacts.fetchProduct(barcode: barcode)
                let product = ScoringEngine.score(raw, for: store.user)
                isLookingUp = false
                if let a = compareWith {
                    store.saveProduct(product)
                    push(.compare(aId: a.id, bId: product.id))
                } else {
                    store.recordScan(product)
                    push(.result(productId: product.id, fromScan: true))
                }
            } catch {
                isLookingUp = false
                lookupError = Self.lookupMessage(for: error, barcode: barcode)
            }
        }
    }

    private static func lookupMessage(for error: Error, barcode: String) -> String {
        guard let e = error as? OpenFoodFactsService.LookupError else {
            return "Something went wrong. Please try again."
        }
        switch e {
        case .notFound: return "No match for barcode \(barcode). It may not be in the database yet — try manual entry."
        case .network:  return "Network error. Check your connection and try again."
        case .decoding: return "We found the product but couldn't read its data."
        }
    }

    private func beginCompare(productId: String) {
        pendingCompareA = store.products[productId]
        showCamera = true
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
                    .font(.system(size: 14, weight: .heavy)).tracking(-0.2)
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
                    .font(.system(size: 16))
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary(dark))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
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

// MARK: - Paywall / Manual / Onboarding (lightweight placeholders)

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
                Text("Sage Premium").font(.system(size: 32, weight: .heavy)).foregroundColor(.white)
                Text("Unlimited scans, AI ingredient analysis, and personalized insights.")
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 30)
                Spacer()
                PillButton(title: "Start free trial", variant: .primary, dark: dark,
                           fullWidth: true, action: onDismiss)
                    .padding(.horizontal, 20)
                Button("Restore purchase", action: onDismiss)
                    .font(.system(size: 13, weight: .semibold))
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
                    Text("Manual Entry").font(.system(size: 16, weight: .bold))
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

struct OnboardingView: View {
    let onFinish: () -> Void
    @EnvironmentObject var store: AppStore
    var body: some View {
        let dark = store.darkMode
        ZStack {
            Theme.bg(dark).ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                SageMark(size: 64, color: store.accent)
                Text("Welcome to Sage").font(.system(size: 28, weight: .heavy))
                    .foregroundColor(Theme.textPrimary(dark))
                Text("Scan any barcode for an instant rating, personalized for you.")
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.textSecondary(dark))
                    .padding(.horizontal, 30)
                Spacer()
                PillButton(title: "Get started", variant: .primary, dark: dark,
                           fullWidth: true, action: onFinish)
                    .padding(.horizontal, 20).padding(.bottom, 40)
            }
        }
    }
}
