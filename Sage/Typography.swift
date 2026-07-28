import SwiftUI

// MARK: - DM Sans PostScript names (verified via UIAppFonts registration)

enum SageTypeface {
    static let regular = "DMSans-Regular"
    static let medium = "DMSans-Medium"
    static let semiBold = "DMSans-SemiBold"
    static let bold = "DMSans-Bold"
    static let italic = "DMSans-Italic"
    static let boldItalic = "DMSans-BoldItalic"
}

// MARK: - Semantic text styles

extension Font {
    /// Large marketing / hero headlines (e.g. "What are you eating?").
    static let sageDisplay = Font.custom(SageTypeface.bold, size: 34, relativeTo: .largeTitle)
    /// Section heroes and primary CTAs (e.g. "Tap to scan").
    static let sageHeadline = Font.custom(SageTypeface.bold, size: 28, relativeTo: .title)
    /// Card titles, section headers, nav titles.
    static let sageTitle = Font.custom(SageTypeface.semiBold, size: 20, relativeTo: .title3)
    /// Body copy and descriptions.
    static let sageBody = Font.custom(SageTypeface.regular, size: 16, relativeTo: .body)
    /// Labels, secondary emphasis, tab bar.
    static let sageLabel = Font.custom(SageTypeface.medium, size: 14, relativeTo: .subheadline)
    /// Captions, footnotes, metadata.
    static let sageCaption = Font.custom(SageTypeface.regular, size: 12, relativeTo: .caption)
    /// Primary buttons.
    static let sageButton = Font.custom(SageTypeface.semiBold, size: 16, relativeTo: .body)

    // Sized variants — use when a screen needs an exact point size from the
    // current layout (typography-only swaps without changing metrics).
    //
    // Every one is anchored to a system text style via `relativeTo:`, so the
    // whole app tracks the user's Dynamic Type setting. Without it,
    // `Font.custom(_:size:)` opts out of scaling entirely.

    /// Maps a design point size onto the nearest system text style, so a 34pt
    /// title scales like `.largeTitle` and an 11pt eyebrow like `.caption2`.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11:   return .caption2
        case ..<13:   return .caption
        case ..<14:   return .footnote
        case ..<15:   return .subheadline
        case ..<17:   return .callout
        case ..<20:   return .body
        case ..<22:   return .title3
        case ..<28:   return .title2
        case ..<34:   return .title
        default:      return .largeTitle
        }
    }

    static func sageRegular(_ size: CGFloat) -> Font {
        .custom(SageTypeface.regular, size: size, relativeTo: textStyle(for: size))
    }
    static func sageMedium(_ size: CGFloat) -> Font {
        .custom(SageTypeface.medium, size: size, relativeTo: textStyle(for: size))
    }
    static func sageSemiBold(_ size: CGFloat) -> Font {
        .custom(SageTypeface.semiBold, size: size, relativeTo: textStyle(for: size))
    }
    static func sageBold(_ size: CGFloat) -> Font {
        .custom(SageTypeface.bold, size: size, relativeTo: textStyle(for: size))
    }

    /// Opts *out* of Dynamic Type. Only for glyphs whose container is a fixed
    /// geometric shape — the number inside a score ring, where scaling the text
    /// past the circle would look broken rather than accessible. The ring's own
    /// accessibility label carries the value for VoiceOver.
    static func sageFixedBold(_ size: CGFloat) -> Font {
        .custom(SageTypeface.bold, fixedSize: size)
    }
    static func sageFixedMedium(_ size: CGFloat) -> Font {
        .custom(SageTypeface.medium, fixedSize: size)
    }
}
