import SwiftUI

// MARK: - Score Ring

struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 132
    var stroke: CGFloat = 11
    var sublabel: String? = nil
    /// When set, overrides the tier-derived arc color (e.g. muted Overall reference).
    var ringColor: Color? = nil

    @State private var animated: Double = 0

    var body: some View {
        let color = ringColor ?? scoreColor(score)
        // The arc and the numeral are driven by one animatable value, so they
        // can never disagree: `trim` is animatable but `Text` is not, so
        // reading both from plain @State snapped the number to its final value
        // while the arc was still sweeping — a 77 sitting inside a half-filled
        // ring for the first second.
        ScoreRingBody(value: animated, color: color, size: size,
                      stroke: stroke, sublabel: sublabel)
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sublabel.map { "\(score), \($0)" } ?? "\(score)")
            .onAppear {
                withAnimation(.easeOut(duration: 1.1)) { animated = Double(score) }
            }
            .onChange(of: score) { _, newScore in
                withAnimation(.easeOut(duration: 1.1)) { animated = Double(newScore) }
            }
    }
}

/// Ring + numeral for one animation frame. Conforming to `Animatable` makes
/// SwiftUI re-evaluate the body as `value` interpolates, which is what lets the
/// numeral count up in lockstep with the arc.
private struct ScoreRingBody: View, Animatable {
    var value: Double
    var color: Color
    var size: CGFloat
    var stroke: CGFloat
    var sublabel: String?

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.ringTrack, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, value))) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(Int(value.rounded()))")
                    .font(.sageFixedBold(size * 0.34))
                    .monospacedDigit()
                    .foregroundColor(Theme.ink)
                if let sublabel {
                    Text(sublabel.uppercased())
                        .font(.sageFixedBold(10))
                        .tracking(1)
                        .foregroundColor(color)
                }
            }
        }
    }
}

/// Compact score ring for list rows (e.g. Recent scans on Home).
/// Pass `score: nil` (or `isUnscored: true`) for the neutral "Unscored" badge —
/// never render a sentinel 0.
struct CompactScoreRing: View {
    let score: Int?
    var isUnscored: Bool = false

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
        ZStack {
            Circle().stroke(Theme.ringTrack, lineWidth: stroke)
            Text("Unscored")
                .font(.sageFixedBold(10))
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.inkSecondary)
                .padding(.horizontal, 4)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text("Unscored"))
    }

    private func scoredRing(_ score: Int) -> some View {
        let style = Self.style(for: score)
        return ZStack {
            Circle().stroke(Theme.ringTrack, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(style.color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(score)")
                    .font(.sageFixedBold(13))
                    .monospacedDigit()
                    .foregroundColor(Theme.ink)
                Text(style.label)
                    .font(.sageFixedMedium(10))
                    .foregroundColor(Theme.inkSecondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(score), \(style.label)")
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
    /// Secondary photo tried when `imageURL` fails (Top Rated / Alternatives
    /// rows whose backend slot 404s degrade to their OFF photo, not the glyph).
    var fallbackImageURL: String? = nil
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
            fallbackURL: fallbackImageURL.flatMap(URL.init(string:)),
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
    var horizontalPadding: CGFloat = 24
    var body: some View {
        Text(text)
            .font(.sageBold(12))
            .tracking(-0.1)
            .foregroundColor(Theme.inkSecondary)
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 14).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var horizontalPadding: CGFloat = 24
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.sageBold(18))
                .tracking(-0.4)
                .foregroundColor(Theme.ink)
            if let sub = subtitle {
                Text(sub)
                    .font(.sageRegular(12))
                    .foregroundColor(Theme.inkSecondary)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 20).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tab bar

/// Tab cases drive `TabView` selection. `.scan` is an action tab — selecting it
/// opens the camera, then selection snaps back to the previous content tab
/// (see `ContentView.restoreContentTab`). Never leave selection on `.scan`:
/// its page is empty and reads as a blank white screen. The system handles
/// selected/filled symbol variants, so there's no `activeIcon` to maintain.
enum AppTab: String, CaseIterable {
    case home, topRated, scan, pantry, you

    var label: String {
        switch self {
        case .home:     return "Home"
        case .topRated: return "Top Rated"
        case .scan:     return "Scan"
        case .pantry:   return "Pantry"
        case .you:      return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home:     return "house"
        case .topRated: return "trophy"
        case .scan:     return "barcode.viewfinder"
        case .pantry:   return "list.bullet"
        case .you:      return "person"
        }
    }
}

// MARK: - Chip

struct ChipView: View {
    let label: String
    let active: Bool
    let accent: Color
    var action: () -> Void = {}

    private static let idle = Color(light: Theme.bgLight, dark: Color.white.opacity(0.05))
    private static let idleStroke = Color(light: .black.opacity(0.08),
                                          dark: .white.opacity(0.08))

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if active {
                    Image(systemName: "checkmark")
                        .font(.sageBold(10))
                        .foregroundColor(accent)
                }
                Text(label)
                    .font(.sageBold(12))
                    .tracking(-0.1)
                    .foregroundColor(active ? accent : Theme.ink)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(active ? accent.opacity(0.10) : Self.idle))
            .overlay(Capsule().stroke(active ? accent : Self.idleStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
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
    var padding: EdgeInsets = EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .stroke(Theme.cardEdge, lineWidth: 0.5)
            )
            .cardShadow()
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

/// Cold-start splash: app background + centered logo mark (no wordmark).
struct SplashView: View {
    var accent: Color = Theme.accent

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            SageMark(size: 88, color: accent)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Native chrome helpers

/// The wordmark, shown centered in a pushed screen's navigation bar.
/// `ToolbarContent` rather than a hand-built HStack, so the system owns the
/// centering, the back button, and the scroll-edge treatment.
struct SageToolbarTitle: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                SageMark(size: 28, color: Theme.accent)
                Text("Sage")
                    .font(.sageBold(24)).tracking(-0.6)
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("Sage")
        }
    }
}

extension View {
    /// Brand page background behind non-List content.
    func sageScreenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }

    /// Inset-grouped `List` on the brand background: system row chrome,
    /// separators, and swipe behavior, Sage's page color.
    func sageListStyle() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
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


// MARK: - Underline tabs & filter chips
//
// Two small primitives that replace the stacked segmented pickers on Pantry.
// A top-level mode switch reads as underline tabs (the App Store / Instagram /
// Spotify pattern); a secondary filter reads as a row of capsule chips (Airbnb,
// Uber Eats). Both animate selection with a spring and fire a selection haptic.

struct SageUnderlineTabs<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item
    @Namespace private var underline

    var body: some View {
        // Equal columns, label centered in each, underline spanning the column
        // — the two tabs mirror each other exactly around the screen's center.
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let on = item == selection
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        selection = item
                    }
                } label: {
                    VStack(spacing: 10) {
                        Text(title(item))
                            .font(.sageBold(16)).tracking(-0.3)
                            .foregroundStyle(on ? Theme.ink : Theme.inkSecondary)
                        ZStack {
                            Capsule().fill(Color.clear).frame(height: 3)
                            if on {
                                Capsule().fill(Theme.accent).frame(height: 3)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Capsule filter chip — filled ink when selected, quiet outline otherwise.
/// The optional count sits after the label in tabular figures so chips don't
/// jitter as numbers change.
struct SageChip: View {
    let title: String
    var count: Int? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.sageSemiBold(14)).tracking(-0.2)
                if let count {
                    Text("\(count)")
                        .font(.sageSemiBold(13)).monospacedDigit()
                        .opacity(0.7)
                }
            }
            .foregroundStyle(selected ? Theme.background : Theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(selected ? Theme.ink : Theme.card))
            .overlay(Capsule().stroke(selected ? Color.clear : Theme.outline, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
    }
}
