import SwiftUI

@main
struct SageApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(store.darkMode ? .dark : .light)
        }
    }
}
