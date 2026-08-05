import SwiftUI
import UIKit

// MARK: - Style

enum ProductImageStyle: Equatable {
    /// History / alternatives / compare rows (~56pt).
    case list
    /// Product detail header — larger fixed frame, no chrome while loading/processing.
    case detail
    /// Explicit size (search, home, compare cards).
    case fixed(CGFloat)

    var size: CGFloat {
        switch self {
        case .list: return 56
        /// ~20% larger than the previous 84pt detail thumb; header row height unchanged.
        case .detail: return 100
        case .fixed(let s): return s
        }
    }

    /// Detail: skip the fallback card until the final image state is known,
    /// so original→cutout never flashes a white tile mid-transition.
    var suppressesChromeUntilSettled: Bool {
        switch self {
        case .detail: return true
        case .list, .fixed: return false
        }
    }
}

// MARK: - Decoded-image memory cache

/// Keeps recently decoded originals in RAM so list/search rows that scroll
/// off-screen (or reappear after a re-query) don't pay URLSession + UIImage
/// decode again. URLCache still owns the bytes on disk.
enum ProductImageMemoryCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 150
        c.totalCostLimit = 40 * 1024 * 1024
        return c
    }()

    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    static func store(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
    }
}

// MARK: - ProductImageView

/// Shared product photo: glyph placeholder → URLCache original → crossfade cutout.
/// Fixed frame per style so layout never jumps when the cutout arrives.
/// Cutouts float (no card); fallbacks keep a neutral `Theme.surface` container.
struct ProductImageView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    let url: URL?
    var style: ProductImageStyle = .list
    var glyph: String = "🛒"
    /// When false, show original (or glyph) only — never run Vision.
    var processCutout: Bool = true

    @State private var original: UIImage?
    @State private var cutout: UIImage?
    /// True once loading/processing finished (or there is nothing to load).
    @State private var settled = false
    @State private var loadTask: Task<Void, Never>?

    private var size: CGFloat { style.size }
    private var corner: CGFloat { 10 }
    private var dark: Bool { colorScheme == .dark }

    /// True only for a real transparent cutout (failed Vision keeps chrome).
    private var isFloatingCutout: Bool {
        cutout.map { ProductImageHeuristics.hasMeaningfulAlpha($0) } == true
    }

    private var showsCardChrome: Bool {
        if isFloatingCutout { return false }
        if style.suppressesChromeUntilSettled && !settled { return false }
        // Glyph / opaque original / no-URL placeholder.
        return true
    }

    var body: some View {
        ZStack {
            if showsCardChrome {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Theme.card)
                    .transition(.opacity)
            }

            if let shown = cutout ?? original {
                Image(uiImage: shown)
                    .resizable()
                    .scaledToFit()
                    .padding(size * (isFloatingCutout ? 0.02 : 0.08))
                    .shadow(
                        color: Color.black.opacity(isFloatingCutout ? 0.08 : 0.04),
                        radius: isFloatingCutout ? 3 : 1,
                        x: 0, y: 1
                    )
                    .transition(.opacity)
            } else if settled || !style.suppressesChromeUntilSettled {
                Text(glyph).font(.sageRegular(size * 0.5))
            }
        }
        .frame(width: size, height: size)
        .modifier(CardChromeClip(
            enabled: showsCardChrome,
            corner: corner,
            dark: dark
        ))
        .animation(.easeInOut(duration: 0.22), value: cutout != nil)
        .animation(.easeInOut(duration: 0.18), value: original != nil)
        .animation(.easeInOut(duration: 0.22), value: isFloatingCutout)
        .animation(.easeInOut(duration: 0.22), value: showsCardChrome)
        .task(id: taskIdentity) {
            await reload()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private var taskIdentity: String {
        "\(url?.absoluteString ?? "nil")|\(processCutout)"
    }

    @MainActor
    private func reload() async {
        loadTask?.cancel()
        original = nil
        cutout = nil
        settled = false

        guard let url else {
            settled = true
            return
        }

        let task = Task {
            // Instant cutout if we already processed this URL.
            if processCutout,
               let cached = await ProductImageProcessor.shared.cachedImage(for: url) {
                if Task.isCancelled { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        cutout = cached
                        original = cached
                        settled = true
                    }
                }
                return
            }

            // Decoded original already in RAM (scroll-off / re-search).
            if let cached = ProductImageMemoryCache.image(for: url) {
                if Task.isCancelled { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        original = cached
                    }
                }
                guard processCutout else {
                    await MainActor.run { settled = true }
                    return
                }
                let processed = await ProductImageProcessor.shared.process(cached, url: url)
                if Task.isCancelled { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        cutout = processed
                        settled = true
                    }
                }
                return
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if Task.isCancelled { return }
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let image = UIImage(data: data) else {
                    await MainActor.run { settled = true }
                    return
                }
                ProductImageMemoryCache.store(image, for: url)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        original = image
                    }
                }

                guard processCutout else {
                    await MainActor.run { settled = true }
                    return
                }
                let processed = await ProductImageProcessor.shared.process(image, url: url)
                if Task.isCancelled { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        cutout = processed
                        settled = true
                    }
                }
            } catch {
                await MainActor.run { settled = true }
            }
        }
        loadTask = task
        await task.value
    }
}

/// Rounded clip + hairline only when the card chrome is visible.
private struct CardChromeClip: ViewModifier {
    let enabled: Bool
    let corner: CGFloat
    let dark: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .inset(by: 0.5)
                        .stroke(dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10),
                                lineWidth: 1)
                )
        } else {
            content
        }
    }
}
