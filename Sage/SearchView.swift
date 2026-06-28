import SwiftUI

struct SearchView: View {
    @EnvironmentObject var store: AppStore
    let onOpenProduct: (String) -> Void

    @State private var query: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        let dark = store.darkMode
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                StaggeredAppear(index: 0) {
                    Text("Search")
                        .font(.system(size: 34, weight: .heavy)).tracking(-1)
                        .foregroundColor(Theme.textPrimary(dark))
                        // 12pt above the system safe-area; ContentView's
                        // tabContent isn't ignoring it, so this is the only
                        // breathing room we need below the Dynamic Island.
                        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
                }

                StaggeredAppear(index: 1) {
                    searchBar(dark: dark)
                        .padding(.horizontal, 16).padding(.top, 12)
                }

                StaggeredAppear(index: 2) { placeholder(dark: dark) }

                Spacer().frame(height: 140)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
    }

    private func searchBar(dark: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(focused ? Theme.textPrimary(dark) : Theme.textSecondary(dark))
                .animation(.easeOut(duration: 0.18), value: focused)
            TextField("Search by product or brand", text: $query)
                .focused($focused)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.textPrimary(dark))
                .submitLabel(.search)
            // Contextual icon: cross-fade in/out instead of binary visibility
            // toggling. Skill values: scale 0.25→1, opacity 0→1, blur 4→0.
            if !query.isEmpty {
                Button {
                    query = ""; focused = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.textPrimary(dark))
                        .padding(5)
                        .background(Circle().fill(dark ? Color.white.opacity(0.12)
                                                         : Color.black.opacity(0.08)))
                        .minHitArea(40) // visible ~22pt; lift hit area for thumbs
                }
                .buttonStyle(.pressable)
                .transition(
                    .scale(0.25)
                    .combined(with: .opacity)
                    .combined(with: .blurReplace)
                )
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface(dark))
        )
        // Concentric: outer 14 + 1pt focus ring inset gives a clean nested look.
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focused ? store.accent.opacity(0.35) : Color.clear, lineWidth: 1.5)
        )
        .cardShadow(dark)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: query.isEmpty)
        .animation(.easeOut(duration: 0.2), value: focused)
    }

    private func placeholder(dark: Bool) -> some View {
        VStack(spacing: 8) {
            Text("🔎").font(.system(size: 32))
            Text("Search coming soon")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.textPrimary(dark))
            Text("Product lookup isn't connected yet.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary(dark))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 80)
    }
}
