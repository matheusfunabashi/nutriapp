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
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(store)
                    .preferredColorScheme(store.darkMode ? .dark : .light)

                if showSplash {
                    SplashView(dark: store.darkMode, accent: store.accent)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
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
