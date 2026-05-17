import SwiftUI

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
        case .poor:      return "Poor"
        case .bad:       return "Bad"
        }
    }
}

func scoreTier(_ score: Int) -> ScoreTier {
    switch score {
    case 75...: return .excellent
    case 50...: return .good
    case 25...: return .poor
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

final class AppStore: ObservableObject {
    @Published var accent: Color = Theme.accent
    @Published var darkMode: Bool = false
    @Published var user: UserProfile = MockData.user
    @Published var history: [HistoryEntry] = MockData.history
    let products: [String: Product] = MockData.products
}
