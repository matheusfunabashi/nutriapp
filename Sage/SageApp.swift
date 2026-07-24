import SwiftUI

@main
struct SageApp: App {
    @StateObject private var store = AppStore()

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
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(store.darkMode ? .dark : .light)
        }
    }
}
