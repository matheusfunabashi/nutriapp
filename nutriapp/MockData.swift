import Foundation

enum MockData {

    // Product database is intentionally empty: the real barcode DB isn't wired up yet.
    static let products: [String: Product] = [:]

    // Scan history starts empty until real scans land.
    static let history: [HistoryEntry] = []

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
