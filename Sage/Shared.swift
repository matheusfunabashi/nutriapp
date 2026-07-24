import SwiftUI

// MARK: - Score Ring

struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 132
    var stroke: CGFloat = 11
    var dark: Bool = false
    var sublabel: String? = nil
    /// When set, overrides the tier-derived arc color (e.g. muted Overall reference).
    var ringColor: Color? = nil

    @State private var animated: Double = 0

    var body: some View {
        let color = ringColor ?? scoreColor(score)
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
                    .font(.sageBold(size * 0.34))
                    .monospacedDigit()
                    .foregroundColor(Theme.textPrimary(dark))
                if let sub = sublabel {
                    Text(sub.uppercased())
                        .font(.sageBold(10))
                        .tracking(1)
                        .foregroundColor(color)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { animated = Double(score) }
    }
}

/// Compact score ring for list rows (e.g. Recent scans on Home).
/// Pass `score: nil` (or `isUnscored: true`) for the neutral "Unscored" badge —
/// never render a sentinel 0.
struct CompactScoreRing: View {
    let score: Int?
    var isUnscored: Bool = false
    var dark: Bool = false

    private let size: CGFloat = 52
    private let stroke: CGFloat = 4.5

    private var showsUnscored: Bool { isUnscored || score == nil }

    var body: some View {
        if showsUnscored {
            unscoredBadge
        } else if let score {
            scoredRing(score)
        }
    }

    private var unscoredBadge: some View {
        let track = dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        let fg = Theme.textSecondary(dark)
        return ZStack {
            Circle().stroke(track, lineWidth: stroke)
            Text("Unscored")
                .font(.sageBold(9))
                .multilineTextAlignment(.center)
                .foregroundColor(fg)
                .padding(.horizontal, 4)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text("Unscored"))
    }

    private func scoredRing(_ score: Int) -> some View {
        let style = Self.style(for: score)
        let track = dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)

        return ZStack {
            Circle().stroke(track, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(style.color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(score)")
                    .font(.sageBold(13))
                    .monospacedDigit()
                    .foregroundColor(Theme.textPrimary(dark))
                Text(style.label)
                    .font(.sageMedium(9))
                    .foregroundColor(Theme.textSecondary(dark))
            }
        }
        .frame(width: size, height: size)
    }

    private static func style(for score: Int) -> (color: Color, label: String) {
        let tier = scoreTier(score)
        return (tier.mid, tier.label)
    }
}

// MARK: - Product thumbnail

struct ProductThumb: View {
    let glyph: String
    /// Unused for tint; kept for call-site stability.
    let score: Int?
    var size: CGFloat = 48
    /// Unused — chrome is always `Theme.surface` on fallbacks; kept for call-site stability.
    var neutral: Bool = false
    /// Product photo; nil (or a failed load) falls back to the glyph tile —
    /// "no image" is a designed state, never an error.
    var imageURL: String? = nil
    /// Run Vision cutout when a remote URL is shown. False for soft OFF shots /
    /// placeholder-only rows.
    var processCutout: Bool = true
    /// Detail header: larger frame + no chrome flash while loading/processing.
    var isDetail: Bool = false

    var body: some View {
        ProductImageView(
            url: imageURL.flatMap(URL.init(string:)),
            style: isDetail ? .detail : .fixed(size),
            glyph: glyph,
            processCutout: processCutout && imageURL != nil
        )
    }
}

// MARK: - YourScorePill

struct YourScorePill: View {
    let score: Int?
    var isUnscored: Bool = false

    private var showsUnscored: Bool { isUnscored || score == nil }

    var body: some View {
        if showsUnscored {
            Text("Unscored")
                .font(.sageBold(10))
                .foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.gray.opacity(0.55)))
        } else if let score {
            Text("\(score)")
                .font(.sageBold(12))
                .monospacedDigit()
                .foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(scoreColor(score)))
        }
    }
}

// MARK: - Eyebrow / section labels

struct EyebrowLabel: View {
    let text: String
    let dark: Bool
    var horizontalPadding: CGFloat = 24
    var body: some View {
        Text(text)
            .font(.sageBold(12))
            .tracking(-0.1)
            .foregroundColor(Theme.textSecondary(dark))
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 14).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String? = nil
    let dark: Bool
    var horizontalPadding: CGFloat = 24
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.sageBold(18))
                .tracking(-0.4)
                .foregroundColor(Theme.textPrimary(dark))
            if let sub = subtitle {
                Text(sub)
                    .font(.sageRegular(12))
                    .foregroundColor(Theme.textSecondary(dark))
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 20).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Circle icon button

struct CircleIconButton: View {
    let systemName: String
    let dark: Bool
    var size: CGFloat = 42
    var accessibilityLabel: String? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(dark ? Color.white.opacity(0.08) : Color.white)
                Image(systemName: systemName)
                    .font(.sageSemiBold(16))
                    .foregroundColor(Theme.textPrimary(dark))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .cardShadow(dark)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }
}

// MARK: - Tab bar

/// Tab cases drive what's rendered in the main area. "Scan" isn't a tab
/// because it triggers an action (open the camera) rather than swap a
/// destination view.
enum AppTab: String, CaseIterable {
    case home, topRated, pantry, you

    var label: String {
        switch self {
        case .home:     return "Home"
        case .topRated: return "Top Rated"
        case .pantry:   return "Pantry"
        case .you:      return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home:     return "house"
        case .topRated: return "trophy"
        case .pantry:   return "line.3.horizontal"
        case .you:      return "person"
        }
    }

    /// Filled variant for the active state; falls back to `icon` when no
    /// filled symbol meaningfully differs.
    var activeIcon: String {
        switch self {
        case .home:     return "house.fill"
        case .topRated: return "trophy.fill"
        case .you:      return "person.fill"
        default:        return icon
        }
    }
}

struct TabBar: View {
    @EnvironmentObject var store: AppStore
    @Binding var tab: AppTab
    /// Tapping the center hero opens the camera — it's an action, not a tab swap.
    let onScan: () -> Void

    var body: some View {
        let dark = store.darkMode
        HStack(spacing: 0) {
            tabButton(.home)
            tabButton(.topRated)
            scanHero
            tabButton(.pantry)
            tabButton(.you)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(dark ? Color(white: 0.10).opacity(0.92) : Color.white.opacity(0.96))
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                        lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 24, x: 0, y: 10)
        .padding(.horizontal, 16)
        // Sits closer to the safe-area edge so the bar feels anchored
        // to the bottom rather than floating mid-air.
        .padding(.bottom, 6)
    }

    // MARK: Standard tab slot

    @ViewBuilder
    private func tabButton(_ t: AppTab) -> some View {
        let active = tab == t
        let dark = store.darkMode
        let primary = Theme.textPrimary(dark)
        let dim = dark ? Color.white.opacity(0.42) : Color.black.opacity(0.38)
        let c = active ? primary : dim

        Button {
            // Spring keeps the active-state transition interruptible — if
            // the user taps a third tab mid-animation it retargets smoothly.
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                tab = t
            }
        } label: {
            VStack(spacing: 4) {
                // Contextual icon swap: cross-fade with scale + opacity
                // instead of snapping between two symbols. iOS 17+ supports
                // a symbol replace transition that does the spring for us.
                Image(systemName: active ? t.activeIcon : t.icon)
                    .font(.system(size: 22, weight: active ? .bold : .regular))
                    .foregroundColor(c)
                    .frame(height: 26)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: active)
                Text(t.label)
                    .font(.sageMedium(11))
                    .tracking(-0.1)
                    .foregroundColor(c)
            }
            .frame(maxWidth: .infinity, minHeight: 44) // ≥44pt hit area
            .contentShape(Rectangle())
        }
        // Static — the tab slot already communicates press via its color
        // change and active backdrop; scaling on top of that is fussy.
        .buttonStyle(.pressableStatic)
    }

    // MARK: Center hero — circular accent, sitting in-line with the tabs
    //
    // Shares the tab slot's VStack(icon, label) structure so all five
    // buttons land on the same vertical baseline; the accent-filled
    // circle around the glyph is the only visual difference, keeping
    // Scan as the primary action without it floating above the bar.

    private var scanHero: some View {
        let dark = store.darkMode
        return Button(action: onScan) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(store.accent)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                    Image(systemName: "viewfinder")
                        .font(.sageBold(16))
                        .foregroundColor(.white)
                }
                .frame(width: 30, height: 30)
                .shadow(color: store.accent.opacity(0.30), radius: 6, x: 0, y: 3)

                Text("Scan")
                    .font(.sageMedium(11))
                    .tracking(-0.1)
                    .foregroundColor(Theme.textPrimary(dark))
            }
            .frame(maxWidth: .infinity, minHeight: 44) // ≥44pt hit area
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable) // primary action — does want a press scale
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
                        .font(.sageBold(10))
                        .foregroundColor(accent)
                }
                Text(label)
                    .font(.sageBold(12))
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
        case .low:      return Color.scoreGood      // green — same as nutrient "Good"
        case .moderate: return Color.scoreOk        // amber — same as nutrient "OK"
        case .high:     return Color.scoreBad       // red   — same as nutrient "High"
        case .unrated:  return Color.neutralMuted   // gray  — neutral / not rated
        }
    }
    static func bg(_ r: RiskLevel) -> Color {
        fg(r).opacity(r == .high ? 0.10 : 0.12)
    }
    static func label(_ r: RiskLevel) -> String {
        switch r {
        case .low: return "Low risk"
        case .moderate: return "Moderate risk"
        case .high: return "High risk"
        case .unrated: return "Unrated"
        }
    }

    /// Compact chip / summary stem without the word "risk" (caller adds it).
    static func shortLabel(_ r: RiskLevel) -> String {
        switch r {
        case .low: return "low risk"
        case .moderate: return "moderate risk"
        case .high: return "high risk"
        case .unrated: return "unrated"
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
        Image("02 Symbol")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
                    .font(.sageBold(15))
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

// MARK: - Polish primitives
//
// Small reusable building blocks that implement the
// `make-interfaces-feel-better` skill rules across the app.

/// Tactile scale-on-press for any Button. SwiftUI's implicit animation
/// on `.scaleEffect` is naturally interruptible — releasing mid-press
/// retargets to 1.0 smoothly, exactly like a CSS transition.
///
/// - Always `0.96` (skill rule: anything below 0.95 feels exaggerated).
/// - Use `.static` for chrome where motion would be distracting
///   (e.g. tab bar slot already has its own selection visual).
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96
    var pressedOpacity: Double = 0.92
    var isStatic: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isStatic ? 1 : (configuration.isPressed ? pressedScale : 1))
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// Default tactile press — scales to 0.96 with a soft opacity dip.
    static var pressable: PressableButtonStyle { .init() }
    /// No-scale variant for chrome/static contexts.
    static var pressableStatic: PressableButtonStyle { .init(isStatic: true) }
}

/// Staggered enter for a slice of layout. Wrap each "semantic chunk"
/// in its own `StaggeredAppear` and bump `index` so the chunks blur+fade
/// in one after another (~80ms gap), matching the skill rule of splitting
/// containers instead of animating one big block.
struct StaggeredAppear<Content: View>: View {
    let index: Int
    var stagger: Double = 0.07
    var duration: Double = 0.45
    var offset: CGFloat = 12
    @ViewBuilder var content: () -> Content

    @State private var visible = false

    var body: some View {
        content()
            .opacity(visible ? 1 : 0)
            .blur(radius: visible ? 0 : 4)
            .offset(y: visible ? 0 : offset)
            .onAppear {
                // Skip work entirely if SwiftUI re-uses the same view
                // (e.g. tab swap back) — the state already says visible.
                guard !visible else { return }
                withAnimation(
                    .easeOut(duration: duration).delay(Double(index) * stagger)
                ) { visible = true }
            }
    }
}

/// Expands the tappable area around a small visual element without
/// resizing it visually. Use on icon-only buttons whose visible glyph
/// is < 44×44.
///
/// Skill rule: minimum 40×40 hit area. Two hit areas should never overlap;
/// `min` lets the caller pick the smallest expansion that still clears
/// 40pt without colliding with a neighbour.
struct MinHitArea: ViewModifier {
    var min: CGFloat = 44
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .frame(minWidth: min, minHeight: min)
    }
}

extension View {
    func minHitArea(_ size: CGFloat = 44) -> some View {
        modifier(MinHitArea(min: size))
    }
}

