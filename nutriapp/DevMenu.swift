import SwiftUI

// MARK: - Public surface
//
// `debugMenuTap()` is the only thing the rest of the app needs to know
// about. In DEBUG builds it adds a hidden 5-tap recognizer that opens
// the dev menu; in RELEASE builds it compiles to a no-op so the gesture
// and menu code are never shipped.

extension View {
    /// Attach to any view to make it a hidden dev-menu trigger
    /// (5 quick taps). No-op in release builds.
    func debugMenuTap() -> some View {
        modifier(DebugMenuTap())
    }
}

#if DEBUG

// MARK: - 5-tap recognizer

private struct DebugMenuTap: ViewModifier {
    @State private var taps = 0
    @State private var showMenu = false
    @State private var resetTask: Task<Void, Never>? = nil

    private let requiredTaps = 5
    private let tapWindow: Duration = .milliseconds(1_500)

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                taps += 1
                resetTask?.cancel()

                if taps >= requiredTaps {
                    taps = 0
                    showMenu = true
                } else {
                    resetTask = Task { @MainActor in
                        try? await Task.sleep(for: tapWindow)
                        if !Task.isCancelled { taps = 0 }
                    }
                }
            }
            .sheet(isPresented: $showMenu) { DevMenu() }
    }
}

// MARK: - Dev menu

private struct DevMenu: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("sage.hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: replayOnboarding) {
                        Label("Replay onboarding", systemImage: "arrow.counterclockwise")
                            .foregroundColor(store.accent)
                    }
                } header: {
                    Text("Onboarding")
                } footer: {
                    Text("Clears the first-launch flag and shows the onboarding flow again.")
                }

                Section("Build") {
                    row("Version", appVersion)
                    row("Build",   buildNumber)
                }
            }
            .navigationTitle("Dev Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: { dismiss() })
                }
            }
        }
        .preferredColorScheme(store.darkMode ? .dark : .light)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }

    /// Dismiss the sheet first so ContentView's onboarding/main swap
    /// animates cleanly, then flip the flag a beat later.
    private func replayOnboarding() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            hasCompletedOnboarding = false
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

#else

private struct DebugMenuTap: ViewModifier {
    func body(content: Content) -> some View { content }
}

#endif
