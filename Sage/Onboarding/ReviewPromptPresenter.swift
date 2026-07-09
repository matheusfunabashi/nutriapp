import StoreKit
import UIKit

// MARK: - Review prompt
//
// StoreKit exposes no completion handler for in-app review. We request the
// prompt, detect when it is actually on screen, then advance shortly after it
// disappears. Detection is limited to StoreKit review UI only — generic window
// or presentation diffs caused false positives and kept users waiting ~15s.

enum ReviewPromptPresenter {
    @MainActor
    static func requestThenContinue(onComplete: @escaping () -> Void) {
        guard let scene = activeWindowScene() else {
            onComplete()
            return
        }

        SKStoreReviewController.requestReview(in: scene)

        // Give StoreKit a moment to present before we start watching.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            watchForDismissal(in: scene, onComplete: onComplete)
        }
    }

    // MARK: - Monitoring

    @MainActor
    private static func watchForDismissal(
        in scene: UIWindowScene,
        onComplete: @escaping () -> Void
    ) {
        var sawPrompt = false
        var absentStreak = 0
        var ticks = 0

        let interval: TimeInterval = 0.08
        // ~160ms stable absence after the prompt was seen.
        let absentThreshold = 2
        // ~2.4s with no prompt → rate-limited this session.
        let noPromptLimit = 30
        // Safety cap ~6s after the prompt appeared.
        let postPromptLimit = 75

        func finish() {
            onComplete()
        }

        func poll() {
            ticks += 1
            let visible = isStoreReviewPromptVisible(in: scene)

            if visible {
                sawPrompt = true
                absentStreak = 0
            } else if sawPrompt {
                absentStreak += 1
                if absentStreak >= absentThreshold {
                    finish()
                    return
                }
            } else if ticks >= noPromptLimit {
                finish()
                return
            }

            if sawPrompt, ticks >= postPromptLimit {
                finish()
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: poll)
        }

        poll()
    }

    // MARK: - Detection

    /// True only when StoreKit's review UI is actively presented.
    private static func isStoreReviewPromptVisible(in scene: UIWindowScene) -> Bool {
        for window in scene.windows where !window.isHidden && window.alpha > 0.01 {
            let windowType = String(describing: type(of: window))
            if windowType.localizedCaseInsensitiveContains("storeproductreview") ||
               windowType.localizedCaseInsensitiveContains("storereview") {
                return true
            }

            if reviewSurface(in: window.rootViewController) != nil {
                return true
            }
        }
        return false
    }

    private static func reviewSurface(in root: UIViewController?) -> UIViewController? {
        walkControllers(from: root) { name in
            name.localizedCaseInsensitiveContains("storeproductreview") ||
            name.localizedCaseInsensitiveContains("storereview") ||
            name.localizedCaseInsensitiveContains("skstorereview") ||
            name.localizedCaseInsensitiveContains("star rating") ||
            name.contains("UIAlertController")
        }
    }

    private static func walkControllers(
        from root: UIViewController?,
        matching: (String) -> Bool
    ) -> UIViewController? {
        guard let root else { return nil }
        var stack: [UIViewController] = [root]
        while let vc = stack.popLast() {
            let name = String(describing: type(of: vc))
            if matching(name) { return vc }
            stack.append(contentsOf: vc.children)
            if let presented = vc.presentedViewController {
                stack.append(presented)
            }
        }
        return nil
    }

    @MainActor
    private static func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}
