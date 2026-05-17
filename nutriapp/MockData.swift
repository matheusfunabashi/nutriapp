import Foundation

enum MockData {

    static let products: [String: Product] = [
        "cokeZero": Product(
            id: "cokeZero", name: "Diet Cola", brand: "Brightside",
            size: "12 fl oz · 355 mL", glyph: "🥤",
            overallScore: 38, yourScore: 52,
            deltaReason: DeltaReason(tone: .positive,
                text: "You don't restrict artificial sweeteners, bumps your score up."),
            nutriGrade: "C", novaGroup: 4,
            nutrients: Nutrients(sugar_g: 0, sodium_mg: 12, satFat_g: 0,
                                 fiber_g: 0, protein_g: 0, calcium_mg: 0),
            bonuses: [], transFats: false, caffeine_mg: 9.7,
            sweeteners: ["aspartame", "acesulfame K"], seedOils: false,
            additives: [
                Additive(name: "Caramel color (E150d)", risk: .moderate),
                Additive(name: "Phosphoric acid", risk: .moderate),
                Additive(name: "Aspartame", risk: .high),
                Additive(name: "Acesulfame K", risk: .moderate),
                Additive(name: "Citric acid", risk: .low),
                Additive(name: "Natural flavors", risk: .low),
            ],
            restrictions: []
        ),
        "cola": Product(
            id: "cola", name: "Original Cola", brand: "Brightside",
            size: "12 fl oz · 355 mL", glyph: "🥤",
            overallScore: 16, yourScore: 12,
            deltaReason: DeltaReason(tone: .negative,
                text: "Added sugar conflicts with your low-sugar diet."),
            nutriGrade: "E", novaGroup: 4,
            nutrients: Nutrients(sugar_g: 11, sodium_mg: 13, satFat_g: 0,
                                 fiber_g: 0, protein_g: 0, calcium_mg: 0),
            bonuses: [], transFats: false, caffeine_mg: 9.5,
            sweeteners: [], seedOils: false,
            additives: [
                Additive(name: "Caramel color (E150d)", risk: .moderate),
                Additive(name: "Phosphoric acid", risk: .moderate),
                Additive(name: "Citric acid", risk: .low),
                Additive(name: "Natural flavors", risk: .low),
            ],
            restrictions: [
                Restriction(type: "low-sugar diet",
                            trigger: "Added sugar (39 g per serving)")
            ]
        ),
        "yogurt": Product(
            id: "yogurt", name: "Plain Greek Yogurt", brand: "Hilltop Creamery",
            size: "5.3 oz · 150 g", glyph: "🥛",
            overallScore: 88, yourScore: 96,
            deltaReason: DeltaReason(tone: .positive,
                text: "Boosted by high protein content, matches your \"build muscle\" objective."),
            nutriGrade: "A", novaGroup: 1,
            nutrients: Nutrients(sugar_g: 3.6, sodium_mg: 36, satFat_g: 0,
                                 fiber_g: 0, protein_g: 10, calcium_mg: 110),
            bonuses: ["protein", "calcium"], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: [], restrictions: []
        ),
        "cereal": Product(
            id: "cereal", name: "Frosted Honey Loops", brand: "Sunbright Foods",
            size: "1 cup · 36 g", glyph: "🥣",
            overallScore: 28, yourScore: 14,
            deltaReason: DeltaReason(tone: .negative,
                text: "Sugar conflicts with your \"low-sugar diet\", and ultra-processed."),
            nutriGrade: "D", novaGroup: 4,
            nutrients: Nutrients(sugar_g: 41, sodium_mg: 580, satFat_g: 2.1,
                                 fiber_g: 2.5, protein_g: 5, calcium_mg: 280),
            bonuses: [], transFats: true, caffeine_mg: nil,
            sweeteners: [], seedOils: true,
            additives: [
                Additive(name: "Yellow 5", risk: .high),
                Additive(name: "Red 40", risk: .high),
                Additive(name: "BHT", risk: .high),
                Additive(name: "Sodium phosphate", risk: .moderate),
                Additive(name: "Tocopherols", risk: .low),
                Additive(name: "Ascorbic acid", risk: .low),
                Additive(name: "Natural flavors", risk: .low),
                Additive(name: "Annatto", risk: .low),
            ],
            restrictions: [
                Restriction(type: "low-sugar diet",
                            trigger: "Added sugar (15 g per serving)"),
                Restriction(type: "low-sodium diet",
                            trigger: "Sodium (210 mg per serving)"),
            ]
        ),
        "bar": Product(
            id: "bar", name: "Chocolate Chip Protein Bar", brand: "Drift Nutrition",
            size: "1 bar · 60 g", glyph: "🍫",
            overallScore: 56, yourScore: 64,
            deltaReason: DeltaReason(tone: .positive,
                text: "Boosted by high protein content (20g), fits your goals."),
            nutriGrade: "B", novaGroup: 4,
            nutrients: Nutrients(sugar_g: 5, sodium_mg: 300, satFat_g: 6.7,
                                 fiber_g: 11.7, protein_g: 33.3, calcium_mg: 100),
            bonuses: ["protein", "fiber"], transFats: false, caffeine_mg: nil,
            sweeteners: ["sucralose", "stevia"], seedOils: true,
            additives: [
                Additive(name: "Sucralose", risk: .high),
                Additive(name: "Stevia leaf extract", risk: .low),
                Additive(name: "Soy lecithin", risk: .low),
            ],
            restrictions: []
        ),
        "oatmilk": Product(
            id: "oatmilk", name: "Barista Oat Milk", brand: "Field & Co.",
            size: "8 fl oz · 240 mL", glyph: "🥛",
            overallScore: 71, yourScore: 78,
            deltaReason: DeltaReason(tone: .positive,
                text: "Boosted by calcium fortification and low saturated fat."),
            nutriGrade: "B", novaGroup: 3,
            nutrients: Nutrients(sugar_g: 2.9, sodium_mg: 42, satFat_g: 0.6,
                                 fiber_g: 0.8, protein_g: 1.2, calcium_mg: 146),
            bonuses: ["calcium"], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false,
            additives: [
                Additive(name: "Tricalcium phosphate", risk: .low),
                Additive(name: "Gellan gum", risk: .moderate),
            ],
            restrictions: []
        ),
    ]

    static let history: [HistoryEntry] = [
        HistoryEntry(productId: "yogurt", when: "Just now", dateLabel: "Today · 12:14 PM"),
        HistoryEntry(productId: "cola", when: "2h ago", dateLabel: "Today · 10:32 AM"),
        HistoryEntry(productId: "cereal", when: "Yesterday", dateLabel: "May 9 · 8:14 AM"),
        HistoryEntry(productId: "bar", when: "Yesterday", dateLabel: "May 9 · 1:02 PM"),
        HistoryEntry(productId: "oatmilk", when: "3 days ago", dateLabel: "May 7 · 7:48 AM"),
        HistoryEntry(productId: "cokeZero", when: "4 days ago", dateLabel: "May 6 · 4:12 PM"),
        HistoryEntry(productId: "yogurt", when: "5 days ago", dateLabel: "May 5 · 9:01 AM"),
    ]

    static let user: UserProfile = UserProfile(
        name: "Jamie Rivera",
        handle: "@jamier",
        age: 32,
        sex: "female",
        dob: "3/14/1993",
        heightIn: 67,
        weightLb: 147,
        goalWeightLb: 140,
        dailyStepGoal: 8000,
        objective: "eat healthier",
        restrictions: ["Low-sugar diet"],
        preferences: ["High protein", "Low sodium"],
        unitSystem: "imperial",
        subscriptionStatus: "trial",
        subscriptionDaysLeft: 5,
        goalsCalories: 1840,
        goalsProtein: 110,
        goalsCarbs: 200,
        goalsFat: 65,
        appearance: "light",
        badgeCelebrations: true,
        liveActivity: false,
        autoFlagRestrictions: true,
        saveScansToHistory: true,
        personalizeScoring: true,
        appleHealth: true
    )
}
