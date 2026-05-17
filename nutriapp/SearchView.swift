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
                Text("Search")
                    .font(.system(size: 34, weight: .heavy)).tracking(-1)
                    .foregroundColor(Theme.textPrimary(dark))
                    .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 8)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Theme.textSecondary(dark))
                    TextField("Search by product or brand", text: $query)
                        .focused($focused)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.textPrimary(dark))
                        .submitLabel(.search)
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
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface(dark))
                )
                .cardShadow(dark)
                .padding(.horizontal, 16).padding(.top, 12)

                placeholder(dark: dark)

                Spacer().frame(height: 140)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
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
