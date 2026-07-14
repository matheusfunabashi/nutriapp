import SwiftUI
import SwiftData

// MARK: - Theme tokens

extension Color {
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

    static func bg(_ dark: Bool) -> Color { dark ? bgDark : bgLight }
    static func surface(_ dark: Bool) -> Color { dark ? surfaceDark : surfaceLight }
    static func textPrimary(_ dark: Bool) -> Color {
        dark ? Color.white : Color(hex: "111111")
    }
    static func textSecondary(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.55) : Color(hex: "111111").opacity(0.55)
    }
    static func divider(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }
}

// MARK: - Semantic score / alarm colors (product detail + shared UI)

extension Color {
    /// Saturated red — reserve for the single worst on-screen signal (e.g. BAD Your Score).
    static let scoreBad = Color(hex: "C9442B")
    /// Muted amber for middling scores and non-primary warnings.
    static let scoreOk = Color(hex: "B0832A")
    /// Positive / good band.
    static let scoreGood = Color(hex: "1F8A5B")
    /// De-emphasized body copy, secondary stats, and quiet warnings.
    static let neutralMuted = Color(hex: "8A8A8A")
    /// Soft caution — restrictions, moderate risk, non-primary deltas.
    static let cautionMuted = Color(hex: "9A8475")
}

// MARK: - Score helpers

enum ScoreTier: String {
    case excellent, good, poor, bad

    var fg: Color {
        switch self {
        case .excellent: return Color(hex: "1F8A5B")
        case .good:      return Color(hex: "B0832A")
        case .poor:      return Color(hex: "C76A1F")
        case .bad:       return Color(hex: "C9442B")
        }
    }
    var mid: Color {
        switch self {
        case .excellent: return Color(hex: "2BA66D")
        case .good:      return Color(hex: "D4A02D")
        case .poor:      return Color(hex: "E07A26")
        case .bad:       return Color(hex: "DB4F33")
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

/// Bands follow the v3 anchored scale (100 perfect · 70 good · 50 neutral ·
/// 30 bad · 10 avoid); scores are floored at 10, never 0.
func scoreTier(_ score: Int) -> ScoreTier {
    switch score {
    case 80...: return .excellent
    case 60...: return .good
    case 40...: return .poor
    default:    return .bad
    }
}
func scoreColor(_ s: Int) -> Color { scoreTier(s).fg }
func scoreLabel(_ s: Int) -> String { scoreTier(s).label }

struct CardShadow: ViewModifier {
    let dark: Bool
    func body(content: Content) -> some View {
        if dark {
            content
        } else {
            content
                .shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.04), radius: 18, x: 0, y: 8)
        }
    }
}
extension View {
    func cardShadow(_ dark: Bool) -> some View { modifier(CardShadow(dark: dark)) }
}

// MARK: - App-wide store

/// Facade the UI talks to. Backed by SwiftData for durable on-device storage:
/// the profile, scanned products, and scan history all survive relaunches.
@MainActor
final class AppStore: ObservableObject {
    @Published var accent: Color = Theme.accent
    @Published var darkMode: Bool = false

    /// Every mutation persists automatically.
    @Published var user: UserProfile { didSet { persistProfile() } }

    /// Read-only to the UI; mutated through recordScan/saveProduct.
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var products: [String: Product] = [:]

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        // Build the persistent store, falling back to in-memory if it fails
        // (e.g. a migration error) so the app still launches.
        let models: [any PersistentModel.Type] = [
            ProfileRecord.self, ProductRecord.self, HistoryRecord.self
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
    }

    // MARK: Loading

    private func loadProfile() {
        if let rec = try? context.fetch(FetchDescriptor<ProfileRecord>()).first,
           let p = try? decoder.decode(UserProfile.self, from: rec.data) {
            user = p
        } else {
            // First launch: seed from the default profile.
            persistProfile()
        }
        darkMode = (user.appearance == "dark")
    }

    private func loadProducts() {
        let recs = (try? context.fetch(FetchDescriptor<ProductRecord>())) ?? []
        products = recs.reduce(into: [:]) { dict, r in
            if let p = try? decoder.decode(Product.self, from: r.data) { dict[p.id] = p }
        }
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
    /// Products whose category is unsupported (water/alcohol) or that lack the
    /// minimum data keep their stored snapshot untouched (they were never a
    /// scored result page to begin with).
    func rescoreAll() {
        guard !products.isEmpty else { return }
        for (id, p) in products {
            guard case .scored(let scored) = ScoringEngineV4.scoreProduct(p, for: user,
                                                                          ruleset: RulesetStore.current)
            else { continue }
            products[id] = scored
            guard let data = try? encoder.encode(scored) else { continue }
            if let rec = try? context.fetch(
                FetchDescriptor<ProductRecord>(predicate: #Predicate { $0.id == id })
            ).first {
                rec.data = data
                rec.updatedAt = .now
            }
        }
        try? context.save()
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

    private static func dateLabel(for date: Date) -> String {
        let day = DateFormatter(); day.dateFormat = "MMM d"
        let time = DateFormatter(); time.dateFormat = "h:mm a"
        return "\(day.string(from: date)) · \(time.string(from: date))"
    }
}
