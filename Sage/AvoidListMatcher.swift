import Foundation

/// Curated synonym matching for user avoid-list categories.
/// Seed oils are matched against OFF ingredient tags/shares first, then
/// normalized ingredient text — including hydrogenated / parenthetical forms
/// like "fully hydrogenated vegetable oils (rapeseed and soybean)".
enum AvoidListMatcher {

    /// Crop / oil names that count as seed oils (not olive, avocado, coconut, palm).
    private static let seedOilCrops = [
        "canola", "rapeseed", "soybean", "soya", "sunflower",
        "cottonseed", "grapeseed", "safflower", "rice bran", "corn",
    ]

    private static let seedOilPhrases = [
        "canola oil", "rapeseed oil", "soybean oil", "soya oil",
        "sunflower oil", "corn oil", "cottonseed oil", "grapeseed oil",
        "safflower oil", "rice bran oil", "rice-bran oil",
        // Parenthetical crop lists (common on US labels)
        "rapeseed and soybean", "rapeseed & soybean",
        "soybean and rapeseed", "soybean & rapeseed",
        // pt-BR
        "óleo de soja", "oleo de soja", "óleo de canola", "oleo de canola",
        "óleo de girassol", "oleo de girassol", "óleo de milho", "oleo de milho",
        "óleo de algodão", "oleo de algodao", "óleo de algodao",
        "óleo de nabo", "oleo de nabo",
    ]

    /// True when the product contains seed oils (informational + avoid matching).
    static func containsSeedOils(
        ingredientsText: String?,
        ingredientShares: [IngredientShare]? = nil,
        ingredientTags: [String]? = nil
    ) -> Bool {
        let text = (ingredientsText ?? "").lowercased()
        if matchesSeedOilText(text) { return true }

        let shareNames = (ingredientShares ?? []).map { $0.name.lowercased() }
        let tags = (ingredientTags ?? []).map { $0.lowercased() }
        if (shareNames + tags).contains(where: isSeedOilTag) { return true }

        // Bare crop names only when the text already frames them as oils
        // (hydrogenated / vegetable oils listings) — avoids "corn syrup" + olive oil.
        if hasVegetableOrHydrogenatedOilContext(text) {
            for crop in seedOilCrops where text.contains(crop) {
                return true
            }
        }
        return false
    }

    /// Match a single avoid-list item against product signals.
    static func matches(
        item: String,
        entry: RulesetV4.AvoidEntry?,
        product: Product
    ) -> Bool {
        let key = item.lowercased()
        if key == "seed oils" {
            if product.seedOils { return true }
            if containsSeedOils(
                ingredientsText: product.ingredientsText,
                ingredientShares: product.ingredientShares,
                ingredientTags: product.ingredientShares?.map(\.name)
            ) { return true }
        }

        if key == "caffeine", matchesCaffeineAvoid(product: product) {
            return true
        }

        guard let entry else { return false }

        let codes = Set(product.additives.compactMap(\.code))
        if let c = entry.codes, !codes.isDisjoint(with: Set(c)) { return true }

        let labels = Set(product.labels ?? [])
        if let l = entry.labels, !labels.isDisjoint(with: Set(l)) { return true }

        let text = (product.ingredientsText ?? "").lowercased()
        let shareBlob = (product.ingredientShares ?? [])
            .map { $0.name.lowercased() }
            .joined(separator: " ")
        let haystack = text + " " + shareBlob

        if let needles = entry.text {
            for needle in needles where haystack.contains(needle.lowercased()) {
                // "fully hydrogenated" alone is too broad (palm etc.) — only
                // accept it when a seed-oil crop also appears.
                let n = needle.lowercased()
                if n == "fully hydrogenated" || n == "partially hydrogenated" {
                    if seedOilCrops.contains(where: { haystack.contains($0) }) { return true }
                    continue
                }
                if n.contains("hydrogenated vegetable") {
                    if seedOilCrops.contains(where: { haystack.contains($0) })
                        || key == "seed oils" {
                        // Still require a crop for seed oils; palm is separate.
                        if seedOilCrops.contains(where: { haystack.contains($0) }) { return true }
                    }
                    continue
                }
                return true
            }
        }

        if key == "seed oils", matchesSeedOilText(haystack) { return true }
        return false
    }

    // MARK: - Caffeine (category + text)

    /// Category-based caffeine avoid: coffees, non-herbal teas, energy drinks,
    /// colas, mate — unless decaf markers appear in name/labels/categories.
    private static let caffeineCategories = [
        "coffees", "coffee", "teas", "tea", "energy-drinks", "energy-drink",
        "colas", "cola", "mate", "yerba-mate",
    ]
    private static let herbalTeaMarkers = ["herbal", "infusion", "tisane"]
    private static let decafMarkers = ["decaffeinated", "descafeinado", "decaf"]

    private static func matchesCaffeineAvoid(product: Product) -> Bool {
        if (product.caffeine_mg ?? 0) > 0 { return true }

        let name = product.name.lowercased()
        let labels = (product.labels ?? []).map { $0.lowercased() }
        let cats = (product.categories ?? []).map { $0.lowercased() }
        let blob = ([name] + labels + cats + [product.ingredientsText?.lowercased() ?? ""])
            .joined(separator: " ")
        if decafMarkers.contains(where: { blob.contains($0) }) { return false }

        for cat in cats {
            if caffeineCategories.contains(where: { cat == $0 || cat.contains($0) }) {
                // Herbal teas: category "teas" but herbal → not caffeine avoid.
                if cat.contains("tea"), herbalTeaMarkers.contains(where: { blob.contains($0) }) {
                    continue
                }
                return true
            }
        }
        return false
    }

    // MARK: - Internals

    private static func matchesSeedOilText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        for phrase in seedOilPhrases where text.contains(phrase) {
            return true
        }
        for crop in seedOilCrops {
            if text.contains("\(crop) oil") { return true }
            if text.contains("oil of \(crop)") { return true }
        }
        return false
    }

    private static func hasVegetableOrHydrogenatedOilContext(_ text: String) -> Bool {
        text.contains("hydrogenated")
            || text.contains("vegetable oil")
            || text.contains("vegetable oils")
            || text.contains("óleo vegetal")
            || text.contains("oleo vegetal")
    }

    private static func isSeedOilTag(_ tag: String) -> Bool {
        let t = tag.replacingOccurrences(of: "_", with: "-")
        let oilish = t.contains("oil") || t.contains("oleo") || t.contains("óleo")
        guard oilish else { return false }
        return seedOilCrops.contains {
            t.contains($0.replacingOccurrences(of: " ", with: "-")) || t.contains($0)
        }
    }
}
