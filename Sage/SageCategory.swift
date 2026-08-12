import Foundation

/// Browse / Top Rated categories — single source for Sage shelves.
enum SageCategory: String, CaseIterable, Identifiable, Hashable {
    case soda, water, chocolate, cookies, cereal, cheese, yogurt, bread
    case juice, chips, coffee, pasta, iceCream, babyFood
    case nutButtersAndSpreads, snackBars, milks, fatsAndOils, instantNoodles
    case energyDrinks

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .soda:                   return "Soda"
        case .water:                  return "Water"
        case .chocolate:              return "Chocolate"
        case .cookies:                return "Cookies"
        case .cereal:                 return "Cereal"
        case .cheese:                 return "Cheese"
        case .yogurt:                 return "Yogurt"
        case .bread:                  return "Bread"
        case .juice:                  return "Juice"
        case .chips:                  return "Chips"
        case .coffee:                 return "Coffee"
        case .pasta:                  return "Pasta"
        case .iceCream:               return "Ice cream"
        case .babyFood:               return "Baby food"
        case .nutButtersAndSpreads:   return "Nut butters"
        case .snackBars:              return "Snack bars"
        case .milks:                  return "Milk"
        case .fatsAndOils:            return "Fats & oils"
        case .instantNoodles:         return "Instant noodles"
        case .energyDrinks:           return "Energy drinks"
        }
    }

    var emoji: String {
        switch self {
        case .soda:                   return "🥤"
        case .water:                  return "💧"
        case .chocolate:              return "🍫"
        case .cookies:                return "🍪"
        case .cereal:                 return "🥣"
        case .cheese:                 return "🧀"
        case .yogurt:                 return "🥛"
        case .bread:                  return "🍞"
        case .juice:                  return "🧃"
        case .chips:                  return "🍟"
        case .coffee:                 return "☕"
        case .pasta:                  return "🍝"
        case .iceCream:               return "🍦"
        case .babyFood:               return "🍼"
        case .nutButtersAndSpreads:   return "🥜"
        case .snackBars:              return "▣"
        case .milks:                  return "🥛"
        case .fatsAndOils:            return "🫒"
        case .instantNoodles:         return "🍜"
        case .energyDrinks:           return "⚡"
        }
    }

    /// Asset-catalog imageset for the Top Rated browse card. Shelves without
    /// one render their emoji tile until a hero photo is added.
    var topRatedHeroAsset: String? {
        switch self {
        case .bread:        return "bread-tr"
        case .cereal:       return "cereal-tr"
        case .cheese:       return "cheese-tr"
        case .chips:        return "chips-tr"
        case .chocolate:    return "chocolate-tr"
        case .energyDrinks: return "energy-tr"
        case .iceCream:     return "ice-cream-tr"
        case .juice:        return "juice-tr"
        case .milks:        return "milk-tr"
        case .pasta:        return "pasta-tr"
        case .snackBars:    return "snackbar-tr"
        case .soda:         return "soda-tr"
        case .yogurt:       return "yogurt-tr"
        default:            return nil
        }
    }

    /// Browse order for the Top Rated grid (two-up cards). Every populated
    /// shelf appears — hero photo when the asset exists, emoji tile otherwise.
    /// Energy drinks are deliberately absent: everything in that category
    /// scores poorly, and a "Top Rated" list of red pills is not a
    /// recommendation.
    static let topRatedBrowse: [SageCategory] = [
        .soda, .juice, .milks, .yogurt,
        .cheese, .iceCream, .cereal, .bread,
        .pasta, .chips, .snackBars, .chocolate,
        .cookies, .nutButtersAndSpreads, .instantNoodles,
        .fatsAndOils, .babyFood,
    ]
}
