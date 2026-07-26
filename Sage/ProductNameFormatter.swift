import Foundation

// MARK: - Display-layer product name formatting
//
// Pure transform: raw OFF strings → brand eyebrow + clean title + pack size.
// Does not mutate stored Product / search index fields — call at render time.

struct FormattedProduct: Equatable, Sendable {
    /// Canonical brand for the uppercase eyebrow; nil when unknown.
    let brand: String?
    /// Title-cased product name with brand and size removed.
    let name: String
    /// Pack size (e.g. "Garrafa 2 L", "350 ml"); nil when none.
    let size: String?
    /// Untouched original `product_name` (search matching / debug).
    let raw: String

    /// Single string for VoiceOver / accessibility.
    var accessibilityLabel: String {
        [brand, name, size]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

enum ProductNameFormatter {

    /// Localized fallback when both name and brand are empty.
    static let unnamedProduct = String(localized: "Unnamed product")

    // MARK: Public API

    static func format(productName: String?,
                       brands: String? = nil,
                       quantity: String? = nil) -> FormattedProduct {
        let rawName = productName ?? ""
        let rawBrands = brands ?? ""
        let rawQty = quantity ?? ""
        let key = rawName + "\u{1e}" + rawBrands + "\u{1e}" + rawQty

        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let hit = memo[key] { return hit }

        let result = compute(productName: rawName, brands: rawBrands, quantity: rawQty)
        if memo.count > 2_000 { memo.removeAll(keepingCapacity: true) }
        memo[key] = result
        return result
    }

    /// Convenience for persisted `Product` rows.
    static func format(_ product: Product) -> FormattedProduct {
        format(productName: product.name,
               brands: product.brand.isEmpty ? nil : product.brand,
               quantity: product.size.isEmpty ? nil : product.size)
    }

    // MARK: Memo

    private static let cacheLock = NSLock()
    private static var memo: [String: FormattedProduct] = [:]

    // MARK: Core

    private static func compute(productName: String,
                                brands: String,
                                quantity: String) -> FormattedProduct {
        let raw = productName
        var working = productName.trimmingCharacters(in: .whitespacesAndNewlines)

        let brand = resolveBrand(brandsField: brands, productName: working)

        // Empty name → brand as title (keep eyebrow), never an empty row.
        if working.isEmpty {
            if let brand, !brand.isEmpty {
                return FormattedProduct(brand: brand, name: brand, size: normalizeQuantity(quantity), raw: raw)
            }
            return FormattedProduct(brand: nil, name: unnamedProduct,
                                    size: normalizeQuantity(quantity), raw: raw)
        }

        if isMostlyUppercase(working) {
            working = restoreAccentsAndRecase(working)
        }

        var size = normalizeQuantity(quantity)
        let extracted = extractTrailingSize(from: working)
        if size == nil {
            working = extracted.remainder
            size = extracted.size
        } else if let trailing = extracted.size, sizesRoughlyMatch(trailing, size!) {
            working = extracted.remainder
        }

        if let brand {
            let stripped = stripBrand(brand, from: working)
            let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                let titled = titleCase(working.isEmpty ? brand : working)
                return FormattedProduct(
                    brand: nil,
                    name: titled.isEmpty ? unnamedProduct : titled,
                    size: size,
                    raw: raw
                )
            }
            working = stripped
        }

        working = cleanupSeparators(working)
        var name = titleCase(working)

        if name.isEmpty {
            if let brand, !brand.isEmpty {
                return FormattedProduct(brand: brand, name: brand, size: size, raw: raw)
            }
            return FormattedProduct(brand: brand, name: unnamedProduct, size: size, raw: raw)
        }

        name = polishLeiteEmPo(name)
        return FormattedProduct(brand: brand, name: name, size: size, raw: raw)
    }

    // MARK: Brand

    private static let knownBrandDisplays: [String] = [
        "Coca-Cola", "Nescau", "Nestlé", "Ninho", "Qualy", "Mãe Terra",
        "Tio João", "Danone", "Itambé", "Piracanjuba", "Bauducco", "Nissin",
        "Ypê", "Toddy", "Elma Chips", "Antarctica", "Jif",
    ]

    private static var knownBrandsFolded: [(fold: String, display: String)] {
        knownBrandDisplays
            .map { (fold($0), $0) }
            .sorted { $0.fold.count > $1.fold.count }
    }

    private static func resolveBrand(brandsField: String, productName: String) -> String? {
        let first = brandsField
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? ""
        if !first.isEmpty {
            return canonicalizeBrand(first)
        }
        let foldedName = fold(productName)
        for entry in knownBrandsFolded {
            if foldedName.hasPrefix(entry.fold + " ")
                || foldedName == entry.fold
                || foldedName.hasSuffix(" " + entry.fold)
                || foldedName.hasSuffix(", " + entry.fold)
                || foldedName.hasSuffix("," + entry.fold)
                || foldedName.contains(", " + entry.fold) {
                return entry.display
            }
        }
        return nil
    }

    private static func canonicalizeBrand(_ raw: String) -> String {
        let folded = fold(raw)
        if let hit = knownBrandsFolded.first(where: { $0.fold == folded }) {
            return hit.display
        }
        return capitalizeHyphenated(raw)
    }

    private static func stripBrand(_ brand: String, from text: String) -> String {
        var result = text
        let variants = [
            brand,
            brand.replacingOccurrences(of: "-", with: " "),
            brand.replacingOccurrences(of: " ", with: "-"),
            brand.replacingOccurrences(of: "-", with: ""),
        ]
        for variant in Set(variants).sorted(by: { $0.count > $1.count }) {
            for range in rangesMatchingFolded(variant, in: result).reversed() {
                result.replaceSubrange(range, with: " ")
            }
        }
        return cleanupSeparators(result)
    }

    /// Find every occurrence of `needle` in `haystack` using fold-equality
    /// (case/diacritic/hyphen-space insensitive).
    private static func rangesMatchingFolded(_ needle: String, in haystack: String) -> [Range<String.Index>] {
        let target = fold(needle)
        guard !target.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var i = haystack.startIndex
        while i < haystack.endIndex {
            var j = i
            var built = ""
            var foundEnd: String.Index?
            while j < haystack.endIndex {
                built.append(haystack[j])
                j = haystack.index(after: j)
                let f = fold(built)
                if f == target {
                    foundEnd = j
                    break
                }
                if f.count > target.count + 1 { break }
            }
            if let end = foundEnd {
                ranges.append(i..<end)
                i = end
            } else {
                i = haystack.index(after: i)
            }
        }
        return ranges
    }

    // MARK: Size

    private static let packagingNouns = [
        "Garrafa", "Lata", "Pacote", "Caixa", "Sachê", "Sache", "Pote", "Bag",
    ]

    private static let sizePattern: NSRegularExpression = {
        let pack = packagingNouns.joined(separator: "|")
        let pattern = #"(?i)(?:(?<pack>"# + pack + #")\s+)?(?<num>\d+(?:[.,]\d+)?)\s*(?<unit>ml|l|kg|g)\b"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static func normalizeQuantity(_ quantity: String) -> String? {
        let t = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let range = NSRange(t.startIndex..., in: t)
        if let match = sizePattern.firstMatch(in: t, range: range) {
            return formatSizeMatch(match, in: t)
        }
        return t
    }

    private static func extractTrailingSize(from text: String) -> (remainder: String, size: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (trimmed, nil) }
        let full = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = sizePattern.matches(in: trimmed, range: full)
        guard let match = matches.last,
              let matchRange = Range(match.range, in: trimmed)
        else { return (trimmed, nil) }

        let after = trimmed[matchRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        guard after.isEmpty else { return (trimmed, nil) }

        let size = formatSizeMatch(match, in: trimmed)
        let before = String(trimmed[..<matchRange.lowerBound])
        return (cleanupSeparators(before), size)
    }

    private static func formatSizeMatch(_ match: NSTextCheckingResult, in text: String) -> String {
        func group(_ name: String) -> String? {
            let nr = match.range(withName: name)
            guard nr.location != NSNotFound, let r = Range(nr, in: text) else { return nil }
            return String(text[r])
        }
        let pack = group("pack")
        let num = group("num") ?? ""
        let unit = normalizeUnit(group("unit") ?? "")
        let core = "\(num) \(unit)"
        if let pack, !pack.isEmpty {
            return "\(capitalizeWord(pack)) \(core)"
        }
        return core
    }

    private static func normalizeUnit(_ unit: String) -> String {
        switch unit.lowercased() {
        case "l": return "L"
        case "ml": return "ml"
        case "kg": return "kg"
        case "g": return "g"
        default: return unit.lowercased()
        }
    }

    private static func sizesRoughlyMatch(_ a: String, _ b: String) -> Bool {
        fold(a).replacingOccurrences(of: " ", with: "")
            == fold(b).replacingOccurrences(of: " ", with: "")
    }

    // MARK: Title case / ALL-CAPS

    private static let particles: Set<String> = [
        "de", "da", "do", "das", "dos", "e", "com", "sem", "em", "no", "na",
        "nos", "nas", "a", "o", "as", "os", "ao", "à", "para", "por", "um", "uma",
    ]

    private static let preserveAllCaps: Set<String> = [
        "uht", "pet", "tp", "mg", "nfc",
    ]

    private static let accentMap: [String: String] = [
        "PO": "Pó", "ACUCAR": "Açúcar", "CAFE": "Café", "LIMAO": "Limão",
        "PAO": "Pão", "ACAI": "Açaí", "MACA": "Maçã", "CHA": "Chá",
        "ORGANICO": "Orgânico", "PROTEINA": "Proteína",
        "MANTEIGA": "Manteiga", "INTEGRAL": "Integral",
        "AVEIA": "Aveia", "MEL": "Mel",
    ]

    private static func isMostlyUppercase(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return false }
        let upper = letters.filter(\.isUppercase).count
        return Double(upper) / Double(letters.count) > 0.80
    }

    private static func restoreAccentsAndRecase(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).map { raw -> String in
            let token = String(raw)
            let core = String(token.filter(\.isLetter))
            guard !core.isEmpty else { return token }
            let upper = core.uppercased()
            if let restored = accentMap[upper] {
                return token.replacingOccurrences(of: core, with: restored)
            }
            return token.replacingOccurrences(of: core, with: core.lowercased())
        }
        .joined(separator: " ")
    }

    private static func titleCase(_ text: String) -> String {
        let cleaned = cleanupSeparators(text)
        guard !cleaned.isEmpty else { return "" }
        return cleaned
            .split(separator: " ", omittingEmptySubsequences: true)
            .enumerated()
            .map { idx, word in titleCaseToken(String(word), isFirst: idx == 0) }
            .joined(separator: " ")
    }

    private static func titleCaseToken(_ token: String, isFirst: Bool) -> String {
        if token.contains("-") {
            return token.split(separator: "-", omittingEmptySubsequences: false)
                .map { capitalizeHyphenSegment(String($0)) }
                .joined(separator: "-")
        }
        return titleCaseWord(token, forceCapitalize: isFirst)
    }

    private static func capitalizeHyphenated(_ text: String) -> String {
        text.split(separator: "-", omittingEmptySubsequences: false)
            .map { capitalizeHyphenSegment(String($0)) }
            .joined(separator: "-")
    }

    private static func capitalizeHyphenSegment(_ word: String) -> String {
        titleCaseWord(word, forceCapitalize: true)
    }

    private static func titleCaseWord(_ word: String, forceCapitalize: Bool) -> String {
        guard !word.isEmpty else { return word }
        if word.contains(where: \.isNumber) { return word }

        let letters = word.filter(\.isLetter)
        if letters.count >= 2 {
            let upperCount = letters.filter(\.isUppercase).count
            // Mixed internal capitals → leave as-is.
            if upperCount > 1 && upperCount < letters.count && word != word.uppercased() {
                return word
            }
        }

        let folded = fold(word)
        if preserveAllCaps.contains(folded) {
            return word.uppercased()
        }
        if !forceCapitalize && particles.contains(folded) {
            return folded
        }
        return capitalizeWord(word)
    }

    private static func capitalizeWord(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first).uppercased() + word.dropFirst().lowercased()
    }

    private static func polishLeiteEmPo(_ name: String) -> String {
        let pattern = #"^(?i)leite pó(\b.*)$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let match = re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let tail = Range(match.range(at: 1), in: name)
        else { return name }
        return "Leite em Pó" + name[tail]
    }

    // MARK: Helpers

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive],
                  locale: Locale(identifier: "pt_BR"))
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func cleanupSeparators(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: #"\s*,\s*"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ",;/-|"))
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }
}
