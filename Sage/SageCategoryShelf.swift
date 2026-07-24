import Foundation

// MARK: - SageCategory → alternatives shelf routing (ALTERNATIVES_SPEC.md §1)
//
// Maps a scanned product to one of the alternatives shelves via exact OFF
// category-tag membership (same style as the ruleset router). Not every
// `SageCategory` browse shelf is an alternatives shelf: `coffee` is scored but
// deliberately shelf-excluded, and `water` is unsupported — both get no def, so
// `shelf(for:)` returns nil and no alternatives row shows (§7).
//
// Tag tables are seed values mined from OFF; refine against real tag frequency.

extension SageCategory {

    private struct ShelfDef {
        let shelf: SageCategory
        let rootTags: [String]   // membership (any hit → this shelf)
        let subTags: [String]    // finer tags, for same-subtype preference (anchorTag)
    }

    // Ordered: least-ambiguous shelves first, so a product carrying tags from two
    // shelves lands in the more specific one (first match wins).
    private static let defs: [ShelfDef] = [
        ShelfDef(shelf: .babyFood,
                 rootTags: ["baby-foods", "baby-milks", "infant-formulas"],
                 subTags: ["infant-formulas", "follow-on-formulas", "baby-cereals",
                           "baby-fruit-purees", "baby-vegetable-purees", "baby-snacks",
                           "toddler-milks"]),
        ShelfDef(shelf: .iceCream,
                 rootTags: ["ice-creams", "frozen-desserts", "ice-creams-and-sorbets",
                            "frozen-yogurts"],
                 subTags: ["vanilla-ice-creams", "chocolate-ice-creams", "sorbets",
                           "gelatos", "ice-cream-bars", "ice-cream-tubs",
                           "ice-cream-cones", "mochi-ice-cream"]),
        ShelfDef(shelf: .cheese,
                 rootTags: ["cheeses"],
                 subTags: ["cheddar-cheese", "mozzarella", "goat-cheeses", "cream-cheeses",
                           "cottage-cheeses", "sliced-cheeses", "blue-cheeses",
                           "soft-cheeses", "hard-cheeses", "grated-cheeses", "string-cheeses"]),
        ShelfDef(shelf: .yogurt,
                 rootTags: ["yogurts", "fermented-milk-products", "drinkable-yogurts"],
                 subTags: ["greek-yogurts", "plain-yogurts", "fruit-yogurts", "skyr",
                           "kefir", "flavored-yogurts", "yogurt-drinks"]),
        ShelfDef(shelf: .cookies,
                 rootTags: ["biscuits", "cookies", "biscuits-and-cakes"],
                 subTags: ["chocolate-chip-cookies", "shortbread-cookies", "sandwich-cookies",
                           "wafers", "digestive-biscuits", "chocolate-biscuits"]),
        ShelfDef(shelf: .chocolate,
                 rootTags: ["chocolates", "chocolate-candies", "chocolate-bars"],
                 subTags: ["dark-chocolates", "milk-chocolates", "white-chocolates",
                           "filled-chocolates", "chocolate-truffles", "pralines"]),
        ShelfDef(shelf: .cereal,
                 rootTags: ["breakfast-cereals"],
                 subTags: ["mueslis", "granolas", "corn-flakes", "chocolate-cereals",
                           "oat-cereals", "puffed-cereals", "bran-cereals"]),
        ShelfDef(shelf: .bread,
                 rootTags: ["breads"],
                 subTags: ["white-breads", "whole-wheat-breads", "whole-grain-breads",
                           "sourdough-breads", "baguettes", "sandwich-breads",
                           "flatbreads", "bagels", "buns", "rye-breads"]),
        ShelfDef(shelf: .pasta,
                 rootTags: ["pastas"],
                 subTags: ["dry-pastas", "fresh-pastas", "stuffed-pastas",
                           "whole-grain-pastas", "egg-pastas", "spaghetti", "penne", "macaroni"]),
        ShelfDef(shelf: .juice,
                 rootTags: ["fruit-juices", "juices", "vegetable-juices"],
                 subTags: ["orange-juices", "apple-juices", "grape-juices", "pineapple-juices",
                           "multifruit-juices", "cranberry-juices", "tomato-juices",
                           "smoothies", "fruit-nectars"]),
        ShelfDef(shelf: .soda,
                 rootTags: ["sodas", "soft-drinks", "carbonated-drinks"],
                 subTags: ["colas", "lemonades", "orange-sodas", "ginger-ales",
                           "tonic-waters", "root-beers"]),
        ShelfDef(shelf: .chips,
                 rootTags: ["chips-and-fries", "crisps", "potato-crisps"],
                 subTags: ["tortilla-chips", "corn-chips", "vegetable-crisps",
                           "potato-chips", "kettle-chips"]),
    ]

    /// The alternatives shelf a scanned product belongs to, or nil when none of
    /// the shelves apply (incl. coffee/water/alcohol/sweetener scans).
    static func shelf(for product: Product) -> SageCategory? {
        let tags = Set(product.categories ?? [])
        guard !tags.isEmpty else { return nil }
        for def in defs where !tags.isDisjoint(with: Set(def.rootTags + def.subTags)) {
            return def.shelf
        }
        return nil
    }

    /// The scanned product's most-specific OFF tag within this shelf (e.g.
    /// "grape-juices"), for same-subtype preference. nil when only a root tag matched.
    func anchorTag(for product: Product) -> String? {
        guard let def = SageCategory.defs.first(where: { $0.shelf == self }) else { return nil }
        let tags = Set(product.categories ?? [])
        return def.subTags.first(where: tags.contains)
    }

    /// Whether this category has a Top Rated / alternatives list. False for the
    /// two categories with no data — water (unsupported) and coffee (deliberately
    /// shelf-excluded) — which the Top Rated grid shows greyed out (TOPRATED_SPEC §2).
    @MainActor var hasTopRated: Bool {
        !AlternativesStore.candidates(for: self).isEmpty
    }
}
