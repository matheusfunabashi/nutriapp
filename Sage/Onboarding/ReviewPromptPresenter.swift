import StoreKit
import UIKit

// MARK: - Review prompt
//
// Wraps SKStoreReviewController so onboarding advances only after the user
// dismisses the system sheet. Apple exposes no completion handler, so we
// snapshot the window hierarchy, request the prompt, then poll until a
// review/alert presentation appears *stably* and later disappears *stably*.
// Debouncing prevents a single false-positive poll from skipping ahead.

enum ReviewPromptPresenter {
    @MainActor
    static func requestThenContinue(onComplete: @escaping () -> Void) {
        guard let scene = activeWindowScene() else {
            onComplete()
            return
        }

        let baseline = SceneSnapshot.capture(in: scene)

        SKStoreReviewController.requestReview(in: scene)

        // Give StoreKit a beat to mount its window before we start polling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            monitorUntilResolved(
                scene: scene,
                baseline: baseline,
                onComplete: onComplete
            )
        }
    }

    // MARK: - Monitoring

    @MainActor
    private static func monitorUntilResolved(
        scene: UIWindowScene,
        baseline: SceneSnapshot,
        onComplete: @escaping () -> Void
    ) {
        var phase: Phase = .waitingForPrompt
        var visibleStreak = 0
        var hiddenStreak = 0
        var ticks = 0

        let interval: TimeInterval = 0.12
        // Require ~360ms stable visibility before we trust the prompt is up.
        let visibleThreshold = 3
        // Require ~480ms stable absence after it was up before we advance.
        let hiddenThreshold = 4
        // ~5s with no prompt → Apple rate-limited this session; move on.
        let noPromptTicks = 42
        // Hard cap ~15s so we never strand the user.
        let maxTicks = 125

        enum Phase {
            case waitingForPrompt
            case promptShowing
        }

        func poll() {
            ticks += 1
            let visible = isReviewPromptVisible(in: scene, comparedTo: baseline)

            switch phase {
            case .waitingForPrompt:
                if visible {
                    visibleStreak += 1
                    hiddenStreak = 0
                    if visibleStreak >= visibleThreshold {
                        phase = .promptShowing
                    }
                } else {
                    visibleStreak = 0
                    if ticks >= noPromptTicks {
                        onComplete()
                        return
                    }
                }

            case .promptShowing:
                if visible {
                    hiddenStreak = 0
                } else {
                    hiddenStreak += 1
                    if hiddenStreak >= hiddenThreshold {
                        onComplete()
                        return
                    }
                }
            }

            if ticks >= maxTicks {
                onComplete()
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: poll)
        }

        poll()
    }

    // MARK: - Detection

    private struct SceneSnapshot: Equatable {
        let visibleWindowCount: Int
        let presentedTypePaths: [[String]]

        static func capture(in scene: UIWindowScene) -> SceneSnapshot {
            let windows = scene.windows.filter { !$0.isHidden && $0.alpha > 0.01 }
            let paths = windows.compactMap { presentedTypePath(from: $0.rootViewController) }
            return SceneSnapshot(
                visibleWindowCount: windows.count,
                presentedTypePaths: paths
            )
        }
    }

    /// True when the scene looks like it is hosting the StoreKit review UI.
    private static func isReviewPromptVisible(
        in scene: UIWindowScene,
        comparedTo baseline: SceneSnapshot
    ) -> Bool {
        let current = SceneSnapshot.capture(in: scene)

        if current.visibleWindowCount > baseline.visibleWindowCount {
            return true
        }

        for window in scene.windows where !window.isHidden && window.alpha > 0.01 {
            if reviewController(in: window.rootViewController) != nil {
                return true
            }

            let windowType = String(describing: type(of: window))
            if windowType.localizedCaseInsensitiveContains("storeproductreview") ||
               windowType.localizedCaseInsensitiveContains("storereview") {
                return true
            }
        }

        // New modal presentations compared to the pre-request snapshot.
        if current.presentedTypePaths != baseline.presentedTypePaths {
            for window in scene.windows where !window.isHidden && window.alpha > 0.01 {
                if reviewController(in: window.rootViewController) != nil ||
                   alertController(in: window.rootViewController) != nil {
                    return true
                }
            }
        }

        return false
    }

    private static func presentedTypePath(from root: UIViewController?) -> [String]? {
        guard let root else { return nil }
        var path: [String] = []
        var current: UIViewController? = root
        while let vc = current {
            path.append(String(describing: type(of: vc)))
            guard let next = vc.presentedViewController else { break }
            current = next
        }
        return path.isEmpty ? nil : path
    }

    private static func reviewController(in root: UIViewController?) -> UIViewController? {
        walkControllers(from: root) { name in
            name.localizedCaseInsensitiveContains("storeproductreview") ||
            name.localizedCaseInsensitiveContains("storereview") ||
            name.localizedCaseInsensitiveContains("skstorereview") ||
            name.localizedCaseInsensitiveContains("star rating")
        }
    }

    private static func alertController(in root: UIViewController?) -> UIViewController? {
        walkControllers(from: root) { name in
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
