import SwiftUI

// MARK: - Progress bar

/// Brand green used on the progress bar and the scores-screen tip banner.
/// Slightly darker / more muted than the app `accent` so the bar reads as
/// chrome rather than competing with active accents inside the screens.
let OnboardingBrandGreen = Color(hex: "2D6A4F")

struct OnboardingProgressBar: View {
    let progress: Double // 0...1
    let dark: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                Capsule()
                    .fill(OnboardingBrandGreen)
                    .frame(width: geo.size.width * max(0, min(1, CGFloat(progress))))
                    .animation(.easeInOut(duration: 0.35), value: progress)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Chromed header (back + progress + optional skip)

struct OnboardingHeader: View {
    let step: OnboardingStep
    let dark: Bool
    let onBack: () -> Void
    let onSkip: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary(dark))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    )
                    .minHitArea(44) // visible 36, lift to 44 for WCAG
            }
            .buttonStyle(.pressable)
            .opacity(step.rawValue > 1 ? 1 : 0.45)
            .disabled(step.rawValue <= 1)

            OnboardingProgressBar(progress: step.progress, dark: dark)

            if step.allowsSkip, let onSkip {
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textSecondary(dark))
                        .padding(.vertical, 10).padding(.leading, 10)
                        .minHitArea(44)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 20)
        // 12pt above the system safe-area inset. OnboardingFlow's VStack
        // already respects the inset (only the background ignores it), so
        // adding 60pt here was stacking on top of the status-bar reserve.
        .padding(.top, 12)
        .padding(.bottom, 18)
    }
}

// MARK: - Title block

struct OnboardingTitle: View {
    let title: String
    let subtitle: String?
    let dark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 28, weight: .heavy)).tracking(-0.7)
                .foregroundColor(Theme.textPrimary(dark))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundColor(Theme.textSecondary(dark))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }
}

// MARK: - Section eyebrow used by interactive steps

struct OnboardingEyebrow: View {
    let text: String
    let dark: Bool

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy)).tracking(1.4)
            .foregroundColor(Theme.textSecondary(dark))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
    }
}

// MARK: - Primary CTA (full-width black pill)

struct OnboardingCTAButton: View {
    let title: String
    let dark: Bool
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .heavy)).tracking(-0.2)
                // Locked to white on black across the entire onboarding,
                // regardless of dark mode. Onboarding's CTA must read as
                // the same neutral primary action on every step — not flip
                // to a white pill mid-flow.
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    Capsule().fill(Color.black)
                )
                .opacity(enabled ? 1 : 0.45)
                .animation(.easeOut(duration: 0.18), value: enabled) // soft enable/disable
        }
        // Static when disabled — pressing a disabled CTA shouldn't react.
        .buttonStyle(enabled ? PressableButtonStyle() : PressableButtonStyle(isStatic: true))
        .disabled(!enabled)
    }
}

struct OnboardingGhostButton: View {
    let title: String
    let dark: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textSecondary(dark))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10) // bumped from 6 → 10 for thumb reach
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Selectable grid card (preferences, symptoms)

struct OnboardingSelectionCard: View {
    let emoji: String?
    let title: String
    let subtitle: String?
    let selected: Bool
    let dark: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    if let emoji {
                        Text(emoji).font(.system(size: 24))
                    }
                    Spacer(minLength: 0)
                    // Contextual icon: empty ring → filled check with a smooth
                    // scale+opacity swap. Reads as a single icon morphing rather
                    // than two views snapping in/out.
                    ZStack {
                        Circle()
                            .stroke(dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12), lineWidth: 1.4)
                            .frame(width: 22, height: 22)
                            .opacity(selected ? 0 : 1)
                            .scaleEffect(selected ? 0.7 : 1)
                        ZStack {
                            Circle().fill(accent).frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.white)
                        }
                        .opacity(selected ? 1 : 0)
                        .scaleEffect(selected ? 1 : 0.6)
                    }
                    .animation(.spring(response: 0.32, dampingFraction: 0.7), value: selected)
                }
                Text(title)
                    .font(.system(size: 15, weight: .heavy)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary(dark))
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(14)
            .background(
                // Concentric: outer card is 18 → keep stroke/overlay matching.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.surface(dark))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? accent : Color.clear, lineWidth: 2)
            )
            .cardShadow(dark)
        }
        .buttonStyle(.pressable)
        .animation(.easeOut(duration: 0.18), value: selected)
    }
}

// MARK: - Diet & allergen pills (onboarding-specific styling)

/// Pill used on the dietary-restrictions screen. Selected = brand green,
/// no border; unselected = white + light gray stroke.
struct OnboardingDietPill: View {
    let label: String
    let selected: Bool
    let dark: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .heavy)).tracking(-0.2)
                .foregroundColor(selected ? .white : Theme.textPrimary(dark))
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(
                    Capsule().fill(selected ? OnboardingBrandGreen : Theme.surface(dark))
                )
                .overlay(
                    Capsule().stroke(
                        selected ? Color.clear : Color.black.opacity(0.10),
                        lineWidth: 1
                    )
                )
                .animation(.easeOut(duration: 0.18), value: selected)
        }
        .buttonStyle(.pressable)
    }
}

/// Grid cell for the allergens screen — rounded rect, not a pill.
struct OnboardingAllergenCell: View {
    let label: String
    let selected: Bool
    let dark: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .heavy)).tracking(-0.2)
                .foregroundColor(selected ? .white : Theme.textPrimary(dark))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? OnboardingBrandGreen : Theme.surface(dark))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(selected ? Color.clear : Color.black.opacity(0.10), lineWidth: 1)
                )
                .animation(.easeOut(duration: 0.18), value: selected)
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Selectable chip (age range, sex, life stage)

struct OnboardingChip: View {
    let label: String
    let selected: Bool
    let dark: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .heavy)).tracking(-0.2)
                .foregroundColor(selected ? .white : Theme.textPrimary(dark))
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(
                    Capsule().fill(selected
                                   ? accent
                                   : (dark ? Color.white.opacity(0.06) : Color.white))
                )
                .overlay(
                    Capsule().stroke(
                        selected ? accent : (dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)),
                        lineWidth: 1
                    )
                )
                .cardShadow(dark)
                .animation(.easeOut(duration: 0.18), value: selected)
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Flow layout that wraps chips onto multiple lines

struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8
    var runSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + runSpacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + runSpacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Bundled onboarding illustrations
//
// Drop PNGs into Assets.xcassets. Each imageset name matches the
// constant below — e.g. onboarding-marketing-hero.png →
// onboarding-marketing-hero.imageset.

enum OnboardingAssets {
    /// Marketing step hero (phone + product scan illustration).
    static let marketingHero = "onboarding-marketing-hero"
}

/// Full-width hero illustration slot. Scales to fit the space it's given;
/// add your PNG to the matching imageset in Assets.xcassets.
struct OnboardingHeroImage: View {
    let assetName: String
    let dark: Bool
    var scale: CGFloat = 1
    var horizontalPadding: CGFloat = 8

    var body: some View {
        Group {
            if UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale, anchor: .top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.10),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.system(size: 22, weight: .medium))
                            Text("Add \(assetName).png")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Theme.textSecondary(dark))
                    )
            }
        }
        .padding(.horizontal, horizontalPadding)
    }
}

// MARK: - Phone illustration used on the welcome screen

struct PhoneShowcase: View {
    let dark: Bool
    let accent: Color

    var body: some View {
        ZStack {
            // Phone body
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(Color(hex: "26201A"))
                .frame(width: 200, height: 260)
                .overlay(
                    Capsule()
                        .fill(Color.black)
                        .frame(width: 80, height: 22)
                        .padding(.top, 10),
                    alignment: .top
                )

            // Product mock card
            VStack(spacing: 0) {
                Spacer().frame(height: 6)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: "F5F0E6"))
                    .frame(width: 88, height: 116)
                    .overlay(
                        VStack(spacing: 6) {
                            Capsule().fill(Color(hex: "B7A786")).frame(width: 56, height: 6)
                            Text("HILLTOP")
                                .font(.system(size: 10, weight: .black)).tracking(1.2)
                            Text("GREEK\nYOGURT")
                                .font(.system(size: 10, weight: .black))
                                .multilineTextAlignment(.center)
                                .lineSpacing(0)
                            barcode
                        }
                        .padding(.top, 22)
                        .foregroundColor(.black)
                    )
            }

            // Floating chips
            VStack {
                HStack {
                    floatingChip(emoji: "•", title: "17g protein",
                                 subtitle: "High-protein goal", trailingCheck: true)
                    Spacer()
                }
                .padding(.leading, -6)

                Spacer().frame(height: 20)

                HStack {
                    Spacer()
                    floatingChip(emoji: "•", title: "2 ingredients",
                                 subtitle: "Whole foods", trailingCheck: false)
                }
                .padding(.trailing, -6)

                Spacer().frame(height: 30)

                HStack {
                    floatingChip(emoji: "•", title: "0 additives",
                                 subtitle: "Nothing flagged", trailingCheck: false)
                    Spacer()
                }
                .padding(.leading, -8)

                Spacer().frame(height: 6)
            }
            .frame(width: 280, height: 240)
        }
        .frame(width: 280, height: 280)
    }

    private var barcode: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<22, id: \.self) { i in
                Rectangle()
                    .fill(Color.black)
                    .frame(width: i % 3 == 0 ? 2.2 : 1, height: 22)
            }
        }
    }

    private func floatingChip(emoji: String, title: String,
                               subtitle: String, trailingCheck: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(accent).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 12, weight: .heavy)).tracking(-0.2)
                    .foregroundColor(.black)
                Text(subtitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(accent)
            }
            if trailingCheck {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(accent)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 4)
    }
}
