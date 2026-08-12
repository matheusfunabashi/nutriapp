import Testing
import Foundation
@testable import Sage

/// Property-based fuzz over the drinks scoring space. Deterministic (seeded
/// LCG — no wall-clock randomness), so failures reproduce exactly.
/// Complements the real-payload corpus: instead of 36 real products, this
/// sweeps thousands of synthetic ones across the noise space OFF produces.
@Suite(.serialized)
struct DrinksPropertyFuzzTests {

    /// Deterministic pseudo-random generator (64-bit LCG).
    private struct LCG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
        mutating func pick<T>(_ xs: [T]) -> T { xs[Int(next() % UInt64(xs.count))] }
        mutating func maybe(_ x: Double, p: Double) -> Double? { unit() < p ? x : nil }
    }

    private static let tagPools: [[String]] = [
        ["beverages", "sodas"], ["beverages", "sodas", "colas"],
        ["beverages", "energy-drinks"], ["beverages", "sports-drinks"],
        ["beverages", "iced-teas"], ["beverages", "iced-coffees", "coffee-drinks"],
        ["beverages", "kombucha"], ["beverages", "juices", "fruit-juices"],
        ["beverages", "nectars"], ["beverages"],
        ["beverages", "carbonated-drinks"], ["beverages", "teas", "black-teas"],
    ]
    private static let sizePool: [String] = [
        "355 ml", "250 ml", "500 ml", "1 L", "1.5 l", "33 cl", "12 fl oz",
        "473ml", "200 g", "banana", "", "0 ml", "999 L", "6 x 330 ml",
    ]
    private static let ingredientPool = [
        "carbonated water, natural flavor",
        "water, sugar, citric acid",
        "carbonated water, sugar, caramel color, caffeine",
        "water, sucrose, glucose, taurine, caffeine",
        "milk, coffee", "oat milk, coffee",
        "carbonated water, aspartame, acesulfame potassium",
        "water, stevia leaf extract, erythritol",
        "brewed tea, water", "orange juice", "",
    ]

    /// Build a synthetic product from the generator, with explicit overrides
    /// for the axis a property test sweeps.
    private func synth(_ rng: inout LCG,
                       tags: [String]? = nil,
                       sugar: Double?? = nil,
                       caffeine: Double?? = nil,
                       size: String? = nil,
                       ingredients: String? = nil) -> Product {
        let sugarValue = sugar ?? rng.maybe(rng.unit() * 60, p: 0.9)
        let caffeineValue = caffeine ?? rng.maybe(rng.unit() * 60, p: 0.5)
        return Product(
            id: "fuzz", name: "Fuzz Drink \(rng.next() % 1000)", brand: "F",
            size: size ?? rng.pick(Self.sizePool), glyph: "🥤",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: Int(rng.next() % 5),
            nutrients: Nutrients(
                sugar_g: sugarValue,
                sodium_mg: rng.maybe(rng.unit() * 900, p: 0.8),
                satFat_g: rng.maybe(rng.unit() * 6, p: 0.7),
                fiber_g: 0, protein_g: rng.maybe(rng.unit() * 5, p: 0.5),
                kcal: rng.maybe(rng.unit() * 120, p: 0.9),
                fvn: rng.maybe(rng.unit() * 100, p: 0.3),
                addedSugar_g: nil
            ),
            bonuses: [], transFats: false,
            caffeine_mg: caffeineValue,
            sweeteners: [], seedOils: false, additives: [], restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredients ?? rng.pick(Self.ingredientPool), imageURL: nil,
            labels: nil, packagingMaterials: nil, origins: nil,
            ingredientShares: nil, categories: tags ?? rng.pick(Self.tagPools)
        )
    }

    /// 1500 random products: never crash, never leave [10, 100], always
    /// deterministic.
    @Test func fuzzNeverCrashesStaysInRange() {
        var rng = LCG(state: 0x5A6E_D21)
        for _ in 0..<1500 {
            let p = synth(&rng)
            guard let r1 = ScoringEngineV4.score(p) else { continue }
            let r2 = ScoringEngineV4.score(p)
            #expect(r1.base == r2?.base, "\(p.name) nondeterministic")
            #expect((10...100).contains(r1.base), "\(p.name) → \(r1.base)")
        }
    }

    /// More sugar never raises a soda's score (fixed everything else).
    @Test func fuzzSugarMonotoneOnSodas() {
        var seeds = LCG(state: 42)
        for _ in 0..<40 {
            let seedState = seeds.next()
            var previous = Int.max
            for sugar in stride(from: 0.0, through: 50.0, by: 2.0) {
                var rng = LCG(state: seedState)
                let p = synth(&rng, tags: ["beverages", "sodas"],
                              sugar: .some(sugar), caffeine: .some(nil),
                              size: "355 ml",
                              ingredients: "water, sugar, natural flavor")
                guard let r = ScoringEngineV4.score(p) else { continue }
                #expect(r.base <= previous,
                        "seed \(seedState): score rose \(previous) → \(r.base) at \(sugar) g/100 ml")
                previous = r.base
            }
        }
    }

    /// F3 at the score level: on an energy drink, a 1 mg/serving caffeine
    /// change never moves the final score by more than 2 points, and never up.
    @Test func fuzzCaffeineSmoothOnEnergy() {
        var previous = Int.max
        for mgServing in stride(from: 0.0, through: 400.0, by: 1.0) {
            var rng = LCG(state: 7)
            let p = synth(&rng, tags: ["beverages", "energy-drinks"],
                          sugar: .some(11), caffeine: .some(mgServing / 4.73),
                          size: "473 ml",
                          ingredients: "carbonated water, sugar, taurine, caffeine")
            guard let r = ScoringEngineV4.score(p) else { continue }
            if previous != Int.max {
                #expect(r.base <= previous, "score rose at \(mgServing) mg/serving")
                #expect(previous - r.base <= 2,
                        "cliff at \(mgServing) mg/serving: \(previous) → \(r.base)")
            }
            previous = r.base
        }
    }

    /// Unknown junk tags never move a score (tag-noise immunity at scale).
    @Test func fuzzJunkTagsInert() {
        var seeds = LCG(state: 99)
        for _ in 0..<100 {
            let seedState = seeds.next()
            var a = LCG(state: seedState)
            var b = LCG(state: seedState)
            let baseTags = a.pick(Self.tagPools)
            _ = b.pick(Self.tagPools)  // keep generators aligned
            let clean = synth(&a, tags: baseTags)
            let noisy = synth(&b, tags: baseTags
                + ["xx-unknown-tag", "de:irgendwas", "fr:n-importe-quoi"])
            let r1 = ScoringEngineV4.score(clean)
            let r2 = ScoringEngineV4.score(noisy)
            #expect(r1?.base == r2?.base,
                    "junk tags moved score: \(r1?.base ?? -1) → \(r2?.base ?? -1)")
        }
    }

    /// Junk size strings (unparseable, zero, absurd) never crash and always
    /// leave a sane effective serving.
    @Test func fuzzJunkSizesSane() {
        var rng = LCG(state: 1234)
        for junk in ["banana", "", "0 ml", "999999 L", "🥤", "1/2 gal", "-5 ml"] {
            for _ in 0..<20 {
                let p = synth(&rng, size: junk)
                guard let r = ScoringEngineV4.score(p) else { continue }
                #expect((10...100).contains(r.base))
                if let bd = r.drinksBreakdown {
                    #expect(bd.effectiveServingMl >= 30 && bd.effectiveServingMl <= 600,
                            "size '\(junk)' → serving \(bd.effectiveServingMl)")
                }
            }
        }
    }
}
