import SwiftUI

// MARK: - Score Ring

struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 132
    var stroke: CGFloat = 11
    var dark: Bool = false
    var sublabel: String? = nil

    @State private var animated: Double = 0

    var body: some View {
        let color = scoreColor(score)
        let track = dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        ZStack {
            Circle().stroke(track, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: CGFloat(animated) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.1), value: animated)
            VStack(spacing: 2) {
                Text("\(Int(animated.rounded()))")
                    .font(.system(size: size * 0.34, weight: .heavy))
                    .monospacedDigit()
                    .foregroundColor(Theme.textPrimary(dark))
                if let sub = sublabel {
                    Text(sub.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1)
                        .foregroundColor(color)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { animated = Double(score) }
    }
}

// MARK: - Product thumbnail

struct ProductThumb: View {
    let glyph: String
    let score: Int
    var size: CGFloat = 48

    var body: some View {
        let c = scoreColor(score)
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(
                    colors: [c.opacity(0.12), c.opacity(0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(c.opacity(0.19), lineWidth: 1)
                )
            Text(glyph).font(.system(size: size * 0.5))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - YourScorePill

struct YourScorePill: View {
    let score: Int
    var body: some View {
        Text("\(score)")
            .font(.system(size: 12, weight: .heavy))
            .monospacedDigit()
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(scoreColor(score)))
    }
}

// MARK: - Eyebrow / section labels

struct EyebrowLabel: View {
    let text: String
    let dark: Bool
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.4)
            .foregroundColor(Theme.textSecondary(dark))
            .padding(.horizontal, 24)
            .padding(.top, 14).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String? = nil
    let dark: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .tracking(-0.4)
                .foregroundColor(Theme.textPrimary(dark))
            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary(dark))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Circle icon button

struct CircleIconButton: View {
    let systemName: String
    let dark: Bool
    var size: CGFloat = 42
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(dark ? Color.white.opacity(0.08) : Color.white)
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textPrimary(dark))
            }
            .frame(width: size, height: size)
            .cardShadow(dark)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab bar

enum AppTab: String, CaseIterable {
    case history, scanner, search, profile

    var label: String {
        switch self {
        case .history: return "History"
        case .scanner: return "Scan"
        case .search:  return "Search"
        case .profile: return "Profile"
        }
    }
    var icon: String {
        switch self {
        case .history: return "list.bullet"
        case .scanner: return "viewfinder"
        case .search:  return "magnifyingglass"
        case .profile: return "person"
        }
    }
}

struct TabBar: View {
    @EnvironmentObject var store: AppStore
    @Binding var tab: AppTab

    var body: some View {
        let dark = store.darkMode
        HStack(spacing: 2) {
            tabButton(.history)
            scanHero
            tabButton(.search)
            tabButton(.profile)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(dark ? Color(white: 0.08).opacity(0.85) : Color.white.opacity(0.85))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 32, x: 0, y: 12)
        .padding(.horizontal, 12)
        .padding(.bottom, 24)
    }

    @ViewBuilder private func tabButton(_ t: AppTab) -> some View {
        let active = tab == t
        let dark = store.darkMode
        let c = active ? store.accent : (dark ? Color.white.opacity(0.5) : Color.black.opacity(0.45))
        Button { tab = t } label: {
            VStack(spacing: 2) {
                Image(systemName: t.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(c)
                Text(t.label)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.2)
                    .foregroundColor(c)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(active ? store.accent.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var scanHero: some View {
        Button { tab = .scanner } label: {
            HStack(spacing: 6) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Text("Scan")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(-0.2)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Capsule().fill(store.accent))
            .shadow(color: store.accent.opacity(0.4), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chip

struct ChipView: View {
    let label: String
    let active: Bool
    let dark: Bool
    let accent: Color
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accent)
                }
                Text(label)
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(-0.1)
                    .foregroundColor(active ? accent : Theme.textPrimary(dark))
            }
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(
                Capsule().fill(active ? accent.opacity(0.10)
                              : (dark ? Color.white.opacity(0.05) : Theme.bgLight))
            )
            .overlay(
                Capsule().stroke(active ? accent
                                : (dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)),
                                lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Risk styles

enum RiskStyle {
    static func fg(_ r: RiskLevel) -> Color {
        switch r {
        case .low:      return Color(hex: "1F8A5B")
        case .moderate: return Color(hex: "D4A02D")
        case .high:     return Color(hex: "C9442B")
        }
    }
    static func bg(_ r: RiskLevel) -> Color {
        switch r {
        case .low:      return Color(hex: "1F8A5B").opacity(0.10)
        case .moderate: return Color(hex: "D4A02D").opacity(0.12)
        case .high:     return Color(hex: "C9442B").opacity(0.10)
        }
    }
    static func label(_ r: RiskLevel) -> String {
        switch r {
        case .low: return "Low"; case .moderate: return "Moderate"; case .high: return "High"
        }
    }
}

// MARK: - Card wrapper

struct CardView<Content: View>: View {
    let dark: Bool
    var padding: EdgeInsets = EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.surface(dark))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(dark ? Color.white.opacity(0.06) : .clear, lineWidth: 0.5)
            )
            .cardShadow(dark)
    }
}

// MARK: - Sage leaf logo

struct SageMark: View {
    var size: CGFloat = 26
    var color: Color = Theme.accent
    var body: some View {
        ZStack {
            LeafShape().fill(color)
            Path { p in
                p.move(to: CGPoint(x: size * 0.28, y: size * 0.69))
                p.addLine(to: CGPoint(x: size * 0.69, y: size * 0.28))
            }
            .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

private struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.15, y: h * 0.69))
        p.addCurve(to: CGPoint(x: w * 0.84, y: h * 0.13),
                   control1: CGPoint(x: w * 0.15, y: h * 0.34),
                   control2: CGPoint(x: w * 0.40, y: h * 0.13))
        p.addCurve(to: CGPoint(x: w * 0.28, y: h * 0.81),
                   control1: CGPoint(x: w * 0.84, y: h * 0.56),
                   control2: CGPoint(x: w * 0.59, y: h * 0.81))
        p.addLine(to: CGPoint(x: w * 0.15, y: h * 0.81))
        p.closeSubpath()
        return p
    }
}

// MARK: - Toggle

struct CustomToggle: View {
    @Binding var isOn: Bool
    let dark: Bool
    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.black : (dark ? Color.white.opacity(0.18) : Color.black.opacity(0.18)))
                    .frame(width: 46, height: 28)
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pill button

struct PillButton: View {
    enum Variant { case primary, secondary, ghost }
    let title: String
    let variant: Variant
    let dark: Bool
    var leadingSystemImage: String? = nil
    var fullWidth: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let n = leadingSystemImage {
                    Image(systemName: n).font(.system(size: 15, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .heavy))
                    .tracking(-0.2)
            }
            .foregroundColor(fg)
            .padding(.horizontal, 22).padding(.vertical, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(Capsule().fill(bg))
            .overlay(Capsule().stroke(strokeC, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var bg: Color {
        switch variant {
        case .primary:   return dark ? .white : .black
        case .secondary: return dark ? Color.white.opacity(0.08) : .white
        case .ghost:     return .clear
        }
    }
    private var fg: Color {
        switch variant {
        case .primary:   return dark ? .black : .white
        case .secondary, .ghost: return dark ? .white : Color(hex: "111111")
        }
    }
    private var strokeC: Color {
        if variant == .secondary {
            return dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
        }
        return .clear
    }
}
