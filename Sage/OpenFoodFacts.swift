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

    static func additive(for tag: String) -> ProductAdditive {
        let code = normalize(tag)
        if let info = entries[code] {
            return ProductAdditive(name: info.name, risk: info.risk, note: info.note, code: code)
        }
        // Unknown additive: show the code, no risk judgment.
        return ProductAdditive(name: code.uppercased(), risk: .unrated, code: code)
    }

    /// Maps an AdditiveDetector hit into the product model used by scoring + UI.
    static func productAdditive(from detected: Additive) -> ProductAdditive {
        let code = normalize(detected.eNumber)
        let catalog = entries[code]
        return ProductAdditive(
            name: detected.commonName,
            risk: risk(for: detected.tier),
            note: catalog?.note,
            code: code,
            tier: detected.tier
        )
    }

    /// Display/scoring risk from detector tier (major → high, etc.).
    static func risk(for tier: AdditiveTier) -> RiskLevel {
        switch tier {
        case .major: return .high
        case .moderate: return .moderate
        case .mild, .soft: return .low
        case .exempt: return .low
        case .unclassified: return .unrated
        }
    }

    /// v3 additive-penalty weight from detector tier.
    static func penaltyWeight(for tier: AdditiveTier) -> Double {
        switch tier {
        case .major: return 1.5
        case .moderate: return 0.75
        case .mild, .soft: return 0.25
        // Detected but not classified — we have no evidence to flag it, so it
        // costs nothing (matches the neutral "UNRATED" the UI shows).
        case .unclassified: return 0
        case .exempt: return 0
        }
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
        "additives_tags", "ingredients_analysis_tags", "allergens_tags",
        "ingredients_text", "categories_tags",
        "image_front_url", "image_url",
        // Scoring-v4 data foundation (kept in sync with the Worker's list).
        "labels_tags", "packagings", "packaging_materials_tags",
        "origins_tags", "manufacturing_places", "ingredients",
        "ecoscore_grade", "environmental_score_grade",
        "completeness", "states_tags", "last_modified_t",
        "serving_size", "countries_tags", "unknown_ingredients_n"
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
            calcium_mg: n?.calcium.map { $0 * 1000 },
            kcal: n?.energyKcal ?? n?.energyKj.map { $0 / 4.184 },  // kJ→kcal fallback
            fvn: n?.fvn,
            addedSugar_g: n?.addedSugars,
            // OFF stores minerals & vitamin C in grams/100g → scale to mg.
            iron_mg: n?.iron.map { $0 * 1000 },
            potassium_mg: n?.potassium.map { $0 * 1000 },
            magnesium_mg: n?.magnesium.map { $0 * 1000 },
            zinc_mg: n?.zinc.map { $0 * 1000 },
            vitaminC_mg: n?.vitaminC.map { $0 * 1000 }
        )

        let additivesScan = scanAdditives(off)
        let additives = additivesScan.additives.map { AdditiveCatalog.productAdditive(from: $0) }
        let sweetenerCodes = additives.compactMap(\.code) + (off.additivesTags ?? []).map { AdditiveCatalog.normalize($0) }
        let sweeteners = detectSweeteners(sweetenerCodes)
        let seedOils = detectSeedOils(off.ingredientsText)
        let transFats = (n?.transFat ?? 0) > 0
        let dietFlags = detectDietFlags(analysis: off.ingredientsAnalysisTags ?? [],
                                        allergens: off.allergensTags ?? [])
        let allergenTags = (off.allergensTags ?? []).map { AdditiveCatalog.normalize($0) }

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
            restrictions: [],            // populated by the ScoringEngine per profile
            dietFlags: dietFlags,
            allergenTags: allergenTags,
            ingredientsText: off.ingredientsText,
            imageURL: sanitizedImageURL(off.imageFrontUrl ?? off.imageUrl),
            labels: normalizedTags(off.labelsTags),
            packagingMaterials: packagingMaterials(off),
            origins: normalizedTags(off.originsTags),
            ingredientShares: ingredientShares(off.ingredients),
            ecoGrade: ecoGrade(off),
            servingSize: off.servingSize?.isEmpty == false ? off.servingSize : nil,
            completeness: off.completeness,
            lastModified: off.lastModifiedT.map { Date(timeIntervalSince1970: $0) },
            countries: normalizedTags(off.countriesTags),
            categories: normalizedTags(off.categoriesTags),
            additiveUndercountSuspected: additivesScan.undercountSuspected,
            additiveIngredientTextMissing: additivesScan.ingredientTextMissing,
            dataSource: off.source
        )
    }

    // MARK: Additive detection

    private static func scanAdditives(_ off: OFFProduct) -> AdditiveScanResult {
        AdditiveDetector.scan(
            ingredientsText: off.ingredientsText,
            offAdditiveTags: off.additivesTags ?? [],
            hasUnrecognizedIngredients: hasUnrecognizedIngredients(off)
        )
    }

    private static func hasUnrecognizedIngredients(_ off: OFFProduct) -> Bool {
        if let n = off.unknownIngredientsN, n > 0 { return true }
        return (off.ingredients ?? []).contains { $0.isInTaxonomy == 0 }
    }

    // MARK: Scoring-v4 field mapping

    private static func normalizedTags(_ tags: [String]?) -> [String]? {
        guard let tags, !tags.isEmpty else { return nil }
        return tags.map { AdditiveCatalog.normalize($0) }
    }

    /// Merge structured `packagings[].material` with the flat materials tags;
    /// deduped, normalized. Empty → nil ("no packaging data" state for S7).
    private static func packagingMaterials(_ off: OFFProduct) -> [String]? {
        var out: [String] = []
        for m in (off.packagings ?? []).compactMap(\.material) {
            let n = AdditiveCatalog.normalize(m)
            if !n.isEmpty, !out.contains(n) { out.append(n) }
        }
        for t in off.packagingMaterialsTags ?? [] {
            let n = AdditiveCatalog.normalize(t)
            if !n.isEmpty, !out.contains(n) { out.append(n) }
        }
        return out.isEmpty ? nil : out
    }

    private static func ingredientShares(_ ingredients: [OFFIngredient]?) -> [IngredientShare]? {
        guard let ingredients, !ingredients.isEmpty else { return nil }
        let shares = ingredients.compactMap { ing -> IngredientShare? in
            guard let raw = ing.id ?? ing.text else { return nil }
            return IngredientShare(name: AdditiveCatalog.normalize(raw),
                                   percent: ing.percent,
                                   percentEstimate: ing.percentEstimate)
        }
        return shares.isEmpty ? nil : shares
    }

    /// "a"–"e" only; OFF also emits "not-applicable"/"unknown", which we treat
    /// as no data. Newer OFF versions rename ecoscore → environmental score.
    private static func ecoGrade(_ off: OFFProduct) -> String? {
        for g in [off.ecoscoreGrade, off.environmentalScoreGrade] {
            if let g = g?.lowercased(), g.count == 1, ("a"..."e").contains(g) { return g }
        }
        return nil
    }

    /// Only keep a usable image URL: non-empty, parseable, and https (ATS
    /// blocks plain http anyway). Anything else is the designed "no image"
    /// state, not an error.
    static func sanitizedImageURL(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty,
              let url = URL(string: s),
              url.scheme?.lowercased() == "https"
        else { return nil }
        return s
    }

    /// Normalize OFF ingredient-analysis + allergen tags into simple diet flags
    /// the ScoringEngine can match against profile restrictions.
    static func detectDietFlags(analysis: [String], allergens: [String]) -> [String] {
        var flags: Set<String> = []
        for tag in analysis {
            switch AdditiveCatalog.normalize(tag) {
            case "non-vegan":       flags.insert("non-vegan")
            case "vegan":           flags.insert("vegan")
            case "non-vegetarian":  flags.insert("non-vegetarian")
            case "vegetarian":      flags.insert("vegetarian")
            case "palm-oil":        flags.insert("palm-oil")
            default: break
            }
        }
        for tag in allergens {
            switch AdditiveCatalog.normalize(tag) {
            case "gluten": flags.insert("gluten")
            case "milk":   flags.insert("milk")
            case "fish":   flags.insert("fish")
            default: break
            }
        }
        return Array(flags)
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

    static func detectSweeteners(_ codes: [String]) -> [String] {
        var seen: [String] = []
        for tag in codes {
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
    let ingredientsAnalysisTags: [String]?
    let allergensTags: [String]?
    let ingredientsText: String?
    let categoriesTags: [String]?
    let imageFrontUrl: String?
    let imageUrl: String?
    let labelsTags: [String]?
    let packagings: [OFFPackaging]?
    let packagingMaterialsTags: [String]?
    let originsTags: [String]?
    let ingredients: [OFFIngredient]?
    let ecoscoreGrade: String?
    let environmentalScoreGrade: String?
    let completeness: Double?
    let lastModifiedT: Double?
    let servingSize: String?
    let countriesTags: [String]?
    let unknownIngredientsN: Int?
    let source: String?   // Worker-injected `_source`: "usda" | "off+usda" (nil = pure OFF)

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands, quantity
        case nutriscoreGrade = "nutriscore_grade"
        case novaGroup = "nova_group"
        case nutriments
        case additivesTags = "additives_tags"
        case ingredientsAnalysisTags = "ingredients_analysis_tags"
        case allergensTags = "allergens_tags"
        case ingredientsText = "ingredients_text"
        case categoriesTags = "categories_tags"
        case imageFrontUrl = "image_front_url"
        case imageUrl = "image_url"
        case labelsTags = "labels_tags"
        case packagings
        case packagingMaterialsTags = "packaging_materials_tags"
        case originsTags = "origins_tags"
        case ingredients
        case ecoscoreGrade = "ecoscore_grade"
        case environmentalScoreGrade = "environmental_score_grade"
        case completeness
        case lastModifiedT = "last_modified_t"
        case servingSize = "serving_size"
        case countriesTags = "countries_tags"
        case unknownIngredientsN = "unknown_ingredients_n"
        case source = "_source"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        productName = try? c.decodeIfPresent(String.self, forKey: .productName)
        brands = try? c.decodeIfPresent(String.self, forKey: .brands)
        quantity = try? c.decodeIfPresent(String.self, forKey: .quantity)
        nutriscoreGrade = try? c.decodeIfPresent(String.self, forKey: .nutriscoreGrade)
        nutriments = try? c.decodeIfPresent(OFFNutriments.self, forKey: .nutriments)
        additivesTags = try? c.decodeIfPresent([String].self, forKey: .additivesTags)
        ingredientsAnalysisTags = try? c.decodeIfPresent([String].self, forKey: .ingredientsAnalysisTags)
        allergensTags = try? c.decodeIfPresent([String].self, forKey: .allergensTags)
        ingredientsText = try? c.decodeIfPresent(String.self, forKey: .ingredientsText)
        categoriesTags = try? c.decodeIfPresent([String].self, forKey: .categoriesTags)
        imageFrontUrl = try? c.decodeIfPresent(String.self, forKey: .imageFrontUrl)
        imageUrl = try? c.decodeIfPresent(String.self, forKey: .imageUrl)
        labelsTags = try? c.decodeIfPresent([String].self, forKey: .labelsTags)
        packagings = try? c.decodeIfPresent([OFFPackaging].self, forKey: .packagings)
        packagingMaterialsTags = try? c.decodeIfPresent([String].self, forKey: .packagingMaterialsTags)
        originsTags = try? c.decodeIfPresent([String].self, forKey: .originsTags)
        ingredients = try? c.decodeIfPresent([OFFIngredient].self, forKey: .ingredients)
        ecoscoreGrade = try? c.decodeIfPresent(String.self, forKey: .ecoscoreGrade)
        environmentalScoreGrade = try? c.decodeIfPresent(String.self, forKey: .environmentalScoreGrade)
        completeness = try? c.decodeIfPresent(Double.self, forKey: .completeness)
        // Epoch seconds, but occasionally a string in old records.
        if let d = try? c.decodeIfPresent(Double.self, forKey: .lastModifiedT) {
            lastModifiedT = d
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .lastModifiedT) {
            lastModifiedT = Double(s)
        } else {
            lastModifiedT = nil
        }
        servingSize = try? c.decodeIfPresent(String.self, forKey: .servingSize)
        countriesTags = try? c.decodeIfPresent([String].self, forKey: .countriesTags)
        if let i = try? c.decodeIfPresent(Int.self, forKey: .unknownIngredientsN) {
            unknownIngredientsN = i
        } else if let d = try? c.decodeIfPresent(Double.self, forKey: .unknownIngredientsN) {
            unknownIngredientsN = Int(d)
        } else {
            unknownIngredientsN = nil
        }
        source = try? c.decodeIfPresent(String.self, forKey: .source)
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

/// One entry of OFF's structured `packagings[]` array.
struct OFFPackaging: Decodable {
    let material: String?
}

/// One entry of OFF's parsed `ingredients[]` array. Percent fields arrive as
/// numbers or strings depending on record age — decode leniently.
struct OFFIngredient: Decodable {
    let id: String?
    let text: String?
    let percent: Double?
    let percentEstimate: Double?
    let isInTaxonomy: Int?

    enum CodingKeys: String, CodingKey {
        case id, text, percent
        case percentEstimate = "percent_estimate"
        case isInTaxonomy = "is_in_taxonomy"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decodeIfPresent(String.self, forKey: .id)
        text = try? c.decodeIfPresent(String.self, forKey: .text)
        func value(_ key: CodingKeys) -> Double? {
            if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
            if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
            return nil
        }
        percent = value(.percent)
        percentEstimate = value(.percentEstimate)
        if let i = try? c.decodeIfPresent(Int.self, forKey: .isInTaxonomy) {
            isInTaxonomy = i
        } else if let b = try? c.decodeIfPresent(Bool.self, forKey: .isInTaxonomy) {
            isInTaxonomy = b ? 1 : 0
        } else {
            isInTaxonomy = nil
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
    let energyKcal: Double?
    let energyKj: Double?   // fallback when kcal is absent (common for EU products)
    let fvn: Double?        // fruit/veg/nuts estimate 0–100
    let addedSugars: Double? // mostly US labels; v4 S3 prefers it over total sugars
    // Beneficial micronutrients — OFF reports minerals in grams/100g (scaled to
    // mg at the mapping site, like calcium). Feed scoring v4's S13 credit.
    let iron: Double?
    let potassium: Double?
    let magnesium: Double?
    let zinc: Double?
    let vitaminC: Double?

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
        case energyKcal = "energy-kcal_100g"
        case energyKj = "energy-kj_100g"
        case fvnNuts = "fruits-vegetables-nuts-estimate-from-ingredients_100g"
        case fvnLegumes = "fruits-vegetables-legumes-estimate-from-ingredients_100g"
        case addedSugars = "added-sugars_100g"
        case iron = "iron_100g"
        case potassium = "potassium_100g"
        case magnesium = "magnesium_100g"
        case zinc = "zinc_100g"
        case vitaminC = "vitamin-c_100g"
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
        energyKcal = value(.energyKcal)
        energyKj = value(.energyKj)
        // OFF populates the "nuts" or the newer "legumes" variant depending on version.
        fvn = value(.fvnNuts) ?? value(.fvnLegumes)
        addedSugars = value(.addedSugars)
        iron = value(.iron)
        potassium = value(.potassium)
        magnesium = value(.magnesium)
        zinc = value(.zinc)
        vitaminC = value(.vitaminC)
    }
}
