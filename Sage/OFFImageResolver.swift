import Foundation
import CoreGraphics

// MARK: - Resolved product image (OFFImageResolver)

/// Best available front-of-pack (or fallback) image URLs for a product.
struct ResolvedProductImage: Equatable {
    /// Highest useful resolution for the product detail screen (`full` when buildable).
    let displayURL: URL
    /// List / grid size (`.400` when buildable). Nil → callers use `displayURL`.
    let thumbURL: URL?
    /// True when the chosen asset is a declared front image (not a generic `image_url`).
    let isFrontImage: Bool
    /// Source `sizes.full` dimensions when known from OFF `images` metadata.
    let estimatedPixelSize: CGSize?
    /// Longest source side under 300px — UI should prefer the glyph placeholder.
    let isLowQuality: Bool
}

/// Pure, stateless selection of the best OFF product image URL.
///
/// Selection order (first hit wins): preferred-language `selected_images.front.display`,
/// product `lang`, any remaining front display entry, `image_front_url`, then
/// generic `image_url` (marked non-front). When barcode + `images[front_<lang>].rev`
/// are available, URLs are built for `.400` (lists) and `full` (detail). Ready-made
/// URLs ending in `.100.jpg` / `.200.jpg` are rewritten to `.400.jpg` without
/// changing language key or revision.
enum OFFImageResolver {

    /// Default language preference for our markets.
    static let defaultPreferredLanguages = ["pt", "en", "es"]

    /// Longest source side below this → `isLowQuality`.
    static let lowQualityLongestSide = 300

    // MARK: Public API

    static func resolve(
        barcode: String,
        lang: String?,
        imageFrontURL: String?,
        imageURL: String?,
        selectedFrontDisplay: [String: String]?,
        imageEntries: [String: OFFImageEntry]?,
        preferredLanguages: [String] = defaultPreferredLanguages
    ) -> ResolvedProductImage? {
        let langs = preferredLanguages.map { normalizeLang($0) }.filter { !$0.isEmpty }
        let productLang = lang.map(normalizeLang).flatMap { $0.isEmpty ? nil : $0 }
        var claimed = Set<String>()

        // a) preferred languages in order — requires selected_images.front.display[lang]
        for code in langs {
            claimed.insert(code)
            if let resolved = resolveSelectedFront(lang: code, barcode: barcode,
                                                   selectedFrontDisplay: selectedFrontDisplay,
                                                   imageEntries: imageEntries) {
                return resolved
            }
        }

        // b) product's own lang
        if let productLang, !claimed.contains(productLang) {
            claimed.insert(productLang)
            if let resolved = resolveSelectedFront(lang: productLang, barcode: barcode,
                                                   selectedFrontDisplay: selectedFrontDisplay,
                                                   imageEntries: imageEntries) {
                return resolved
            }
        }

        // c) any remaining selected_images.front.display.*
        if let display = selectedFrontDisplay {
            for (rawKey, rawURL) in display.sorted(by: { $0.key < $1.key }) {
                let code = normalizeLang(rawKey)
                if claimed.contains(code) { continue }
                claimed.insert(code)
                if let resolved = resolveSelectedFront(
                    lang: code, barcode: barcode,
                    selectedFrontDisplay: selectedFrontDisplay,
                    imageEntries: imageEntries,
                    readyURL: rawURL
                ) {
                    return resolved
                }
            }
        }

        // d) image_front_url
        if let resolved = fromReadyURL(imageFrontURL, barcode: barcode, lang: nil,
                                       isFront: true, imageEntries: imageEntries) {
            return resolved
        }

        // e) image_url (generic — may not be front)
        if let resolved = fromReadyURL(imageURL, barcode: barcode, lang: nil,
                                       isFront: false, imageEntries: imageEntries) {
            return resolved
        }

        return nil
    }

    /// Convenience over a decoded `OFFProduct`.
    static func resolve(from off: OFFProduct, barcode: String,
                        preferredLanguages: [String] = defaultPreferredLanguages)
    -> ResolvedProductImage? {
        resolve(
            barcode: barcode,
            lang: off.lang,
            imageFrontURL: off.imageFrontUrl,
            imageURL: off.imageUrl,
            selectedFrontDisplay: off.selectedImages?.front?.display,
            imageEntries: off.images,
            preferredLanguages: preferredLanguages
        )
    }

    /// Device language tags → 2-letter codes for OFF (`pt-BR` → `pt`).
    static func preferredLanguages(from localeIdentifiers: [String] = Locale.preferredLanguages)
    -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for id in localeIdentifiers {
            let code = normalizeLang(id)
            guard !code.isEmpty, !seen.contains(code) else { continue }
            seen.insert(code)
            out.append(code)
        }
        // Always keep EN as a last resort after device prefs.
        for fallback in defaultPreferredLanguages where !seen.contains(fallback) {
            out.append(fallback)
            seen.insert(fallback)
        }
        return out
    }

    /// Upgrade a ready-made OFF size suffix without changing lang/rev.
    /// `.100.jpg` / `.200.jpg` → `.400.jpg`; otherwise unchanged.
    static func upgradeToDisplaySize(_ raw: String?) -> String? {
        guard let s = sanitize(raw) else { return nil }
        return rewriteSize(s, to: "400") ?? s
    }

    static func sanitize(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty,
              let url = URL(string: s),
              url.scheme?.lowercased() == "https"
        else { return nil }
        return s
    }

    // MARK: Internals

    /// Steps a–c: only when `selected_images.front.display` has this language.
    private static func resolveSelectedFront(
        lang: String,
        barcode: String,
        selectedFrontDisplay: [String: String]?,
        imageEntries: [String: OFFImageEntry]?,
        readyURL: String? = nil
    ) -> ResolvedProductImage? {
        let raw = readyURL
            ?? selectedFrontDisplay?[lang]
            ?? selectedFrontDisplay?.first(where: { normalizeLang($0.key) == lang })?.value
        guard let raw else { return nil }

        let key = "front_\(lang)"
        // Prefer constructing from rev when metadata exists.
        if let entry = imageEntries?[key], let rev = entry.rev, !rev.isEmpty {
            return build(barcode: barcode, imageKey: key, rev: rev,
                         entry: entry, isFront: true)
        }
        return fromReadyURL(raw, barcode: barcode, lang: lang,
                            isFront: true, imageEntries: imageEntries)
    }

    private static func fromReadyURL(
        _ raw: String?,
        barcode: String,
        lang: String?,
        isFront: Bool,
        imageEntries: [String: OFFImageEntry]?
    ) -> ResolvedProductImage? {
        guard var s = sanitize(raw) else { return nil }

        // If the URL encodes front_<lang>.<rev>.<size>.jpg, upgrade sizes / build full.
        if let parts = parseOFFImageURL(s) {
            let entry = imageEntries?[parts.imageKey]
            if let rev = entry?.rev ?? Optional(parts.rev), !rev.isEmpty {
                return build(barcode: barcode.isEmpty ? parts.barcodeHint ?? barcode
                                                      : barcode,
                             imageKey: parts.imageKey,
                             rev: rev,
                             entry: entry,
                             isFront: isFront || parts.imageKey.hasPrefix("front_"))
            }
            // No rev metadata — only safe rewrite is 100/200 → 400.
            s = rewriteSize(s, to: "400") ?? s
        } else {
            s = rewriteSize(s, to: "400") ?? s
        }

        guard let display = URL(string: s) else { return nil }
        let thumb = URL(string: rewriteSize(s, to: "400") ?? s)
        let size = estimatedSize(imageKey: lang.map { "front_\($0)" },
                                 entries: imageEntries)
        return ResolvedProductImage(
            displayURL: display,
            thumbURL: thumb,
            isFrontImage: isFront,
            estimatedPixelSize: size,
            isLowQuality: isLowQuality(size)
        )
    }

    private static func build(
        barcode: String,
        imageKey: String,
        rev: String,
        entry: OFFImageEntry?,
        isFront: Bool
    ) -> ResolvedProductImage? {
        let folder = splitBarcodeFolder(barcode)
        guard !folder.isEmpty else { return nil }
        let base = "https://images.openfoodfacts.org/images/products/\(folder)/\(imageKey).\(rev)"
        guard let display = URL(string: "\(base).full.jpg"),
              let thumb = URL(string: "\(base).400.jpg")
        else { return nil }
        let size = estimatedSize(from: entry)
        return ResolvedProductImage(
            displayURL: display,
            thumbURL: thumb,
            isFrontImage: isFront,
            estimatedPixelSize: size,
            isLowQuality: isLowQuality(size)
        )
    }

    /// `0123456789012` → `012/345/678/9012` when length ≥ 9; else unsplit.
    static func splitBarcodeFolder(_ barcode: String) -> String {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty else { return barcode }
        if digits.count >= 9 {
            let a = digits.prefix(3)
            let b = digits.dropFirst(3).prefix(3)
            let c = digits.dropFirst(6).prefix(3)
            let d = digits.dropFirst(9)
            return "\(a)/\(b)/\(c)/\(d)"
        }
        return String(digits)
    }

    private static func normalizeLang(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return "" }
        // `pt-BR`, `en_US`, `fr` → first segment
        let sep = t.firstIndex(where: { $0 == "-" || $0 == "_" }) ?? t.endIndex
        return String(t[..<sep])
    }

    private static func rewriteSize(_ url: String, to size: String) -> String? {
        // Match .../front_en.12.100.jpg or .200.jpg → .400.jpg / .full.jpg
        let pattern = #"\.(100|200|400|full)\.jpg$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else { return nil }
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        guard regex.firstMatch(in: url, options: [], range: range) != nil else { return nil }
        return regex.stringByReplacingMatches(
            in: url, options: [], range: range,
            withTemplate: ".\(size).jpg"
        )
    }

    private struct ParsedOFFURL {
        let imageKey: String   // e.g. front_en
        let rev: String
        let barcodeHint: String?
    }

    /// Parse `.../products/012/345/678/9012/front_en.12.400.jpg`.
    private static func parseOFFImageURL(_ url: String) -> ParsedOFFURL? {
        guard let regex = try? NSRegularExpression(
            pattern: #"images/products/(?:((?:\d{3}/){3}\d+|\d+)/)?([a-z]+_[a-z]{2})\.(\d+)\.(100|200|400|full)\.jpg$"#,
            options: .caseInsensitive
        ) else { return nil }
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        guard let m = regex.firstMatch(in: url, options: [], range: range),
              m.numberOfRanges >= 4,
              let keyR = Range(m.range(at: 2), in: url),
              let revR = Range(m.range(at: 3), in: url)
        else { return nil }
        var hint: String?
        if m.range(at: 1).location != NSNotFound, let fR = Range(m.range(at: 1), in: url) {
            hint = url[fR].replacingOccurrences(of: "/", with: "")
        }
        return ParsedOFFURL(imageKey: String(url[keyR]), rev: String(url[revR]), barcodeHint: hint)
    }

    private static func estimatedSize(imageKey: String?,
                                      entries: [String: OFFImageEntry]?) -> CGSize? {
        guard let imageKey, let entry = entries?[imageKey] else { return nil }
        return estimatedSize(from: entry)
    }

    private static func estimatedSize(from entry: OFFImageEntry?) -> CGSize? {
        guard let full = entry?.sizes?["full"],
              let w = full.w, let h = full.h, w > 0, h > 0
        else { return nil }
        return CGSize(width: w, height: h)
    }

    private static func isLowQuality(_ size: CGSize?) -> Bool {
        guard let size else { return false }
        return max(size.width, size.height) < CGFloat(lowQualityLongestSide)
    }
}

// MARK: - OFF image DTOs (shared by decoder + resolver)

struct OFFSelectedImages: Decodable, Equatable {
    let front: OFFSelectedImageSet?
}

struct OFFSelectedImageSet: Decodable, Equatable {
    let display: [String: String]?
    let small: [String: String]?
    let thumb: [String: String]?
}

struct OFFImageEntry: Decodable, Equatable {
    let rev: String?
    let sizes: [String: OFFImageSizeDims]?

    enum CodingKeys: String, CodingKey { case rev, sizes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decodeIfPresent(String.self, forKey: .rev) {
            rev = s
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .rev) {
            rev = String(i)
        } else {
            rev = nil
        }
        sizes = try? c.decodeIfPresent([String: OFFImageSizeDims].self, forKey: .sizes)
    }

    init(rev: String?, sizes: [String: OFFImageSizeDims]?) {
        self.rev = rev
        self.sizes = sizes
    }
}

struct OFFImageSizeDims: Decodable, Equatable {
    let w: Int?
    let h: Int?

    enum CodingKeys: String, CodingKey { case w, h }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        w = Self.int(c, .w)
        h = Self.int(c, .h)
    }

    init(w: Int?, h: Int?) {
        self.w = w
        self.h = h
    }

    private static func int(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Int? {
        if let i = try? c.decodeIfPresent(Int.self, forKey: k) { return i }
        if let d = try? c.decodeIfPresent(Double.self, forKey: k) { return Int(d) }
        if let s = try? c.decodeIfPresent(String.self, forKey: k) { return Int(s) }
        return nil
    }
}
