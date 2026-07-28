import SwiftUI

@main
struct SageApp: App {
    @StateObject private var store = AppStore()
    @State private var showSplash = true

    init() {
        // AsyncImage uses URLSession.shared → URLCache.shared. Size the disk
        // cache so list scrolling doesn't refetch product thumbs every time.
        URLCache.shared = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 50 * 1024 * 1024,
            diskPath: "sage_image_cache"
        )
        Self.configureNavigationBarTypography()
    }

    /// The navigation bar is UIKit-backed, so `.font(.sage…)` can't reach its
    /// titles. Registering the typeface here is what lets us use real system
    /// nav bars — large-title collapse, back button, scroll-edge blur — while
    /// the wordmark and section titles stay in DM Sans.
    private static func configureNavigationBarTypography() {
        guard let large = UIFont(name: SageTypeface.bold, size: 32),
              let inline = UIFont(name: SageTypeface.semiBold, size: 17) else { return }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.largeTitleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large),
            .kern: -1,
        ]
        appearance.titleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline),
            .kern: -0.4,
        ]
        let scrollEdge = appearance.copy()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.largeTitleTextAttributes = appearance.largeTitleTextAttributes
        scrollEdge.titleTextAttributes = appearance.titleTextAttributes

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = scrollEdge
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(store)

                if showSplash {
                    SplashView(accent: store.accent)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            // nil when the user picked "System" — the app then follows the
            // device instead of being pinned to one scheme.
            .preferredColorScheme(store.colorScheme)
            // Type scales with the user's setting up to accessibility2. Past
            // that, score dials and nutrient tables stop being readable rather
            // than more readable, so the ceiling is deliberate.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .onAppear {
                // Brief hold so the system launch screen → in-app splash feels continuous.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        showSplash = false
                    }
                }
            }
        }
    }
}
