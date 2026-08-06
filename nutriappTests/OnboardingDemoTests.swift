import Testing
import Foundation
@testable import Sage

/// The onboarding demo step is the only place where a silent failure is
/// invisible: if the fixture stops decoding, stops scoring, or stops routing
/// onto the cereal shelf, the screen simply renders nothing rather than
/// erroring. These tests pin the behavior the screen's copy depends on.
@MainActor
struct OnboardingDemoTests {

    /// A profile carrying only onboarding answers, matching what
    /// `OnboardingState.previewProfile` hands the demo screen.
    private func profile(goals: [String] = [], avoids: [String] = []) -> UserProfile {
        var p = MockData.user
        p.restrictions = []
        p.preferences = []
        p.allergies = nil
        p.healthGoals = goals
        p.avoidList = avoids
        p.personalizeScoring = true
        p.autoFlagRestrictions = true
        return p
    }

    @Test func fixtureDecodes() {
        let candidate = OnboardingDemoProduct.candidate
        #expect(candidate != nil)
        #expect(candidate?.barcode == "0856416000710")
        #expect(candidate?.brand == "Bear Naked")
        #expect(candidate?.name == "Vanilla Almond Crisp")
        // The nutriments block must survive decoding — it's what drives the
        // score, and a silent nil here would still "work" but score wrong.
        #expect(candidate?.nutriments?.sugars == 13.46)
        #expect(candidate?.novaGroup == 4)
    }

    /// The demo's premise is a product that *looks* fine on the shelf. If
    /// Overall collapses into the "just bad" band, the Your Score delta
    /// stops teaching anything about personalization.
    @Test func overallStaysRespectable() {
        let product = try! #require(OnboardingDemoProduct.scored(for: profile()))
        let overall = try! #require(product.overallScore)
        #expect(overall > 45)
    }

    /// picked Less sugar should see Your Score drop relative to Overall,
    /// with a nameable signed factor the reveal sheet can cite.
    @Test func lessSugarGoalSeesADrop() {
        let p = profile(goals: ["Less sugar"])
        let product = try! #require(OnboardingDemoProduct.scored(for: p))
        let overall = try! #require(product.overallScore)
        let yours = try! #require(product.yourScore)

        #expect(overall - yours >= 4)
        let factors = ScoringEngine.signedFactors(product, profile: p)
        #expect(factors.contains { $0.lowercased().contains("sugar") })
    }

    /// Your Score can still rise for a heart-goal user when fiber is high
    /// and sat fat stays moderate — the reveal sheet's `.better` branch.
    @Test func heartGoalCanRaiseOrHoldYourScore() {
        let p = profile(goals: ["Heart health"])
        let product = try! #require(OnboardingDemoProduct.scored(for: p))
        let overall = try! #require(product.overallScore)
        let yours = try! #require(product.yourScore)
        // Hold-or-better is enough; sodium on this label keeps a big lift rare.
        #expect(yours + 2 >= overall)
    }

    /// With nothing selected there should be no meaningful personalization,
    /// so the sheet's `.level` copy ("this one clears your bar") is honest.
    @Test func noSelectionsMeansNoMeaningfulGap() {
        let product = try! #require(OnboardingDemoProduct.scored(for: profile()))
        let overall = try! #require(product.overallScore)
        let yours = try! #require(product.yourScore)
        #expect(abs(overall - yours) <= 3)
    }

    /// `Alternatives.suggest` returning `.noShelf` would leave the "show me a
    /// better one" button doing nothing at all.
    @Test func fixtureRoutesToCerealShelf() {
        let product = try! #require(OnboardingDemoProduct.scored(for: profile()))
        #expect(SageCategory.shelf(for: product) == .cereal)
    }

    @Test func swapIsAvailable() {
        let p = profile(goals: ["Less sugar"])
        let product = try! #require(OnboardingDemoProduct.scored(for: p))
        let swap = try! #require(
            OnboardingDemoSwap.alternative(beating: product, profile: p))
        let baseline = product.yourScore ?? product.overallScore ?? 0
        #expect(swap.score > baseline)
        #expect(swap.product.brand == OnboardingDemoSwap.displayBrand)
        #expect(swap.product.name == OnboardingDemoSwap.displayName)
        // Bundled asset — never a remote URL that would stall the reveal.
        #expect(swap.product.imageURL == nil)
        #expect(swap.product.imageThumbURL == nil)
    }

    @Test func swapFixtureDecodes() {
        let candidate = OnboardingDemoSwap.candidate
        #expect(candidate != nil)
        #expect(candidate?.barcode == "0055577101100")
        #expect(OnboardingDemoSwap.displayBrand == "Quaker")
        #expect(OnboardingDemoSwap.displayName == "Quick Oats")
    }

    /// `AppStore` seeds `user` from `MockData.user`, which ships with a
    /// low-sugar restriction and high-protein/low-sodium preferences. The
    /// demo must not cite those as the user's own choices.
    @Test func previewProfileDropsSeededDefaults() {
        let state = OnboardingState()
        state.healthGoals = ["Heart health"]

        var seeded = MockData.user
        seeded.restrictions = ["Low-sugar diet"]
        seeded.preferences = ["High protein"]

        let preview = state.previewProfile(basedOn: seeded)
        #expect(preview.restrictions.isEmpty)
        #expect(preview.preferences.isEmpty)
        #expect(preview.healthGoals == ["Heart health"])
    }

    @Test func skippedIdentityDoesNotKeepPlaceholderName() {
        let state = OnboardingState()
        // Simulate a profile that still carries the old seed name.
        var user = MockData.user
        user.name = "Jamie Rivera"
        user.sex = "female"

        state.apply(to: &user)
        #expect(user.name.isEmpty)
        #expect(user.sex.isEmpty)
    }

    @Test func aboutYouWritesNameAndSex() {
        let state = OnboardingState()
        state.firstName = "  Alex  "
        state.sex = .male
        var user = MockData.user
        state.apply(to: &user)
        #expect(user.name == "Alex")
        #expect(user.sex == "male")
    }
}
