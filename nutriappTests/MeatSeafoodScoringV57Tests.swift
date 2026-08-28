import Testing
import Foundation
@testable import Sage

/// V5.7.0 — Meat & seafood in three forms (SCORING_V5.md §"V5.7.0 Meat & seafood").
/// meat_fresh / meat_processed / seafood, the protein-delivery S12, species
/// reference priors, omega-3, cure evidence with celery-powder equivalence,
/// the IARC Group 1 ceiling, mercury tiers, the sparse fresh-record identity
/// gate, and the routing evidence (plant analogues out, junk-tag rerails in).
struct MeatSeafoodScoringV57Tests {

    private let rs = RulesetV4.bundled

    private func product(
        kcal: Double? = 120, protein: Double? = 22.5, sugar: Double? = 0,
        addedSugar: Double? = nil, satFat: Double? = 1.0, sodium: Double? = 45,
        omega3: Double? = nil, iron: Double? = nil, potassium: Double? = nil,
        nova: Int = 1, name: String, ingredientsText: String? = "chicken breast",
        additives: [ProductAdditive] = [], labels: [String]? = nil,
        categories: [String]? = ["meats", "poultry", "chicken"],
        servingSize: String? = nil
    ) -> Product {
        var nutrients = Nutrients(sugar_g: sugar, sodium_mg: sodium, satFat_g: satFat,
                                  fiber_g: nil, protein_g: protein, calcium_mg: nil,
                                  kcal: kcal, fvn: nil, addedSugar_g: addedSugar)
        nutrients.omega3_g = omega3
        nutrients.iron_mg = iron
        nutrients.potassium_mg = potassium
        var p = Product(
            id: name, name: name, brand: "B", size: "", glyph: "🥩",
            overallScore: 0, yourScore: 0, overview: nil,
            nutriGrade: "?", novaGroup: nova,
            nutrients: nutrients,
            bonuses: [], transFats: false, caffeine_mg: nil,
            sweeteners: [], seedOils: false, additives: additives, restrictions: [],
            dietFlags: nil, allergenTags: nil,
            ingredientsText: ingredientsText, imageURL: nil,
            labels: labels, packagingMaterials: nil, origins: nil,
            ingredientShares: nil, categories: categories
        )
        p.servingSize = servingSize
        return p
    }

    private func rule(_ id: String, _ r: V4Result) -> V4RuleResult? {
        r.rules.first { $0.rule == id }
    }

    // MARK: Routing — three forms

    @Test func threeFormsRoute() {
        #expect(ScoringEngineV4.route(product(name: "chicken breast")) == "meat_fresh")
        #expect(ScoringEngineV4.route(product(
            kcal: 417, protein: 13.7, satFat: 13, sodium: 1717, nova: 4,
            name: "bacon", ingredientsText: "pork, water, salt, sugar, sodium nitrite",
            additives: [ProductAdditive(name: "e250", risk: .high, code: "e250", tier: .major)],
            categories: ["meats", "pork", "bacons"])) == "meat_processed")
        #expect(ScoringEngineV4.route(product(
            kcal: 208, protein: 24.6, satFat: 1.5, sodium: 400,
            nova: 3, name: "sardines in olive oil", ingredientsText: "sardines, olive oil, salt",
            categories: ["seafood", "fishes", "canned-fishes", "sardines"])) == "seafood")
    }

    /// Fresh-tagged products with cure evidence are processed meat.
    @Test func cureEvidencePromotesFreshTags() {
        let snack = product(
            kcal: 312, protein: 30, sugar: 4, satFat: 4, sodium: 900, nova: 3,
            name: "Beef snack",
            ingredientsText: "grass-fed beef, water, encapsulated lactic acid, sea salt, cultured celery powder",
            categories: ["meats", "beef"])
        #expect(ScoringEngineV4.route(snack) == "meat_processed")
    }

    /// M08 — plant analogues leave the meat profiles.
    @Test func plantAnaloguesRouteToGeneral() {
        let beyond = product(
            kcal: 230, protein: 18, satFat: 5, sodium: 390, nova: 4,
            name: "Plant-Based Burger Patties",
            ingredientsText: "water, pea protein, expeller-pressed canola oil, refined coconut oil, rice protein",
            categories: ["meat-alternatives", "meat-analogues"])
        #expect(ScoringEngineV4.route(beyond) == "general")
        // …even when they also carry a plain meat tag.
        let crossTagged = product(
            kcal: 230, protein: 18, satFat: 5, sodium: 390, nova: 4,
            name: "Meatless Crumbles",
            ingredientsText: "textured soy protein, water, salt",
            categories: ["meats", "meat-alternatives"])
        #expect(ScoringEngineV4.route(crossTagged) == "general")
    }

    /// M08 — junk-tagged franks rerail by name + composition evidence.
    @Test func junkTaggedFranksRerail() {
        let franks = product(
            kcal: 214, protein: 11, sugar: 1.5, satFat: 5.4, sodium: 1050, nova: 4,
            name: "Turkey Franks",
            ingredientsText: "mechanically separated turkey, water, salt, modified food starch, sodium nitrite",
            categories: ["undefined"])
        #expect(ScoringEngineV4.route(franks) == "meat_processed")
    }

    /// Meat tags on baby purées and soups fall through to other routes.
    @Test func babyFoodAndSoupsStayOffMeat() {
        let puree = product(
            kcal: 90, protein: 9, sugar: 0.5, satFat: 1, sodium: 30, nova: 3,
            name: "Chicken and Gravy", ingredientsText: "ground chicken, water, cornstarch",
            categories: ["meats", "baby-foods", "main-meals-for-babies"])
        #expect(!MeatScoring.isMeat(ScoringEngineV4.route(puree)))
        let soup = product(
            kcal: 36, protein: 2.5, sugar: 1, satFat: 0.3, sodium: 320, nova: 3,
            name: "chicken noodle soup", ingredientsText: "chicken broth, noodles, chicken",
            categories: ["meats", "soups"])
        #expect(!MeatScoring.isMeat(ScoringEngineV4.route(soup)))
    }

    // MARK: M02 — identity gate (sparse fresh records)

    @Test func noListChuckRoastScoresLikeListedGroundBeef() throws {
        let noList = product(
            kcal: 180, protein: 19, satFat: 5, sodium: 60, nova: 0,
            name: "Beef chuck roast", ingredientsText: nil,
            categories: ["meats", "beef"])
        var q = noList
        q.novaGroup = 0
        let a = try #require(ScoringEngineV4.score(noList))
        let listed = product(
            kcal: 180, protein: 19, satFat: 5, sodium: 60, nova: 1,
            name: "Ground beef", ingredientsText: "ground beef",
            categories: ["meats", "beef", "ground-beef"])
        let b = try #require(ScoringEngineV4.score(listed))
        #expect(a.profileId == "meat_fresh")
        #expect(abs(a.base - b.base) <= 5, "no-list \(a.base) vs listed \(b.base)")
        #expect(a.base >= 70)
    }

    /// The gate needs a plausible panel — a sparse record outside the envelope
    /// keeps the punitive unknown.
    @Test func identityGateNeedsTheEnvelope() {
        let sweetMystery = product(
            kcal: 180, protein: 19, sugar: 14, satFat: 5, sodium: 60, nova: 0,
            name: "Beef entree", ingredientsText: nil,
            categories: ["meats", "beef"])
        let r = ScoringEngineV4.score(sweetMystery)
        // sugar 14 fails the guard (max 25 passes) but fails the identity
        // envelope (max 2) → S1 stays at the packaged-food unknown.
        if let r { #expect(rule("S1", r)?.fraction ?? 1.0 <= 0.25) }
    }

    // MARK: M01 — processed meat, the celery loophole and the ceiling

    @Test func celeryPowderCureEqualsNitriteCure() throws {
        let cured = product(
            kcal: 417, protein: 13.7, sugar: 1, satFat: 13, sodium: 1717, nova: 4,
            name: "bacon", ingredientsText: "pork, water, salt, sugar, sodium phosphate, sodium erythorbate, sodium nitrite",
            additives: [ProductAdditive(name: "e250", risk: .high, code: "e250", tier: .major),
                        ProductAdditive(name: "e316", risk: .low, code: "e316", tier: .soft),
                        ProductAdditive(name: "e339", risk: .moderate, code: "e339", tier: .moderate)],
            categories: ["meats", "pork", "bacons"])
        let uncured = product(
            kcal: 400, protein: 13, sugar: 1, satFat: 12.5, sodium: 1500, nova: 3,
            name: "Uncured bacon", ingredientsText: "pork, water, salt, sugar, celery powder, sea salt",
            categories: ["meats", "pork", "bacons"])
        let a = try #require(ScoringEngineV4.score(cured))
        let b = try #require(ScoringEngineV4.score(uncured))
        #expect(a.profileId == "meat_processed" && b.profileId == "meat_processed")
        #expect(abs(a.base - b.base) <= 8, "cured \(a.base) vs uncured \(b.base)")
        #expect(a.base <= 54 && b.base <= 54)
    }

    @Test func group1CeilingBindsCharcuterie() throws {
        let prosciutto = product(
            kcal: 250, protein: 26, sugar: 0, satFat: 5.5, sodium: 1800, nova: 3,
            name: "Prosciutto", ingredientsText: "pork, sea salt",
            categories: ["meats", "cured-meats", "prosciutto"])
        let r = try #require(ScoringEngineV4.score(prosciutto))
        #expect(r.base <= 54, "IARC Group 1 ceiling: \(r.base)")
        let outcome = ScoringEngineV4.scoreProduct(prosciutto, for: MockData.user, ruleset: rs)
        guard case .scored(let scored) = outcome else {
            Issue.record("expected scored prosciutto"); return
        }
        #expect(scored.overallFiredCaps?.contains { $0.kind == "processedMeat" } == true)
    }

    /// Merely cooked-and-salted deli roast takes the lighter ceiling.
    @Test func cleanDeliTakesLighterCeiling() throws {
        let clean = product(
            kcal: 104, protein: 17, sugar: 0, satFat: 0.9, sodium: 800, nova: 3,
            name: "Sliced roasted turkey", ingredientsText: "turkey breast, salt",
            categories: ["meats", "prepared-meats", "cold-cuts"])
        let r = try #require(ScoringEngineV4.score(clean))
        #expect(r.base <= 58 && r.base >= 50)
    }

    /// M07 — additive-count pile-up no longer ranks deli turkey under Spam.
    @Test func deliTurkeyBeatsSpam() throws {
        let deli = product(
            kcal: 101, protein: 14.5, sugar: 2.1, satFat: 0.6, sodium: 1015, nova: 4,
            name: "Deli turkey breast",
            ingredientsText: "turkey breast, water, potassium lactate, modified corn starch, salt, dextrose, carrageenan, sodium phosphates, sodium diacetate, sodium erythorbate, sodium nitrite",
            additives: [ProductAdditive(name: "e250", risk: .high, code: "e250", tier: .major),
                        ProductAdditive(name: "e316", risk: .low, code: "e316", tier: .soft),
                        ProductAdditive(name: "e326", risk: .low, code: "e326", tier: .soft),
                        ProductAdditive(name: "e339", risk: .moderate, code: "e339", tier: .moderate),
                        ProductAdditive(name: "e262", risk: .low, code: "e262", tier: .soft),
                        ProductAdditive(name: "e407", risk: .moderate, code: "e407", tier: .moderate)],
            categories: ["meats", "prepared-meats", "cold-cuts"])
        let spam = product(
            kcal: 310, protein: 13, sugar: 1, satFat: 10, sodium: 1411, nova: 4,
            name: "Canned luncheon meat",
            ingredientsText: "pork with ham, salt, water, modified potato starch, sugar, sodium nitrite",
            additives: [ProductAdditive(name: "e250", risk: .high, code: "e250", tier: .major)],
            categories: ["meats", "pork", "canned-meats"])
        let d = try #require(ScoringEngineV4.score(deli))
        let s = try #require(ScoringEngineV4.score(spam))
        #expect(d.base > s.base, "deli \(d.base) should beat Spam \(s.base)")
    }

    // MARK: M03 — seafood: omega-3 and the consensus ordering

    @Test func sardinesOutrankRibeye() throws {
        let sardines = try #require(ScoringEngineV4.score(product(
            kcal: 208, protein: 24.6, satFat: 1.5, sodium: 400, omega3: 1.5, nova: 3,
            name: "Sardines in olive oil", ingredientsText: "sardines, olive oil, salt",
            categories: ["seafood", "fishes", "canned-fishes", "sardines"])))
        let ribeye = try #require(ScoringEngineV4.score(product(
            kcal: 291, protein: 23.7, satFat: 9.7, sodium: 54,
            name: "Ribeye steak", ingredientsText: "beef ribeye",
            categories: ["meats", "beef", "steaks"])))
        #expect(sardines.base > ribeye.base + 10,
                "sardines \(sardines.base) must clearly outrank ribeye \(ribeye.base)")
        #expect(sardines.base >= 88)
    }

    @Test func oilyFishOutranksLeanFishSlightly() throws {
        let salmon = try #require(ScoringEngineV4.score(product(
            kcal: 131, protein: 22.3, satFat: 0.8, sodium: 78, omega3: 1.0,
            name: "Wild sockeye salmon", ingredientsText: "sockeye salmon",
            categories: ["seafood", "fishes", "salmons"])))
        let cod = try #require(ScoringEngineV4.score(product(
            kcal: 82, protein: 17.8, satFat: 0.1, sodium: 54,
            name: "Cod fillet", ingredientsText: "cod",
            categories: ["seafood", "fishes", "cods"])))
        #expect(salmon.base > cod.base)
        #expect(cod.base >= 82, "lean fish is not penalized: \(cod.base)")
    }

    /// Canning is not ultra-processing: a NOVA-3 tag on "fish, water, salt"
    /// costs nothing on S2.
    @Test func cannedFishS2Clean() throws {
        let tuna = product(
            kcal: 90, protein: 20, satFat: 0.2, sodium: 320, nova: 3,
            name: "Chunk light tuna in water", ingredientsText: "light tuna, water, salt",
            categories: ["seafood", "fishes", "canned-fishes", "tunas"])
        let r = try #require(ScoringEngineV4.score(tuna))
        #expect(rule("S2", r)?.fraction == 1.0)
        #expect(r.base >= 80)
    }

    // MARK: M04 — mercury

    @Test func mercuryAvoidSpeciesCapped() throws {
        let swordfish = product(
            kcal: 144, protein: 19.7, satFat: 1.8, sodium: 81, omega3: 0.8,
            name: "Swordfish steak", ingredientsText: "swordfish",
            categories: ["seafood", "fishes", "swordfish"])
        let r = try #require(ScoringEngineV4.score(swordfish))
        #expect(r.base <= 54)
        let outcome = ScoringEngineV4.scoreProduct(swordfish, for: MockData.user, ruleset: rs)
        guard case .scored(let scored) = outcome else {
            Issue.record("expected scored swordfish"); return
        }
        #expect(scored.overallFiredCaps?.contains { $0.kind == "mercury" } == true)
    }

    @Test func albacoreTakesModerateMercuryCap() throws {
        let albacore = product(
            kcal: 127, protein: 23.2, satFat: 0.2, sodium: 320,
            name: "Albacore wild tuna", ingredientsText: "albacore tuna",
            categories: ["seafood", "fishes", "canned-fishes", "tunas"])
        let r = try #require(ScoringEngineV4.score(albacore))
        #expect(r.base <= 84)
    }

    // MARK: M05 — composition separates cuts

    @Test func leannessOrdering() throws {
        let breast = try #require(ScoringEngineV4.score(product(name: "Chicken breast")))
        let belly = try #require(ScoringEngineV4.score(product(
            kcal: 518, protein: 9.3, satFat: 19.3, sodium: 32,
            name: "Pork belly", ingredientsText: "pork belly",
            categories: ["meats", "pork"])))
        let lean = try #require(ScoringEngineV4.score(product(
            kcal: 152, protein: 20.9, satFat: 3.0, sodium: 66,
            name: "Ground beef 93/7", ingredientsText: "ground beef",
            categories: ["meats", "beef", "ground-beef"])))
        let fatty = try #require(ScoringEngineV4.score(product(
            kcal: 254, protein: 17.2, satFat: 7.6, sodium: 67,
            name: "Ground beef 80/20", ingredientsText: "ground beef",
            categories: ["meats", "beef", "ground-beef"])))
        #expect(breast.base >= 93)
        #expect(lean.base > fatty.base + 8)
        #expect(belly.base < 65, "pork belly is not Excellent: \(belly.base)")
        #expect(breast.base > lean.base)
    }

    /// Label claims (grass-fed, organic) never move the score.
    @Test func labelClaimsDontScore() throws {
        let plain = product(
            kcal: 215, protein: 18.6, satFat: 6.0, sodium: 68,
            name: "Ground beef 85/15", ingredientsText: "ground beef",
            categories: ["meats", "beef", "ground-beef"])
        var claimed = plain
        claimed.labels = ["grass-fed", "organic"]
        let a = try #require(ScoringEngineV4.score(plain))
        let b = try #require(ScoringEngineV4.score(claimed))
        #expect(a.base == b.base)
    }

    // MARK: M06 — species reference prior

    @Test func s13PriorDifferentiatesSpecies() throws {
        let liver = try #require(ScoringEngineV4.score(product(
            kcal: 135, protein: 20.4, satFat: 1.2, sodium: 69, iron: 4.9, potassium: 313,
            name: "Beef liver", ingredientsText: "beef liver",
            categories: ["meats", "beef", "offals", "livers"])))
        #expect(rule("S13", liver)?.fraction ?? 0 >= 0.95)
        let breast = try #require(ScoringEngineV4.score(product(name: "chicken breast")))
        #expect(rule("S13", breast)?.fraction == 0.70)
        #expect(rule("S13", breast)?.hadData == true)
    }

    // MARK: Forms & caps — seafood pack forms

    @Test func smokedFishCapped() throws {
        let lox = product(
            kcal: 117, protein: 18.3, satFat: 0.9, sodium: 672, omega3: 0.5, nova: 3,
            name: "Smoked salmon", ingredientsText: "atlantic salmon, salt, natural hardwood smoke",
            categories: ["seafood", "fishes", "smoked-fishes", "smoked-salmons"])
        let r = try #require(ScoringEngineV4.score(lox))
        #expect(r.base <= 68)
    }

    /// A dash of "smoke flavor" in a salmon burger is seasoning, not a smoked
    /// product — the same list must not flip profiles on a spelling change.
    @Test func smokeFlavorIsNotSmokedFish() {
        let burger = product(
            kcal: 150, protein: 17.7, satFat: 1.5, sodium: 400, nova: 4,
            name: "Alaska salmon burgers",
            ingredientsText: "pink salmon, vegetable oil, water, ground onion, salt, mesquite smoke flavor",
            categories: ["frozen-foods", "meats", "frozen-meats"])
        #expect(ScoringEngineV4.route(burger) == "meat_fresh")
    }

    @Test func condimentFishSodiumCapped() throws {
        let anchovies = product(
            kcal: 210, protein: 28.9, satFat: 2.2, sodium: 3668, omega3: 1.4, nova: 3,
            name: "Anchovies in olive oil", ingredientsText: "anchovies, olive oil, salt",
            categories: ["seafood", "fishes", "canned-fishes", "anchovies"])
        let r = try #require(ScoringEngineV4.score(anchovies))
        #expect(r.base <= 64)
    }

    @Test func surimiAndBreadedDock() throws {
        let sticks = product(
            kcal: 230, protein: 10, sugar: 1, satFat: 1.0, sodium: 400, nova: 4,
            name: "Fish sticks",
            ingredientsText: "minced alaska pollock, wheat flour, vegetable oil, water, modified corn starch, salt, sugar",
            additives: [ProductAdditive(name: "e451", risk: .moderate, code: "e451", tier: .moderate)],
            categories: ["seafood", "fishes", "breaded-fish", "fish-sticks"])
        let r = try #require(ScoringEngineV4.score(sticks))
        #expect(r.base < 65)
        let krab = product(
            kcal: 95, protein: 7.6, sugar: 5.5, addedSugar: 4.0, satFat: 0.1, sodium: 529, nova: 4,
            name: "Imitation crab sticks",
            ingredientsText: "alaska pollock, water, wheat starch, sugar, sorbitol, natural and artificial flavor, carrageenan, sodium tripolyphosphate",
            additives: [ProductAdditive(name: "e407", risk: .moderate, code: "e407", tier: .moderate),
                        ProductAdditive(name: "e451", risk: .moderate, code: "e451", tier: .moderate),
                        ProductAdditive(name: "e420", risk: .low, code: "e420", tier: .soft)],
            categories: ["seafood", "surimi", "imitation-crab"])
        let k = try #require(ScoringEngineV4.score(krab))
        #expect(k.base < r.base, "surimi \(k.base) below breaded whole fish \(r.base)")
        #expect(k.base < 58)
    }

    // MARK: S12 meat variant mechanics

    @Test func s12ZeroProteinIsUnknownNotZero() throws {
        let junk = product(
            kcal: 0, protein: 0, sugar: 0, satFat: 0, sodium: 0, nova: 3,
            name: "Sardines in olive oil", ingredientsText: "sardines, olive oil, salt",
            categories: ["seafood", "fishes", "canned-fishes", "sardines"])
        let r = try #require(ScoringEngineV4.score(junk))
        let s12 = try #require(rule("S12", r))
        #expect(s12.hadData == false)
        #expect(s12.fraction >= 0.4)
    }
}
