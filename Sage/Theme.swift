import SwiftUI
import SwiftData

// MARK: - Theme tokens

extension Color {
    /// A light/dark pair resolved at draw time by the trait system, so a single
    /// token adapts to the environment instead of being picked by a `Bool` the
    /// caller had to thread down by hand.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    init(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6: (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8: (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red:   Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue:  Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}

enum Theme {
    static let accent = Color(hex: "1F8A5B")
    static let bgLight = Color(hex: "F5F4F0")
    static let bgDark = Color(hex: "0F0F0E")
    static let surfaceLight = Color.white
    static let surfaceDark = Color(hex: "1A1A1A")
    static let inkLight = Color(hex: "111111")

    // MARK: Dynamic tokens
    //
    // Each token resolves itself from the environment, so no view has to know
    // which scheme is active or thread a `dark` flag to its children. They also
    // work inside UIKit-backed chrome — nav bars, tab bars, list separators —
    // where a SwiftUI-only flag would never reach.

    static let background = Color(light: bgLight, dark: bgDark)
    static let card = Color(light: surfaceLight, dark: surfaceDark)
    static let ink = Color(light: inkLight, dark: .white)
    static let inkSecondary = Color(light: inkLight.opacity(0.55),
                                    dark: Color.white.opacity(0.55))
    static let hairline = Color(light: .black.opacity(0.06),
                                dark: .white.opacity(0.06))
    /// Card outline — only dark mode needs one; light mode uses the shadow.
    static let cardEdge = Color(light: .clear, dark: .white.opacity(0.06))
    /// Unfilled portion of a score ring.
    static let ringTrack = Color(light: .black.opacity(0.06),
                                 dark: .white.opacity(0.08))
    /// Quietest fill — the wash behind glyph tiles, meters, and inset panels.
    static let fillQuiet = Color(light: .black.opacity(0.04),
                                 dark: .white.opacity(0.04))
    /// Neutral pill/track fill, one step up from `fillQuiet`.
    static let fillMuted = Color(light: .black.opacity(0.05),
                                 dark: .white.opacity(0.08))
    /// De-emphasized meter/bar segments (e.g. unlit NOVA bars).
    static let fillTrack = Color(light: .black.opacity(0.06),
                                 dark: .white.opacity(0.10))
    /// Visible outline on controls and selectable cards (unlike `cardEdge`,
    /// this one shows in light mode too).
    static let outline = Color(light: .black.opacity(0.08),
                               dark: .white.opacity(0.10))

    // MARK: Corner radii
    //
    // Four sizes, always with `style: .continuous`. Pick by role, not by
    // eye — new radii are drift, not design. (Capsules and tiny geometric
    // accents like the 6pt NOVA bars stay literal; they're shape, not radius.)
    enum Radius {
        /// Hero surfaces: score panels, comparison cards, pledge card.
        static let panel: CGFloat = 22
        /// The standard card everything else sits on.
        static let card: CGFloat = 18
        /// Inner elements: inputs, tiles inside cards, banners.
        static let control: CGFloat = 14
        /// Small squares behind glyphs and tags.
        static let chip: CGFloat = 8
    }
}

// MARK: - Semantic score / alarm colors (product detail + shared UI)

extension Color {
    /// Saturated red — reserve for the single worst on-screen signal (e.g. BAD Your Score).
    static let scoreBad = Color(hex: ScoreBandColor.bad)
    /// Muted amber — nutrient "OK" / middling warnings (also the OK score band).
    static let scoreOk = Color(hex: ScoreBandColor.ok)
    /// Deep green — nutrient "Good" / positive accents (also the Excellent score band).
    static let scoreGood = Color(hex: ScoreBandColor.excellent)
    /// De-emphasized body copy, secondary stats, and quiet warnings.
    static let neutralMuted = Color(hex: "8A8A8A")
    /// Soft caution — restrictions, moderate risk, non-primary deltas.
    static let cautionMuted = Color(hex: "9A8475")
}

// MARK: - Score bands (cuts + colors — single source of truth)

/// Hex tokens for score-band colors. Band cuts live in `RulesetV4.bands`;
/// `ScoreTier` maps each band to these tokens. No other file may keep a
/// local Excellent/Good/OK/Bad color table.
enum ScoreBandColor {
    /// Excellent — deep green (brand / nutrient-good family).
    static let excellent = "1F8A5B"
    static let excellentMid = "2BA66D"
    /// Good — solid mid green (must read as green, not amber).
    static let good = "2F9E66"
    static let goodMid = "3FB87A"
    /// OK — amber/gold.
    static let ok = "B0832A"
    static let okMid = "D4A02D"
    /// Bad — saturated red.
    static let bad = "C9442B"
    static let badMid = "DB4F33"
}

/// Band cuts come from the live ruleset; band → color is defined via `ScoreBandColor`.
enum ScoreTier: String {
    case excellent, good, poor, bad

    /// Live cut points (Excellent ≥75 · Good ≥55 · OK ≥35 · Bad else).
    static var cuts: (excellent: Int, good: Int, ok: Int) {
        let b = RulesetV4.bundled.bands
        return (b.excellent, b.good, b.ok)
    }

    /// Primary fill / large-ring color for this band.
    var fg: Color {
        switch self {
        case .excellent: return Color(hex: ScoreBandColor.excellent)
        case .good:      return Color(hex: ScoreBandColor.good)
        case .poor:      return Color(hex: ScoreBandColor.ok)
        case .bad:       return Color(hex: ScoreBandColor.bad)
        }
    }

    /// Brighter stroke for compact rings (number sits in primary text, not white-on-fill).
    var mid: Color {
        switch self {
        case .excellent: return Color(hex: ScoreBandColor.excellentMid)
        case .good:      return Color(hex: ScoreBandColor.goodMid)
        case .poor:      return Color(hex: ScoreBandColor.okMid)
        case .bad:       return Color(hex: ScoreBandColor.badMid)
        }
    }

    var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .good:      return "Good"
        case .poor:      return "OK"
        case .bad:       return "Bad"
        }
    }
}

/// Bands follow the live bundled ruleset (Excellent ≥75 · Good ≥55 · OK ≥35 · Bad).
func scoreTier(_ score: Int) -> ScoreTier {
    RulesetV4.bundled.scoreTier(for: score)
}
func scoreColor(_ s: Int) -> Color { scoreTier(s).fg }
func scoreLabel(_ s: Int) -> String { scoreTier(s).label }

/// Elevation for the one card per screen that should read as raised.
/// Reads the scheme itself — shadows are invisible on a near-black background,
/// so dark mode gets none.
struct CardShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
        } else {
            content
                .shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.04), radius: 18, x: 0, y: 8)
        }
    }
}
extension View {
    func cardShadow() -> some View { modifier(CardShadow()) }
}

// MARK: - App-wide store

/// Facade the UI talks to. Backed by SwiftData for durable on-device storage:
/// the profile, scanned products, and scan history all survive relaunches.
@MainActor
final class AppStore: ObservableObject {
    @Published var accent: Color = Theme.accent

    /// Scheme override for the whole app. `nil` means "follow the system",
    /// which is what the Preferences → System tile has always promised.
    var colorScheme: ColorScheme? {
        switch user.appearance {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    /// Temporary scheme forced by a screen that owns its own background
    /// regardless of the user's preference — the dark-green onboarding steps.
    ///
    /// This has to live here because `preferredColorScheme` is resolved at the
    /// `WindowGroup`, so an inner application of it (inside `OnboardingFlow`)
    /// never reaches the status bar. Without it, the system clock renders in
    /// dark-mode-off glyphs on a near-black background.
    @Published var schemeOverride: ColorScheme? = nil

    /// What the root actually applies.
    var effectiveColorScheme: ColorScheme? { schemeOverride ?? colorScheme }

    /// Every mutation persists automatically.
    @Published var user: UserProfile { didSet { persistProfile() } }

    /// Read-only to the UI; mutated through recordScan/saveProduct.
    @Published private(set) var history: [HistoryEntry] = []
    /// User-curated favorites shelf, newest first. Mutated through toggleFavorite.
    @Published private(set) var favorites: [FavoriteEntry] = []
    @Published private(set) var products: [String: Product] = [:]
    /// Product ids currently awaiting an overview from `/explain`.
    @Published private(set) var overviewGenerating: Set<String> = []

    private let container: ModelContainer
    private let backend = BackendService()
    private var overviewInFlight: Set<String> = []
    private var context: ModelContext { container.mainContext }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        // Build the persistent store, falling back to in-memory if it fails
        // (e.g. a migration error) so the app still launches.
        let models: [any PersistentModel.Type] = [
            ProfileRecord.self, ProductRecord.self, HistoryRecord.self, FavoriteRecord.self
        ]
        if let c = try? ModelContainer(for: Schema(models)) {
            container = c
        } else {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: Schema(models), configurations: config)
        }

        // Placeholder so `self` is fully initialized before we query the store.
        user = MockData.user

        loadProfile()
        loadProducts()
        loadHistory()
        loadFavorites()
    }

    // MARK: Loading

    private func loadProfile() {
        if let rec = try? context.fetch(FetchDescriptor<ProfileRecord>()).first,
           let p = try? decoder.decode(UserProfile.self, from: rec.data) {
            user = p
            // Drop the old mock seed so a never-entered name doesn't show as real.
            if user.name == "Jamie Rivera" {
                user.name = ""
                if user.handle == "@jamier" { user.handle = "" }
                if user.sex == "female", user.dob == "3/14/1993" {
                    user.sex = ""
                    user.dob = ""
                    user.age = 0
                }
                persistProfile()
            }
        } else {
            // First launch: seed from the default profile.
            persistProfile()
        }
    }

    private func loadProducts() {
        let recs = (try? context.fetch(FetchDescriptor<ProductRecord>())) ?? []
        products = recs.reduce(into: [:]) { dict, r in
            if let p = decodeProduct(from: r.data) { dict[p.id] = p }
        }
        invalidateAndRescoreForV506IfNeeded()
        invalidateAndRescoreForV507IfNeeded()
        invalidateAndRescoreForV509IfNeeded()
        invalidateAndRescoreForV510IfNeeded()
        invalidateAndRescoreForV520IfNeeded()
        invalidateAndRescoreForV530IfNeeded()
        invalidateAndRescoreForV540IfNeeded()
        invalidateAndRescoreForV550IfNeeded()
    }

    /// Decode a stored snapshot, migrating legacy `deltaReason` → `overview`.
    private func decodeProduct(from data: Data) -> Product? {
        if let p = try? decoder.decode(Product.self, from: data) {
            return migrateOverviewIfNeeded(p)
        }
        guard var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if dict["overview"] == nil, let legacy = dict["deltaReason"] {
            dict["overview"] = legacy
            dict.removeValue(forKey: "deltaReason")
        }
        guard let migrated = try? JSONSerialization.data(withJSONObject: dict),
              let p = try? decoder.decode(Product.self, from: migrated) else { return nil }
        return migrateOverviewIfNeeded(p)
    }

    /// Stale cached overviews that may hallucinate additive presence.
    private func migrateOverviewIfNeeded(_ product: Product) -> Product {
        var out = product
        if !out.hasScoreableIngredientSignal, out.overview != nil {
            out.overviewStale = true
        }
        return out
    }

    /// One-shot V5.0.6 migration: whole_foods/fats weight touch-ups + overview
    /// truthfulness; mark overviews stale so they regenerate under exp-v8.
    private func invalidateAndRescoreForV506IfNeeded() {
        let key = "rulesetV506Rescored"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        rescoreAll()
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.set(true, forKey: "overviewExpV8Invalidated")
    }

    /// One-shot V5.0.7 migration: pure sweeteners become unscored (no dials,
    /// no overview); other products rescore with expected Δ0.
    private func invalidateAndRescoreForV507IfNeeded() {
        let key = "rulesetV507Rescored"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        rescoreAll()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// One-shot V5.0.9 — ice_cream ingredient integrity + UPF band display caps.
    private func invalidateAndRescoreForV509IfNeeded() {
        let key = "rulesetV509Rescored"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        rescoreAll()
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.set(true, forKey: "overviewExpV9Invalidated")
    }

    /// One-shot V5.1.0 — Real Food / Fat Quality axes.
    private func invalidateAndRescoreForV510IfNeeded() {
        let key = "rulesetV510Rescored"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard RulesetStore.v510Enabled else { return }
        rescoreAll()
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.set(true, forKey: "overviewExpV9Invalidated")
    }

    /// One-shot V5.2.0 — dairy-aware milk scoring (S12 dairy axes, processing
    /// tags, raw-milk gate, fortification exemption, powder reconstitution).
    private func invalidateAndRescoreForV520IfNeeded() {
        let key = "rulesetV520Rescored"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        rescoreAll()
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.set(true, forKey: "overviewExpV9Invalidated")
    }

    /// One-shot V5.3.0 — dedicated `eggs` profile (S12/S13 egg variants,
    /// egg-dominance routing guard, NOVA inference, S14 token / whitelist fixes).
    private func invalidateAndRescoreForV530IfNeeded() {
        let key = "rulesetV530Rescored"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        rescoreAll()
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.set(true, forKey: "overviewExpV9Invalidated")
    }

    /// One-shot V5.4.0 — dedicated `bread` profile (graded whole-grain share,
    /// evidence-based processing, S12 grain variant, bread sodium anchors,
    /// S14 whitelist / water fixes).
    private func invalidateAndRescoreForV540IfNeeded() {
        let key = "rulesetV540Rescored"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        rescoreAll()
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.set(true, forKey: "overviewExpV9Invalidated")
    }

    /// One-shot V5.5.0 — dedicated `protein_bars` profile (protein delivery +
    /// source quality, evidence-based processing, sweetener tiers, capped
    /// fruit-sugar discount, S14 whitelist / neutral protein sources,
    /// palm-kernel fat tier).
    private func invalidateAndRescoreForV550IfNeeded() {
        let key = "rulesetV550Rescored"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        rescoreAll()
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.set(true, forKey: "overviewExpV9Invalidated")
    }

    private func loadHistory() {
        let desc = FetchDescriptor<HistoryRecord>(
            sortBy: [SortDescriptor(\.scannedAt, order: .reverse)]
        )
        let recs = (try? context.fetch(desc)) ?? []
        history = recs.map {
            HistoryEntry(productId: $0.productId, when: $0.when,
                         dateLabel: $0.dateLabel, scannedAt: $0.scannedAt)
        }
    }

    private func loadFavorites() {
        let desc = FetchDescriptor<FavoriteRecord>(
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        let recs = (try? context.fetch(desc)) ?? []
        favorites = recs.map { FavoriteEntry(productId: $0.productId, addedAt: $0.addedAt) }
    }

    // MARK: Persistence

    private func persistProfile() {
        guard let data = try? encoder.encode(user) else { return }
        if let rec = try? context.fetch(FetchDescriptor<ProfileRecord>()).first {
            rec.data = data
        } else {
            context.insert(ProfileRecord(data: data))
        }
        try? context.save()
        rescoreAll()
    }

    /// Recompute every stored product's scores against the current profile.
    /// Scoring is idempotent — re-running it overwrites the score fields cleanly.
    /// Persists both `.scored` and `.unscored` outcomes. Unsupported / insufficient
    /// products keep their stored snapshot untouched.
    func rescoreAll() {
        guard !products.isEmpty else { return }
        for (id, p) in products {
            let updated: Product
            switch ScoringEngineV4.scoreProduct(p, for: user, ruleset: RulesetStore.current) {
            case .scored(var scored):
                scored.overview = nil
                scored.overviewStale = true
                updated = scored
            case .unscored(var unscored, _):
                // Clear any legacy dials / LLM overview from pre-V5.0.7 saves.
                unscored.overallScore = nil
                unscored.yourScore = nil
                unscored.overview = nil
                unscored.overviewStale = false
                unscored.firedCaps = nil
                unscored.bindingCap = nil
                unscored.overallFiredCaps = nil
                unscored.overallBindingCap = nil
                unscored.overallBandCap = nil
                unscored.bonuses = []
                updated = unscored
            case .unsupported, .insufficientData:
                continue
            }
            products[id] = updated
            guard let data = try? encoder.encode(updated) else { continue }
            if let rec = try? context.fetch(
                FetchDescriptor<ProductRecord>(predicate: #Predicate { $0.id == id })
            ).first {
                rec.data = data
                rec.updatedAt = .now
            }
        }
        try? context.save()
    }

    /// Lazy overview regeneration — one product at a time, on open or after scan.
    /// Unscored products never call `/explain`.
    func requestOverview(for productId: String) {
        guard let product = products[productId], !product.isUnscored else { return }
        let needsRefresh = product.overviewStale == true || product.overview == nil
        guard needsRefresh else { return }
        guard !overviewInFlight.contains(productId) else { return }
        overviewInFlight.insert(productId)
        overviewGenerating.insert(productId)
        Task { await fetchOverview(productId: productId) }
    }

    private func fetchOverview(productId: String) async {
        defer {
            overviewInFlight.remove(productId)
            overviewGenerating.remove(productId)
        }
        guard var product = products[productId], !product.isUnscored,
              let ctx = ScoringEngineV4.overviewContext(for: product, profile: user,
                                                        ruleset: RulesetStore.current)
        else { return }

        let classHash = ScoreClass(user).hash
        let payload = BackendService.ExplainPayload(
            barcode: product.id, classHash: classHash, context: ctx)

        let llmText = await backend.explain(payload)
        let text: String
        if let llmText, OverviewValidator.isValid(llmText, ctx: ctx) {
            text = llmText
        } else {
            text = OverviewTemplate.generate(ctx)
        }

        guard ScoreClass(user).hash == classHash,
              var current = products[productId],
              !current.isUnscored,
              current.overallScore == product.overallScore,
              current.yourScore == product.yourScore,
              let overall = current.overallScore,
              let your = current.yourScore else { return }

        let delta = your - overall
        let tone: DeltaReason.Tone = delta > 0 ? .positive : delta < 0 ? .negative : .positive
        current.overview = ProductOverview(tone: tone, text: text)
        current.overviewStale = false
        saveProduct(current)
    }

    /// Upsert a product snapshot (used by scan + search lookups).
    func saveProduct(_ product: Product) {
        products[product.id] = product
        guard let data = try? encoder.encode(product) else { return }
        let id = product.id
        if let rec = try? context.fetch(
            FetchDescriptor<ProductRecord>(predicate: #Predicate { $0.id == id })
        ).first {
            rec.data = data
            rec.updatedAt = .now
        } else {
            context.insert(ProductRecord(id: id, data: data))
        }
        try? context.save()
    }

    /// Record a scan: snapshots the product and (if enabled) prepends a history entry.
    func recordScan(_ product: Product, when: String = "Just now") {
        saveProduct(product)
        guard user.saveScansToHistory else { return }
        let now = Date.now
        let label = Self.dateLabel(for: now)
        context.insert(HistoryRecord(productId: product.id, when: when,
                                     dateLabel: label, scannedAt: now))
        try? context.save()
        history.insert(
            HistoryEntry(productId: product.id, when: when,
                         dateLabel: label, scannedAt: now),
            at: 0
        )
    }

    /// Remove a single history entry.
    func deleteHistory(_ entry: HistoryEntry) {
        let label = entry.dateLabel
        let pid = entry.productId
        if let rec = try? context.fetch(
            FetchDescriptor<HistoryRecord>(
                predicate: #Predicate { $0.productId == pid && $0.dateLabel == label }
            )
        ).first {
            context.delete(rec)
            try? context.save()
        }
        history.removeAll { $0.id == entry.id }
    }

    /// Clear all scan history (products are kept).
    func clearHistory() {
        let recs = (try? context.fetch(FetchDescriptor<HistoryRecord>())) ?? []
        recs.forEach { context.delete($0) }
        try? context.save()
        history.removeAll()
    }

    // MARK: Favorites

    func isFavorite(_ productId: String) -> Bool {
        favorites.contains { $0.productId == productId }
    }

    /// Add or remove a product from the favorites shelf. Adding snapshots the
    /// product first, so a favorite made from Search / Top Rated stays openable
    /// even if it was never scanned. Returns the new favorited state.
    @discardableResult
    func toggleFavorite(_ product: Product) -> Bool {
        let id = product.id
        if isFavorite(id) {
            removeFavorite(productId: id)
            return false
        }
        saveProduct(product)
        let now = Date.now
        context.insert(FavoriteRecord(productId: id, addedAt: now))
        try? context.save()
        favorites.insert(FavoriteEntry(productId: id, addedAt: now), at: 0)
        return true
    }

    /// Remove a single favorite (swipe action).
    func removeFavorite(_ entry: FavoriteEntry) {
        removeFavorite(productId: entry.productId)
    }

    private func removeFavorite(productId id: String) {
        if let rec = try? context.fetch(
            FetchDescriptor<FavoriteRecord>(predicate: #Predicate { $0.productId == id })
        ).first {
            context.delete(rec)
            try? context.save()
        }
        favorites.removeAll { $0.productId == id }
    }

    /// Clear the favorites shelf (products and history are kept).
    func clearFavorites() {
        let recs = (try? context.fetch(FetchDescriptor<FavoriteRecord>())) ?? []
        recs.forEach { context.delete($0) }
        try? context.save()
        favorites.removeAll()
    }

    private static func dateLabel(for date: Date) -> String {
        let day = DateFormatter(); day.dateFormat = "MMM d"
        let time = DateFormatter(); time.dateFormat = "h:mm a"
        return "\(day.string(from: date)) · \(time.string(from: date))"
    }
}
