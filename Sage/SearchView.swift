import SwiftUI

struct SearchView: View {
    @EnvironmentObject var store: AppStore
    /// Called with the barcode of the tapped hit — ContentView runs the same
    /// lookup → score → /explain pipeline as a camera scan.
    let onSelect: (String) -> Void

    private enum Phase: Equatable {
        case idle          // under 2 chars typed
        case searching
        case results([BackendService.SearchHit])
        case empty         // OFF has no match → "Product not available."
        case failed
    }

    @State private var query: String = ""
    @State private var phase: Phase = .idle
    @State private var searchTask: Task<Void, Never>? = nil
    @FocusState private var focused: Bool

    private let backend = BackendService()

    var body: some View {
        let dark = store.darkMode
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                StaggeredAppear(index: 0) {
                    Text("Search")
                        .font(.sageBold(34)).tracking(-1)
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

                StaggeredAppear(index: 2) { phaseContent(dark: dark) }

                Spacer().frame(height: 140)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
        .onChange(of: query) { _, newValue in scheduleSearch(for: newValue) }
    }

    // MARK: Debounced typeahead

    /// Waits out a typing pause before hitting the backend, and cancels the
    /// in-flight request whenever another character arrives — only the latest
    /// query's results ever land.
    private func scheduleSearch(for raw: String) {
        searchTask?.cancel()
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            phase = .idle
            return
        }
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            phase = .searching
            do {
                let hits = try await backend.search(q)
                guard !Task.isCancelled else { return }
                phase = hits.isEmpty ? .empty : .results(hits)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed
            }
        }
    }

    // MARK: Search bar (unchanged design)

    private func searchBar(dark: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(focused ? Theme.textPrimary(dark) : Theme.textSecondary(dark))
                .animation(.easeOut(duration: 0.18), value: focused)
            TextField("Search by product or brand", text: $query)
                .focused($focused)
                .font(.sageMedium(15))
                .foregroundColor(Theme.textPrimary(dark))
                .submitLabel(.search)
                .autocorrectionDisabled()
            // Contextual icon: cross-fade in/out instead of binary visibility
            // toggling. Skill values: scale 0.25→1, opacity 0→1, blur 4→0.
            if !query.isEmpty {
                Button {
                    query = ""; focused = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.sageBold(10))
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

    // MARK: Phase content

    @ViewBuilder private func phaseContent(dark: Bool) -> some View {
        switch phase {
        case .idle:
            categoryGrid(dark: dark)
        case .searching:
            VStack(spacing: 12) {
                ProgressView().tint(store.accent)
                Text("Searching…")
                    .font(.sageRegular(13))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        case .results(let hits):
            VStack(spacing: 8) {
                ForEach(hits) { hit in
                    SearchHitRow(hit: hit, dark: dark) {
                        // Drop the keyboard before the result is pushed. If it's
                        // still up when the overlay appears, iOS's tap-to-dismiss
                        // gesture swallows the first tap on the new view — which
                        // reads as the back button "not working" on first press.
                        focused = false
                        onSelect(hit.code)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14)
        case .empty:
            hint(icon: "🤷", title: "Product not available.",
                 body: "Nothing in the database matches “\(query.trimmingCharacters(in: .whitespaces))”. Try a shorter name or scan the barcode.",
                 dark: dark)
        case .failed:
            hint(icon: "📡", title: "Search failed",
                 body: "Check your connection and try again.",
                 dark: dark)
        }
    }

    // MARK: Browse categories (idle opener)

    /// Tapping a tile drops the term into the search field, which fires the same
    /// debounced typeahead pipeline as manual typing.
    private static let categories: [(emoji: String, name: String)] = [
        ("🥤", "Soda"),        ("💧", "Water"),
        ("🍫", "Chocolate"),   ("🍪", "Cookies"),
        ("🥣", "Cereal"),      ("🧀", "Cheese"),
        ("🥛", "Yogurt"),      ("🍞", "Bread"),
        ("🧃", "Juice"),       ("🍟", "Chips"),
        ("☕", "Coffee"),      ("🍝", "Pasta"),
        ("🍦", "Ice cream"),   ("🍼", "Baby food"),
    ]

    private func categoryGrid(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BROWSE")
                .font(.sageBold(11)).tracking(1.3)
                .foregroundColor(Theme.textSecondary(dark))
                .padding(.horizontal, 8)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Self.categories, id: \.name) { category in
                    Button {
                        focused = false
                        query = category.name
                    } label: {
                        HStack(spacing: 10) {
                            Text(category.name)
                                .font(.sageBold(15)).tracking(-0.2)
                                .foregroundColor(Theme.textPrimary(dark))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(category.emoji).font(.sageRegular(22))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Theme.surface(dark))
                        )
                        .cardShadow(dark)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Browse \(category.name)")
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 14)
    }

    private func hint(icon: String, title: String, body: String, dark: Bool) -> some View {
        VStack(spacing: 8) {
            Text(icon).font(.sageRegular(32))
            Text(title)
                .font(.sageBold(16))
                .foregroundColor(Theme.textPrimary(dark))
            Text(body)
                .font(.sageRegular(13))
                .foregroundColor(Theme.textSecondary(dark))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 60)
    }
}

// MARK: - Result row

private struct SearchHitRow: View {
    let hit: BackendService.SearchHit
    let dark: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                thumb
                VStack(alignment: .leading, spacing: 1) {
                    if !eyebrow.isEmpty {
                        Text(eyebrow.uppercased())
                            .font(.sageBold(10)).tracking(1.2)
                            .foregroundColor(Theme.textSecondary(dark))
                    }
                    Text(hit.name)
                        .font(.sageBold(14))
                        .foregroundColor(Theme.textPrimary(dark))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.sageBold(12))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
            )
            .cardShadow(dark)
        }
        .buttonStyle(.pressable)
    }

    /// Brand plus pack size (when known) — distinguishes remaining variants
    /// after the backend collapses same-brand-same-name duplicates.
    private var eyebrow: String {
        [hit.brand, hit.quantity ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// No score exists before the lookup, so this is a plain photo tile with
    /// the generic glyph as loading/failure/no-image fallback.
    private var thumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            if let url = hit.imageURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .background(Color.white)
                    } else {
                        Text("🛒").font(.sageRegular(20))
                    }
                }
            } else {
                Text("🛒").font(.sageRegular(20))
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
