import SwiftUI
import UIKit

// MARK: - Style

enum ProductImageStyle: Equatable {
    /// History / alternatives / compare rows (~56pt).
    case list
    /// Product detail header — larger fixed frame.
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

/// Shared product photo: skeleton placeholder → finished image, one fade.
/// Nothing is shown until the image is in its final form (cutout processing
/// included), so the background removal never plays out on screen. Fixed frame
/// per style so layout never jumps. Cutouts float (no card); opaque photos and
/// the placeholder keep a neutral container.
struct ProductImageView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    let url: URL?
    var style: ProductImageStyle = .list
    /// Unused for rendering — the placeholder is a neutral skeleton, never an
    /// emoji. Kept for call-site stability and accessibility copy.
    var glyph: String = "🛒"
    /// Tried when `url` fails to load (missing, non-2xx, or undecodable) —
    /// Top Rated / Alternatives rows fall back to their dataset OFF photo
    /// instead of the placeholder.
    var fallbackURL: URL? = nil
    /// When false, show the original photo as-is — never run Vision.
    var processCutout: Bool = true

    /// The finished image. Set exactly once, after any cutout processing, so
    /// the view never renders an intermediate state.
    @State private var finished: UIImage?
    @State private var loadTask: Task<Void, Never>?

    private var size: CGFloat { style.size }
    /// Chrome radius scales with the frame — a 176pt hero on a 10pt corner
    /// reads as a web thumbnail; large frames take the card radius.
    private var corner: CGFloat { size >= 120 ? Theme.Radius.card : 10 }
    private var dark: Bool { colorScheme == .dark }

    /// True only for a real transparent cutout (failed Vision keeps chrome).
    private var isFloatingCutout: Bool {
        finished.map { ProductImageHeuristics.hasMeaningfulAlpha($0) } == true
    }

    private var showsCardChrome: Bool { !isFloatingCutout }

    var body: some View {
        ZStack {
            if showsCardChrome {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Theme.card)
            }

            if let finished {
                Image(uiImage: finished)
                    .resizable()
                    .scaledToFit()
                    .padding(size * (isFloatingCutout ? 0.02 : 0.08))
                    .shadow(
                        color: Color.black.opacity(isFloatingCutout ? 0.08 : 0.04),
                        radius: isFloatingCutout ? 3 : 1,
                        x: 0, y: 1
                    )
                    .transition(.opacity)
            } else {
                // Loading *and* no-image resolve to the same neutral tile, so a
                // slow load never flashes a different shape than the result.
                ProductImageSkeleton(size: size)
            }
        }
        .frame(width: size, height: size)
        .modifier(CardChromeClip(
            enabled: showsCardChrome,
            corner: corner,
            dark: dark
        ))
        .animation(.easeInOut(duration: 0.22), value: finished != nil)
        .animation(.easeInOut(duration: 0.22), value: isFloatingCutout)
        .task(id: taskIdentity) {
            await reload()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private var taskIdentity: String {
        "\(url?.absoluteString ?? "nil")|\(fallbackURL?.absoluteString ?? "nil")|\(processCutout)"
    }

    @MainActor
    private func reload() async {
        loadTask?.cancel()
        finished = nil

        // Primary first, dataset fallback second; a URL that fails any tier
        // simply hands over to the next candidate.
        let candidates = [url, fallbackURL].compactMap { $0 }
        guard !candidates.isEmpty else { return }

        let task = Task {
            /// Publish the final image exactly once — the skeleton stays up
            /// until this fires, so background removal is never seen happening.
            @MainActor func publish(_ image: UIImage?) {
                withAnimation(.easeInOut(duration: 0.22)) { finished = image }
            }

            // Already-processed cutout for one of these URLs: final immediately.
            if processCutout {
                for candidate in candidates {
                    guard let cached = await ProductImageProcessor.shared.cachedImage(for: candidate)
                    else { continue }
                    if Task.isCancelled { return }
                    await publish(cached)
                    return
                }
            }

            // Decoded original already in RAM (scroll-off / re-search),
            // else network. First URL that yields a decodable image wins.
            var loaded: (image: UIImage, url: URL)?
            for candidate in candidates {
                if let cached = ProductImageMemoryCache.image(for: candidate) {
                    loaded = (cached, candidate)
                    break
                }
                if let fetched = await fetchImage(from: candidate) {
                    ProductImageMemoryCache.store(fetched, for: candidate)
                    loaded = (fetched, candidate)
                    break
                }
                if Task.isCancelled { return }
            }

            guard let loaded else {
                await publish(nil)          // nothing anywhere — keep the skeleton
                return
            }

            guard processCutout else {
                if Task.isCancelled { return }
                await publish(loaded.image)
                return
            }

            // Hold the skeleton across Vision so the cutout appears finished.
            let processed = await ProductImageProcessor.shared.process(loaded.image, url: loaded.url)
            if Task.isCancelled { return }
            await publish(processed)
        }
        loadTask = task
        await task.value
    }

    /// One network attempt; nil on transport error, non-2xx, or undecodable bytes.
    private func fetchImage(from url: URL) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else { return nil }
        return UIImage(data: data)
    }
}

/// Neutral tile shown while a photo loads and when there is none — a faint
/// barcode mark on the card surface. Deliberately identical in both cases so a
/// slow load never flashes a different shape than the final result, and never
/// an emoji.
struct ProductImageSkeleton: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "barcode")
            .font(.system(size: size * 0.34, weight: .regular))
            .foregroundStyle(Theme.inkSecondary.opacity(0.35))
            .accessibilityHidden(true)
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
