import SwiftUI

// MARK: - Progress bar

/// Brand green used on the progress bar and the scores-screen tip banner.
/// Slightly darker / more muted than the app `accent` so the bar reads as
/// chrome rather than competing with active accents inside the screens.
let OnboardingBrandGreen = Color(hex: "2D6A4F")

// MARK: - Chromed header (back + progress + optional skip)
//
// The bar itself is a stock `ProgressView` — it gets the system's easing,
// its accessibility value, and Reduce Motion handling for free. Only the
// surrounding row is ours, because it has to invert on the dark steps.

struct OnboardingHeader: View {
    let step: OnboardingStep
    let onBack: () -> Void
    let onSkip: (() -> Void)?

    /// White-on-green for the inverted steps, normal ink elsewhere.
    private var tint: Color { step.isInverted ? .white : Theme.ink }
    private var secondary: Color {
        step.isInverted ? Color.white.opacity(0.6) : Theme.inkSecondary
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.sageSemiBold(15))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(step.isInverted ? Color.white.opacity(0.12)
                                                      : Color.black.opacity(0.05))
                    )
                    .minHitArea(44) // visible 36, lift to 44 for WCAG
            }
            .buttonStyle(.pressable)
            .opacity(step.rawValue > 1 ? 1 : 0.45)
            .disabled(step.rawValue <= 1)
            .accessibilityLabel("Back")

            ProgressView(value: max(0, min(1, step.progress)))
                .progressViewStyle(.linear)
                .tint(step.isInverted ? .white : OnboardingBrandGreen)
                .animation(.easeInOut(duration: 0.35), value: step.progress)
                .accessibilityLabel("Onboarding progress")

            if step.allowsSkip, let onSkip {
                Button("Skip", action: onSkip)
                    .font(.sageSemiBold(14))
                    .foregroundStyle(secondary)
                    .padding(.vertical, 10).padding(.leading, 10)
                    .minHitArea(44)
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
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.sageHeadline).tracking(-0.7)
                .foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            if let subtitle {
                Text(subtitle)
                    .font(.sageRegular(15))
                    .lineSpacing(3)
                    .foregroundColor(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}

// MARK: - Primary CTA (full-width black pill)

struct OnboardingCTAButton: View {
    let title: String
    var enabled: Bool = true
    /// Inverted steps flip to a white pill with dark text so the CTA keeps
    /// the same visual weight against the dark-green background.
    var inverted: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// The pill must contrast with whatever ground it sits on: dark pill on
    /// the light background, light pill on the dark background or the
    /// inverted green steps. A black pill in dark mode disappears.
    private var flipped: Bool { inverted || colorScheme == .dark }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.sageBold(16)).tracking(-0.2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(flipped ? .white : .black)
        .foregroundStyle(flipped ? Color.black : Color.white)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .animation(.easeOut(duration: 0.18), value: enabled) // soft enable/disable
        .sensoryFeedback(.selection, trigger: enabled)
    }
}

struct OnboardingGhostButton: View {
    let title: String
    var inverted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.sageSemiBold(14))
            .foregroundStyle(inverted ? Color.white.opacity(0.7) : Theme.inkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10) // bumped from 6 → 10 for thumb reach
            .contentShape(Rectangle())
            .buttonStyle(.pressable)
    }
}

// MARK: - Selectable list row
//
// The workhorse of the new question steps. Competitors all converge on the
// same shape — symbol in a tinted circle, label, trailing state — and it's
// what a `List` row wants to be anyway, so this stays a plain `Label`-ish
// row and lets the enclosing `List` supply insets, separators and the
// press highlight.

struct OnboardingChoiceRow: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    let selected: Bool
    /// Multi-select rows show a checkmark; single-select rows that advance
    /// on tap show a chevron instead, which reads as "this goes somewhere".
    var showsChevron: Bool = false
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.sageSemiBold(15))
                    .foregroundStyle(selected ? .white : accent)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(selected ? accent : accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.sageBold(15)).tracking(-0.2)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.sageRegular(12))
                            .foregroundStyle(Theme.inkSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.sageSemiBold(13))
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    // The system checkmark is how iOS shows a chosen row;
                    // a custom radio would only look foreign here.
                    Image(systemName: "checkmark")
                        .font(.sageBold(14))
                        .foregroundStyle(accent)
                        .opacity(selected ? 1 : 0)
                        .scaleEffect(selected ? 1 : 0.6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7),
                                   value: selected)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - List styling for question steps

extension View {
    /// `sageListStyle` plus room to scroll clear of the pinned CTA.
    ///
    /// The flow lays the footer out *below* the screen body, so a `List` that
    /// ends flush with its own bounds leaves the last section footer tucked
    /// under the Continue pill with no way to scroll it into view.
    ///
    /// Top margin is zeroed so a section-header title sits flush with the
    /// chrome above instead of floating in the default inset-grouped band.
    func onboardingListStyle() -> some View {
        sageListStyle()
            .contentMargins(.top, 0, for: .scrollContent)
            .contentMargins(.bottom, 16, for: .scrollContent)
            .listSectionSpacing(12)
    }

    /// Strip the system section-header chrome (uppercase, secondary tint,
    /// extra vertical padding) so an `OnboardingTitle` can live inside a
    /// `Section` header without a dead band above the rows.
    func onboardingListHeader() -> some View {
        self
            .textCase(nil)
            // List headers inherit the row's leading inset; the title already
            // pads itself to 24pt, so undo the double inset.
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Inverted-step scaffolding
//
// `howItWorks` and `pledge` sit on the same dark green the results screen
// already uses, so white text and a translucent surface are hard-coded
// rather than resolved from the color scheme.

enum OnboardingInverted {
    static let background = Color(hex: "0B2A1F")
    static let surface = Color(hex: "133A2C")
    static let ink = Color.white
    static let inkSecondary = Color.white.opacity(0.65)
}

struct OnboardingInvertedTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.sageHeadline).tracking(-0.7)
                .foregroundStyle(OnboardingInverted.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.sageRegular(15))
                    .lineSpacing(3)
                    .foregroundStyle(OnboardingInverted.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }
}

// MARK: - Bundled onboarding illustrations
//
// Drop PNGs into Assets.xcassets. Each imageset name matches the
// constant below — e.g. onboarding-marketing-hero.png →
// onboarding-marketing-hero.imageset.

enum OnboardingAssets {
    /// Welcome step hero (replaces the hand-drawn phone mockup).
    static let welcomeHero = "onboarding-img-1"
    /// Marketing step hero (phone + product scan illustration).
    static let marketingHero = "onboarding-marketing-hero"
}

/// Full-width hero illustration slot. Scales to fit the space it's given;
/// add your PNG to the matching imageset in Assets.xcassets.
struct OnboardingHeroImage: View {
    let assetName: String
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
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Color.black.opacity(0.10),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.sageMedium(22))
                            Text("Add \(assetName).png")
                                .font(.sageSemiBold(12))
                        }
                        .foregroundColor(Theme.inkSecondary)
                    )
            }
        }
        .padding(.horizontal, horizontalPadding)
    }
}
