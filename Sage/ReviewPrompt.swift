import Foundation
#if canImport(StoreKit) && canImport(UIKit)
import StoreKit
import UIKit
#endif

// MARK: - Review prompt
//
// App Review guideline 5.6.3 forbids soliciting ratings outside of genuine
// engagement — the onboarding-time ask (and the fake 5-star testimonial screen
// that fronted it) got the app rejected and is gone. The system prompt now
// fires only after the user has actually used the app:
//
//   • at least `minimumScans` completed scans, and
//   • a later session than the one they installed in (launch count > 1), and
//   • at least a day since first launch,
//   • and never more than once per app version.
//
// StoreKit applies its own annual cap on top of this and may show nothing at
// all; the prompt is fire-and-forget by design and the app never reacts to it.

enum ReviewPrompt {
    private static let minimumScans = 3
    private static let minimumAgeSinceFirstLaunch: TimeInterval = 24 * 60 * 60

    private enum Key {
        static let scanCount = "review.scanCount"
        static let firstLaunchDate = "review.firstLaunchDate"
        static let launchCount = "review.launchCount"
        static let lastPromptedVersion = "review.lastPromptedVersion"
    }

    private static var defaults: UserDefaults { .standard }

    // MARK: - Engagement tracking

    /// Called once per cold start. Stamps the install date on first run and
    /// counts sessions, so "a session after their first" is checkable.
    static func registerLaunch() {
        if defaults.object(forKey: Key.firstLaunchDate) == nil {
            defaults.set(Date.now, forKey: Key.firstLaunchDate)
        }
        defaults.set(defaults.integer(forKey: Key.launchCount) + 1,
                     forKey: Key.launchCount)
    }

    /// Called on every completed scan lookup.
    static func recordScan() {
        defaults.set(defaults.integer(forKey: Key.scanCount) + 1, forKey: Key.scanCount)
    }

    // MARK: - Gate

    static var hasEarnedPrompt: Bool {
        guard defaults.integer(forKey: Key.scanCount) >= minimumScans else { return false }
        guard defaults.integer(forKey: Key.launchCount) > 1 else { return false }
        guard let first = defaults.object(forKey: Key.firstLaunchDate) as? Date,
              Date.now.timeIntervalSince(first) >= minimumAgeSinceFirstLaunch
        else { return false }
        return defaults.string(forKey: Key.lastPromptedVersion) != currentVersion
    }

    /// Asks StoreKit for the review sheet if — and only if — the gate is met.
    /// Safe to call after any successful scan; no-ops otherwise.
    @MainActor
    static func requestIfEarned() {
        guard hasEarnedPrompt else { return }
        #if canImport(StoreKit) && canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }
        defaults.set(currentVersion, forKey: Key.lastPromptedVersion)
        // Module-qualified: the app has its own `AppStore` observable object.
        StoreKit.AppStore.requestReview(in: scene)
        #endif
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
