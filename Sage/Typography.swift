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
    static let sageDisplay = Font.custom(SageTypeface.bold, size: 34)
    /// Section heroes and primary CTAs (e.g. "Tap to scan").
    static let sageHeadline = Font.custom(SageTypeface.bold, size: 28)
    /// Card titles, section headers, nav titles.
    static let sageTitle = Font.custom(SageTypeface.semiBold, size: 20)
    /// Body copy and descriptions.
    static let sageBody = Font.custom(SageTypeface.regular, size: 16)
    /// Labels, secondary emphasis, tab bar.
    static let sageLabel = Font.custom(SageTypeface.medium, size: 14)
    /// Captions, footnotes, metadata.
    static let sageCaption = Font.custom(SageTypeface.regular, size: 12)
    /// Primary buttons.
    static let sageButton = Font.custom(SageTypeface.semiBold, size: 16)

    // Sized variants — use when a screen needs an exact pixel size from the
    // current layout (typography-only swaps without changing metrics).

    static func sageRegular(_ size: CGFloat) -> Font {
        .custom(SageTypeface.regular, size: size)
    }
    static func sageMedium(_ size: CGFloat) -> Font {
        .custom(SageTypeface.medium, size: size)
    }
    static func sageSemiBold(_ size: CGFloat) -> Font {
        .custom(SageTypeface.semiBold, size: size)
    }
    static func sageBold(_ size: CGFloat) -> Font {
        .custom(SageTypeface.bold, size: size)
    }
}
