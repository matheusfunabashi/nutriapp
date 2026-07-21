import Testing
import Foundation
@testable import Sage

/// Stacked caps + low-sugar dietConflictCap linear taper calibration.
struct CapTaperTests {

    private let rs = RulesetV4.bundled

    private func lowSugarProfile(avoidSeedOils: Bool = false) -> UserProfile {
        var u = MockData.user
        u.objective = "eat healthier"
        u.personalizeScoring = true
        u.autoFlagRestrictions = true
        u.restrictions = ["Low-sugar diet"]
        u.avoidList = avoidSeedOils ? ["Seed oils"] : nil
        return u
    }

    private func product(sugar: Double, seedOils: Bool = false,
                         sodium: Double = 180, name: String = "Bar") -> Product {
        Product(
            id: "cap-\(Int(sugar * 10))",
            name: name,
            brand: "Test",
            size: "100 g",
            glyph: "🍪",
            overallScore: 0,
            yourScore: 0,
            overview: nil,
            nutriGrade: "D",
            novaGroup: 4,
            nutrients: Nutrients(
                sugar_g: sugar, sodium_mg: sodium, satFat_g: 1.5,
                fiber_g: 4, protein_g: 7, kcal: 190,
                addedSugar_g: min(sugar, 11)
            ),
            bonuses: [],
            transFats: false,
            caffeine_mg: nil,
            sweeteners: [],
            seedOils: seedOils,
            additives: [],
            restrictions: [],
            ingredientsText: seedOils
                ? "whole grain oats, sugar, canola oil, honey, salt"
                : "whole grain oats, sugar, honey, salt",
            categories: ["cereals", "granola-bars", "snacks"]
        )
    }

    private func taper() -> RulesetV4.HardGates.DietConflictTaper {
        rs.hardGates!.dietConflictTapers!["low-sugar diet"]!
    }

    // MARK: - Taper calibration

    @Test func sugarBelowAndAtStartDoesNotFireCap() {
        let t = taper()
        #expect(ScoringEngineV4.taperedDietCap(amount: 2, taper: t) == 100)
        #expect(ScoringEngineV4.taperedDietCap(amount: 9.1, taper: t) == 100)
        #expect(ScoringEngineV4.taperedDietCap(amount: 15, taper: t) == 100)

        for sugar in [2.0, 9.1, 15.0] {
            guard case .scored(let s) = ScoringEngineV4.scoreProduct(
                product(sugar: sugar), for: lowSugarProfile()
            ) else {
                Issue.record("expected scored"); return
            }
            #expect(s.bindingCap == nil)
            #expect((s.firedCaps ?? []).isEmpty)
            #expect(s.yourScore == s.overallScore || s.restrictions.isEmpty
                    || s.bindingCap == nil)
        }
    }

    @Test func sugar16CapApproximately92() {
        let t = taper()
        #expect(ScoringEngineV4.taperedDietCap(amount: 16, taper: t) == 92)
    }

    @Test func sugar20CapIs60AndBindsWhenWeightedHigher() {
        let t = taper()
        #expect(ScoringEngineV4.taperedDietCap(amount: 20, taper: t) == 60)

        guard case .scored(let s) = ScoringEngineV4.scoreProduct(
            product(sugar: 20, name: "Mid"), for: lowSugarProfile()
        ) else {
            Issue.record("expected scored"); return
        }
        // Cap value is 60; final score is min(weighted, 60).
        let your = s.yourScore ?? 0
        #expect(your == min(your, 60))
        if let bind = s.bindingCap {
            #expect(bind.id == "dietConflictCap")
            #expect(bind.value == 60)
            #expect(s.yourScore == 60)
        } else {
            // Weighted already ≤ 60 — cap fired but did not bind.
            #expect((s.firedCaps ?? []).contains { $0.value == 60 })
        }
    }

    @Test func sugar24CapIs28() {
        #expect(ScoringEngineV4.taperedDietCap(amount: 24, taper: taper()) == 28)
    }

    @Test func sugar25And26FullCap20() {
        let t = taper()
        #expect(ScoringEngineV4.taperedDietCap(amount: 25, taper: t) == 20)
        #expect(ScoringEngineV4.taperedDietCap(amount: 26, taper: t) == 20)

        guard case .scored(let s) = ScoringEngineV4.scoreProduct(
            product(sugar: 26, seedOils: true, name: "Nature Valley-like"),
            for: lowSugarProfile(avoidSeedOils: true)
        ) else {
            Issue.record("expected scored"); return
        }
        #expect(s.yourScore == 20)
        #expect(s.bindingCap?.id == "dietConflictCap")
        #expect(s.bindingCap?.value == 20)
        #expect(s.bindingCap?.intensity == "full")
        let ids = Set((s.firedCaps ?? []).map(\.id))
        #expect(ids.contains("dietConflictCap"))
        #expect(ids.contains("seedOilCap"))
    }

    @Test func taperMonotonicNonIncreasing() {
        let t = taper()
        var prev = 100
        for g in stride(from: 0.0, through: 30.0, by: 0.5) {
            let cap = ScoringEngineV4.taperedDietCap(amount: g, taper: t)
            #expect(cap <= prev)
            prev = cap
        }
    }

    @Test func taperContinuityNoCliffAtStart() {
        let t = taper()
        let atStart = ScoringEngineV4.taperedDietCap(amount: t.taperStart, taper: t)
        let oneGram = ScoringEngineV4.taperedDietCap(amount: t.taperStart + 1, taper: t)
        #expect(atStart == 100)
        let slope = (100.0 - Double(t.minCap)) / (t.taperEnd - t.taperStart)
        // Jump from start → start+1 must not exceed the per-gram slope (plus rounding).
        #expect(Double(atStart - oneGram) <= slope + 1.0)
    }

    // MARK: - Stacked caps

    @Test func onlySeedOilCapBindsWhenWeightedAbove49() {
        // High-sugar-free snack that still scores well overall but has seed oils.
        var p = Product(
            id: "seed-only",
            name: "Oat Crackers",
            brand: "T",
            size: "",
            glyph: "🍪",
            overallScore: 0,
            yourScore: 0,
            overview: nil,
            nutriGrade: "B",
            novaGroup: 3,
            nutrients: Nutrients(
                sugar_g: 2, sodium_mg: 120, satFat_g: 1,
                fiber_g: 8, protein_g: 10, kcal: 160
            ),
            bonuses: [],
            transFats: false,
            caffeine_mg: nil,
            sweeteners: [],
            seedOils: true,
            additives: [],
            restrictions: [],
            ingredientsText: "whole grain oats, canola oil, salt",
            categories: ["snacks", "crackers"]
        )
        var u = MockData.user
        u.restrictions = []  // no diet conflict
        u.autoFlagRestrictions = true
        u.personalizeScoring = true
        u.avoidList = ["Seed oils"]
        u.objective = "maintain" // weaker multipliers if any

        guard case .scored(let s) = ScoringEngineV4.scoreProduct(p, for: u) else {
            Issue.record("expected scored"); return
        }
        #expect((s.firedCaps ?? []).contains { $0.id == "seedOilCap" })
        if let bind = s.bindingCap {
            #expect(bind.id == "seedOilCap")
            #expect(bind.value == 49)
            #expect(s.yourScore == 49)
        } else {
            // Weighted ≤ 49 → fired but not bound (ramen-like).
            #expect((s.yourScore ?? 0) <= 49)
        }
    }

    @Test func noCapsLeavesBindingNil() {
        guard case .scored(let s) = ScoringEngineV4.scoreProduct(
            product(sugar: 2), for: lowSugarProfile(avoidSeedOils: false)
        ) else {
            Issue.record("expected scored"); return
        }
        #expect(s.bindingCap == nil)
        #expect((s.firedCaps ?? []).isEmpty)
    }

    @Test func jifAndYorgusLikeDoNotFire() {
        var u = lowSugarProfile()
        for sugar in [2.0, 9.1] {
            guard case .scored(let s) = ScoringEngineV4.scoreProduct(
                product(sugar: sugar), for: u
            ) else {
                Issue.record("expected scored"); return
            }
            #expect(s.bindingCap == nil)
            #expect(!(s.firedCaps ?? []).contains { $0.kind == "dietConflict" })
        }
    }
}
