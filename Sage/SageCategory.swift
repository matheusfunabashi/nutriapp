import Foundation

/// Browse / Top Rated categories — single source for Sage shelves.
enum SageCategory: String, CaseIterable, Identifiable, Hashable {
    case soda, water, chocolate, cookies, cereal, cheese, yogurt, bread
    case juice, chips, coffee, pasta, iceCream, babyFood
    case nutButtersAndSpreads, snackBars, milks, fatsAndOils, instantNoodles

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
        }
    }
}
