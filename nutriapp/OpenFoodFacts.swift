import Foundation

// MARK: - Additive catalog

/// Looks up Open Food Facts additive tags (e.g. "en:e150d") against a bundled
/// table of names + risk ratings. Unknown additives fall back to `.unrated`.
enum AdditiveCatalog {
    struct Info: Codable {
        let name: String
        let risk: RiskLevel
        var note: String? = nil
    }

    private final class BundleToken {}

    static let entries: [String: Info] = {
        // Resolve via the bundle that owns this code so it also works under a
        // hosted test target (where Bundle.main is the test runner).
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "Additives", withExtension: "json")
                ?? Bundle.main.url(forResource: "Additives", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: Info].self, from: data)
        else { return [:] }
        return dict
    }()

    /// Normalize an OFF tag like "en:e150d" → "e150d".
    static func normalize(_ tag: String) -> String {
        let lower = tag.lowercased()
        if let range = lower.range(of: ":") {
            return String(lower[range.upperBound...])
        }
        return lower
    }

    static func additive(for tag: String) -> Additive {
        let code = normalize(tag)
        if let info = entries[code] {
            return Additive(name: info.name, risk: info.risk, note: info.note)
        }
        // Unknown additive: show the code, no risk judgment.
        return Additive(name: code.uppercased(), risk: .unrated)
    }
}

// MARK: - Open Food Facts service

struct OpenFoodFactsService {
    enum LookupError: Error, Equatable {
        case notFound
        case network
        case decoding
    }

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    private static let fields = [
        "code", "product_name", "brands", "quantity",
        "nutriscore_grade", "nova_group", "nutriments",
        "additives_tags", "ingredients_analysis_tags",
        "ingredients_text", "categories_tags"
    ].joined(separator: ",")

    func fetchProduct(barcode: String) async throws -> Product {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(trimmed).json?fields=\(Self.fields)")
        else { throw LookupError.network }

        var req = URLRequest(url: url)
        req.setValue("Sage/1.0 (iOS nutrition scanner)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw LookupError.network
        }

        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw LookupError.notFound
        }
        return try Self.makeProduct(from: data, barcode: trimmed)
    }

    /// Pure decode + map step, separated from networking so it can be unit-tested.
    static func makeProduct(from data: Data, barcode: String) throws -> Product {
        let decoded: OFFResponse
        do {
            decoded = try JSONDecoder().decode(OFFResponse.self, from: data)
        } catch {
            throw LookupError.decoding
        }
        guard let p = decoded.product,
              (p.productName?.isEmpty == false) || p.nutriments != nil else {
            throw LookupError.notFound
        }
        return map(p, barcode: barcode)
    }

    // MARK: Mapping

    static func map(_ off: OFFProduct, barcode: String) -> Product {
        let n = off.nutriments

        // Sodium: OFF reports grams/100g. Prefer sodium, else derive from salt (salt ≈ sodium × 2.5).
        let sodiumMg: Double? = {
            if let s = n?.sodium { return s * 1000 }
            if let salt = n?.salt { return (salt / 2.5) * 1000 }
            return nil
        }()

        let nutrients = Nutrients(
            sugar_g: n?.sugars,
            sodium_mg: sodiumMg,
            satFat_g: n?.saturatedFat,
            fiber_g: n?.fiber,
            protein_g: n?.proteins,
            calcium_mg: n?.calcium.map { $0 * 1000 }
        )

        let additives = (off.additivesTags ?? []).map { AdditiveCatalog.additive(for: $0) }
        let sweeteners = detectSweeteners(off.additivesTags ?? [])
        let seedOils = detectSeedOils(off.ingredientsText)
        let transFats = (n?.transFat ?? 0) > 0

        let grade = off.nutriscoreGrade?.uppercased()
        let overall = placeholderScore(grade: grade, nova: off.novaGroup)

        return Product(
            id: barcode,
            name: off.productName?.isEmpty == false ? off.productName! : "Unknown product",
            brand: primaryBrand(off.brands),
            size: off.quantity ?? "",
            glyph: glyph(for: off.categoriesTags ?? []),
            overallScore: overall,
            yourScore: overall,          // personalized later (Phase 3)
            deltaReason: nil,            // AI explanation later (Phase 4)
            nutriGrade: (grade?.isEmpty == false) ? grade! : "?",
            novaGroup: off.novaGroup ?? 0,
            nutrients: nutrients,
            bonuses: [],                 // computed by scoring engine (Phase 3)
            transFats: transFats,
            caffeine_mg: n?.caffeine,
            sweeteners: sweeteners,
            seedOils: seedOils,
            additives: additives,
            restrictions: []             // profile flagging later (Phase 3)
        )
    }

    // MARK: Detection helpers

    /// Artificial-sweetener E-numbers → the keys ResultView's `sweetenerLabel` understands.
    private static let sweetenerCodes: [String: String] = [
        "e951": "aspartame",
        "e950": "acesulfame K",
        "e954": "saccharin",
        "e955": "sucralose",
        "e960": "stevia"
    ]

    static func detectSweeteners(_ tags: [String]) -> [String] {
        var seen: [String] = []
        for tag in tags {
            let code = AdditiveCatalog.normalize(tag)
            if let key = sweetenerCodes[code], !seen.contains(key) {
                seen.append(key)
            }
        }
        return seen
    }

    private static let seedOilKeywords = [
        "sunflower oil", "rapeseed oil", "canola oil", "soybean oil", "soya oil",
        "corn oil", "cottonseed oil", "safflower oil", "grapeseed oil", "rice bran oil"
    ]

    static func detectSeedOils(_ ingredients: String?) -> Bool {
        guard let text = ingredients?.lowercased() else { return false }
        return seedOilKeywords.contains { text.contains($0) }
    }

    static func primaryBrand(_ brands: String?) -> String {
        guard let brands, !brands.isEmpty else { return "" }
        return brands.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? brands
    }

    /// Temporary score from the Nutri-Score grade (or NOVA as a fallback).
    /// Replaced by the real scoring engine in Phase 3.
    static func placeholderScore(grade: String?, nova: Int?) -> Int {
        switch grade {
        case "A": return 90
        case "B": return 72
        case "C": return 54
        case "D": return 34
        case "E": return 16
        default: break
        }
        switch nova {
        case 1: return 80
        case 2: return 65
        case 3: return 45
        case 4: return 25
        default: return 50
        }
    }

    static func glyph(for categories: [String]) -> String {
        let joined = categories.joined(separator: " ").lowercased()
        let map: [(String, String)] = [
            ("beverage", "🥤"), ("drink", "🥤"), ("water", "💧"), ("juice", "🧃"),
            ("soda", "🥤"), ("coffee", "☕"), ("tea", "🍵"),
            ("dairy", "🥛"), ("milk", "🥛"), ("cheese", "🧀"), ("yogurt", "🥛"),
            ("chocolate", "🍫"), ("candy", "🍬"), ("sweet", "🍬"),
            ("biscuit", "🍪"), ("cookie", "🍪"), ("cake", "🍰"),
            ("snack", "🍿"), ("chip", "🍟"), ("crisp", "🍟"),
            ("bread", "🍞"), ("cereal", "🥣"), ("pasta", "🍝"), ("rice", "🍚"),
            ("meat", "🥩"), ("chicken", "🍗"), ("fish", "🐟"), ("seafood", "🦐"),
            ("fruit", "🍎"), ("vegetable", "🥦"),
            ("sauce", "🥫"), ("soup", "🍲"), ("oil", "🫒"),
            ("ice-cream", "🍨"), ("frozen", "🧊"), ("egg", "🥚")
        ]
        for (key, emoji) in map where joined.contains(key) { return emoji }
        return "🛒"
    }
}

// MARK: - Open Food Facts DTOs

struct OFFResponse: Decodable {
    let product: OFFProduct?
}

struct OFFProduct: Decodable {
    let productName: String?
    let brands: String?
    let quantity: String?
    let nutriscoreGrade: String?
    let novaGroup: Int?
    let nutriments: OFFNutriments?
    let additivesTags: [String]?
    let ingredientsText: String?
    let categoriesTags: [String]?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands, quantity
        case nutriscoreGrade = "nutriscore_grade"
        case novaGroup = "nova_group"
        case nutriments
        case additivesTags = "additives_tags"
        case ingredientsText = "ingredients_text"
        case categoriesTags = "categories_tags"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        productName = try? c.decodeIfPresent(String.self, forKey: .productName)
        brands = try? c.decodeIfPresent(String.self, forKey: .brands)
        quantity = try? c.decodeIfPresent(String.self, forKey: .quantity)
        nutriscoreGrade = try? c.decodeIfPresent(String.self, forKey: .nutriscoreGrade)
        nutriments = try? c.decodeIfPresent(OFFNutriments.self, forKey: .nutriments)
        additivesTags = try? c.decodeIfPresent([String].self, forKey: .additivesTags)
        ingredientsText = try? c.decodeIfPresent(String.self, forKey: .ingredientsText)
        categoriesTags = try? c.decodeIfPresent([String].self, forKey: .categoriesTags)
        // nova_group may arrive as Int, Double, or String — decode flexibly.
        if let i = try? c.decodeIfPresent(Int.self, forKey: .novaGroup) {
            novaGroup = i
        } else if let d = try? c.decodeIfPresent(Double.self, forKey: .novaGroup) {
            novaGroup = Int(d)
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .novaGroup) {
            novaGroup = Int(s)
        } else {
            novaGroup = nil
        }
    }
}

struct OFFNutriments: Decodable {
    let sugars: Double?
    let sodium: Double?
    let salt: Double?
    let saturatedFat: Double?
    let transFat: Double?
    let fiber: Double?
    let proteins: Double?
    let calcium: Double?
    let caffeine: Double?

    enum CodingKeys: String, CodingKey {
        case sugars = "sugars_100g"
        case sodium = "sodium_100g"
        case salt = "salt_100g"
        case saturatedFat = "saturated-fat_100g"
        case transFat = "trans-fat_100g"
        case fiber = "fiber_100g"
        case proteins = "proteins_100g"
        case calcium = "calcium_100g"
        case caffeine = "caffeine_100g"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // OFF nutriment values are usually numbers but can occasionally be strings.
        func value(_ key: CodingKeys) -> Double? {
            if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
            if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
            return nil
        }
        sugars = value(.sugars)
        sodium = value(.sodium)
        salt = value(.salt)
        saturatedFat = value(.saturatedFat)
        transFat = value(.transFat)
        fiber = value(.fiber)
        proteins = value(.proteins)
        calcium = value(.calcium)
        caffeine = value(.caffeine)
    }
}
