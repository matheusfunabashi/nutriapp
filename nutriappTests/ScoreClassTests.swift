import Testing
import Foundation
@testable import Sage

struct ScoreClassTests {

    private func profile(
        objective: String = "lose weight",
        preferences: [String] = [],
        restrictions: [String] = [],
        allergies: [String] = []
    ) -> UserProfile {
        var u = MockData.user
        u.objective = objective
        u.preferences = preferences
        u.restrictions = restrictions
        u.allergies = allergies
        return u
    }

    @Test func sameProfileSameHash() {
        let a = profile(preferences: ["High protein"])
        let b = profile(preferences: ["High protein"])
        #expect(ScoreClass(a).hash == ScoreClass(b).hash)
    }

    @Test func preferenceOrderIndependent() {
        let a = profile(preferences: ["High protein", "Low sugar"])
        let b = profile(preferences: ["Low sugar", "High protein"])
        #expect(ScoreClass(a).hash == ScoreClass(b).hash)
    }

    @Test func caseInsensitive() {
        let a = profile(preferences: ["High Protein"])
        let b = profile(preferences: ["high protein"])
        #expect(ScoreClass(a).hash == ScoreClass(b).hash)
    }

    @Test func objectiveChangesHash() {
        #expect(ScoreClass(profile(objective: "lose weight")).hash
                != ScoreClass(profile(objective: "build muscle")).hash)
    }

    @Test func allergiesDoNotAffectHash() {
        // Allergies are deterministic + never enter the LLM bucket.
        let a = profile(allergies: ["Peanuts"])
        let b = profile(allergies: ["Milk", "Eggs"])
        #expect(ScoreClass(a).hash == ScoreClass(b).hash)
    }

    @Test func nonScoringRestrictionIgnored() {
        // Pescatarian doesn't change the score, so it shouldn't change the bucket.
        let a = profile(restrictions: ["Vegan"])
        let b = profile(restrictions: ["Vegan", "Pescatarian"])
        #expect(ScoreClass(a).hash == ScoreClass(b).hash)
    }

    @Test func scoringRestrictionChangesHash() {
        let a = profile(restrictions: [])
        let b = profile(restrictions: ["Low-sugar diet"])
        #expect(ScoreClass(a).hash != ScoreClass(b).hash)
    }

    @Test func hashIsShortHex() {
        let h = ScoreClass(MockData.user).hash
        #expect(h.count == 16)
        #expect(h.allSatisfy { $0.isHexDigit })
    }
}
