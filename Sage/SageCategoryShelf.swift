import Foundation

// MARK: - SageCategory → alternatives shelf routing (ALTERNATIVES_SPEC.md §1)
//
// Maps a scanned product to one of the alternatives shelves via exact OFF
// category-tag membership (same style as the ruleset router). Not every
// `SageCategory` browse shelf is an alternatives shelf: `coffee` is scored but
// deliberately shelf-excluded, and `water` is unsupported — both get no def, so
// `shelf(for:)` returns nil and no alternatives row shows (§7).
//
// A shelf is deliberately coarse (coverage). Two finer layers sit on top of it
// so a suggestion is something the shopper would actually pick up instead:
//
//  • `anchorTag` — the product's most-specific OFF sub-tag (grape → grape).
//  • `form`      — the *kind of thing* it is within the shelf (a loaf vs a
//                  tortilla, a cheddar block vs cottage cheese, a candy bar vs
//                  baking chocolate, cow's milk vs oat milk). Forms carry a
//                  compatibility `group`; a candidate in a different group is
//                  never suggested, and some forms are not suggestible at all
//                  (infant formula, baking chocolate, lemon juice, caffeine
//                  tablets — things that leaked into a shelf via OFF's
//                  community tags but are not swaps for anything).
//
// Tag tables are seed values mined from OFF; refine against real tag frequency.

extension SageCategory {

    /// A product form within a shelf. First matching form wins (tags, then
    /// name pattern); `defaultForm` applies when nothing matches.
    struct ShelfForm: Equatable {
        let id: String
        /// Compatibility group — candidates must share the scanned product's
        /// group (when both are known) to be suggested. Often == id; differs
        /// where two forms are interchangeable in use (butter ↔ margarine).
        let group: String
        let tags: [String]
        /// Case-insensitive regex over brand + name for tag-less records.
        let namePattern: String?
        /// False ⇒ never offered as a swap (still routable when scanned).
        let suggestible: Bool
        /// Compiled once (the tables are static); `form(of:)` runs per
        /// candidate per scan, and compiling ~10 patterns each time was the
        /// dominant cost of a suggestion pass.
        private let nameRegex: NSRegularExpression?

        init(_ id: String, group: String? = nil, tags: [String] = [],
             name: String? = nil, suggestible: Bool = true) {
            self.id = id
            self.group = group ?? id
            self.tags = tags
            self.namePattern = name
            self.suggestible = suggestible
            self.nameRegex = name.flatMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        }

        func nameMatches(_ haystack: String) -> Bool {
            guard let nameRegex else { return false }
            let range = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
            return nameRegex.firstMatch(in: haystack, options: [], range: range) != nil
        }

        static func == (lhs: ShelfForm, rhs: ShelfForm) -> Bool {
            lhs.id == rhs.id && lhs.group == rhs.group
        }
    }

    private struct ShelfDef {
        let shelf: SageCategory
        let rootTags: [String]   // membership (any hit → this shelf)
        let subTags: [String]    // finer tags, for same-subtype preference (anchorTag)
        let forms: [ShelfForm]
        let defaultForm: String?

        init(shelf: SageCategory, rootTags: [String], subTags: [String],
             forms: [ShelfForm] = [], defaultForm: String? = nil) {
            self.shelf = shelf
            self.rootTags = rootTags
            self.subTags = subTags
            self.forms = forms
            self.defaultForm = defaultForm
        }
    }

    // Ordered: least-ambiguous shelves first, so a product carrying tags from two
    // shelves lands in the more specific one (first match wins).
    private static let defs: [ShelfDef] = [
        // Infant formula / baby milks are deliberately NOT routed here (and
        // never suggestible): formula is a medical-adjacent staple, not a snack
        // you swap for a fruit pouch. It falls through to `.noShelf`.
        ShelfDef(shelf: .babyFood,
                 rootTags: ["baby-foods"],
                 subTags: ["baby-cereals", "baby-fruit-purees", "baby-vegetable-purees",
                           "baby-snacks", "snacks-and-desserts-for-babies"],
                 forms: [
                    ShelfForm("formula", tags: ["infant-formulas", "baby-milks", "follow-on-formulas",
                                                "toddler-milks", "baby-milks-in-powder"],
                              name: #"formula|infant milk|toddler milk|nutritional supplement"#,
                              suggestible: false),
                    ShelfForm("cereal", tags: ["baby-cereals"], name: #"\bcereal|oatmeal|porridge"#),
                    ShelfForm("yogurt", tags: ["yogurts", "dairy-dessert-for-baby"], name: #"yogurt|yoghurt"#),
                    ShelfForm("snack", tags: ["baby-snacks"],
                              name: #"puffs?\b|melts?\b|teeth|wafer|crisps?\b|snack|bites\b|\bbars?\b|crackers?\b|yogis"#),
                    ShelfForm("puree", tags: ["baby-fruit-purees", "baby-vegetable-purees", "fruit-purees",
                                              "vegetable-purees", "baby-food-purees"],
                              name: #"pur[eé]e|pouch|squeeze|blend"#),
                 ]),
        ShelfDef(shelf: .iceCream,
                 rootTags: ["ice-creams", "frozen-desserts", "ice-creams-and-sorbets",
                            "frozen-yogurts"],
                 subTags: ["vanilla-ice-creams", "chocolate-ice-creams", "sorbets",
                           "gelatos", "ice-cream-bars", "ice-cream-tubs",
                           "ice-cream-cones", "mochi-ice-cream"],
                 forms: [
                    ShelfForm("novelty", tags: ["ice-cream-bars", "ice-cream-sandwiches", "ice-cream-cones",
                                                "popsicles", "ice-pops", "frozen-novelties", "ice-lollies",
                                                "mochi-ice-cream"],
                              name: #"\bbars?\b|sandwich|\bcones?\b|popsicle|\bpops?\b|stick|bites\b|lolly|mochi"#),
                    ShelfForm("sorbet", group: "tub", tags: ["sorbets", "fruit-ices", "sherbets"],
                              name: #"sorbet|sherbet"#),
                    ShelfForm("tub", tags: ["ice-cream-tubs"]),
                 ],
                 defaultForm: "tub"),
        // `noodles` alone is a pasta ancestor in OFF (dry soba / udon), and
        // dehydrated soups / dried meals are not ramen — only the instant
        // family routes here.
        ShelfDef(shelf: .instantNoodles,
                 rootTags: ["instant-noodles", "cup-noodles", "ramen"],
                 subTags: ["ramen", "cup-noodles", "instant-pasta", "noodle-soups"],
                 forms: [
                    ShelfForm("cup", group: "noodles", tags: ["cup-noodles"], name: #"\bcup\b|\bbowl\b"#),
                    ShelfForm("pack", group: "noodles"),
                 ],
                 defaultForm: "pack"),
        ShelfDef(shelf: .snackBars,
                 rootTags: ["cereal-bars", "granola-bars", "protein-bars",
                            "meal-replacement-bars", "energy-bars"],
                 subTags: ["nut-bars", "fruit-bars", "energy-bars", "cereal-bars", "protein-bars",
                           "granola-bars"],
                 forms: [
                    ShelfForm("protein", group: "bar", tags: ["protein-bars"], name: #"protein"#),
                    ShelfForm("fruitnut", group: "bar", tags: ["fruit-bars", "nut-bars"],
                              name: #"l[äa]rabar|rxbar|fruit (&|and) nut|nut bar|date bar"#),
                    ShelfForm("granola", group: "bar", tags: ["granola-bars", "cereal-bars"],
                              name: #"granola|oat|chewy|crunchy"#),
                    ShelfForm("bar", group: "bar"),
                 ],
                 defaultForm: "bar"),
        ShelfDef(shelf: .nutButtersAndSpreads,
                 rootTags: ["peanut-butters", "nut-butters", "almond-butters",
                            "hazelnut-spreads", "chocolate-spreads", "sweet-spreads"],
                 subTags: ["peanut-butters", "almond-butters", "cashew-butters",
                           "hazelnut-spreads", "chocolate-hazelnut-spreads",
                           "sunflower-seed-butters"],
                 forms: [
                    ShelfForm("peanut", group: "spread", tags: ["peanut-butters"], name: #"peanut"#),
                    ShelfForm("almond", group: "spread", tags: ["almond-butters"], name: #"almond|almendra"#),
                    ShelfForm("cashew", group: "spread", tags: ["cashew-butters"], name: #"cashew"#),
                    ShelfForm("seed", group: "spread", tags: ["sunflower-seed-butters", "tahini"],
                              name: #"sunflower|tahini|sesame|pumpkin seed"#),
                    ShelfForm("chocolate", group: "spread", tags: ["hazelnut-spreads", "chocolate-spreads",
                                                                    "chocolate-hazelnut-spreads"],
                              name: #"nutella|hazelnut|chocolate|cocoa"#),
                    ShelfForm("spread", group: "spread"),
                 ],
                 defaultForm: "spread"),
        // Butter ↔ margarine/spreads are interchangeable in use (group
        // `spread`); liquid cooking oils are their own group.
        ShelfDef(shelf: .fatsAndOils,
                 rootTags: ["fats", "butters", "margarines", "vegetable-oils",
                            "olive-oils", "coconut-oils", "seed-oils"],
                 subTags: ["extra-virgin-olive-oils", "sunflower-oils", "canola-oils",
                           "rapeseed-oils", "avocado-oils", "ghee", "lards"],
                 forms: [
                    ShelfForm("oil", tags: ["vegetable-oils", "olive-oils", "coconut-oils", "seed-oils",
                                            "sunflower-oils", "canola-oils", "rapeseed-oils", "avocado-oils",
                                            "extra-virgin-olive-oils", "cooking-oils"],
                              name: #"\boils?\b|\bspray\b"#),
                    ShelfForm("butter", group: "spread", tags: ["butters", "ghee"], name: #"butter|ghee"#),
                    ShelfForm("margarine", group: "spread", tags: ["margarines", "spreads", "lards"],
                              name: #"margarine|spread|lard|shortening"#),
                 ]),
        // Yogurt BEFORE milks: kefir / yogurt drinks are cross-tagged
        // `dairy-drinks` in OFF and would otherwise be told to buy plain milk.
        ShelfDef(shelf: .yogurt,
                 rootTags: ["yogurts", "fermented-milk-products", "drinkable-yogurts"],
                 subTags: ["greek-yogurts", "plain-yogurts", "fruit-yogurts", "skyr",
                           "kefir", "flavored-yogurts", "yogurt-drinks"],
                 forms: [
                    ShelfForm("plant", tags: ["plant-based-yogurts", "non-dairy-yogurts", "soy-yogurts",
                                              "coconut-yogurts", "almond-yogurts", "oat-yogurts",
                                              "plant-based-yogurt-alternatives"],
                              name: #"plant|non-?dairy|dairy-free|almond|coconut|\bsoy\b|oatmilk|\boat\b"#),
                    ShelfForm("drinkable", group: "dairy", tags: ["drinkable-yogurts", "kefir", "yogurt-drinks",
                                                                  "fermented-milk-drinks"],
                              name: #"drink|kefir|smoothie|shake"#),
                    ShelfForm("cup", group: "dairy"),
                 ],
                 defaultForm: "cup"),
        // Dairy and plant milks are separate groups: a vegan shopper scanning
        // oat milk must never be told to buy cow's milk, and vice versa.
        ShelfDef(shelf: .milks,
                 rootTags: ["milks", "plant-milks", "dairy-drinks", "milk-substitutes"],
                 subTags: ["whole-milks", "semi-skimmed-milks", "skimmed-milks",
                           "almond-milks", "oat-milks", "soy-milks", "rice-milks",
                           "coconut-milks", "cashew-milks", "lactose-free-milks"],
                 forms: [
                    ShelfForm("plant", tags: ["plant-milks", "almond-milks", "oat-milks", "soy-milks",
                                              "rice-milks", "coconut-milks", "cashew-milks", "pea-milks",
                                              "plant-based-milk-alternatives", "milk-substitutes"],
                              name: #"almond|\boat\b|oatmilk|\bsoy\b|soymilk|rice milk|coconut|cashew|pea milk|plant|non-?dairy|dairy-free"#),
                    ShelfForm("dairy", tags: ["milks", "whole-milks", "semi-skimmed-milks", "skimmed-milks",
                                              "lactose-free-milks"]),
                 ],
                 defaultForm: "dairy"),
        // Fresh/spreadable vs firm vs soft-ripened: cottage cheese is not what
        // a cheddar buyer is looking for, however well it scores.
        ShelfDef(shelf: .cheese,
                 rootTags: ["cheeses"],
                 subTags: ["cheddar-cheese", "mozzarella", "goat-cheeses", "cream-cheeses",
                           "cottage-cheeses", "sliced-cheeses", "blue-cheeses",
                           "soft-cheeses", "hard-cheeses", "grated-cheeses", "string-cheeses"],
                 forms: [
                    ShelfForm("fresh", tags: ["cottage-cheeses", "cream-cheeses", "ricottas", "fresh-cheeses",
                                              "quarks", "mascarpone", "cheese-spreads"],
                              name: #"cottage|cream cheese|ricotta|quark|mascarpone|farmer'?s? cheese|spreadable"#),
                    ShelfForm("soft", tags: ["brie", "camembert", "blue-cheeses", "goat-cheeses", "fetas",
                                             "feta-cheeses", "soft-cheeses", "bries"],
                              name: #"\bbrie\b|camembert|\bblue\b|gorgonzola|roquefort|\bgoat\b|ch[eè]vre|\bfeta\b"#),
                    ShelfForm("firm", tags: ["cheddar-cheese", "cheddars", "mozzarella", "mozzarellas",
                                             "sliced-cheeses", "hard-cheeses", "grated-cheeses",
                                             "string-cheeses", "semi-hard-cheeses", "processed-cheeses",
                                             "american-cheeses", "swiss-cheeses", "goudas", "parmesan"]),
                 ],
                 defaultForm: "firm"),
        // Crackers, oatcakes, energy bars and savoury bakes leak into
        // `biscuits` via OFF's hierarchy; they are never offered as a cookie.
        ShelfDef(shelf: .cookies,
                 rootTags: ["biscuits", "cookies", "biscuits-and-cakes"],
                 subTags: ["chocolate-chip-cookies", "shortbread-cookies", "sandwich-cookies",
                           "wafers", "digestive-biscuits", "chocolate-biscuits"],
                 forms: [
                    ShelfForm("cracker", tags: ["crackers", "crackers-appetizers", "oatcakes", "crispbreads",
                                                "savory-biscuits", "appetizers"],
                              name: #"oatcake|cracker|triscuit|crispbread|\bcrisps?\b|pretzel"#,
                              suggestible: false),
                    ShelfForm("bar", tags: ["bars", "cereal-bars", "granola-bars", "energy-bars", "fruit-bars",
                                            "protein-bars", "curd-snacks"],
                              name: #"energy bars?|granola bars?|fruit bars?|l[äa]rabar|macrobar|\bbars?\b|bites\b"#,
                              suggestible: false),
                    ShelfForm("savory", name: #"sausage|\brolls?\b|pasty|\bpie\b|pizza"#, suggestible: false),
                    ShelfForm("cookie"),
                 ],
                 defaultForm: "cookie"),
        // Baking chocolate / chips / nibs / 100 % cocoa are ingredients, not a
        // swap for a snack bar — excluded. Filled candies and bars are
        // separate groups.
        ShelfDef(shelf: .chocolate,
                 rootTags: ["chocolates", "chocolate-candies", "chocolate-bars"],
                 subTags: ["dark-chocolates", "milk-chocolates", "white-chocolates",
                           "filled-chocolates", "chocolate-truffles", "pralines"],
                 forms: [
                    ShelfForm("baking", tags: ["baking-chocolates", "chocolate-chips", "cocoa-nibs",
                                               "cacao-nibs", "cocoa-powders", "cooking-chocolates",
                                               "chocolate-morsels"],
                              name: #"baking|\bchips\b|morsels|\bnibs\b|cocoa powder|cacao powder|100 ?%|unsweetened|cooking chocolate"#,
                              suggestible: false),
                    ShelfForm("notchocolate", tags: ["bars", "cereal-bars", "fruit-bars", "fishes", "canned-fishes"],
                              name: #"l[äa]rabar|energy bar|protein bar|granola|macrobar|fillets?|mackerel|sardine|tuna"#,
                              suggestible: false),
                    ShelfForm("candy", tags: ["filled-chocolates", "chocolate-candies", "pralines",
                                              "chocolate-truffles", "truffles", "bonbons", "chocolate-covered-nuts",
                                              "peanut-butter-cups", "chocolate-coated-almonds"],
                              name: #"truffle|praline|\bcups?\b|bites\b|covered|coated|bonbon|nougat|whips|crisps\b|medley|bites"#),
                    ShelfForm("bar", tags: ["chocolate-bars", "dark-chocolates", "milk-chocolates", "white-chocolates"]),
                 ],
                 defaultForm: "bar"),
        // Hot cereal (rolled oats, porridge) vs ready-to-eat: a Cheerios buyer
        // is not shopping for a bag of raw oats.
        ShelfDef(shelf: .cereal,
                 rootTags: ["breakfast-cereals"],
                 subTags: ["mueslis", "granolas", "corn-flakes", "chocolate-cereals",
                           "oat-cereals", "puffed-cereals", "bran-cereals"],
                 forms: [
                    ShelfForm("hot", tags: ["oats", "rolled-oats", "rolled-flakes", "porridges", "oatmeals",
                                            "instant-oatmeals", "grits", "cream-of-wheat", "hot-cereals",
                                            "oat-flakes", "steel-cut-oats", "porridge-oats"],
                              name: #"rolled oats|old.fashioned oats|steel.cut|porridge|oatmeal|\bgrits\b|cream of wheat|instant oats|quick oats|quick.1.minute|copos de avena|whole grain oats"#),
                    ShelfForm("rte"),
                 ],
                 defaultForm: "rte"),
        ShelfDef(shelf: .bread,
                 rootTags: ["breads"],
                 subTags: ["white-breads", "whole-wheat-breads", "whole-grain-breads",
                           "sourdough-breads", "baguettes", "sandwich-breads",
                           "flatbreads", "bagels", "buns", "rye-breads"],
                 forms: [
                    ShelfForm("flat", tags: ["tortillas", "wraps", "flatbreads", "pitas", "pita-breads", "naans",
                                             "lavash"],
                              name: #"tortilla|\bwraps?\b|\bpita\b|\bnaan\b|flatbread|lavash|chapati|roti"#),
                    ShelfForm("bagel", tags: ["bagels"], name: #"bagel"#),
                    ShelfForm("bun", tags: ["buns", "rolls", "hamburger-buns", "hot-dog-buns", "burger-buns",
                                            "dinner-rolls", "bread-rolls"],
                              name: #"\bbuns?\b|\brolls?\b|hawaiian sweet"#),
                    ShelfForm("muffin", tags: ["english-muffins"], name: #"english muffin"#),
                    ShelfForm("loaf", tags: ["sliced-breads", "sandwich-breads", "white-breads", "whole-wheat-breads",
                                             "whole-grain-breads", "sourdough-breads", "rye-breads",
                                             "multigrain-breads", "baguettes"]),
                 ],
                 defaultForm: "loaf"),
        ShelfDef(shelf: .pasta,
                 rootTags: ["pastas"],
                 subTags: ["dry-pastas", "fresh-pastas", "stuffed-pastas",
                           "whole-grain-pastas", "egg-pastas", "spaghetti", "penne", "macaroni"],
                 forms: [
                    ShelfForm("noodle", tags: ["noodles", "ramen", "instant-noodles", "soba", "udon",
                                               "rice-noodles", "asian-noodles", "egg-noodles", "chinese-noodles"],
                              name: #"ramen|noodle|\bsoba\b|\budon\b|vermicelli"#),
                    ShelfForm("pasta"),
                 ],
                 defaultForm: "pasta"),
        // Eggs AFTER pasta: egg pasta / lasagne sheets are cross-tagged en:eggs
        // in OFF; shell eggs never carry pasta tags, so nothing legit is stolen.
        ShelfDef(shelf: .eggs,
                 rootTags: ["eggs", "chicken-eggs"],
                 subTags: ["free-range-chicken-eggs", "barn-chicken-eggs", "cage-chicken-eggs",
                           "fresh-eggs", "egg-white", "egg-yolk", "hard-boiled-egg",
                           "boiled-eggs", "quail-eggs", "duck-eggs"]),
        // Lemon/lime juice is a cooking ingredient and popsicles are not a
        // drink — both leak into `fruit-juices` and are never suggested.
        // Vegetable juices and smoothies are their own groups.
        ShelfDef(shelf: .juice,
                 rootTags: ["fruit-juices", "juices", "vegetable-juices"],
                 subTags: ["orange-juices", "apple-juices", "grape-juices", "pineapple-juices",
                           "multifruit-juices", "cranberry-juices", "tomato-juices",
                           "smoothies", "fruit-nectars"],
                 forms: [
                    ShelfForm("lemon", tags: ["lemon-juices", "lime-juices"],
                              name: #"lemon juice|lime juice|realemon|realime"#, suggestible: false),
                    ShelfForm("pops", tags: ["popsicles", "ice-pops"], name: #"\bpops?\b|popsicle|freezer"#,
                              suggestible: false),
                    ShelfForm("vegetable", tags: ["vegetable-juices", "tomato-juices", "carrot-juices"],
                              name: #"tomato|vegetable|\bv8\b|carrot|beet|celery|pomidor"#),
                    ShelfForm("smoothie", tags: ["smoothies"], name: #"smoothie|machine\b"#),
                    ShelfForm("fruit"),
                 ],
                 defaultForm: "fruit"),
        // Energy drinks BEFORE soda: some are cross-tagged en:sodas in OFF, so
        // matching energy-drinks first keeps them on their own shelf (regular
        // sodas lack en:energy-drinks, so nothing legit is stolen).
        ShelfDef(shelf: .energyDrinks,
                 rootTags: ["energy-drinks"],
                 subTags: ["energy-drink-with-sugar",
                           "energy-drink-without-sugar-and-with-artificial-sweeteners",
                           "energy-shots"],
                 forms: [
                    ShelfForm("tablet", name: #"tablet|powder|sachet|\bmix\b|sticks?\b"#, suggestible: false),
                    ShelfForm("shot", tags: ["energy-shots"], name: #"\bshots?\b"#),
                    ShelfForm("drink"),
                 ],
                 defaultForm: "drink"),
        ShelfDef(shelf: .soda,
                 rootTags: ["sodas", "soft-drinks", "carbonated-drinks"],
                 subTags: ["colas", "lemonades", "orange-sodas", "ginger-ales",
                           "tonic-waters", "root-beers"]),
        // `chips-and-fries` is where frozen oven fries live in OFF — a fries
        // scan must not get crisps as "better options".
        ShelfDef(shelf: .chips,
                 rootTags: ["crisps", "potato-crisps", "tortilla-chips", "corn-chips"],
                 subTags: ["tortilla-chips", "corn-chips", "vegetable-crisps",
                           "potato-chips", "kettle-chips"],
                 forms: [
                    ShelfForm("potato", group: "chips", tags: ["potato-crisps", "potato-chips", "kettle-chips"],
                              name: #"potato|kettle"#),
                    ShelfForm("tortilla", group: "chips", tags: ["tortilla-chips", "corn-chips"],
                              name: #"tortilla|corn chips"#),
                    ShelfForm("other", group: "chips"),
                 ],
                 defaultForm: "other"),
    ]

    private static func normalized(_ tags: [String]?) -> Set<String> {
        Set((tags ?? []).map { tag in
            let t = tag.lowercased()
            return t.hasPrefix("en:") ? String(t.dropFirst(3)) : t
        })
    }

    /// The alternatives shelf a scanned product belongs to, or nil when none of
    /// the shelves apply (incl. coffee/water/alcohol/sweetener/formula scans).
    static func shelf(for product: Product) -> SageCategory? {
        let tags = normalized(product.categories)
        guard !tags.isEmpty else { return nil }
        for def in defs where !tags.isDisjoint(with: Set(def.rootTags + def.subTags)) {
            return def.shelf
        }
        return nil
    }

    private var def: ShelfDef? { SageCategory.defs.first { $0.shelf == self } }

    /// The scanned product's most-specific OFF tag within this shelf (e.g.
    /// "grape-juices"), for same-subtype preference. nil when only a root tag matched.
    func anchorTag(for product: Product) -> String? {
        guard let def else { return nil }
        let tags = SageCategory.normalized(product.categories)
        return def.subTags.first(where: tags.contains)
    }

    /// The product's form within this shelf (see header). nil when the shelf
    /// has no form table or nothing matched and there is no default.
    func form(of product: Product) -> ShelfForm? {
        guard let def, !def.forms.isEmpty else { return nil }
        let tags = SageCategory.normalized(product.categories)
        let haystack = (product.brand + " " + product.name).lowercased()
        for f in def.forms {
            if !tags.isDisjoint(with: Set(f.tags)) { return f }
            if f.nameMatches(haystack) { return f }
        }
        if let d = def.defaultForm { return def.forms.first { $0.id == d } }
        return nil
    }

    /// Whether `candidate` may be offered as a swap for `scanned` on this
    /// shelf: the candidate's form must be suggestible, and when both forms
    /// are known they must share a compatibility group. Unknown forms are
    /// permissive (coverage beats precision on tag-less records).
    func isSwapCompatible(scanned: Product, candidate: Product) -> Bool {
        SageCategory.isSwapCompatible(scannedForm: form(of: scanned), candidateForm: form(of: candidate))
    }

    /// Same rule over already-resolved forms (callers that loop over a shelf
    /// resolve the scanned form once and each candidate's form once).
    static func isSwapCompatible(scannedForm sf: ShelfForm?, candidateForm cf: ShelfForm?) -> Bool {
        guard let cf else { return true }
        guard cf.suggestible else { return false }
        guard let sf else { return true }
        return sf.group == cf.group
    }

    /// Whether this category has a Top Rated / alternatives list. False for the
    /// two categories with no data — water (unsupported) and coffee (deliberately
    /// shelf-excluded). The browse grid only shows shelves with a hero asset
    /// (`SageCategory.topRatedBrowse`); this flag is still used by tests /
    /// deep links that ask whether a shelf can rank.
    @MainActor var hasTopRated: Bool {
        !AlternativesStore.candidates(for: self).isEmpty
    }
}
