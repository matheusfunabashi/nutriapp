import Foundation

// V5.7.0 — Meat & seafood in three forms (SCORING_V5.md §"V5.7.0 Meat & seafood").
//
//   meat_fresh      whole cuts, plain ground, organ meats — beef, pork, poultry,
//                   lamb, game; rotisserie / plain cooked meat with additives
//                   stays here (S1 judges the additives, the food is still meat)
//   meat_processed  cured, smoked, dried, fermented or restructured meat —
//                   bacon, ham, salami, deli slices, hot dogs, jerky, canned
//                   luncheon meat. IARC Group 1: a structural ceiling, then
//                   sodium / fat / additives separate lean deli from salami.
//   seafood         fish and shellfish in every pack form — fresh, frozen,
//                   canned, smoked, breaded, surimi. Omega-3 is the category's
//                   merit axis; species-level mercury is the safety axis.
//
// Stance (the dairy/egg line, applied to meat): health only. Welfare, housing,
// feed, wild-vs-farmed sustainability, certifications, packaging and lab-report
// transparency are not health evidence and never score (grass-fed / wild-caught
// stay display chips). The one contaminant scored is mercury, because it is
// species-deterministic — the name on the pack is the evidence. Curing chemistry
// is judged by what it is, not what the label calls it: celery powder is a
// nitrate cure, and "uncured" is a labeling word, not a food.
//
// What lives here: the per-form rules (protein delivery, species reference
// prior, omega-3, form & cure), the identity gate for sparse fresh records
// (most fresh meat UPCs print no ingredient list), cure / smoke / mercury
// evidence, the processed-meat and mercury ceilings, and the routing evidence
// (plant analogues off the meat profiles, name rerails for junk-tagged franks).
enum MeatScoring {

    enum Form: String {
        case fresh, processed, seafood
    }

    static func form(_ profileId: String) -> Form? {
        switch profileId {
        case "meat_fresh": return .fresh
        case "meat_processed": return .processed
        case "seafood": return .seafood
        default: return nil
        }
    }

    static func isMeat(_ profileId: String) -> Bool { form(profileId) != nil }

    static let profileIds: [String] = ["meat_fresh", "meat_processed", "seafood"]

    // MARK: Config

    struct Config: Codable {
        struct Envelope: Codable {
            let kcalMin: Double; let kcalMax: Double
            let proteinMin: Double; let proteinMax: Double
            let sugarMax: Double; let sodiumMax: Double
        }
        struct S12: Codable {
            let proteinTargetG: Double        // g/100 g earning full absolute credit
            let energyShareTarget: Double     // protein share of kcal earning full credit
            let absWeight: Double             // rest of the rule is the energy share
            let unknownCredit: Double
        }
        struct Lift: Codable { let threshold: Double; let lift: Double }
        struct Omega3: Codable {
            /// Declared omega-3 g/100 g: ≥ [0] → credits[0], ≥ [1] → credits[1], …
            let declaredThresholds: [Double]
            let declaredCredits: [Double]
            /// Credit below the last threshold (an explicit near-zero declaration).
            let declaredFloor: Double
            /// Species-class fallback when the label is silent.
            let classCredits: [String: Double]
            let unknownCredit: Double
        }
        struct Caps: Codable {
            let cured: Int            // IARC Group 1 ceiling (cure / smoke / dry / restructure)
            let processedOther: Int   // cooked-and-salted only
            let mercury: Int          // FDA/EPA "avoid" species
            let mercuryModerate: Int  // FDA/EPA "good choice" (not best) species
            let smokedFish: Int
            let seafoodSodiumMg: Double
            let seafoodSodium: Int    // condiment-pattern fish (anchovies, lox)
        }
        struct RoutingGuard: Codable {
            let minProteinG: Double
            let maxKcal: Double
            let maxSugarG: Double
        }
        struct PlantEvidence: Codable {
            let labels: [String]; let nameWords: [String]; let firstIngredients: [String]
        }
        let identityEnvelope: [String: Envelope]   // "fresh", "seafood"
        let identityS1Unknown: Double
        let identityS2Credit: Double
        let s2NoListUnknown: Double
        /// Marker-free list credit by form (fresh/seafood 1.0; processed keeps
        /// a traditional ceiling — charcuterie is never "unprocessed").
        let s2Clean: [String: Double]
        let markerFamilies: [String: [String]]
        let markerCredits: [Double]
        let s12: S12
        let s13Prior: [String: Double]             // species class → prior
        let s13ProcessedFactor: Double
        let s13Lifts: [String: Lift]
        let s13MaxLift: Double
        let speciesWords: [String: [String]]       // class → name/ingredient words
        let speciesTags: [String: [String]]        // class → category tags
        let omega3: Omega3
        let formCredits: [String: Double]
        let cureAdditives: [String]                // e249–e252 (also S1-exempt on processed)
        let cureTextMarkers: [String]
        let smokeMarkers: [String]
        let dryMarkers: [String]
        let emulsifiedMarkers: [String]
        let surimiMarkers: [String]
        let breadedMarkers: [String]
        let caps: Caps
        /// Category tags that are Group 1 by definition (cured-meats, jerky…).
        let group1Tags: [String]
        let mercuryAvoidWords: [String]
        let mercuryAvoidTags: [String]
        let mercuryModerateWords: [String]
        let routingGuard: RoutingGuard
        let plantEvidence: PlantEvidence
        let processedNameWords: [String]           // junk-tag rerail vocabulary
        let neutralTokens: [String]
    }

    // MARK: Species classification

    /// The most specific class wins: organ before red meat ("beef liver"),
    /// oily fish before the generic "fish" word. leanFish is last — its
    /// "fishes" tag is the generic fallback OFF stamps on everything wet.
    private static let classOrder = [
        "organ", "oilyFish", "shellfish", "redMeat", "pork", "poultry", "leanFish",
    ]

    static func speciesClass(_ p: Product, cfg: Config) -> String? {
        let tags = Set(p.categories ?? [])
        let hay = (p.name + " " + firstTokens(p, count: 2).joined(separator: " ")).lowercased()
        for cls in classOrder {
            if let t = cfg.speciesTags[cls], !tags.isDisjoint(with: t) { return cls }
            if let words = cfg.speciesWords[cls],
               words.contains(where: { ScoringEngineV4.matchesWord($0, in: hay) }) {
                return cls
            }
        }
        return nil
    }

    private static func firstTokens(_ p: Product, count: Int) -> [String] {
        guard let text = p.ingredientsText else { return [] }
        return Array(IngredientIntegrity.tokens(from: text).prefix(count))
    }

    // MARK: Identity gate (sparse fresh records)

    /// Most fresh meat / seafood UPCs print no ingredient list, and in-store
    /// scans arrive through the USDA nutrition path with no list and no NOVA.
    /// A record whose panel sits inside the form's envelope, carries no
    /// additive tags and names a single species is, with high probability, the
    /// plain cut its tag says it is. The packaged-food S1 unknown credit
    /// (0.20) is calibrated for foods where a missing list hides additives; a
    /// chuck roast's additive prior is near zero. Confidence still takes the
    /// haircut — the number is provisional, just not punitive.
    static func passesIdentityEnvelope(_ p: Product, form: Form, cfg: Config) -> Bool {
        guard form != .processed else { return false }
        let key = form == .seafood ? "seafood" : "fresh"
        guard let env = cfg.identityEnvelope[key], p.additives.isEmpty else { return false }
        guard speciesClass(p, cfg: cfg) != nil else { return false }
        // Processed evidence in the name defeats the gate ("smoked", "cured").
        guard !hasCureEvidence(p, cfg: cfg), !hasSmokeEvidence(p, cfg: cfg) else { return false }
        let n = p.nutrients
        guard let kcal = n.kcal, kcal >= env.kcalMin, kcal <= env.kcalMax else { return false }
        guard let prot = n.protein_g, prot >= env.proteinMin, prot <= env.proteinMax else { return false }
        if let s = n.sugar_g, s > env.sugarMax { return false }
        if let na = n.sodium_mg, na > env.sodiumMax { return false }
        return true
    }

    static func s1UnknownCredit(_ p: Product, form: Form, cfg: Config) -> Double {
        passesIdentityEnvelope(p, form: form, cfg: cfg) ? cfg.identityS1Unknown : 0.20
    }

    // MARK: S2 — marker-family processing

    /// Ultra-processing read off the list as marker families (the bread/dairy
    /// pattern): canning, cooking and plain salt are not ultra-processing, so
    /// "sardines, olive oil, salt" is clean whatever NOVA tag the can carries.
    /// Cure chemistry is deliberately NOT a family here — the form rule and the
    /// processed ceiling own curing; S2 measures the industrial build
    /// (mechanically separated meat, sugars, flavor enhancers, modified starch).
    static func s2Credit(_ p: Product, form: Form, cfg: Config) -> (Double, Bool, String?) {
        let clean = cfg.s2Clean[form.rawValue] ?? 1.0
        guard let text = p.ingredientsText?.lowercased(), !text.isEmpty else {
            if passesIdentityEnvelope(p, form: form, cfg: cfg) {
                return (cfg.identityS2Credit, false, "S2 meat: no list → identity prior")
            }
            return (cfg.s2NoListUnknown, false, "S2 meat: no list → unknown")
        }
        let families = cfg.markerFamilies.compactMap { family, needles in
            needles.contains { text.contains($0) } ? family : nil
        }
        guard !families.isEmpty else {
            return (clean, true, "S2 meat: no ultra-processing markers")
        }
        let idx = min(families.count - 1, cfg.markerCredits.count - 1)
        let f = min(clean, cfg.markerCredits[idx])
        return (f, true, "S2 meat: \(families.count) marker families (\(families.sorted().joined(separator: ", ")))")
    }

    // MARK: S12 — protein delivery

    /// What the food delivers: absolute protein per 100 g blended with protein's
    /// share of energy. The share axis is what separates a lean cut from a
    /// fatty one — fiber and fruit/veg (60% of the generic rule) are
    /// structurally zero for any animal product, which is why chicken breast
    /// used to cap at f 0.40.
    static func s12Credit(_ p: Product, cfg: Config) -> (Double, Bool, String) {
        let c = cfg.s12
        guard let prot = p.nutrients.protein_g, prot > 0 else {
            // No real meat or fish has 0 g protein — a declared zero is an
            // empty OFF panel, not evidence.
            return (c.unknownCredit, false, "meatProtein: protein undeclared → unknown")
        }
        let abs = min(1, prot / c.proteinTargetG)
        guard let kcal = p.nutrients.kcal, kcal > 0 else {
            return (abs, true, String(format: "meatProtein: %.1f g/100 g (no kcal → absolute only)", prot))
        }
        let share = min(1, (prot * 4 / kcal) / c.energyShareTarget)
        let f = c.absWeight * abs + (1 - c.absWeight) * share
        return (f, true, String(format: "meatProtein: %.1f g/100 g, %.0f%% of energy → f %.2f", prot, prot * 4 / kcal * 100, f))
    }

    // MARK: S13 — species reference prior

    /// Meat's micronutrient story (heme iron, B12, zinc, selenium; D and
    /// iodine for fish) is invisible to the %DV rule because US meat panels
    /// never print micros. Like V5.3 eggs and V5.6 dairy: a reference prior by
    /// species class, lifted by declared values, discounted on processed forms
    /// (cooking-out and dilution by fat / water / binders).
    static func s13Credit(_ p: Product, form: Form, cfg: Config) -> (Double, Bool, String?) {
        let cls = speciesClass(p, cfg: cfg)
        var prior = cfg.s13Prior[cls ?? "unknown"] ?? cfg.s13Prior["unknown"] ?? 0.6
        if form == .processed { prior *= cfg.s13ProcessedFactor }
        let n = p.nutrients
        var lift = 0.0
        var hits: [String] = []
        func check(_ key: String, _ value: Double?) {
            guard let l = cfg.s13Lifts[key], let v = value, v >= l.threshold else { return }
            lift += l.lift; hits.append(key)
        }
        check("iron_mg", n.iron_mg)
        check("potassium_mg", n.potassium_mg)
        check("vitaminD_ug", n.vitaminD_ug)
        check("vitaminB12_ug", n.vitaminB12_ug)
        let f = min(1.0, prior + min(lift, cfg.s13MaxLift))
        let label = cls ?? "unknown species"
        let note = hits.isEmpty
            ? String(format: "S13 meat: %@ reference prior %.2f", label, f)
            : String(format: "S13 meat: %@ prior %.2f + declared (%@) → %.2f", label, prior, hits.joined(separator: ", "), f)
        return (f, true, note)
    }

    // MARK: Omega-3 (seafood)

    /// The reason guidelines say "oily fish": declared EPA/DHA when the label
    /// carries it, else a species-class prior. Lean fish earns a partial
    /// credit, never a penalty — cod is not worse food for being lean.
    static func omega3Credit(_ p: Product, cfg: Config) -> (Double, Bool, String?) {
        let c = cfg.omega3
        if let declared = p.nutrients.omega3_g {
            for (i, t) in c.declaredThresholds.enumerated() where declared >= t {
                let f = i < c.declaredCredits.count ? c.declaredCredits[i] : c.declaredFloor
                return (f, true, String(format: "omega3: declared %.2f g → f %.2f", declared, f))
            }
            return (c.declaredFloor, true, String(format: "omega3: declared %.2f g → f %.2f", declared, c.declaredFloor))
        }
        if let cls = speciesClass(p, cfg: cfg), let f = c.classCredits[cls] {
            return (f, true, "omega3: \(cls) species prior → f \(String(format: "%.2f", f))")
        }
        return (c.unknownCredit, false, "omega3: no declaration, species unknown")
    }

    // MARK: Form & cure

    /// Word-bounded haystack over name + labels + ingredient text.
    private static func evidenceHay(_ p: Product) -> String {
        let labels = (p.labels ?? []).joined(separator: " ").replacingOccurrences(of: "-", with: " ")
        return (p.name + " " + labels + " " + (p.ingredientsText ?? "")).lowercased()
    }

    /// Curing chemistry by what it is: nitrite / nitrate salts, curing-salt
    /// blends, or the celery loophole (celery powder / juice / cultured celery
    /// is a nitrate source — USDA itself requires the "uncured" wording only
    /// because no synthetic nitrite was added, not because none is present).
    static func hasCureEvidence(_ p: Product, cfg: Config) -> Bool {
        if p.additives.contains(where: { a in a.code.map { cfg.cureAdditives.contains($0) } ?? false }) {
            return true
        }
        let hay = evidenceHay(p)
        return cfg.cureTextMarkers.contains { ScoringEngineV4.matchesWord($0, in: hay) }
    }

    /// Smoked as a process — the product's own identity (name, labels, tags),
    /// never a dash of "smoke flavor" in the list: that is seasoning, and the
    /// S2 flavoring family already prices it. Matching it here sent the same
    /// salmon burger to two different profiles on a spelling difference.
    static func hasSmokeEvidence(_ p: Product, cfg: Config) -> Bool {
        let name = (p.name + " " + (p.labels ?? []).joined(separator: " ")).lowercased()
        if cfg.smokeMarkers.contains(where: { ScoringEngineV4.matchesWord($0, in: name) }) { return true }
        return (p.categories ?? []).contains { $0.hasPrefix("smoked-") }
    }

    private static func matchesAny(_ markers: [String], in hay: String) -> Bool {
        markers.contains { $0.contains(" ") ? hay.contains($0) : ScoringEngineV4.matchesWord($0, in: hay) }
    }

    /// The processed form ladder — the worst matched form binds (min credit,
    /// the dairy-processing pattern). A processed-profile product matching
    /// nothing is cooked-and-salted (clean deli roast).
    static func formCredit(_ p: Product, form: Form, cfg: Config) -> (Double, Bool, String?) {
        let c = cfg.formCredits
        let hay = evidenceHay(p)
        let tags = Set(p.categories ?? [])
        switch form {
        case .fresh:
            // The species ladder: consensus ranks poultry above red meat
            // (IARC 2A on red meat, AHA/DGA fish-and-poultry-first) — a modest
            // structural step, not a demonization. Organ meats carry a small
            // portion-caution dock (vitamin A / purine load at liver density).
            let cls = speciesClass(p, cfg: cfg)
            switch cls {
            case "poultry": return (c["freshPoultry"] ?? 1.0, true, "form: poultry")
            case "organ": return (c["freshOrgan"] ?? 0.8, true, "form: organ meat")
            case "pork": return (c["freshPork"] ?? 0.8, true, "form: pork")
            case "redMeat": return (c["freshRedMeat"] ?? 0.75, true, "form: red meat")
            default: return (c["freshUnknown"] ?? 0.85, false, "form: species unknown")
            }
        case .processed:
            var hits: [(String, Double)] = []
            if matchesAny(cfg.emulsifiedMarkers, in: hay) || !tags.isDisjoint(with: ["hot-dogs", "frankfurter-sausages"]) {
                hits.append(("emulsified / restructured", c["processedEmulsified"] ?? 0.1))
            }
            if hasCureEvidence(p, cfg: cfg) {
                hits.append(("cured", c["processedCured"] ?? 0.15))
            }
            if matchesAny(cfg.dryMarkers, in: hay) || !tags.isDisjoint(with: ["dried-meats", "jerky", "beef-jerky"]) {
                hits.append(("dried", c["processedDried"] ?? 0.35))
            }
            if hasSmokeEvidence(p, cfg: cfg) {
                hits.append(("smoked", c["processedSmoked"] ?? 0.35))
            }
            guard !hits.isEmpty else {
                guard p.hasIngredientData else { return (c["processedUnknown"] ?? 0.4, false, "form: processed, no evidence") }
                return (c["processedCooked"] ?? 0.6, true, "form: cooked / salted, no cure")
            }
            let worst = hits.min { $0.1 < $1.1 }!
            return (worst.1, true, "form: " + hits.map(\.0).sorted().joined(separator: ", "))
        case .seafood:
            if matchesAny(cfg.surimiMarkers, in: hay) || tags.contains("surimi") {
                return (c["seafoodSurimi"] ?? 0.2, true, "form: surimi / imitation")
            }
            if matchesAny(cfg.breadedMarkers, in: hay) || !tags.isDisjoint(with: ["breaded-fish", "fish-sticks", "fish-fingers"]) {
                return (c["seafoodBreaded"] ?? 0.5, true, "form: breaded / fried")
            }
            if hasSmokeEvidence(p, cfg: cfg) || !tags.isDisjoint(with: ["smoked-fishes", "smoked-salmons"]) {
                return (c["seafoodSmoked"] ?? 0.6, true, "form: smoked")
            }
            if hasCureEvidence(p, cfg: cfg) {
                return (c["seafoodCured"] ?? 0.6, true, "form: cured")
            }
            return (c["seafoodPlain"] ?? 1.0, true, "form: plain (fresh / frozen / canned)")
        }
    }

    // MARK: Caps (Overall)

    struct CapHit { let id: String; let value: Int; let shortLabel: String; let kind: String; let detail: String }

    static func isMercuryAvoidSpecies(_ p: Product, cfg: Config) -> Bool {
        let tags = Set(p.categories ?? [])
        if !tags.isDisjoint(with: cfg.mercuryAvoidTags) { return true }
        let hay = (p.name + " " + (p.ingredientsText ?? "")).lowercased()
        return cfg.mercuryAvoidWords.contains { hay.contains($0) }
    }

    static func isMercuryModerateSpecies(_ p: Product, cfg: Config) -> Bool {
        let hay = (p.name + " " + (p.ingredientsText ?? "")).lowercased()
        return cfg.mercuryModerateWords.contains { hay.contains($0) }
    }

    static func caps(_ p: Product, form: Form, cfg: Config) -> [CapHit] {
        var out: [CapHit] = []
        switch form {
        case .processed:
            // IARC's Group 1 definition covers salting, curing, fermentation
            // and smoking — a dry-cured prosciutto or a smoked kielbasa takes
            // the same ceiling as nitrite bacon. Only merely-cooked-and-salted
            // deli roasts get the lighter one.
            let hay = evidenceHay(p)
            let group1 = hasCureEvidence(p, cfg: cfg) || hasSmokeEvidence(p, cfg: cfg)
                || matchesAny(cfg.dryMarkers, in: hay) || matchesAny(cfg.emulsifiedMarkers, in: hay)
                || !Set(p.categories ?? []).isDisjoint(with: cfg.group1Tags)
            if group1 {
                out.append(CapHit(
                    id: "processedMeatCap", value: cfg.caps.cured, shortLabel: "processed meat",
                    kind: "processedMeat",
                    detail: "Cured, smoked or dried meat — the WHO classifies processed meat as carcinogenic to humans (Group 1), and a celery-powder cure is the same nitrate chemistry as a conventional one. Caps the overall score at \(cfg.caps.cured)."))
            } else {
                out.append(CapHit(
                    id: "processedMeatCap", value: cfg.caps.processedOther, shortLabel: "processed meat",
                    kind: "processedMeat",
                    detail: "Processed meat — health guidance is to eat little of it. Caps the overall score at \(cfg.caps.processedOther)."))
            }
        case .seafood:
            if hasSmokeEvidence(p, cfg: cfg) || !Set(p.categories ?? []).isDisjoint(with: ["smoked-fishes", "smoked-salmons"]) {
                out.append(CapHit(
                    id: "smokedFishCap", value: cfg.caps.smokedFish, shortLabel: "smoked fish",
                    kind: "smokedFish",
                    detail: "Smoked fish — the fish's benefits with a cured product's salt. Fine as an occasional food; caps the overall score at \(cfg.caps.smokedFish)."))
            }
            if isMercuryAvoidSpecies(p, cfg: cfg) {
                out.append(CapHit(
                    id: "mercuryCap", value: cfg.caps.mercury, shortLabel: "high mercury",
                    kind: "mercury",
                    detail: "This species is on the FDA/EPA \"choices to avoid\" list for mercury — advised against for pregnant people and young children. Caps the overall score at \(cfg.caps.mercury)."))
            } else if isMercuryModerateSpecies(p, cfg: cfg) {
                out.append(CapHit(
                    id: "mercuryModerateCap", value: cfg.caps.mercuryModerate, shortLabel: "moderate mercury",
                    kind: "mercury",
                    detail: "An FDA/EPA \"good choice\" species — fine weekly, carries more mercury than the best choices. Caps the overall score at \(cfg.caps.mercuryModerate)."))
            }
            if let na = p.nutrients.sodium_mg, na >= cfg.caps.seafoodSodiumMg {
                out.append(CapHit(
                    id: "seafoodSodiumCap", value: cfg.caps.seafoodSodium, shortLabel: "very high sodium",
                    kind: "seafoodSodium",
                    detail: String(format: "%.0f mg sodium per 100 g — a garnish, not a portion. Fine in small amounts; caps the overall score at %d.", na, cfg.caps.seafoodSodium)))
            }
        case .fresh:
            break
        }
        return out
    }

    // MARK: Routing evidence

    /// Meat router tags ride on prepared dishes (soups, pies, ready meals).
    /// A product declaring meat-implausible composition falls through to its
    /// other tags. Undeclared values pass — the identity gate judges those.
    static func passesGuard(_ p: Product, cfg: Config) -> Bool {
        // A chicken purée is baby food that contains chicken, not a cut of
        // meat — baby-tagged products never take a meat profile.
        if !Set(p.categories ?? []).isDisjoint(with: ["baby-foods", "baby-food", "meals-for-babies", "main-meals-for-babies"]) {
            return false
        }
        let g = cfg.routingGuard
        // A zero-filled panel (kcal 0 AND protein 0) is an empty OFF record,
        // not a food with no energy — treat as undeclared.
        let zeroPanel = (p.nutrients.kcal ?? 0) == 0 && (p.nutrients.protein_g ?? 0) == 0
        if !zeroPanel, let prot = p.nutrients.protein_g, prot < g.minProteinG { return false }
        if let kcal = p.nutrients.kcal, kcal > g.maxKcal { return false }
        if let sugar = p.nutrients.sugar_g, sugar > g.maxSugarG { return false }
        return true
    }

    /// Plant-based analogues riding meat tags (Beyond-style burgers carry
    /// `meat-alternatives` and often plain meat tags too): vegan/vegetarian
    /// analysis flags, plant words in the name, or a plant base leading the
    /// list. Word-bounded — "beefsteak tomato" is caught by nameWords, but
    /// "chicken" must not match "chickpea" and vice versa.
    static func isPlantBased(_ p: Product, cfg: Config) -> Bool {
        // Deliberately NOT OFF's vegan/vegetarian analysis flags: label bugs
        // (a bacon whose printed list forgets the pork) read as vegan there.
        let labels = (p.labels ?? []).map { raw -> String in
            let l = raw.lowercased()
            return l.range(of: ":").map { String(l[$0.upperBound...]) } ?? l
        }
        if cfg.plantEvidence.labels.contains(where: { l in labels.contains { $0 == l } }) { return true }
        let name = p.name.lowercased()
        if cfg.plantEvidence.nameWords.contains(where: { $0.contains(" ") ? name.contains($0) : ScoringEngineV4.matchesWord($0, in: name) }) { return true }
        if let text = p.ingredientsText {
            let toks = IngredientIntegrity.tokens(from: text)
            let plants = cfg.plantEvidence.firstIngredients
            if let first = toks.first {
                if plants.contains(where: { first.hasPrefix($0) }) { return true }
                if IngredientIntegrity.isWaterToken(first),
                   let second = toks.dropFirst().first,
                   plants.contains(where: { second.hasPrefix($0) }) { return true }
            }
        }
        return false
    }

    /// Junk-tag rerail: real hot dogs and deli meats routinely carry
    /// `en:undefined` categories on OFF and fell to `general`. A processed-meat
    /// word in the name plus a meat species (name or first ingredient), meat
    /// composition, and no plant evidence is a processed meat whatever the
    /// tags say.
    static func hasProcessedMeatNameEvidence(_ p: Product, cfg: Config) -> Bool {
        let name = p.name.lowercased()
        guard cfg.processedNameWords.contains(where: {
            $0.contains(" ") ? name.contains($0) : ScoringEngineV4.matchesWord($0, in: name)
        }) else { return false }
        guard !isPlantBased(p, cfg: cfg) else { return false }
        guard passesGuard(p, cfg: cfg), p.nutrients.protein_g != nil else { return false }
        // Species word in the name, or a meat species leading the list
        // ("mechanically separated turkey" starts with a strippable qualifier
        // for speciesClass's first-token check).
        if speciesClass(p, cfg: cfg) != nil { return true }
        let hay = firstTokens(p, count: 1).joined(separator: " ")
        return cfg.speciesWords.values.flatMap { $0 }.contains { hay.contains($0) }
    }

    /// Untagged plain cuts: a species word in the NAME plus a species word
    /// leading the list, inside the fresh envelope. Name + list together,
    /// never either alone ("chicken broth" fails the envelope; "chicken salad"
    /// fails the first-ingredient test).
    static func hasFreshMeatEvidence(_ p: Product, cfg: Config) -> Bool {
        guard passesGuard(p, cfg: cfg), !isPlantBased(p, cfg: cfg) else { return false }
        let name = p.name.lowercased()
        let allSpecies = cfg.speciesWords.values.flatMap { $0 }
        guard allSpecies.contains(where: { ScoringEngineV4.matchesWord($0, in: name) }) else { return false }
        guard let first = firstTokens(p, count: 1).first,
              allSpecies.contains(where: { first.contains($0) }) else { return false }
        let key = (speciesClass(p, cfg: cfg).map { ["oilyFish", "leanFish", "shellfish"].contains($0) } ?? false)
            ? "seafood" : "fresh"
        guard let env = cfg.identityEnvelope[key] else { return false }
        let n = p.nutrients
        guard let kcal = n.kcal, kcal >= env.kcalMin, kcal <= env.kcalMax,
              let prot = n.protein_g, prot >= env.proteinMin, prot <= env.proteinMax else { return false }
        if let s = n.sugar_g, s > env.sugarMax { return false }
        return true
    }

    /// Fresh-tag products carrying cure / smoke / dry / restructure / breading
    /// evidence are processed meat ("uncured beef snack" tagged only `meats`,
    /// chicken nuggets tagged `chicken`).
    static func promotesToProcessed(_ p: Product, cfg: Config) -> Bool {
        let hay = evidenceHay(p)
        return hasCureEvidence(p, cfg: cfg)
            || hasSmokeEvidence(p, cfg: cfg)
            || matchesAny(cfg.dryMarkers, in: hay)
            || matchesAny(cfg.emulsifiedMarkers, in: hay)
            || matchesAny(cfg.breadedMarkers, in: hay)
    }
}
