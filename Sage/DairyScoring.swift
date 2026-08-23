import Foundation

// V5.6.0 — Dairy: four forms, one family (SCORING_V5.md §"V5.6.0 Dairy").
//
//   dairy_milk       fluid milk, lactose-free, UHT, ultrafiltered, goat/sheep,
//                    buttermilk, evaporated / condensed, powders (reconstituted)
//   dairy_fermented  yogurt, Greek, skyr, kefir, quark, labneh, drinkable yogurts
//   dairy_cheese     fresh, aged and processed cheese
//   dairy_cream      heavy / light cream, half-and-half, sour cream, crème
//                    fraîche, whipped cream and dairy whipped toppings
//
// Stance (unchanged from V5.2 / V5.3, now written down): health only; fat level
// is preference (whole = skim in Overall, personalized in Your Score); unknown
// is a confidence haircut with a form-appropriate prior, never a guess; raw
// fluid / fresh-fermented milk is a safety cap; no points for sourcing,
// welfare, packaging or certification (those are Oasis' axes, not health).
//
// What lives here: the per-form rules (free sugar with a lactose allowance,
// marker-family processing, the form-and-cultures rule, the S13 reference
// prior), the dairy identity gate for sparse records, the plausibility guard
// for per-serving panels entered as per-100 g, and the routing evidence gates
// (plant-based alternatives, protein shakes, infant formula).
enum DairyScoring {

    enum Form: String {
        case milk, fermented, cheese, cream
    }

    /// Profile id → form. Legacy ids (`yogurt_cheese`, frozen v5.0.9) return
    /// nil so the old code paths stay untouched.
    static func form(_ profileId: String) -> Form? {
        switch profileId {
        case "dairy_milk": return .milk
        case "dairy_fermented": return .fermented
        case "dairy_cheese": return .cheese
        case "dairy_cream": return .cream
        default: return nil
        }
    }

    static func isDairy(_ profileId: String) -> Bool { form(profileId) != nil }

    static let profileIds: [String] = ["dairy_milk", "dairy_fermented", "dairy_cheese", "dairy_cream"]

    // MARK: Config

    struct Config: Codable {
        struct Envelope: Codable {
            let kcalMin: Double; let kcalMax: Double
            let proteinMin: Double; let proteinMax: Double
            let sugarMax: Double; let sodiumMax: Double
        }
        struct Lift: Codable { let threshold: Double; let lift: Double }
        struct Plausibility: Codable { let kcalMax: Double }
        struct PlantEvidence: Codable {
            let labels: [String]; let nameWords: [String]; let firstIngredients: [String]
        }
        struct ShakeEvidence: Codable {
            let minProteinGPer100ml: Double; let nameWords: [String]; let flavorWords: [String]
        }
        let lactoseAllowance: [String: Double]
        let strainedMarkers: [String]
        let s13Prior: [String: Double]
        let s13Lifts: [String: Lift]
        let s13CalciumByForm: [String: Double]
        let s13CalciumLift: Double
        let s4FermentedPrior: Double
        let identityEnvelope: [String: Envelope]
        let identityS1Unknown: Double
        let offEnvelopeS1Unknown: Double
        let identityS2Unknown: Double
        let plausibility: [String: Plausibility]
        let markerFamilies: [String: [String]]
        let markerCredits: [Double]
        let cultureMarkers: [String]
        let heatTreatedMarkers: [String]
        let formCredits: [String: Double]
        let analogueMarkers: [String]
        let antiCakeMarkers: [String]
        let processedCheeseTags: [String]
        let rawMilkCheeseTags: [String]
        let plantEvidence: PlantEvidence
        let proteinShakeEvidence: ShakeEvidence
        let dairyProteinTerms: [String]
        let neutralTokens: [String]
        /// [[freeSugarGPer100, cap], …] — a sweet yogurt is never Excellent.
        let freeSugarCaps: [[Double]]
        /// Tier-1 non-nutritive sweetener (sucralose / Ace-K / aspartame)
        /// on fermented dairy or cream — same precautionary ceiling as the
        /// table-sweetener gate.
        let sweetenerCap: Int
        struct SodiumCap: Codable { let thresholdMg: Double; let cap: Int }
        /// Cheese at or above 1 200 mg sodium / 100 g (processed singles,
        /// halloumi, grated parmesan) tops out in the OK band.
        let cheeseSodiumCap: SodiumCap
    }

    // MARK: Normalization

    /// Applied before any rule evaluates (one entry point so score, overview
    /// payload and evidence summary see the same product):
    /// 1. plausibility — a per-serving panel entered as per 100 g (a 150 kcal
    ///    "whole milk", an 8 000 kcal grated parmesan) is rescaled through the
    ///    declared serving when that lands inside the form's envelope;
    /// 2. powder reconstitution (fluid milk only — processed cheese and yogurt
    ///    legitimately list milk powder and are dense per 100 g);
    /// 3. fortification exemption (vitamins, minerals, DHA, choline, lactase,
    ///    prebiotic fibre) stripped from the list;
    /// 4. evidence-based NOVA — a list that is dairy base + {cultures, enzymes,
    ///    rennet, salt, lactase, fortificants} is NOVA 1 (milk / fermented /
    ///    cream) whatever OFF's tag says, including when the tag is missing.
    static func normalized(_ p: Product, form: Form, rs: RulesetV4, cfg: Config) -> Product {
        var q = p
        q = rescaledIfImplausible(q, form: form, rs: rs, cfg: cfg)

        if form == .milk,
           let pw = rs.dairyPowder,
           let kcal = q.nutrients.kcal, kcal >= pw.kcalTrigger,
           looksLikePowder(q, cfg: pw) {
            scaleNutrients(&q, by: pw.factor)
        }

        if let fort = rs.dairyFortification, let text = q.ingredientsText {
            let tokens = IngredientIntegrity.tokens(from: text)
            let kept = tokens.filter { t in !fort.exempt.contains { t.contains($0) } }
            if kept.count < tokens.count, !kept.isEmpty {
                q.ingredientsText = kept.joined(separator: ", ")
            }
            // Evidence-NOVA: milk / fermented / cream lists made only of dairy
            // base + neutral tokens are unprocessed whatever the tag says.
            if form != .cheese, q.additives.isEmpty, !kept.isEmpty,
               kept.allSatisfy({ IngredientIntegrity.isWholeFoodToken($0) || isNeutralToken($0, cfg: cfg) }),
               kept.contains(where: IngredientIntegrity.isWholeFoodToken) {
                q.novaGroup = 1
            }
        }
        return q
    }

    static func looksLikePowder(_ p: Product, cfg: RulesetV4.DairyPowder) -> Bool {
        let hay = (p.name + " " + (p.ingredientsText ?? "")).lowercased()
        return cfg.keywords.contains { hay.contains($0) }
    }

    static func isNeutralToken(_ token: String, cfg: Config) -> Bool {
        cfg.neutralTokens.contains { token == $0 || token.hasPrefix($0 + " ") || token.hasSuffix(" " + $0) }
    }

    private static func scaleNutrients(_ q: inout Product, by f: Double) {
        func scale(_ v: inout Double?) { v = v.map { $0 * f } }
        scale(&q.nutrients.sugar_g); scale(&q.nutrients.sodium_mg); scale(&q.nutrients.satFat_g)
        scale(&q.nutrients.fiber_g); scale(&q.nutrients.protein_g); scale(&q.nutrients.calcium_mg)
        scale(&q.nutrients.kcal); scale(&q.nutrients.addedSugar_g); scale(&q.nutrients.transFat_g)
        scale(&q.nutrients.iron_mg); scale(&q.nutrients.potassium_mg); scale(&q.nutrients.magnesium_mg)
        scale(&q.nutrients.zinc_mg); scale(&q.nutrients.vitaminC_mg); scale(&q.nutrients.vitaminD_ug)
        scale(&q.nutrients.vitaminB12_ug); scale(&q.nutrients.polyols_g)
    }

    /// Per-serving values entered in the per-100 g fields: kcal above the
    /// form's ceiling, a parseable serving (5–400 g/ml), and the rescaled panel
    /// landing inside the ceiling. Powders / evaporated / condensed milks are
    /// legitimately dense and excluded.
    static func rescaledIfImplausible(_ p: Product, form: Form, rs: RulesetV4, cfg: Config) -> Product {
        guard let lim = cfg.plausibility[form.rawValue],
              let kcal = p.nutrients.kcal, kcal > lim.kcalMax else { return p }
        if form == .milk {
            let tags = Set(p.categories ?? [])
            let dense = ["evaporated-milks", "condensed-milks", "sweetened-condensed-milks",
                         "powdered-milks", "milk-powders"]
            if !tags.isDisjoint(with: dense) { return p }
            if let pw = rs.dairyPowder, looksLikePowder(p, cfg: pw) { return p }
            let name = p.name.lowercased()
            if name.contains("evaporated") || name.contains("condensed") || name.contains("powder") { return p }
        }
        guard let serving = servingGrams(p.servingSize), serving >= 5, serving <= 400 else { return p }
        let factor = 100.0 / serving
        guard kcal * factor <= lim.kcalMax else { return p }
        var q = p
        scaleNutrients(&q, by: factor)
        return q
    }

    /// "240 ml", "1 cup (240ml)", "5 g", "28g", "1 oz (28 g)" → grams/ml.
    static func servingGrams(_ raw: String?) -> Double? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased().replacingOccurrences(of: ",", with: ".")
        let patterns: [(String, Double)] = [
            (#"(\d+(?:\.\d+)?)\s*(?:g|ml|gram|grams|mL)\b"#, 1.0),
            (#"(\d+(?:\.\d+)?)\s*(?:fl\.?\s*oz|oz)\b"#, 29.5735),
        ]
        for (pattern, factor) in patterns {
            if let re = try? NSRegularExpression(pattern: pattern),
               let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: s),
               let v = Double(s[r]), v > 0 {
                return v * factor
            }
        }
        return nil
    }

    // MARK: Identity gate (sparse records)

    /// A record with no ingredient list whose panel sits inside the form's
    /// envelope and carries no additive tags is, with high probability, the
    /// plain food its tag says it is. The generic S1 unknown credit (0.20) is
    /// calibrated for packaged food where a missing list often hides
    /// additives; milk's additive prior is near zero. Confidence still takes
    /// the haircut — the number is provisional, just not punitive.
    static func passesIdentityEnvelope(_ p: Product, form: Form, cfg: Config) -> Bool {
        guard let env = cfg.identityEnvelope[form.rawValue], p.additives.isEmpty else { return false }
        let n = p.nutrients
        guard let kcal = n.kcal, kcal >= env.kcalMin, kcal <= env.kcalMax else { return false }
        guard let prot = n.protein_g, prot >= env.proteinMin, prot <= env.proteinMax else { return false }
        if let s = n.sugar_g, s > env.sugarMax { return false }
        if let na = n.sodium_mg, na > env.sodiumMax { return false }
        return true
    }

    static func s1UnknownCredit(_ p: Product, form: Form, cfg: Config) -> Double {
        passesIdentityEnvelope(p, form: form, cfg: cfg) ? cfg.identityS1Unknown : cfg.offEnvelopeS1Unknown
    }

    // MARK: S2 — marker-family processing (milk, cream)

    /// Ultra-processing read off the (fortification-stripped) list: each
    /// marker family present costs one step. Dairy lists made only of dairy
    /// base + neutral tokens are 1.0 whatever OFF's NOVA says; a missing list
    /// falls back to the identity envelope.
    static func s2Credit(_ p: Product, form: Form, cfg: Config) -> (Double, Bool, String?) {
        guard let text = p.ingredientsText?.lowercased(), !text.isEmpty else {
            let f = passesIdentityEnvelope(p, form: form, cfg: cfg) ? cfg.identityS2Unknown : 0.40
            return (f, false, "S2 dairy: no list → \(passesIdentityEnvelope(p, form: form, cfg: cfg) ? "identity prior" : "unknown")")
        }
        let families = markerFamilies(in: text, cfg: cfg)
        let idx = min(families.count, cfg.markerCredits.count - 1)
        let f = cfg.markerCredits[idx]
        let note = families.isEmpty
            ? "S2 dairy: no ultra-processing markers"
            : "S2 dairy: \(families.count) marker families (\(families.sorted().joined(separator: ", ")))"
        return (f, true, note)
    }

    static func markerFamilies(in text: String, cfg: Config) -> [String] {
        cfg.markerFamilies.compactMap { family, needles in
            needles.contains { text.contains($0) } ? family : nil
        }
    }

    // MARK: S3 — free sugar with a lactose allowance

    /// Declared added sugar wins (no further discount — the V5.1 intrinsic ×0.7
    /// discount double-counted it). Otherwise total sugar minus the form's
    /// lactose allowance: WHO's free-sugar definition excludes milk sugars.
    /// Strained products (Greek / skyr / labneh / quark) carry less lactose.
    static func s3Credit(_ p: Product, form: Form, rs: RulesetV4, cfg: Config,
                         thresholds: [Double]) -> (Double, Bool, String?) {
        let n = p.nutrients
        if let added = trustedAddedSugar(p) {
            let r = ScoringEngineV4.stepped(added, thresholds: thresholds, unknownCredit: 0.25)
            return (r.0, r.1, String(format: "S3 dairy: declared added sugar %.1f g → f %.3f", added, r.0))
        }
        guard let total = n.sugar_g else {
            // Cheese sugar is structurally low; an undeclared value is an
            // omission, not a risk. Milk / fermented / cream keep the unknown.
            if form == .cheese { return (0.90, false, "S3 dairy: sugar undeclared on cheese → structural prior") }
            return (0.25, false, "S3 dairy: no sugar data")
        }
        let allowance = lactoseAllowance(p, form: form, cfg: cfg)
        let free = max(0, total - allowance)
        let r = ScoringEngineV4.stepped(free, thresholds: thresholds, unknownCredit: 0.25)
        return (r.0, r.1, String(format: "S3 dairy: total %.1f − lactose %.1f = %.1f g free → f %.3f", total, allowance, free, r.0))
    }

    /// Declared added sugar, when sane: OFF carries per-serving or copy-paste
    /// errors ("added sugars 11.5 g" on a plain Greek with 3.5 g total sugar),
    /// so a value above total sugar is ignored.
    static func trustedAddedSugar(_ p: Product) -> Double? {
        guard let added = p.nutrients.addedSugar_g, added > 0 else { return nil }
        if let total = p.nutrients.sugar_g, added > total + 0.5 { return nil }
        return added
    }

    static func lactoseAllowance(_ p: Product, form: Form, cfg: Config) -> Double {
        if form == .fermented, isStrained(p, cfg: cfg) {
            return cfg.lactoseAllowance["strained"] ?? 3.0
        }
        return cfg.lactoseAllowance[form.rawValue] ?? 0
    }

    static func isStrained(_ p: Product, cfg: Config) -> Bool {
        let tags = Set(p.categories ?? [])
        if !tags.isDisjoint(with: ["greek-yogurts", "skyr", "strained-yogurts", "labneh", "quark"]) { return true }
        let name = p.name.lowercased()
        return cfg.strainedMarkers.contains { name.contains($0) }
    }

    // MARK: S6 — sweeteners (fermented, cream)

    static func s6Credit(_ p: Product) -> (Double, Bool, String?) {
        guard p.hasIngredientData else { return (0.90, false, "S6 dairy: no list → assumed unsweetened") }
        let r = DrinksScoring.s6Credit(p)
        return (r.0, r.1, r.2.isEmpty ? nil : "S6 dairy: " + r.2.joined(separator: ", "))
    }

    // MARK: Processing (milk, cream) — heat and filtration

    /// HTST / vat pasteurized 1.0 (the norm — pasteurized by law unless
    /// labelled raw, so the default is evidence, not assumption) · UHT /
    /// ultra-pasteurized / sterilized 0.7 · ultrafiltered 0.7 (0.6 if also
    /// UHT) · evaporated / condensed / powder 0.7 · raw 0.5 (+ the 54 cap).
    static func processingCredit(_ p: Product, rs: RulesetV4, cfg: Config) -> (Double, Bool, String?) {
        let tags = Set((p.categories ?? []) + (p.labels ?? []))
        var hits: [(String, Double)] = []
        for entry in rs.dairyProcessing ?? [] where tags.contains(entry.match) {
            hits.append((entry.match, entry.credit))
        }
        let name = p.name.lowercased()
        for entry in rs.dairyProcessingName ?? [] where ScoringEngineV4.matchesWord(entry.kw, in: name) {
            hits.append((entry.kw, entry.credit))
        }
        if let pw = rs.dairyPowder, let kcal = p.nutrients.kcal, kcal >= pw.kcalTrigger, looksLikePowder(p, cfg: pw) {
            hits.append(("powder", 0.7))
        }
        guard !hits.isEmpty else {
            return (rs.dairyProcessingDefault ?? 1.0, true, "processing: pasteurized (default)")
        }
        var f = hits.map(\.1).min() ?? 1.0
        let names = hits.map(\.0)
        let uf = names.contains { $0.contains("ultrafilt") || $0.contains("ultra-filt") || $0.contains("ultra filt") }
        let uht = names.contains { $0.contains("uht") || $0.contains("ultra-past") || $0.contains("ultra past") || $0.contains("steril") }
        if uf, uht { f = min(f, 0.6) }
        return (f, true, "processing: " + Array(Set(names)).sorted().joined(separator: ", ") + String(format: " → %.2f", f))
    }

    // MARK: Form & cultures (fermented, cheese)

    static func formCredit(_ p: Product, form: Form, cfg: Config) -> (Double, Bool, String?) {
        let c = cfg.formCredits
        let tags = Set((p.categories ?? []) + (p.labels ?? []))
        let text = (p.ingredientsText ?? "").lowercased()
        switch form {
        case .fermented:
            guard !text.isEmpty else { return (c["unknown"] ?? 0.85, false, "form: no list") }
            if cfg.heatTreatedMarkers.contains(where: { text.contains($0) }) {
                return (c["fermentedHeatTreated"] ?? 0.6, true, "form: heat-treated after culturing")
            }
            if cfg.cultureMarkers.contains(where: { text.contains($0) }) {
                return (c["fermentedLive"] ?? 1.0, true, "form: live cultures declared")
            }
            return (c["fermentedAssumed"] ?? 0.9, true, "form: fermented, cultures not declared")
        case .cheese:
            let processedTag = !tags.isDisjoint(with: cfg.processedCheeseTags)
            guard !text.isEmpty else {
                if processedTag { return (c["cheeseProcessed"] ?? 0.35, true, "form: processed cheese (tag)") }
                return (c["unknown"] ?? 0.85, false, "form: no list")
            }
            let oil = cfg.analogueMarkers.contains { $0.contains("oil") && text.contains($0) }
            if oil { return (c["cheeseAnalogue"] ?? 0.1, true, "form: vegetable oil in a cheese (analogue / cheese product)") }
            let salts = cfg.markerFamilies["emulsifyingSalt"] ?? []
            if processedTag || salts.contains(where: { text.contains($0) }) {
                return (c["cheeseProcessed"] ?? 0.35, true, "form: processed cheese (emulsifying salts)")
            }
            if !tags.isDisjoint(with: cfg.rawMilkCheeseTags) || text.contains("raw milk") || text.contains("lait cru")
                || text.contains("leche cruda") || text.contains("leite cru") {
                return (c["cheeseRawMilk"] ?? 0.8, true, "form: raw-milk cheese")
            }
            if cfg.antiCakeMarkers.contains(where: { text.contains($0) }) {
                return (c["cheeseAntiCake"] ?? 0.9, true, "form: natural cheese with anti-caking / surface treatment")
            }
            return (c["cheeseNatural"] ?? 1.0, true, "form: natural cheese")
        case .milk, .cream:
            return (1.0, false, nil)
        }
    }

    // MARK: S13 — dairy reference prior

    /// Dairy's micronutrient matrix (B12, riboflavin, iodine, phosphorus,
    /// potassium, calcium, vitamin D when fortified) is invisible to the
    /// %DV-per-100 g rule. Like V5.3 eggs: a reference prior by form, lifted
    /// by declared vitamin D / potassium / B12 / calcium. The prior is
    /// evidence of the food's identity, so hadData is true.
    static func s13Credit(_ p: Product, form: Form, cfg: Config) -> (Double, Bool, String?) {
        let prior = cfg.s13Prior[form.rawValue] ?? 0.5
        let n = p.nutrients
        var lift = 0.0
        var hits: [String] = []
        func check(_ key: String, _ value: Double?) {
            guard let l = cfg.s13Lifts[key], let v = value, v >= l.threshold else { return }
            lift += l.lift; hits.append(key)
        }
        check("vitaminD_ug", n.vitaminD_ug)
        check("potassium_mg", n.potassium_mg)
        check("vitaminB12_ug", n.vitaminB12_ug)
        if let ca = n.calcium_mg, let t = cfg.s13CalciumByForm[form.rawValue], ca >= t {
            lift += cfg.s13CalciumLift; hits.append("calcium_mg")
        }
        let f = min(1.0, prior + lift)
        let note = hits.isEmpty
            ? String(format: "S13 dairy: %@ reference prior %.2f", form.rawValue, prior)
            : String(format: "S13 dairy: %@ prior %.2f + declared (%@) → %.2f", form.rawValue, prior, hits.joined(separator: ", "), f)
        return (f, true, note)
    }

    // MARK: S12 isolate exemption

    /// Milk-derived proteins (milk protein concentrate, whey protein
    /// concentrate, skim milk powder, ultrafiltered milk) are the product's
    /// own protein, not an isolate to halve S12 for — the V5.5 protein-bar
    /// principle. They stay non-whole tokens in S14.
    static func hasNonDairyIsolate(_ p: Product, cfg: Config) -> Bool {
        guard var text = p.ingredientsText?.lowercased() else { return false }
        for term in cfg.dairyProteinTerms.sorted(by: { $0.count > $1.count }) {
            text = text.replacingOccurrences(of: term, with: "milk")
        }
        return IngredientIntegrity.hasIsolateProtein(ingredientsText: text)
    }

    /// Cream S12: a declared protein of exactly 0 is per-tablespoon rounding
    /// (real cream is ~2 g/100 ml), not evidence of zero protein.
    static func creamProteinIsRounding(_ p: Product) -> Bool {
        p.nutrients.protein_g == 0
    }

    // MARK: S12 — cheese variant

    /// Cheese-scaled protein + calcium: the yogurt targets (6 g / 150 mg)
    /// saturate on every cheese. Protein is the blend of absolute per 100 g
    /// (target 20 g) and per-kcal density (15 g / 100 kcal) so cottage cheese
    /// (11 g in 98 kcal) is not outranked by a dense block; calcium carries
    /// the rest (acid-set fresh cheeses genuinely have less).
    static func s12CheeseCredit(_ p: Product, cfg: RulesetV4.S12DairyCheese?) -> (Double, Bool) {
        let protTarget = cfg?.proteinTargetG ?? 20
        let calTarget = cfg?.calciumTargetMg ?? 600
        let wProt = cfg?.proteinWeight ?? 0.7
        let n = p.nutrients
        let protCredit: Double? = n.protein_g.map { prot in
            let abs = min(1, prot / protTarget)
            guard let kcal = n.kcal, kcal > 0 else { return abs }
            let dens = min(1, (prot / (kcal / 100)) / 15)
            return (abs + dens) / 2
        }
        let cal = n.calcium_mg.map { min(1, $0 / calTarget) }
        switch (protCredit, cal) {
        case let (pr?, ca?): return (wProt * pr + (1 - wProt) * ca, true)
        case let (pr?, nil): return (pr, true)
        case let (nil, ca?): return (ca, true)
        default: return (cfg?.unknownCredit ?? 0.5, false)
        }
    }

    // MARK: Caps (Overall)

    struct CapHit { let id: String; let value: Int; let shortLabel: String; let kind: String; let detail: String }

    /// Free sugar per 100 g (declared added, else total − lactose allowance).
    static func freeSugarPer100(_ p: Product, form: Form, cfg: Config) -> Double? {
        if let added = trustedAddedSugar(p) { return added }
        guard let total = p.nutrients.sugar_g else { return nil }
        return max(0, total - lactoseAllowance(p, form: form, cfg: cfg))
    }

    static func caps(_ p: Product, form: Form, cfg: Config) -> [CapHit] {
        var out: [CapHit] = []
        if let free = freeSugarPer100(p, form: form, cfg: cfg) {
            var cap: Int? = nil
            for step in cfg.freeSugarCaps where step.count == 2 && free >= step[0] {
                cap = Int(step[1])
            }
            if let cap {
                out.append(CapHit(id: "dairyFreeSugarCap", value: cap, shortLabel: "added sugar", kind: "dairyFreeSugar",
                                  detail: String(format: "About %.0f g of free sugar per 100 g — milk sugar (lactose) is not counted. Caps the overall score at %d.", free, cap)))
            }
        }
        if form == .fermented || form == .cream {
            let t = DrinksScoring.detectSweetenerTiers(p)
            if t.tier1 > 0 {
                out.append(CapHit(id: "dairySweetenerCap", value: cfg.sweetenerCap, shortLabel: "artificial sweetener", kind: "dairyNns",
                                  detail: "Sweetened with an artificial sweetener (sucralose, acesulfame K or aspartame). Caps the overall score at \(cfg.sweetenerCap)."))
            }
        }
        if form == .cheese, let na = p.nutrients.sodium_mg, na >= cfg.cheeseSodiumCap.thresholdMg {
            out.append(CapHit(id: "dairySodiumCap", value: cfg.cheeseSodiumCap.cap, shortLabel: "very high sodium", kind: "dairySodium",
                              detail: String(format: "%.0f mg sodium per 100 g — among the saltiest foods on the shelf. Caps the overall score at %d.", na, cfg.cheeseSodiumCap.cap)))
        }
        return out
    }

    // MARK: Routing evidence

    /// OFF's `baby-milks` / `infant-formulas` tags ride on protein shakes and
    /// growth milks too; only a product that reads as formula (name words, or
    /// a powder-dense panel) leaves the scored world.
    static func looksLikeInfantFormula(_ p: Product) -> Bool {
        let name = p.name.lowercased()
        let words = ["formula", "fórmula", "formule", "infant", "lactante", "nourrisson", "bébé",
                     "baby", "bebê", "bebé", "stage 1", "stage 2", "stage 3", "1er âge", "2e âge",
                     "follow-on", "follow on", "toddler", "growing up", "croissance", "kendamil",
                     "similac", "enfamil", "aptamil", "nan ", "nutrilon", "hipp", "gerber good start"]
        if words.contains(where: { name.contains($0) }) { return true }
        // Powder-dense panel (≥ 400 kcal, milk-like protein share) with no list
        // reading as a shake.
        if let kcal = p.nutrients.kcal, kcal >= 400, let prot = p.nutrients.protein_g, prot <= 16 {
            return true
        }
        return false
    }

    /// Plant-based "milk" / "yogurt" / "cheese" riding dairy tags: vegan or
    /// dairy-free labels, plant words in the name, or a plant base as the
    /// first ingredient.
    static func isPlantBased(_ p: Product, cfg: Config) -> Bool {
        // Exact label match ("vegan", not "non-vegan" / "vegan-friendly-packaging").
        let labels = (p.labels ?? []).map { raw -> String in
            let l = raw.lowercased()
            return l.range(of: ":").map { String(l[$0.upperBound...]) } ?? l
        }
        if cfg.plantEvidence.labels.contains(where: { l in labels.contains { $0 == l } }) { return true }
        let name = p.name.lowercased()
        // Word-bounded: "goat milk" must not match "oat milk".
        if cfg.plantEvidence.nameWords.contains(where: { ScoringEngineV4.matchesWord($0, in: name) }) { return true }
        if let text = p.ingredientsText {
            let toks = IngredientIntegrity.tokens(from: text)
            if let first = toks.first {
                let plants = cfg.plantEvidence.firstIngredients
                // "coconut milk" / "almondmilk" / "cashews" lead a plant base;
                // plain "milk" leads dairy. "filtered water, coconut oil" too.
                if plants.contains(where: { first.hasPrefix($0) }) { return true }
                if IngredientIntegrity.isWaterToken(first),
                   let second = toks.dropFirst().first,
                   plants.contains(where: { second.hasPrefix($0) }) { return true }
            }
        }
        return false
    }

    /// Sweetened, flavored protein shakes tagged `milks` (Core Power, Muscle
    /// Milk): protein ≥ 6 g/100 ml plus shake/protein words in the name plus a
    /// flavor word, sweetener or declared added sugar. Plain high-protein milk
    /// (Lactaid Protein, fairlife 2 %) stays on the milk profile.
    static func isProteinShake(_ p: Product, cfg: Config) -> Bool {
        let e = cfg.proteinShakeEvidence
        guard let prot = p.nutrients.protein_g, prot >= e.minProteinGPer100ml else { return false }
        let name = p.name.lowercased()
        guard e.nameWords.contains(where: { name.contains($0) }) else { return false }
        let flavored = e.flavorWords.contains { name.contains($0) }
        let tiers = DrinksScoring.detectSweetenerTiers(p)
        let sweetened = (p.nutrients.addedSugar_g ?? 0) > 0 || (tiers.tier1 + tiers.tier2 + tiers.tier3) > 0
        return flavored || sweetened
    }
}
