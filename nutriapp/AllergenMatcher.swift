import Foundation

// MARK: - Allergen matching
//
// Deterministic, rule-based allergen detection — intentionally NOT an LLM task.
// A probabilistic model must never be the gate on whether a product is safe for
// someone with an allergy. We match the user's declared allergens against Open
// Food Facts' structured allergen tags first (high confidence) and fall back to
// scanning the ingredient text (lower confidence). Because OFF data is
// crowdsourced and may be incomplete, a non-match never implies "safe" — the UI
// always tells the user to check the physical packaging.

enum AllergenCatalog {
    /// One selectable allergen: the label shown in the UI, the OFF allergen tags
    /// that map to it, and ingredient-text keywords as a fallback signal.
    struct Entry {
        let label: String
        let tags: [String]
        let keywords: [String]
    }

    /// The 8 most common major allergens.
    static let common: [Entry] = [
        Entry(label: "Milk",
              tags: ["milk"],
              keywords: ["milk", "dairy", "lactose", "whey", "casein", "butter", "cheese", "cream"]),
        Entry(label: "Eggs",
              tags: ["eggs"],
              keywords: ["egg"]),
        Entry(label: "Peanuts",
              tags: ["peanuts"],
              keywords: ["peanut", "groundnut"]),
        Entry(label: "Tree nuts",
              tags: ["nuts"],
              keywords: ["almond", "hazelnut", "walnut", "cashew", "pistachio",
                         "pecan", "macadamia", "brazil nut", "tree nut"]),
        Entry(label: "Soy",
              tags: ["soybeans"],
              keywords: ["soy", "soya", "soybean"]),
        Entry(label: "Wheat / gluten",
              tags: ["gluten"],
              keywords: ["wheat", "gluten", "barley", "rye", "spelt"]),
        Entry(label: "Fish",
              tags: ["fish"],
              keywords: ["fish", "cod", "salmon", "tuna", "anchovy", "haddock", "sardine"]),
        Entry(label: "Shellfish",
              tags: ["crustaceans", "molluscs"],
              keywords: ["shrimp", "prawn", "crab", "lobster", "shellfish",
                         "mussel", "oyster", "clam", "squid", "scallop"]),
    ]

    /// The labels offered as selectable chips in the UI.
    static var labels: [String] { common.map(\.label) }

    static func entry(forLabel label: String) -> Entry? {
        common.first { $0.label.caseInsensitiveCompare(label) == .orderedSame }
    }
}

struct AllergenWarning: Identifiable, Hashable {
    let id = UUID()
    let label: String
    /// true when matched via an OFF allergen tag (high confidence) vs. only an
    /// ingredient-text keyword (lower confidence).
    let fromTag: Bool
}

enum AllergenMatcher {

    /// Returns one warning per user allergen the product appears to contain.
    static func warnings(product: Product, allergies: [String]) -> [AllergenWarning] {
        guard !allergies.isEmpty else { return [] }
        let tags = Set(product.allergenTags ?? [])
        let ingredients = (product.ingredientsText ?? "").lowercased()

        var results: [AllergenWarning] = []
        for allergy in allergies {
            if let entry = AllergenCatalog.entry(forLabel: allergy) {
                // Preset allergen: structured tag match first, then keywords.
                if !tags.isDisjoint(with: entry.tags) {
                    results.append(AllergenWarning(label: allergy, fromTag: true))
                } else if entry.keywords.contains(where: { ingredients.contains($0) }) {
                    results.append(AllergenWarning(label: allergy, fromTag: false))
                }
            } else {
                // Free-text allergen: keyword match against ingredients / tag names.
                let needle = allergy.lowercased().trimmingCharacters(in: .whitespaces)
                guard needle.count >= 3 else { continue }
                if ingredients.contains(needle) || tags.contains(where: { $0.contains(needle) }) {
                    results.append(AllergenWarning(label: allergy, fromTag: false))
                }
            }
        }
        return results
    }
}
