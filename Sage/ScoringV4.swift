import Foundation

// MARK: - Scoring v5 (SCORING_V5.md) — health-only category-aware rule engine
//
// Score measures HEALTH only. Ethics / environment / packaging factors are
// out unless they have a direct health pathway (e.g. brewMaterial microplastics,
// contaminantRisk arsenic, drinks S7 packaging leaching). Architecture: all
// tunable data lives in RulesetV5.json; this file only knows rule *shapes*.
// Score = Σ(w·f)/Σw, floored at 10. Base caps (trans fat, free-sugar ceiling)
// can limit Overall; preference caps (diet/avoid) limit Your Score only.

// MARK: Ruleset (mirrors RulesetV5.json)

struct RulesetV4: Codable {
    struct Bands: Codable { let excellent: Int; let good: Int; let ok: Int }
    struct Dampening: Codable { let afterCount: Int; let factor: Double }
    struct ProfileRule: Codable { let rule: String; let w: Double; let variant: String? }
    struct RouterEntry: Codable { let match: String; let profile: String }
    struct RuleMeta: Codable {
        let displayName: String
        let driverKind: String   // "merit" | "hygiene"
    }

    struct SourceCredit: Codable { let match: String; let credit: Double }
    struct KwCredit: Codable { let kw: String; let credit: Double }
    struct PointsRule: Codable {
        let points: [String: Double]
        let denominator: Double
        let plantNeutral: Double?
    }
    /// Arsenic pathway for plant milks: rice capped; all other crops neutral.
    struct ContaminantRisk: Codable {
        let riceCap: Double
    }

    let version: String
    let bands: Bands
    let tierFractions: [String: Double]
    let dampening: Dampening
    let additiveTiers: [String: String]
    let gumCodes: [String]
    let sweetenerCodes: [String]
    let textSignals: [String: String]
    let s3Thresholds: [String: [Double]]
    let s4Thresholds: [Double]
    /// V5.4: per-variant sodium anchors (e.g. `bread`); falls back to `s4Thresholds`.
    var s4ThresholdsByVariant: [String: [Double]]? = nil
    let s5Thresholds: [String: [Double]]
    /// Removed in v5 (packaging non-health); kept optional for older downloads.
    let s7Materials: [String: Double]?
    let certLabels: [String]?
    let profiles: [String: [ProfileRule]]
    let router: [RouterEntry]
    /// Human labels + driverKind for overview prose (fail closed when missing).
    var ruleMeta: [String: RuleMeta]? = nil
    /// Remote feature flags (V5.1.0+). Optional for older downloaded rulesets.
    struct Flags: Codable {
        let rulesetV510Enabled: Bool?
    }
    var flags: Flags? = nil

    /// True for the v5.1.0 Real Food engine and later (not the frozen 5.0.9).
    /// Version strings sort lexicographically ("2026.07-v5.0.9" < "2026.07-v5.1.0"
    /// < "2026.08-v5.2.0"), so >= keeps the flag on across future bumps.
    var isV510: Bool { version >= "2026.07-v5.1.0" }

    // Category rules — optional so an older downloaded ruleset can't crash
    // decoding; evaluators fall back to unknown credit when absent.
    let waterSource: [SourceCredit]?
    let contaminantRisk: ContaminantRisk?
    let dairyLabels: PointsRule?
    let dairyProcessing: [SourceCredit]?
    let dairyProcessingDefault: Double?
    /// V5.2: processing words in the product NAME ("Ultra-Pasteurized", "UHT")
    /// — printed on front labels far more often than tagged. Word-bounded.
    let dairyProcessingName: [KwCredit]?
    let brewMaterial: [KwCredit]?
    let brewMaterialDefault: Double?
    let sweetenerType: [KwCredit]?
    let sweetenerTypeDefault: Double?
    let authenticityBad: [String]?
    let sweetenerProcessing: [KwCredit]?
    let sweetenerProcessingDefault: Double?
    let wholeGrainKw: [String]?
    let stabilizerPenalties: [String: Double]?
    let welfare: PointsRule?
    let heroCredit: [[Double]]?

    // V5.2 dairy — all optional so older rulesets (and frozen v5.0.9) keep
    // their behavior when the config is absent.
    /// S12 `dairy` variant: protein + calcium replace the fiber/FVN axes that
    /// are structurally zero for milk.
    struct S12Dairy: Codable {
        let proteinTargetG: Double      // g/100 ml earning full protein credit
        let calciumTargetMg: Double     // mg/100 ml earning full calcium credit
        let unknownCredit: Double       // neither reported
    }
    let s12Dairy: S12Dairy?
    /// S12 `dairyDense` variant (yogurt/cheese): same axes, but protein blends
    /// absolute per-100 g with per-kcal density — absolute alone would rank
    /// cream cheese above plain yogurt, density alone would break the
    /// whole-vs-nonfat neutrality stance.
    let s12DairyDense: S12Dairy?
    /// V5.6 S12 `dairyCheese` variant: cheese-scaled protein (abs + density
    /// blend) and calcium targets, protein-weighted.
    struct S12DairyCheese: Codable {
        let proteinTargetG: Double
        let calciumTargetMg: Double
        let proteinWeight: Double
        let unknownCredit: Double
    }
    var s12DairyCheese: S12DairyCheese? = nil
    /// Powdered milk reconstitution: per-100 g panel → per-100 ml as prepared.
    struct DairyPowder: Codable {
        let factor: Double              // standard reconstitution (≈12.5 g/100 ml)
        let kcalTrigger: Double         // liquid milk can't reach this per 100 ml
        let keywords: [String]          // matched in name/ingredients, not tags
    }
    let dairyPowder: DairyPowder?
    /// Fortificants (vitamin D/A, lactase) that must not count as processing.
    struct DairyFortification: Codable {
        let exempt: [String]
    }
    let dairyFortification: DairyFortification?

    // V5.3 eggs — optional so older rulesets (and frozen v5.0.9) keep their
    // behavior when the config is absent.
    struct EggConfig: Codable {
        struct Prior: Codable { let whole: Double; let whites: Double }
        struct WhitesEnvelope: Codable {
            let maxSatFatG: Double; let maxKcal: Double; let minProteinG: Double
        }
        struct RoutingGuard: Codable {
            let minProteinG: Double; let maxProteinG: Double
            let maxKcal: Double; let yolkMaxKcal: Double; let maxSugarG: Double
        }
        struct Powder: Codable { let factor: Double; let kcalTrigger: Double; let keywords: [String] }
        /// g protein / 100 g earning full S12 credit (USDA whole egg 12.6).
        let proteinTargetG: Double
        let s12UnknownCredit: Double
        /// S13 reference-composition prior by form (whole/yolk vs whites).
        let s13Prior: Prior
        /// S13 lift per declared enrichment nutrient at/above its threshold
        /// (≈2× a reference egg: vitamin D µg, B12 µg, omega-3 g, selenium µg).
        let s13EnrichmentStep: Double
        /// Ceiling on the total lift — an enriched egg is better, not perfect.
        let s13EnrichmentMaxLift: Double
        let s13Enrichment: [String: Double]
        /// S3 credit when sugars are undeclared on a plain egg (structurally <1 g).
        let s3UnknownCredit: Double
        let eggWords: [String]
        let whitesWords: [String]
        let whitesTags: [String]
        let yolkWords: [String]
        let yolkTags: [String]
        let whitesEnvelope: WhitesEnvelope
        let routingGuard: RoutingGuard
        let powder: Powder
        enum CodingKeys: String, CodingKey {
            case proteinTargetG, s12UnknownCredit, s13Prior, s13EnrichmentStep
            case s13EnrichmentMaxLift, s13Enrichment
            case s3UnknownCredit
            case eggWords, whitesWords, whitesTags, yolkWords, yolkTags, whitesEnvelope
            case routingGuard = "guard"
            case powder
        }
    }
    var eggs: EggConfig? = nil

    /// V5.6 dairy — four forms (milk / fermented / cheese / cream), lactose
    /// allowance, marker-family processing, form & cultures, S13 reference
    /// prior, identity gate, routing evidence. See DairyScoring.swift.
    var dairy: DairyScoring.Config? = nil

    // V5.4 bread — optional so older rulesets (and frozen v5.0.9) keep their
    // behavior when the config is absent. Shapes live in BreadScoring.swift.
    struct BreadConfig: Codable {
        struct FiberCap: Codable { let belowG: Double; let maxShare: Double }
        struct UPFMarker: Codable { let family: String; let text: [String]; let codes: [String]? }
        struct S2: Codable {
            /// Credit for a list with no ultra-processing markers (NOVA 3 —
            /// the best class a bread can be).
            let traditional: Double
            /// Credit by distinct marker-family count (index 0 = one family;
            /// the last entry covers every larger count).
            let markerCredits: [Double]
            let novaFourNoList: Double
            let unknownCredit: Double
        }
        struct S12: Codable {
            let fiberZeroG: Double
            let fiberFullG: Double
            let proteinTargetG: Double
            let fiberWeight: Double
            let proteinWeight: Double
            let isolatedFiberDamp: Double
            let unknownFiberPrior: Double
            let unknownFiberPriorWhole: Double
        }
        struct Sodium: Codable { let minSodiumMgWithSalt: Double; let saltWords: [String] }
        let wholeGrainKw: [String]
        let partialWholeKw: [String]
        let refinedKw: [String]
        let grainIgnoreKw: [String]
        let partialCredit: Double
        let rankDecay: Double
        let nameWholeClaims: [String]
        let nameClaimShare: Double
        let wholeTagFallback: [String]
        let unknownCredit: Double
        let unknownWholeCredit: Double
        let fiberCaps: [FiberCap]
        let isolatedFiberKw: [String]
        let upfMarkers: [UPFMarker]
        let s2: S2
        let s12: S12
        let sodium: Sodium
    }
    var bread: BreadConfig? = nil

    // V5.5 protein bars — optional so older rulesets (and frozen v5.0.9) keep
    // their behavior when the config is absent. Shapes live in
    // ProteinBarScoring.swift.
    struct ProteinBarConfig: Codable {
        struct Gate: Codable {
            let barTags: [String]
            let barWords: [String]
            let proteinWords: [String]
            let minKcal: Double
            let maxKcal: Double
            let maxProteinG: Double
            let minProteinShareNamed: Double
            let minProteinShareUnnamed: Double
            let minProteinGUnnamed: Double
            let fallbackProfiles: [String]
        }
        struct Serving: Codable { let defaultG: Double; let minG: Double; let maxG: Double }
        struct Source: Codable {
            let match: String
            /// DIAAS-style quality credit (whey / milk / egg 1.0 … collagen 0.25).
            let credit: Double
            /// Typical protein fraction of the ingredient — the label-position
            /// weight is scaled by it so a 25 %-protein peanut listed first
            /// doesn't outweigh a 90 % isolate listed second.
            let density: Double
        }
        struct S12: Codable {
            let servingFullG: Double
            let shareFull: Double
            let per100FullG: Double
            /// Share of the rule carried by protein (amount × quality); the
            /// rest is fiber.
            let proteinWeight: Double
            /// Quality scales the amount credit between `qualityFloor` (credit 0
            /// — e.g. pure collagen) and 1.0 (whey / milk / egg).
            let qualityFloor: Double
            let fiberWeight: Double
            let fiberFullG: Double
            let isolatedFiberDamp: Double
            let unknownFiberCredit: Double
            let rankDecay: Double
            let unknownQuality: Double
            let unknownCredit: Double
            let sources: [Source]
            let complementaryPairs: [[String]]
            let complementaryCredit: Double
        }
        struct S3: Codable { let fvnDiscountCap: Double }
        struct S2: Codable {
            let clean: Double
            /// Share of top-level tokens that must be recognizable (whole food,
            /// protein source, marker, additive code, water/salt) before a
            /// marker-free list earns the clean credit — OFF's OCR'd
            /// `ingredients_text` is often a nutrition table or a foreign
            /// language the marker lists don't cover, and "no markers found"
            /// must not read as "clean".
            let minRecognizedShare: Double
            let markerCredits: [Double]
            let novaFourNoList: Double
            let novaThreeNoList: Double
            let novaLowNoList: Double
            let unknownCredit: Double
            let upfMarkers: [BreadConfig.UPFMarker]
        }
        struct S6: Codable { let polyolLoadG: [Double]; let polyolLoadFactors: [Double] }
        struct S14: Codable { let neutralTokenKw: [String]; let neutralIsolateMarkers: [String] }
        let gate: Gate
        let serving: Serving
        let s12: S12
        let s3: S3
        let s2: S2
        let s1ExemptSignals: [String]
        let s6: S6
        let sodiumMaxPlausibleMg: Double
        let s14: S14
    }
    var proteinBars: ProteinBarConfig? = nil

    // S13 — beneficial micronutrient credit (positive-only). NRF-style: each
    // present nutrient contributes min(cap, %DV per 100g); the capped sum is
    // normalized by `target`. Optional so an older ruleset falls back to unknown.
    struct Micronutrients: Codable {
        let dv: [String: Double]        // nutrient key → daily reference value (mg)
        let capPerNutrient: Double      // one nutrient's max contribution (fraction of DV)
        let target: Double              // capped-sum that earns full credit
        let unknownCredit: Double       // neutral fraction when no micros reported
        /// V5.2: reported micros never score below the unknown credit —
        /// declaring data must not rank a product under an identical silent one.
        let dataFloor: Bool?
    }
    let micronutrients: Micronutrients?

    // Phase D personalization (SCORING_V4.md §7) — optional for back-compat.
    struct Multipliers: Codable {
        let objective: [String: [String: Double]]
        let goal: [String: [String: Double]]
        let slider: [String: [String: [String: Double]]]   // key → level → {rule: factor}
        /// Soft preference chips (V5.0.4). Optional so older downloaded rulesets decode.
        let preference: [String: [String: Double]]?
    }
    struct AvoidEntry: Codable { let codes: [String]?; let text: [String]?; let labels: [String]? }
    /// Personalization ceilings (§7.3). Stacked: effectiveCap = min(fired).
    /// Base gates (transFat, freeSugarCeiling) apply to Overall; preference
    /// gates (avoid/diet) apply to Your Score only.
    struct HardGates: Codable {
        let avoidListCap: Int
        /// Legacy flat ceiling for non-tapered diet conflicts (e.g. vegan).
        let dietConflictCap: Int?
        /// Per-restriction linear tapers (keys = restriction type, lowercased).
        let dietConflictTapers: [String: DietConflictTaper]?
        let transFat: TransFatGate?
        let freeSugarCeiling: FreeSugarCeiling?
        let nnsCeiling: NNSCeiling?

        struct DietConflictTaper: Codable {
            let metric: String      // "sugar_g" | "sodium_mg"
            let taperStart: Double
            let taperEnd: Double
            let minCap: Int
        }
        struct TransFatGate: Codable {
            let threshold: Double   // g/100g
            let cap: Int
        }
        struct FreeSugarCeiling: Codable {
            let cap: Int
        }
        struct NNSCeiling: Codable {
            let cap: Int
        }
        /// V5.2: unpasteurized fluid milk — pathogen risk the label can't
        /// certify away (Listeria / STEC / Salmonella). Fires on tag evidence.
        struct RawMilkGate: Codable {
            let cap: Int
            let tags: [String]
            /// Word-bounded phrases matched in the product name ("raw milk") —
            /// producers print it on the front label more often than OFF tags it.
            let names: [String]?
        }
        let rawMilk: RawMilkGate?
        /// Drinks-only gradual free-sugar damper (per-serving grams → score ×factor).
        struct DrinksFreeSugarDamper: Codable {
            let startG: Double    // factor 1.0 at/below
            let endG: Double      // factor minFactor at/above
            let minFactor: Double
        }
        let drinksFreeSugarDamper: DrinksFreeSugarDamper?
    }

    let multipliers: Multipliers?
    let avoidList: [String: AvoidEntry]?
    let hardGates: HardGates?

    /// Post-router nutritional plausibility envelopes (Fix 4). Key = profile id.
    /// On violation, reroute to `rerouteTo` (usually `drinks`).
    struct RoutingEnvelope: Codable {
        let rerouteTo: String
        /// Reject profile when caffeine_mg (per 100 ml) is ≥ this.
        let maxCaffeineMgPer100ml: Double?
        /// Reject profile when sugars_100g is ≥ this.
        let maxSugarGPer100ml: Double?
        /// M1: envelope bounds are per-100 ml, so they only make sense for
        /// liquids. When true, the envelope fires only if the product's size or
        /// serving parses as a volume — a 3-in-1 coffee *powder* at 60 g
        /// sugar/100 g must not be compared against a 5 g/100 ml liquid bound
        /// and handed a fictional 355 ml serving.
        let requiresLiquid: Bool?
    }
    var routingPlausibility: [String: RoutingEnvelope]? = nil

    /// Fix 5: waters-family + flavor evidence → `drinks` instead of `unsupported`.
    struct FlavoredWaterEvidence: Codable {
        let watersFamilyTags: [String]
        let nameFlavorWords: [String]
        let ingredientFlavorTerms: [String]
    }
    var flavoredWaterEvidence: FlavoredWaterEvidence? = nil

    /// Field QA: plain unflavored water must stay unscored no matter what OFF
    /// tags it wears. A US S.Pellegrino payload carried Spanish category tags
    /// ("Aguas", "Bebidas") that matched nothing in the router and scored 77.
    /// This gate recognizes water by *evidence* — name, zero energy/sugar, no
    /// flavor terms, no additives, no sweeteners — independent of tags.
    struct PlainWaterEvidence: Codable {
        let nameWaterWords: [String]
        let maxKcalPer100ml: Double
        let maxSugarGPer100ml: Double
    }
    var plainWaterEvidence: PlainWaterEvidence? = nil

    /// M2: WHO's free-sugar definition excludes intrinsic milk sugars. For RTDs
    /// with dairy evidence, up to `gPer100ml` of total sugar is treated as
    /// lactose and excluded from S3 and the sugar cap. Plant-milk phrases are
    /// stripped before the dairy-term match so "oat milk" never qualifies.
    struct DairyLactoseAllowance: Codable {
        let gPer100ml: Double
        let dairyTerms: [String]
        let plantMilkPhrases: [String]
    }
    var dairyLactoseAllowance: DairyLactoseAllowance? = nil

    /// Track 2: drinks S3 credit anchors as `[[gramsPerServing, credit]]`.
    /// A plain threshold list cannot express this curve — the credits at the
    /// interior anchors (0.48 / 0.25) are not `stepped`'s fixed 0.60 / 0.30.
    var s3DrinksServingCurve: [[Double]]? = nil

    /// v2.4: caffeine + stimulant ingredients → energy drink, independent of OFF tags.
    struct EnergyDrinkEvidence: Codable {
        let minCaffeineMgPer100ml: Double
        let stimulantIngredients: [String]
    }
    var energyDrinkEvidence: EnergyDrinkEvidence? = nil

    /// Band label for a score under this ruleset (single source for all UI).
    func bandLabel(_ score: Int) -> String {
        if score >= bands.excellent { return "Excellent" }
        if score >= bands.good { return "Good" }
        if score >= bands.ok { return "OK" }
        return "Bad"
    }

    func scoreTier(for score: Int) -> ScoreTier {
        if score >= bands.excellent { return .excellent }
        if score >= bands.good { return .good }
        if score >= bands.ok { return .poor }
        return .bad
    }

    /// All known rule ids (profiles ∪ meta keys) for validator fail-closed checks.
    var allRuleIds: [String] {
        var ids = Set<String>()
        if let keys = ruleMeta?.keys { ids.formUnion(keys) }
        for list in profiles.values {
            for pr in list { ids.insert(pr.rule) }
        }
        return Array(ids).sorted()
    }

    func displayName(for rule: String) -> String? {
        guard let name = ruleMeta?[rule]?.displayName, !name.isEmpty else { return nil }
        return name
    }

    func isMerit(_ rule: String) -> Bool {
        (ruleMeta?[rule]?.driverKind ?? "merit") == "merit"
    }

    private final class BundleToken {}

    /// The ruleset shipped inside the app. A downloaded ruleset takes
    /// precedence when newer (see RulesetStore).
    static let bundled: RulesetV4 = {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "RulesetV5", withExtension: "json")
                ?? Bundle.main.url(forResource: "RulesetV5", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rs = try? JSONDecoder().decode(RulesetV4.self, from: data)
        else {
            fatalError("RulesetV5.json missing or malformed — the app cannot score without it")
        }
        return rs
    }()

    /// Frozen v5.0.9 — kill-switch fallback (RulesetStore.v510Enabled == false).
    static let bundledV509: RulesetV4 = {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "RulesetV509", withExtension: "json")
                ?? Bundle.main.url(forResource: "RulesetV509", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rs = try? JSONDecoder().decode(RulesetV4.self, from: data)
        else {
            fatalError("RulesetV509.json missing or malformed — kill switch cannot fall back")
        }
        return rs
    }()
}

// MARK: Engine output

struct V4RuleResult {
    let rule: String
    let weight: Double
    let fraction: Double
    /// False when the rule fell back to its Tier-2 "unknown" credit — feeds
    /// the weight-backed Data Confidence (§3.2).
    let hadData: Bool
    /// Optional debug note (e.g. isolate discount).
    var note: String? = nil
}

struct V4Result {
    let rulesetVersion: String
    let profileId: String
    let base: Int
    /// Weight-backed confidence: Σ(w where rule had data) / Σw.
    let confidence: Double
    let rules: [V4RuleResult]
    /// Drinks v2 breakdown (caps, serving, flags). Nil for other profiles.
    var drinksBreakdown: DrinksScoreBreakdown? = nil
}

// MARK: Engine

enum ScoringEngineV4 {

    static let floorScore = 10
    /// Engine identity — bumped with health-only v5 rewrite.
    static let engineVersion = "v5"

    struct FVNResolution: Equatable {
        let value: Double?
        /// Nil for measured/absent values; category family for inferred values.
        let inferredFrom: String?
    }

    /// Resolve missing FVN from narrow whole-food category truth. The NOVA
    /// guard prevents processed derivatives from inheriting an ancestral tag.
    static func resolvedFVN(_ p: Product) -> FVNResolution {
        if let measured = p.nutrients.fvn {
            return FVNResolution(value: measured, inferredFrom: nil)
        }
        guard p.novaGroup == 1 || p.novaGroup == 2 else {
            return FVNResolution(value: nil, inferredFrom: nil)
        }
        let tags = Set(p.categories ?? [])
        let fruitTags: Set<String> = [
            "fruits", "fresh-fruits", "berries", "tropical-fruits",
        ]
        let vegetableTags: Set<String> = [
            "vegetables", "fresh-vegetables", "salads",
        ]
        if !tags.isDisjoint(with: fruitTags) {
            return FVNResolution(value: 100, inferredFrom: "fruits")
        }
        if !tags.isDisjoint(with: vegetableTags) {
            return FVNResolution(value: 100, inferredFrom: "vegetables")
        }
        if tags.contains("nuts") {
            return FVNResolution(value: 100, inferredFrom: "nuts")
        }
        if tags.contains("legumes") {
            return FVNResolution(value: 100, inferredFrom: "legumes")
        }
        return FVNResolution(value: nil, inferredFrom: nil)
    }

    /// Engine-level normalization used before any rule or cap evaluates.
    private static func applyingInferredFVN(to product: Product) -> Product {
        guard product.nutrients.fvn == nil,
              let inferred = resolvedFVN(product).value
        else { return product }
        var normalized = product
        normalized.nutrients.fvn = inferred
        return normalized
    }

    /// V5.2 dairy normalization (`dairy_milk` route only).
    /// 1. Powdered milk: the per-100 g panel is rewritten to per-100 ml as
    ///    reconstituted, so concentrated lactose isn't judged as a sugar bomb
    ///    against liquid thresholds. Keyword evidence comes from name/ingredients
    ///    (never category tags — OFF's `milks-liquid-and-powder` ancestor tag
    ///    also rides on liquid milks) plus a kcal trigger no liquid can reach.
    /// 2. Fortification exemption: vitamin D/A and lactase tokens are stripped
    ///    from the ingredient list, and when everything left is whole food the
    ///    product returns to NOVA 1 — fortifying milk is a public-health win,
    ///    not processing, and must not cost S2/S14/S15 points.
    static func dairyNormalized(_ p: Product, rs: RulesetV4,
                                includePowder: Bool = true) -> Product {
        var q = p
        // Powder reconstitution is fluid-milk only: processed cheeses and
        // yogurts legitimately list "milk powder" as an ingredient and are
        // dense per 100 g — they must never be rescaled.
        if includePowder,
           let cfg = rs.dairyPowder,
           let kcal = q.nutrients.kcal, kcal >= cfg.kcalTrigger {
            let hay = (q.name + " " + (q.ingredientsText ?? "")).lowercased()
            if cfg.keywords.contains(where: { hay.contains($0) }) {
                let f = cfg.factor
                func scale(_ v: inout Double?) { v = v.map { $0 * f } }
                scale(&q.nutrients.sugar_g)
                scale(&q.nutrients.sodium_mg)
                scale(&q.nutrients.satFat_g)
                scale(&q.nutrients.fiber_g)
                scale(&q.nutrients.protein_g)
                scale(&q.nutrients.calcium_mg)
                scale(&q.nutrients.kcal)
                scale(&q.nutrients.addedSugar_g)
                scale(&q.nutrients.transFat_g)
                scale(&q.nutrients.iron_mg)
                scale(&q.nutrients.potassium_mg)
                scale(&q.nutrients.magnesium_mg)
                scale(&q.nutrients.zinc_mg)
                scale(&q.nutrients.vitaminC_mg)
            }
        }
        if let cfg = rs.dairyFortification, let text = q.ingredientsText {
            let tokens = IngredientIntegrity.tokens(from: text)
            let kept = tokens.filter { t in !cfg.exempt.contains { t.contains($0) } }
            if kept.count < tokens.count, !kept.isEmpty {
                q.ingredientsText = kept.joined(separator: ", ")
                if q.additives.isEmpty,
                   kept.allSatisfy(IngredientIntegrity.isWholeFoodToken) {
                    q.novaGroup = 1
                }
            }
        }
        return q
    }

    /// Profile-specific normalization applied before any rule evaluates
    /// (dairy: powder reconstitution + fortification exemption; eggs: powder
    /// reconstitution + evidence-based NOVA). One entry point so the score,
    /// the overview payload and the evidence summary always see the same product.
    static func normalizedForRules(_ p: Product, profileId: String, rs: RulesetV4) -> Product {
        if let cfg = rs.dairy, let form = DairyScoring.form(profileId) {
            return DairyScoring.normalized(p, form: form, rs: rs, cfg: cfg)
        }
        switch profileId {
        case "dairy_milk": return dairyNormalized(p, rs: rs)
        case "yogurt_cheese": return dairyNormalized(p, rs: rs, includePowder: false)
        case "eggs": return eggNormalized(p, rs: rs)
        default: return p
        }
    }

    /// nil when the product fails the minimum-data requirement (§3.3) —
    /// callers show the insufficient-data state, never a made-up number.
    static func score(_ p: Product, ruleset rs: RulesetV4 = .bundled) -> V4Result? {
        var p = applyingInferredFVN(to: p)
        guard p.hasMinimumData else { return nil }
        let profileId = route(p, ruleset: rs)
        if profileId == "unsupported" || profileId == "unscored_sweetener" { return nil }
        p = normalizedForRules(p, profileId: profileId, rs: rs)

        // Drinks v2.3 — cap-based path (`drinks` + dose-aware `juice_100`).
        if profileId == "drinks" || profileId == "juice_100" {
            guard let bd = DrinksScoring.score(product: p, ruleset: rs, profileId: profileId)
            else { return nil }
            let totalW = bd.rules.reduce(0.0) { $0 + $1.weight }
            let backed = bd.rules.filter(\.hadData).reduce(0.0) { $0 + $1.weight }
            let conf = totalW > 0 ? adjustedConfidence(base: backed / totalW, product: p, results: bd.rules) : 0.6
            let afterHard = applyBaseCaps(base: bd.finalScore, product: p, rs: rs).capped
            return V4Result(rulesetVersion: rs.version, profileId: profileId,
                            base: afterHard, confidence: conf, rules: bd.rules,
                            drinksBreakdown: bd)
        }

        guard let profile = rs.profiles[profileId] else { return nil }

        let (results, _) = evaluatedRules(profile: profile, profileId: profileId, product: p, rs: rs)
        let usable = activeWeightResults(results)
        let totalW = usable.reduce(0) { $0 + $1.weight }
        guard totalW > 0 else { return nil }
        let earned = usable.reduce(0) { $0 + $1.weight * $1.fraction }
        let backed = usable.filter(\.hadData).reduce(0) { $0 + $1.weight }

        let raw = earned / totalW * 100
        var base = max(floorScore, Int(raw.rounded()))
        base = applyBaseCaps(base: base, product: p, rs: rs).capped
        let conf = adjustedConfidence(base: backed / totalW, product: p, results: usable)
        return V4Result(rulesetVersion: rs.version,
                        profileId: profileId,
                        base: base,
                        confidence: conf,
                        rules: results)
    }

    // MARK: Full scored product (Phase D — SCORING_V4.md §7)

    /// Outcome of the app-facing scoring path.
    enum Outcome {
        case scored(Product)      // Overall + Your Score filled in
        /// Pure sweeteners etc. — data shown, health score withheld.
        case unscored(Product, reasonKey: String)
        case unsupported          // water / alcohol → Sage doesn't rate these
        case insufficientData     // fails the minimum-data requirement
    }

    /// Drop-in replacement for the v3 `ScoringEngine.score`: returns the product
    /// with overallScore, yourScore, deltaReason, bonuses, and restrictions
    /// filled from the v4 rule engine + multiplier personalization + hard gates.
    static func scoreProduct(_ p: Product, for profile: UserProfile,
                             ruleset rs: RulesetV4 = .bundled) -> Outcome {
        let originalProduct = p
        var p = applyingInferredFVN(to: p)
        // Route before the minimum-data gate: water/alcohol often lack a full
        // nutrition table, and would otherwise be mis-labeled "not enough data"
        // instead of the deliberate unsupported explanation.
        let profileId = route(p, ruleset: rs)
        if profileId == "unsupported" { return .unsupported }
        guard p.hasMinimumData else { return .insufficientData }
        p = normalizedForRules(p, profileId: profileId, rs: rs)

        // Diet / avoid flags still run for unscored sweeteners — there is just
        // no number to cap.
        let restrictions: [Restriction] = profile.autoFlagRestrictions
            ? restrictionInputs(profile).compactMap { name in
                evalRestriction(name, product: p, ruleset: rs).map {
                    Restriction(type: $0.type, trigger: $0.trigger)
                }
              }
            : []

        if profileId == "unscored_sweetener" {
            var out = originalProduct
            out.scoreState = .unscored(reasonKey: "sweetener")
            out.overallScore = nil
            out.yourScore = nil
            out.bonuses = []
            out.firedCaps = nil
            out.bindingCap = nil
            out.overallFiredCaps = nil
            out.overallBindingCap = nil
            out.overallBandCap = nil
            out.overview = nil
            out.overviewStale = false
            out.restrictions = restrictions
            return .unscored(out, reasonKey: "sweetener")
        }

        // MARK: Drinks / juice_100 v2.3 path
        if profileId == "drinks" || profileId == "juice_100" {
            return scoreDrinksProduct(original: originalProduct, product: p,
                                      profile: profile, restrictions: restrictions,
                                      rs: rs, profileId: profileId)
        }

        guard let ruleList = rs.profiles[profileId] else { return .insufficientData }

        // Evaluate every rule once; reuse for Overall and Your Score.
        let (results, _) = evaluatedRules(profile: ruleList, profileId: profileId, product: p, rs: rs)
        let usable = activeWeightResults(results)
        let totalW = usable.reduce(0) { $0 + $1.weight }
        guard totalW > 0 else { return .insufficientData }
        var overall = max(floorScore,
                          Int((usable.reduce(0) { $0 + $1.weight * $1.fraction } / totalW * 100).rounded()))
        // Health hard gates on Overall (trans fat, free-sugar ceiling, NNS).
        let baseGate = applyBaseCaps(base: overall, product: p, rs: rs)
        overall = baseGate.capped

        // Keep raw OFF nutrients in the returned/stored product. Inference is
        // engine-local so debug can always distinguish it from measured FVN.
        var out = originalProduct
        out.scoreState = .scored
        out.overallScore = overall
        out.bonuses = nutrientBonuses(p.nutrients)
        out.overallFiredCaps = baseGate.fired.isEmpty ? nil : baseGate.fired
        out.overallBindingCap = baseGate.binding
        out.overallBandCap = nil
        out.restrictions = restrictions
        out.lowDataConfidence = nil
        out.estimatedServing = nil
        out.drinksBindingCapId = nil

        guard profile.personalizeScoring else {
            out.yourScore = overall
            out.overview = nil
            out.overviewStale = true
            out.firedCaps = nil
            out.bindingCap = nil
            return .scored(out)
        }

        let mult = ruleMultipliers(profile, rs: rs)
        var yEarned = 0.0, yTotal = 0.0
        for r in usable {
            let m = mult[r.rule] ?? 1.0
            yEarned += r.weight * m * r.fraction
            yTotal += r.weight * m
        }
        var your = yTotal > 0 ? max(floorScore, Int((yEarned / yTotal * 100).rounded())) : overall
        your = max(floorScore, min(100, your + nutrientNudge(profile.objective, p.nutrients)))

        let avoidHits = avoidListHits(p, profile: profile, rs: rs)
        let (prefFired, _, _) = applyCaps(weighted: your,
                                          restrictions: out.restrictions,
                                          avoidHits: avoidHits,
                                          nutrients: p.nutrients,
                                          rs: rs)
        let stacked = baseGate.fired + prefFired
        if let effective = stacked.map(\.value).min() {
            your = min(your, effective)
        }

        let binding: ScoreCap? = {
            guard let effective = stacked.map(\.value).min() else { return nil }
            var uncapped = yTotal > 0
                ? max(floorScore, Int((yEarned / yTotal * 100).rounded()))
                : overall
            uncapped = max(floorScore, min(100, uncapped + nutrientNudge(profile.objective, p.nutrients)))
            guard uncapped > effective else { return nil }
            let preferenceFirst = stacked.filter { $0.value == effective }
                .sorted { a, b in
                    let rank: (ScoreCap) -> Int = {
                        switch $0.kind {
                        case "dietConflict": return 0
                        case "avoidList": return 1
                        case "transFat", "freeSugar", "nns",
                             "dairyFreeSugar", "dairyNns", "dairySodium", "rawMilk": return 2
                        default: return 3
                        }
                    }
                    return rank(a) != rank(b) ? rank(a) < rank(b) : a.id < b.id
                }
            return preferenceFirst.first
        }()

        out.firedCaps = prefFired.isEmpty ? nil : prefFired
        out.bindingCap = {
            guard let b = binding, b.kind == "dietConflict" || b.kind == "avoidList"
            else { return nil }
            return b
        }()
        out.yourScore = your
        out.overview = nil
        out.overviewStale = true
        return .scored(out)
    }

    /// Drinks / juice_100 product scoring — caps not user-adjustable; preference caps only lower.
    private static func scoreDrinksProduct(original: Product, product p: Product,
                                           profile: UserProfile,
                                           restrictions: [Restriction],
                                           rs: RulesetV4,
                                           profileId: String) -> Outcome {
        guard let bdOverall = DrinksScoring.score(product: p, ruleset: rs, profileId: profileId)
        else {
            return .insufficientData
        }
        #if DEBUG
        DrinksScanDebug.logScore(product: p, profileId: profileId, bd: bdOverall)
        #endif
        let hard = applyBaseCaps(base: bdOverall.finalScore, product: p, rs: rs)
        let overall = hard.capped

        var drinksCaps: [ScoreCap] = []
        func appendCap(id: String, value: Int, label: String) {
            guard value < 100, value < bdOverall.weightedScore else { return }
            drinksCaps.append(ScoreCap(
                id: id, value: value, shortLabel: label, kind: "freeSugar",
                intensity: value <= 30 ? "full" : "soft",
                detail: "Score limited by \(label) (cap \(value))."
            ))
        }
        appendCap(id: "sugarCap", value: bdOverall.sugarCap, label: "sugar content")
        appendCap(id: "caffeineCap", value: bdOverall.caffeineCap, label: "caffeine")
        appendCap(id: "sweetenerCap", value: bdOverall.sweetenerCap, label: "artificial sweeteners")

        var overallFired = hard.fired + drinksCaps
        let overallBinding: ScoreCap? = {
            if let id = bdOverall.bindingCapId,
               let c = drinksCaps.first(where: { $0.id == id }),
               bdOverall.weightedScore > bdOverall.finalScore {
                return c
            }
            return hard.binding
        }()

        var out = original
        out.scoreState = .scored
        out.overallScore = overall
        out.bonuses = nutrientBonuses(p.nutrients)
        out.overallFiredCaps = overallFired.isEmpty ? nil : overallFired
        out.overallBindingCap = overallBinding
        out.overallBandCap = nil
        out.restrictions = restrictions
        out.lowDataConfidence = bdOverall.lowDataConfidence
        out.estimatedServing = bdOverall.estimatedServing
        out.drinksBindingCapId = bdOverall.bindingCapId

        guard profile.personalizeScoring else {
            out.yourScore = overall
            out.overview = nil
            out.overviewStale = true
            out.firedCaps = nil
            out.bindingCap = nil
            return .scored(out)
        }

        let mult = ruleMultipliers(profile, rs: rs)
        guard let bdYour = DrinksScoring.score(product: p, ruleset: rs, profileId: profileId,
                                               ruleMultipliers: mult)
        else { return .insufficientData }
        var your = applyBaseCaps(base: bdYour.finalScore, product: p, rs: rs).capped
        // Nutrient nudge after caps would raise — apply before preference, then
        // re-apply drinks caps (caps are not user-adjustable / cannot be raised past).
        your = max(floorScore, min(100, your + nutrientNudge(profile.objective, p.nutrients)))
        your = min(your, bdYour.sugarCap, bdYour.caffeineCap, bdYour.sweetenerCap)

        let avoidHits = avoidListHits(p, profile: profile, rs: rs)
        let (prefFired, _, _) = applyCaps(weighted: your,
                                          restrictions: restrictions,
                                          avoidHits: avoidHits,
                                          nutrients: p.nutrients,
                                          rs: rs)
        // Preference / diet can only lower.
        if let effective = (hard.fired + prefFired).map(\.value).min() {
            your = min(your, effective)
        }

        out.firedCaps = prefFired.isEmpty ? nil : prefFired
        out.bindingCap = prefFired.sorted { $0.value < $1.value }.first.flatMap { c in
            (c.kind == "dietConflict" || c.kind == "avoidList") ? c : nil
        }
        out.yourScore = your
        out.overview = nil
        out.overviewStale = true
        return .scored(out)
    }

    /// Signed drivers for the backend /explain prompt (§7.5). Restriction /
    /// avoid conflicts lead; then the rules the user's profile most emphasized.
    static func signedFactors(_ p: Product, profile: UserProfile,
                              ruleset rs: RulesetV4 = .bundled) -> [String] {
        var p = applyingInferredFVN(to: p)
        var factors: [String] = []
        if let r = p.restrictions.first {
            factors.append("- conflicts with your \(r.type) restriction (\(r.trigger))")
        }
        if let a = avoidListHit(p, profile: profile, rs: rs) {
            factors.append("- contains \(a), which you chose to avoid")
        }
        let profileId = route(p, ruleset: rs)
        guard let ruleList = rs.profiles[profileId] else { return factors }
        p = normalizedForRules(p, profileId: profileId, rs: rs)
        let mult = ruleMultipliers(profile, rs: rs)
        let scored = ruleList.map { pr -> (rule: String, f: Double, m: Double) in
            let (f, _, _) = evaluate(pr.rule, variant: pr.variant, product: p, rs: rs,
                                     profileId: profileId)
            return (pr.rule, f, mult[pr.rule] ?? 1.0)
        }
        // Emphasized rules first (biggest |m−1|·weight), then plain strong drivers.
        let ranked = scored.sorted {
            abs($0.m - 1) != abs($1.m - 1) ? abs($0.m - 1) > abs($1.m - 1) : $0.f < $1.f
        }
        for r in ranked.prefix(4) {
            guard let (label, positive) = ruleFactor(r.rule, fraction: r.f, product: p) else { continue }
            factors.append((positive ? "+ " : "- ") + label)
        }
        return Array(factors.prefix(5))
    }

    // MARK: Personalization helpers

    /// One factor that contributed to a rule's final multiplier (before clamp).
    struct MultiplierFactor: Equatable {
        let source: String       // "objective" | "goal" | "slider" | "preference"
        let selection: String    // e.g. "eat healthier", "high protein"
        let factor: Double
    }

    /// Per-rule multiplier with provenance; `product` is clamped to [0.5, 2.0].
    struct RuleMultiplierDetail: Equatable {
        let factors: [MultiplierFactor]
        var product: Double {
            let raw = factors.reduce(1.0) { $0 * $1.factor }
            return min(2.0, max(0.5, raw))
        }
    }

    /// Organic preference is display-only — no health-scoring pathway.
    static let organicPreferenceKey = "organic"

    /// True when the user opted into Organic and OFF labels confirm a certification.
    static func showsOrganicChip(product: Product, profile: UserProfile) -> Bool {
        let prefs = Set(profile.preferences.map { $0.lowercased() })
        guard prefs.contains(organicPreferenceKey) else { return false }
        let labels = Set((product.labels ?? []).map { $0.lowercased() })
        let organicTags: Set<String> = [
            "organic", "eu-organic", "usda-organic", "organic-certification",
        ]
        return !labels.isDisjoint(with: organicTags)
    }

    /// Per-rule multiplier breakdown from objective + goals + sliders + preferences.
    static func ruleMultiplierBreakdown(_ profile: UserProfile, rs: RulesetV4)
    -> [String: RuleMultiplierDetail] {
        guard let m = rs.multipliers else { return [:] }
        var factorsByRule: [String: [MultiplierFactor]] = [:]
        func apply(_ table: [String: Double]?, source: String, selection: String) {
            for (rule, factor) in table ?? [:] {
                factorsByRule[rule, default: []].append(
                    MultiplierFactor(source: source, selection: selection, factor: factor)
                )
            }
        }
        let objective = profile.objective.lowercased()
        apply(m.objective[objective], source: "objective", selection: objective)
        for g in profile.healthGoals ?? [] {
            let key = g.lowercased()
            apply(m.goal[key], source: "goal", selection: key)
        }
        let sliders: [(String, Int?)] = [
            ("clean", profile.sliderCleanIngredients),
            ("nutrition", profile.sliderNutrition),
        ]
        for (key, level) in sliders where level != nil && level != 1 {
            apply(m.slider[key]?[String(level!)], source: "slider", selection: "\(key):\(level!)")
        }
        let prefTable = m.preference ?? [:]
        for pref in profile.preferences {
            let key = pref.lowercased()
            // Organic is intentionally absent from the preference map.
            apply(prefTable[key], source: "preference", selection: key)
        }
        return factorsByRule.mapValues { RuleMultiplierDetail(factors: $0) }
    }

    /// Per-rule multiplier from objective + health goals + priority sliders + preferences.
    private static func ruleMultipliers(_ profile: UserProfile, rs: RulesetV4) -> [String: Double] {
        ruleMultiplierBreakdown(profile, rs: rs).mapValues(\.product)
    }

    /// Human phrase for a preference-sourced delta driver ("your high-protein preference").
    private static func preferenceDriverPhrase(_ selection: String) -> String {
        let hyphenated = selection.replacingOccurrences(of: " ", with: "-")
        return "your \(hyphenated) preference"
    }

    /// Bounded Your-Score nudge for goals that reward a specific nutrient the
    /// blended rules dilute. Muscle: protein per 100 kcal. Weight loss: calorie
    /// lightness, gated so sugary drinks earn no lightness credit.
    private static func nutrientNudge(_ objective: String, _ n: Nutrients) -> Int {
        switch objective.lowercased() {
        case "build muscle":
            guard let kcal = n.kcal, kcal > 5, let prot = n.protein_g else { return 0 }
            let dens = min(1.0, (prot / (kcal / 100)) / 15)
            return Int(((dens - 0.35) * 16).rounded())      // ≈ −6 … +10
        case "lose weight":
            guard let kcal = n.kcal else { return 0 }
            let light = max(0, min(1, (500 - kcal) / 450))
            let sugarGate = 1 - min(1, (n.sugar_g ?? 0) / 25)
            return Int(((light * sugarGate - 0.3) * 12).rounded())   // ≈ −4 … +8
        default: return 0
        }
    }

    /// The product contains an item the user chose to avoid → item name, else nil.
    static func avoidListHit(_ p: Product, profile: UserProfile, rs: RulesetV4) -> String? {
        avoidListHits(p, profile: profile, rs: rs).first
    }

    /// All avoid-list items that match this product (display order preserved).
    static func avoidListHits(_ p: Product, profile: UserProfile, rs: RulesetV4) -> [String] {
        guard let chosen = profile.avoidList, !chosen.isEmpty else { return [] }
        let avoid = rs.avoidList
        var hits: [String] = []
        for item in chosen {
            let entry = avoid?[item.lowercased()]
            if AvoidListMatcher.matches(item: item, entry: entry, product: p) {
                hits.append(item)
            }
        }
        return hits
    }

    /// Existing scoring restrictions plus the new single diet pattern (§7.1).
    private static func restrictionInputs(_ profile: UserProfile) -> [String] {
        var out = profile.restrictions
        if let d = profile.dietPattern, d.lowercased() != "none" { out.append(d) }
        return out
    }

    /// Deterministic restriction conflict check. Metric diets use taper thresholds
    /// from the ruleset when present; otherwise legacy fixed cutoffs.
    private static func evalRestriction(_ name: String, product p: Product,
                                        ruleset rs: RulesetV4 = .bundled)
    -> (type: String, trigger: String)? {
        let flags = Set(p.dietFlags ?? [])
        let n = p.nutrients
        let key = name.lowercased()
        switch key {
        case "vegan":       return flags.contains("non-vegan") ? ("vegan", "animal-derived ingredients") : nil
        case "vegetarian":  return flags.contains("non-vegetarian") ? ("vegetarian", "meat or fish") : nil
        case "low-sugar diet", "low sugar":
            let type = "low-sugar diet"
            if let taper = dietTaper(for: type, rs: rs), let s = n.sugar_g {
                // Fires only once sugar exceeds taperStart (inclusive start = no fire).
                return s > taper.taperStart ? (type, "high sugar") : nil
            }
            if let s = n.sugar_g, s > 12.5 { return (type, "high sugar") }
            return nil
        case "low-sodium diet", "low-sodium", "low sodium":
            let type = "low-sodium diet"
            if let taper = dietTaper(for: type, rs: rs), let s = n.sodium_mg {
                return s > taper.taperStart ? (type, "high sodium") : nil
            }
            if let s = n.sodium_mg, s > 400 { return (type, "high sodium") }
            return nil
        case "gluten-free": return flags.contains("gluten") ? ("gluten-free", "gluten") : nil
        case "dairy-free":  return flags.contains("milk") ? ("dairy-free", "milk") : nil
        default:            return nil
        }
    }

    private static func dietTaper(for type: String, rs: RulesetV4)
    -> RulesetV4.HardGates.DietConflictTaper? {
        rs.hardGates?.dietConflictTapers?[type.lowercased()]
    }

    /// Linear taper: ≤ start → 100; ≥ end → minCap; between → interpolate.
    static func taperedDietCap(amount: Double,
                               taper: RulesetV4.HardGates.DietConflictTaper) -> Int {
        if amount <= taper.taperStart { return 100 }
        if amount >= taper.taperEnd { return taper.minCap }
        let span = taper.taperEnd - taper.taperStart
        guard span > 0 else { return taper.minCap }
        let t = (amount - taper.taperStart) / span
        return Int((100.0 - (100.0 - Double(taper.minCap)) * t).rounded())
    }

    /// Cap for a single diet restriction (taper or flat legacy).
    static func dietCapValue(for restriction: Restriction, nutrients: Nutrients,
                             rs: RulesetV4) -> (value: Int, intensity: String)? {
        let type = restriction.type.lowercased()
        if let taper = dietTaper(for: type, rs: rs) {
            let amount: Double?
            switch taper.metric {
            case "sugar_g": amount = nutrients.sugar_g
            case "sodium_mg": amount = nutrients.sodium_mg
            default: amount = nil
            }
            guard let amount else { return nil }
            let value = taperedDietCap(amount: amount, taper: taper)
            guard value < 100 else { return nil }
            let intensity = amount >= taper.taperEnd ? "full" : "partial"
            return (value, intensity)
        }
        let flat = rs.hardGates?.dietConflictCap ?? 20
        return (flat, "full")
    }

    /// Collect fired caps and apply stacked min. Binding = tightest that limits weighted.
    static func applyCaps(weighted: Int, restrictions: [Restriction],
                          avoidHits: [String], nutrients: Nutrients,
                          rs: RulesetV4)
    -> (fired: [ScoreCap], binding: ScoreCap?, capped: Int) {
        var fired: [ScoreCap] = []

        for r in restrictions {
            guard let (value, intensity) = dietCapValue(for: r, nutrients: nutrients, rs: rs)
            else { continue }
            let sugarNote: String? = {
                if r.type.lowercased().contains("sugar"), let s = nutrients.sugar_g {
                    return String(format: "%.0f g of sugar", s)
                }
                if r.type.lowercased().contains("sodium"), let s = nutrients.sodium_mg {
                    return String(format: "%.0f mg of sodium", s)
                }
                return r.trigger
            }()
            fired.append(ScoreCap(
                id: "dietConflictCap",
                value: value,
                shortLabel: r.type.lowercased(),
                kind: "dietConflict",
                intensity: intensity,
                detail: {
                    let base = "Conflicts with your \(r.type.lowercased())."
                    if intensity == "full" {
                        return "\(base) Caps your score at \(value)."
                    }
                    if let note = sugarNote {
                        return "\(base) Limits your score (\(note))."
                    }
                    return "\(base) Limits your score."
                }()
            ))
        }

        let avoidCap = rs.hardGates?.avoidListCap ?? 49
        for hit in avoidHits {
            let isSeed = hit.lowercased().contains("seed")
            fired.append(ScoreCap(
                id: isSeed ? "seedOilCap" : "avoidListCap",
                value: avoidCap,
                shortLabel: hit.lowercased(),
                kind: "avoidList",
                intensity: "full",
                detail: "On your avoid list. Caps your score at \(avoidCap)."
            ))
        }

        guard !fired.isEmpty else { return ([], nil, weighted) }

        // effectiveCap = min(all firing caps)
        let effective = fired.map(\.value).min()!
        let capped = min(weighted, effective)
        // Binding = the minimum-value cap among those that actually limit the score.
        let binding: ScoreCap? = {
            guard weighted > effective else { return nil }
            return fired.filter { $0.value == effective }
                .sorted { $0.id < $1.id }
                .first
        }()
        return (fired, binding, capped)
    }

    /// Public helper for UI copy: avoid-list ceiling from the live ruleset.
    static func avoidListCapValue(rs: RulesetV4 = .bundled) -> Int {
        rs.hardGates?.avoidListCap ?? 49
    }

    /// Health-only base caps that limit Overall (and Your when stacked).
    /// - transFat: industrial TFA only (NOVA-4 numeric path, or partially-hydrogenated text)
    /// - freeSugarCeiling: caloric sweeteners / high sugar with low FVN (fruit sugar exempt)
    static func applyBaseCaps(base: Int, product p: Product, rs: RulesetV4)
    -> (fired: [ScoreCap], binding: ScoreCap?, capped: Int) {
        let p = applyingInferredFVN(to: p)
        var fired: [ScoreCap] = []

        if let gate = rs.hardGates?.transFat, firesIndustrialTransFat(p, rs: rs, gate: gate) {
            fired.append(ScoreCap(
                id: "transFatCap",
                value: gate.cap,
                shortLabel: "trans fat",
                kind: "transFat",
                intensity: "full",
                detail: "Contains industrial trans fat. Caps the overall score at \(gate.cap)."
            ))
        }

        if let gate = rs.hardGates?.freeSugarCeiling,
           isCaloricSweetener(p),
           !isNonNutritiveTableSweetener(p) {
            fired.append(ScoreCap(
                id: "freeSugarCeiling",
                value: gate.cap,
                shortLabel: "free sugar",
                kind: "freeSugar",
                intensity: "full",
                detail: "Caloric sweetener. Caps the overall score at \(gate.cap)."
            ))
        }

        if let gate = rs.hardGates?.rawMilk {
            let tags = Set((p.categories ?? []) + (p.labels ?? []))
            let name = p.name.lowercased()
            let evidenced = !tags.isDisjoint(with: gate.tags)
                || (gate.names ?? []).contains { matchesWord($0, in: name) }
            let routed = route(p, ruleset: rs)
            let rawScope = routed == "dairy_milk" || routed == "dairy_fermented"
            if evidenced, rawScope {
                fired.append(ScoreCap(
                    id: "rawMilkCap",
                    value: gate.cap,
                    shortLabel: "unpasteurized",
                    kind: "rawMilk",
                    intensity: "full",
                    detail: "Unpasteurized milk can carry harmful bacteria such as Listeria, E. coli, and Salmonella. Public-health agencies advise young children, pregnant people, older adults, and immunocompromised people to avoid it. Caps the overall score at \(gate.cap)."
                ))
            }
        }

        // V5.6 dairy caps — sweet yogurt / dessert dairy is never Excellent,
        // tier-1 sweeteners on fermented dairy and cream take the NNS ceiling,
        // and very salty cheese tops out in the OK band.
        if let cfg = rs.dairy, let form = DairyScoring.form(route(p, ruleset: rs)) {
            let q = DairyScoring.normalized(p, form: form, rs: rs, cfg: cfg)
            for hit in DairyScoring.caps(q, form: form, cfg: cfg) {
                fired.append(ScoreCap(id: hit.id, value: hit.value, shortLabel: hit.shortLabel,
                                      kind: hit.kind, intensity: "full", detail: hit.detail))
            }
        }

        if let gate = rs.hardGates?.nnsCeiling,
           route(p, ruleset: rs) == "unscored_sweetener",
           (p.nutrients.sugar_g ?? 0) < 10,
           isNonNutritiveTableSweetener(p) {
            // Dead path after V5.0.7: table NNS products are unscored, so this
            // ceiling never binds a dial. Kept for completeness if route changes.
            fired.append(ScoreCap(
                id: "nnsCeiling",
                value: gate.cap,
                shortLabel: "non-nutritive sweetener",
                kind: "nns",
                intensity: "full",
                detail: "Non-nutritive table sweetener. Caps the overall score at \(gate.cap)."
            ))
        }

        guard !fired.isEmpty else { return ([], nil, base) }
        let effective = fired.map(\.value).min()!
        let capped = min(base, effective)
        let binding: ScoreCap? = {
            guard base > effective else { return nil }
            return fired.filter { $0.value == effective }.sorted { $0.id < $1.id }.first
        }()
        return (fired, binding, capped)
    }

    /// Industrial TFA: text signal always; numeric needs NOVA 4 + threshold
    /// (ruminant profiles dairy_milk / yogurt_cheese / meat use > 2.0 g).
    private static func firesIndustrialTransFat(
        _ p: Product, rs: RulesetV4, gate: RulesetV4.HardGates.TransFatGate
    ) -> Bool {
        let text = (p.ingredientsText ?? "").lowercased()
        if text.range(of: #"partially hydrogenated|parcialmente hidrogenad"#,
                      options: .regularExpression) != nil {
            return true
        }
        guard let tf = p.nutrients.transFat_g, p.novaGroup == 4 else { return false }
        let profileId = route(p, ruleset: rs)
        let ruminant = ["dairy_milk", "yogurt_cheese", "meat"].contains(profileId)
            || DairyScoring.isDairy(profileId)
        let threshold = ruminant ? 2.0 : gate.threshold
        return tf > threshold
    }

    /// Sugars / honeys / syrups category OR (sugar ≥ 50 g with FVN < 80).
    /// High-FVN dried fruit is exempt from the sugar≥50 numeric path.
    private static func isCaloricSweetener(_ p: Product) -> Bool {
        let tags = (p.categories ?? []).map { $0.lowercased() }
        let needles = ["sugars", "honeys", "syrups", "molasses", "sweeteners"]
        // V5.6: OFF also emits nutrition-level tags ("low-sugars",
        // "no-added-sugars", "reduced-sugars") on every kind of product; a
        // substring hit on those capped a 0 g-sugar grated parmesan at 34.
        // Only real sweetener categories count, and never when the panel
        // itself says the product is not sugar-rich.
        let negations = ["low-", "no-", "reduced-", "without-", "less-", "free-", "zero-"]
        let isSweetenerCategory = tags.contains { tag in
            guard needles.contains(where: { tag == $0 || tag.hasSuffix("-" + $0) || tag.hasPrefix($0 + "-") })
            else { return false }
            return !negations.contains { tag.hasPrefix($0) } && !tag.contains("-free")
        }
        if isSweetenerCategory {
            if let s = p.nutrients.sugar_g, s < 25 { return false }
            return true
        }
        if let s = p.nutrients.sugar_g, s >= 50, (p.nutrients.fvn ?? 0) < 80 {
            return true
        }
        return false
    }

    /// Stevia / monk fruit / erythritol table products with sugar_g < 10.
    private static func isNonNutritiveTableSweetener(_ p: Product) -> Bool {
        let sugar = p.nutrients.sugar_g ?? 0
        guard sugar < 10 else { return false }
        let hay = ([p.name] + (p.categories ?? []) + (p.labels ?? [])
                   + [p.ingredientsText ?? ""]).joined(separator: " ").lowercased()
        let markers = ["stevia", "monk fruit", "monkfruit", "erythritol",
                       "e960", "e968", "e955", "sucralose", "aspartame", "e951"]
        return markers.contains { hay.contains($0) }
    }

    private static func nutrientBonuses(_ n: Nutrients) -> [String] {
        var b: [String] = []
        if let f = n.fiber_g, f >= 6 { b.append("fiber") }
        if let p = n.protein_g, p >= 12 { b.append("protein") }
        if let c = n.calcium_mg, c >= 120 { b.append("calcium") }
        if let i = n.iron_mg, i >= 4.5 { b.append("iron") }               // ≥25% DV
        if let k = n.potassium_mg, k >= 700 { b.append("potassium") }     // ≥15% DV
        return b
    }

    private static func deltaReasonV4(overall: Int, your: Int, restriction: Restriction?,
                                      avoid: String?, results: [V4RuleResult],
                                      mult: [String: Double]) -> DeltaReason? {
        if let r = restriction {
            return DeltaReason(tone: .negative,
                text: "Capped — contains \(r.trigger), which conflicts with your \(r.type) restriction.")
        }
        if let a = avoid {
            return DeltaReason(tone: .negative,
                text: "Capped — contains \(a), which you chose to avoid.")
        }
        let delta = your - overall
        guard abs(delta) >= 3 else { return nil }
        // Name the most emphasized rule as the driver.
        let driver = results.max {
            abs((mult[$0.rule] ?? 1) - 1) * $0.weight < abs((mult[$1.rule] ?? 1) - 1) * $1.weight
        }
        let label = driver.flatMap { ruleFactor($0.rule, fraction: $0.fraction, product: nil)?.0 } ?? "your goals"
        let positive = delta > 0
        return DeltaReason(tone: positive ? .positive : .negative,
            text: positive ? "Scores higher for you — \(label)." : "Scores lower for you — \(label).")
    }

    /// Human phrase + polarity for a rule at a given fraction, for factors and
    /// the deltaReason placeholder. Nutrient claims defer to the badge levels
    /// (NutrientLevels) so wording never contradicts the Breakdown card.
    private static func ruleFactor(_ rule: String, fraction f: Double,
                                   product p: Product?) -> (String, Bool)? {
        switch rule {
        case "S12": return f >= 0.4 ? ("good nutritional quality", true)
                                    : ("limited nutritional quality", false)
        case "S2":  return f >= 0.7 ? ("minimally processed", true) : ("highly processed", false)
        case "S1":  return f >= 0.85 ? ("clean ingredient list", true) : ("riskier additives", false)
        case "S3":
            if let n = p?.nutrients.sugar_g.map(NutrientLevels.sugar) {
                switch n { case .high: return ("high sugar", false)
                           case .moderate: return ("moderate sugar", false)
                           case .low: return ("low sugar", true) }
            }
            return f >= 0.6 ? ("low sugar", true) : ("high sugar", false)
        case "S4":
            if let n = p?.nutrients.sodium_mg.map(NutrientLevels.sodium), n == .high {
                return ("high sodium", false)
            }
            return f >= 0.6 ? nil : ("high sodium", false)
        case "S5":
            if let n = p?.nutrients.satFat_g.map(NutrientLevels.satFat), n == .high {
                return ("high saturated fat", false)
            }
            return f >= 0.6 ? nil : ("high saturated fat", false)
        case "S6":
            return f >= 0.85 ? ("no artificial sweeteners", true) : ("artificial sweeteners", false)
        case "S7":
            return f >= 0.7 ? ("lower-leach packaging", true) : ("higher-leach packaging", false)
        case "S8":
            return f >= 0.75 ? ("low caffeine", true) : ("high caffeine", false)
        case "S13": return f >= 0.5 ? ("rich in vitamins & minerals", true) : nil
        case "wholeGrain":
            if f >= 0.6 { return ("whole grain", true) }
            if f <= 0.25 { return ("refined grains", false) }
            return nil
        default:    return nil
        }
    }

    /// Most-specific-first router over normalized category tags. OFF category
    /// arrays include ancestors, so exact tag membership is enough.
    /// Defense in depth (V5.0.4): `whole_foods` only accepts NOVA ∈ {0,1,2} so
    /// processed derivatives that inherit ancestral tags (e.g. peanut butter →
    /// `nuts`) fall through to snacks/general instead of skipping S5.
    ///
    /// Fix 5: waters-family + flavor evidence → `drinks` instead of unsupported.
    /// Fix 4: nutritional plausibility envelopes may rerail a matched profile.
    ///
    /// Precedence (v2.4): evidence gates (energy, flavored water) >
    /// category tag matches > catch-all `beverages`. Alcohol exclusions
    /// still win over evidence.
    static func route(_ p: Product, ruleset rs: RulesetV4 = .bundled) -> String {
        let tags = Set(p.categories ?? [])
        let nova = p.novaGroup

        if firstAlcoholMatch(in: tags, rs: rs) != nil {
            return "unsupported"
        }

        // Evidence gate — energy drink (tags OR nutrition/ingredient evidence).
        if DrinksScoring.hasEnergyDrinkEvidence(p, rs: rs) {
            let attempted = firstTagProfile(p, rs: rs)
            if attempted != "drinks" {
                logEvidenceRerail(p, attempted: attempted, used: "drinks",
                                  gate: "energyDrinkEvidence")
            }
            return "drinks"
        }

        // Evidence gate — plain water (outranks tags in every language).
        if isPlainWaterByEvidence(p, rs: rs) {
            let attempted = firstTagProfile(p, rs: rs)
            if attempted != "unsupported" {
                logEvidenceRerail(p, attempted: attempted, used: "unsupported",
                                  gate: "plainWaterEvidence")
            }
            return "unsupported"
        }

        for entry in rs.router where tags.contains(entry.match) {
            if entry.profile == "whole_foods", !(nova == 0 || nova == 1 || nova == 2) {
                continue
            }
            // V5.3: the `eggs` tag is inherited by scotch eggs, egg pasta and
            // egg dishes — only egg-dominant products take the eggs profile.
            if entry.profile == "eggs", !passesEggGuard(p, rs: rs) {
                continue
            }
            // V5.5: OFF's `protein-bars` tag is inherited by protein powders
            // and shakes — only bar-shaped compositions take the profile.
            if entry.profile == "protein_bars", !ProteinBarScoring.passesGuard(p, rs: rs) {
                continue
            }
            // V5.6: infant-formula tags ride on shakes and growth milks; only
            // a product that reads as formula is unsupported.
            if entry.profile == "unsupported", infantFormulaRouterMatches.contains(entry.match),
               !DairyScoring.looksLikeInfantFormula(p) {
                continue
            }
            var profile = entry.profile
            // V5.6 dairy evidence gates — plant-based "milk" / "yogurt" /
            // "cheese" riding dairy tags leave the dairy family (milk-tagged →
            // plant_milk, the rest → general); sweetened protein shakes tagged
            // `milks` score as drinks.
            if let cfg = rs.dairy, let form = DairyScoring.form(profile) {
                if DairyScoring.isPlantBased(p, cfg: cfg) {
                    let used = form == .milk ? "plant_milk" : "general"
                    logEvidenceRerail(p, attempted: profile, used: used, gate: "dairyPlantEvidence")
                    return applyRoutingPlausibility(p, attempted: used, rs: rs)
                }
                if form == .milk, DairyScoring.isProteinShake(p, cfg: cfg) {
                    logEvidenceRerail(p, attempted: profile, used: "drinks", gate: "dairyProteinShakeEvidence")
                    return "drinks"
                }
            }
            // V5.5 evidence gate — a bar marketed on / built around protein
            // scores as a protein bar even when OFF only tagged it `snacks` /
            // `cereal-bars` (most US protein bars carry no `protein-bars` tag).
            if ProteinBarScoring.fallbackProfiles(rs).contains(profile),
               ProteinBarScoring.hasProteinBarEvidence(p, rs: rs) {
                logEvidenceRerail(p, attempted: profile, used: "protein_bars",
                                  gate: "proteinBarEvidence")
                return "protein_bars"
            }
            // Fix 5 — plain water tags with flavor evidence score as drinks.
            if profile == "unsupported",
               isWatersFamilyRouterMatch(entry.match, rs: rs),
               hasFlavoredWaterEvidence(p, rs: rs) {
                logEvidenceRerail(p, attempted: "unsupported", used: "drinks",
                                  gate: "flavoredWaterEvidence")
                profile = "drinks"
            }
            // Upgrade eligible 100% juices to the dose-aware juice_100 profile.
            if profile == "drinks", DrinksScoring.qualifiesAsJuice100(p) {
                return applyRoutingPlausibility(p, attempted: "juice_100", rs: rs)
            }
            return applyRoutingPlausibility(p, attempted: profile, rs: rs)
        }
        // V5.3 evidence gate — untagged egg products (OFF US imports often carry
        // no categories at all): an egg word in the product NAME plus an egg
        // word as the first ingredient, inside the plain-egg envelope, is an
        // egg whatever the tags say. Name + list together, never either alone
        // ("egg noodles" fails the list; "eggs, mayonnaise…" salads fail the
        // protein floor).
        if hasEggEvidence(p, rs: rs) {
            logEvidenceRerail(p, attempted: "general", used: "eggs", gate: "eggEvidence")
            return "eggs"
        }
        // V5.5 — untagged protein bars (OFF US imports with no categories).
        if ProteinBarScoring.fallbackProfiles(rs).contains("general"),
           ProteinBarScoring.hasProteinBarEvidence(p, rs: rs) {
            logEvidenceRerail(p, attempted: "general", used: "protein_bars", gate: "proteinBarEvidence")
            return "protein_bars"
        }
        return applyRoutingPlausibility(p, attempted: "general", rs: rs)
    }

    static let infantFormulaRouterMatches: Set<String> = [
        "infant-formulas", "baby-milks", "follow-on-milks", "baby-formula", "infant-milks",
        "growing-up-milks",
    ]

    private static let alcoholRouterMatches: Set<String> = [
        "alcoholic-beverages", "beers", "wines", "spirits", "ciders",
    ]

    private static func firstAlcoholMatch(in tags: Set<String>, rs: RulesetV4) -> String? {
        for entry in rs.router where tags.contains(entry.match) {
            if alcoholRouterMatches.contains(entry.match) { return entry.match }
        }
        return nil
    }

    /// Tag-only profile (no evidence gates, no plausibility envelopes).
    static func firstTagProfile(_ p: Product, rs: RulesetV4 = .bundled) -> String {
        let tags = Set(p.categories ?? [])
        let nova = p.novaGroup
        for entry in rs.router where tags.contains(entry.match) {
            if entry.profile == "whole_foods", !(nova == 0 || nova == 1 || nova == 2) {
                continue
            }
            // V5.3: the `eggs` tag is inherited by scotch eggs, egg pasta and
            // egg dishes — only egg-dominant products take the eggs profile.
            if entry.profile == "eggs", !passesEggGuard(p, rs: rs) {
                continue
            }
            if entry.profile == "protein_bars", !ProteinBarScoring.passesGuard(p, rs: rs) {
                continue
            }
            if entry.profile == "drinks", DrinksScoring.qualifiesAsJuice100(p) {
                return "juice_100"
            }
            return entry.profile
        }
        return "general"
    }

    private static func logEvidenceRerail(
        _ p: Product, attempted: String, used: String, gate: String
    ) {
        #if DEBUG
        DrinksScanDebug.logRerail(
            productId: p.id,
            productName: p.name,
            attempted: attempted,
            used: used,
            thresholdsFired: [gate]
        )
        #endif
    }

    /// Waters-family router match ids (from ruleset list, with safe defaults).
    private static func isWatersFamilyRouterMatch(_ match: String, rs: RulesetV4) -> Bool {
        let family = Set(rs.flavoredWaterEvidence?.watersFamilyTags
            ?? ["waters", "carbonated-waters", "mineral-waters", "spring-waters", "drinking-water"])
        return family.contains(match)
    }

    /// Plain unflavored water, recognized by evidence rather than tags:
    /// a water word in the NAME, essentially zero energy and sugar, no flavor
    /// evidence, no additives, no measured caffeine, no sweeteners. Flavored
    /// waters keep their `drinks` path — the flavor vocabulary disqualifies
    /// them. Name-only on purpose: "carbonated water" leads the ingredient
    /// list of every soda, so ingredient matching would swallow zero-calorie
    /// flavored drinks whose flavor phrasing escapes the vocabulary.
    static func isPlainWaterByEvidence(_ p: Product, rs: RulesetV4 = .bundled) -> Bool {
        guard let cfg = rs.plainWaterEvidence else { return false }
        let fold = { (s: String) in
            s.lowercased().folding(options: .diacriticInsensitive,
                                   locale: Locale(identifier: "en_US"))
        }
        let hay = fold(p.name)
        guard cfg.nameWaterWords.contains(where: { hay.contains(fold($0)) }) else {
            return false
        }
        if hasFlavoredWaterEvidence(p, rs: rs) { return false }
        if let sugar = p.nutrients.sugar_g, sugar > cfg.maxSugarGPer100ml { return false }
        if let kcal = p.nutrients.kcal, kcal > cfg.maxKcalPer100ml { return false }
        if let caf = p.caffeine_mg, caf > 0 { return false }
        guard p.additives.isEmpty else { return false }
        let tiers = DrinksScoring.detectSweetenerTiers(p)
        if tiers.hadData, (tiers.tier1 + tiers.tier2 + tiers.tier3) > 0 { return false }
        return true
    }

    /// Name or ingredients contain configurable flavor evidence.
    static func hasFlavoredWaterEvidence(_ p: Product, rs: RulesetV4 = .bundled) -> Bool {
        guard let cfg = rs.flavoredWaterEvidence else { return false }
        let name = p.name.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
        for word in cfg.nameFlavorWords {
            let w = word.lowercased()
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            if !w.isEmpty, name.contains(w) { return true }
        }
        let ingredients = (p.ingredientsText ?? "").lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
        for term in cfg.ingredientFlavorTerms {
            let t = term.lowercased()
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            if !t.isEmpty, ingredients.contains(t) { return true }
        }
        return false
    }

    /// Fix 4 — validate nutritional signature; rerail on envelope violation.
    static func applyRoutingPlausibility(
        _ p: Product, attempted: String, rs: RulesetV4
    ) -> String {
        guard let envelope = rs.routingPlausibility?[attempted] else {
            return attempted
        }
        // M1: per-100 ml envelopes only apply to products that are demonstrably
        // liquids. Dry goods (beans, powders, mixes) stay on their tag profile,
        // whose own S3 variant handles sugar per 100 g honestly.
        if envelope.requiresLiquid == true {
            let isLiquid = DrinksScoring.parseVolumeMilliliters(p.size) != nil
                || DrinksScoring.parseVolumeMilliliters(p.servingSize) != nil
            guard isLiquid else { return attempted }
        }
        let sugar = p.nutrients.sugar_g
        let caffeine = p.caffeine_mg  // mapped OFF caffeine_100g → mg/100 ml

        var fired: [String] = []
        if let maxCaf = envelope.maxCaffeineMgPer100ml,
           let caf = caffeine, caf >= maxCaf {
            fired.append(String(format: "caffeine_mg/100ml %.1f ≥ %.1f", caf, maxCaf))
        }
        if let maxSugar = envelope.maxSugarGPer100ml,
           let s = sugar, s >= maxSugar {
            fired.append(String(format: "sugars_100g %.1f ≥ %.1f", s, maxSugar))
        }
        guard !fired.isEmpty else { return attempted }

        let used = envelope.rerouteTo
        #if DEBUG
        DrinksScanDebug.logRerail(
            productId: p.id,
            productName: p.name,
            attempted: attempted,
            used: used,
            thresholdsFired: fired
        )
        #endif
        // Rerailed drinks may still upgrade to juice_100.
        if used == "drinks", DrinksScoring.qualifiesAsJuice100(p) {
            return "juice_100"
        }
        return used
    }

    // MARK: V5.0.9 / V5.1.0 — integrity helpers

    /// Drink-like profiles skip food-only v5.1.0 axes (sweetener cap / isolate / S15 foods).
    private static let drinkLikeProfiles: Set<String> = ["drinks", "juice_100", "unscored_sweetener"]

    private static func isFoodProfile(_ id: String) -> Bool {
        !drinkLikeProfiles.contains(id)
    }

    /// Evaluate profile rules, then apply isolate discount (v5.0.9 ice_cream / v5.1.0 all foods).
    private static func evaluatedRules(
        profile: [RulesetV4.ProfileRule], profileId: String, product p: Product, rs: RulesetV4
    ) -> (results: [V4RuleResult], s12IsolateDiscount: Bool) {
        var results = profile.map { pr -> V4RuleResult in
            let (f, had, note) = evaluate(pr.rule, variant: pr.variant, product: p, rs: rs,
                                          profileId: profileId)
            return V4RuleResult(rule: pr.rule, weight: pr.w, fraction: f, hadData: had, note: note)
        }
        var discounted = false
        let isolateProfiles: Set<String> = rs.isV510
            ? Set(rs.profiles.keys.filter(isFoodProfile))
            : ["ice_cream"]
        // V5.5: never on protein bars — isolated protein is the product's
        // purpose and the S12 `proteinBar` variant scores its quality directly.
        // V5.6: milk-derived proteins (milk protein concentrate, whey protein
        // concentrate, milk powder) are a dairy product's own protein — no halving.
        let isolateHit: Bool = {
            if DairyScoring.isDairy(profileId), let cfg = rs.dairy {
                return DairyScoring.hasNonDairyIsolate(p, cfg: cfg)
            }
            return IngredientIntegrity.hasIsolateProtein(ingredientsText: p.ingredientsText)
        }()
        if isolateProfiles.contains(profileId), profileId != "protein_bars",
           isolateHit,
           let idx = results.firstIndex(where: { $0.rule == "S12" }) {
            let r = results[idx]
            let match = IngredientIntegrity.evaluate(ingredientsText: p.ingredientsText)
                .isolateMatches.first ?? "isolate"
            results[idx] = V4RuleResult(
                rule: r.rule, weight: r.weight, fraction: r.fraction * 0.5,
                hadData: r.hadData,
                note: "S12 isolate discount ×0.5 (\(match))"
            )
            discounted = true
        }
        return (results, discounted)
    }

    /// S14/S15 with no usable ingredient signal drop out of Σw (weight redistributed).
    /// M5: S12 joins them only on the `dryBrew` variant (note-marked), so
    /// ingredient-only products on other profiles keep their current scores.
    private static func activeWeightResults(_ results: [V4RuleResult]) -> [V4RuleResult] {
        results.filter { r in
            if (r.rule == "S14" || r.rule == "S15"), !r.hadData { return false }
            if r.rule == "S12", !r.hadData, r.note?.hasPrefix("dryBrew") == true { return false }
            return true
        }
    }

    /// Missing nutrition inputs used by the profile haircut confidence.
    private static func adjustedConfidence(
        base: Double, product p: Product, results: [V4RuleResult]
    ) -> Double {
        let byRule = Dictionary(uniqueKeysWithValues: results.map { ($0.rule, $0.weight) })
        var haircutPP = 0.0
        let n = p.nutrients
        // The dairy S12 variant runs on protein + calcium; fiber and kcal are
        // not inputs there, so their absence must not shave milk's confidence.
        // Same for the V5.3 egg variant (protein per 100 g only).
        // V5.4: the grain variant has no kcal axis either.
        let s12IsDairy: Bool = {
            let note = results.first { $0.rule == "S12" }?.note ?? ""
            return note.hasPrefix("dairy") || note.hasPrefix("egg") || note.hasPrefix("grain")
        }()
        if n.sugar_g == nil, let w = byRule["S3"] { haircutPP += w / 2 }
        if n.satFat_g == nil, let w = byRule["S5"] { haircutPP += w / 2 }
        if n.sodium_mg == nil, let w = byRule["S4"] { haircutPP += w / 2 }
        if n.fiber_g == nil, !s12IsDairy, let w = byRule["S12"] { haircutPP += w / 2 }
        if n.protein_g == nil, let w = byRule["S12"] { haircutPP += w / 2 }
        if n.kcal == nil, !s12IsDairy, let w = byRule["S12"] { haircutPP += w / 2 }
        let pct = max(60.0, base * 100 - haircutPP)
        return pct / 100.0
    }

    /// Formerly capped NOVA 4 / Nutri-Score E to OK without changing the number.
    /// Removed: band color and label always match the numeric score.
    static func displayBandCap(for p: Product) -> ScoreCap? { nil }

    /// Band label for UI — always the natural band for `score`.
    static func displayBandLabel(score: Int, product: Product,
                                 ruleset rs: RulesetV4 = .bundled) -> String {
        _ = product
        return rs.bandLabel(score)
    }

    static func displayScoreTier(score: Int, product: Product,
                                 ruleset rs: RulesetV4 = .bundled) -> ScoreTier {
        _ = product
        return rs.scoreTier(for: score)
    }

    // MARK: Rule dispatch

    private static func evaluate(_ rule: String, variant: String?,
                                 product p: Product, rs: RulesetV4,
                                 profileId: String = "general") -> (Double, Bool, String?) {
        let dairyForm = DairyScoring.form(profileId)
        let dairyCfg = rs.dairy
        switch rule {
        case "S1":
            // V5.5: on protein bars the isolate text signals are the protein
            // source, not an additive — S12 `proteinBar` judges them instead.
            let exempt: Set<String> = profileId == "protein_bars"
                ? Set(rs.proteinBars?.s1ExemptSignals ?? []) : []
            // V5.6: a sparse dairy record inside its identity envelope takes a
            // form-appropriate unknown credit, not the packaged-food 0.20.
            var unknown = 0.20
            if let form = dairyForm, let cfg = dairyCfg, !p.hasIngredientData {
                unknown = DairyScoring.s1UnknownCredit(p, form: form, cfg: cfg)
            }
            let r = s1(p, rs: rs, exemptSignals: exempt, unknownCredit: unknown)
            return (r.0, r.1, r.1 ? nil : (unknown > 0.20 ? "S1 dairy: no list → identity prior" : nil))
        case "S2":
            // V5.6: dairy processing is read off the list as marker families;
            // a pure dairy list is NOVA 1 whatever OFF says.
            if variant == "dairy", let form = dairyForm, let cfg = dairyCfg {
                return DairyScoring.s2Credit(p, form: form, cfg: cfg)
            }
            // V5.4: bread processing is read off the ingredient list (marker
            // families), not OFF's NOVA tag — see BreadScoring.s2Credit.
            if variant == "bread", let cfg = rs.bread {
                return BreadScoring.s2Credit(p, cfg: cfg)
            }
            // V5.5: protein bars are NOVA 4 by construction; marker families
            // separate an egg-white-and-nut bar from a candy-bar build.
            if variant == "proteinBar", let cfg = rs.proteinBars {
                return ProteinBarScoring.s2Credit(p, cfg: cfg)
            }
            let r = s2(p); return (r.0, r.1, nil)
        case "S3":
            // V5.6: dairy scores free sugar (declared added, else total minus
            // the form's lactose allowance) — no intrinsic discount, no
            // sweetener cap (S6 grades sweeteners on fermented / cream).
            if let form = dairyForm, let cfg = dairyCfg {
                let t = rs.s3Thresholds[variant ?? "dairy"] ?? rs.s3Thresholds["dairy"] ?? [3, 8, 13]
                return DairyScoring.s3Credit(p, form: form, rs: rs, cfg: cfg, thresholds: t)
            }
            return s3(p, variant: variant ?? "foods", rs: rs, profileId: profileId)
        case "S4":
            // V5.6: yogurt sodium is structurally 30–80 mg; an undeclared
            // value is an omission, not a risk.
            if variant == "fermented", p.nutrients.sodium_mg == nil, let cfg = dairyCfg {
                return (cfg.s4FermentedPrior, false, "S4 fermented: sodium undeclared → structural prior")
            }
            let thresholds = variant.flatMap { rs.s4ThresholdsByVariant?[$0] } ?? rs.s4Thresholds
            // V5.4: salt entered in the wrong unit (1 mg sodium on a salted
            // loaf) must not earn full credit — unknown, not low.
            if variant == "bread", let cfg = rs.bread, BreadScoring.sodiumIsImplausible(p, cfg: cfg) {
                return (0.30, false, "S4 bread: sodium implausible for a salted bread → unknown")
            }
            // V5.5: a bar declaring more sodium than table-salt-level food is
            // a unit error (field QA: 161 538 mg/100 g), not a salty bar.
            if variant == "proteinBar", let cfg = rs.proteinBars,
               let na = p.nutrients.sodium_mg, na > cfg.sodiumMaxPlausibleMg {
                return (0.30, false, "S4 protein bar: sodium implausible → unknown")
            }
            let r = stepped(p.nutrients.sodium_mg, thresholds: thresholds,
                            unknownCredit: 0.30)
            return (r.0, r.1, nil)
        case "S5":
            let r = stepped(p.nutrients.satFat_g,
                            thresholds: rs.s5Thresholds[variant ?? "standard"]
                                ?? rs.s5Thresholds["standard"] ?? [3, 8, 15],
                            unknownCredit: 0.40)
            return (r.0, r.1, nil)
        case "S6":
            // V5.6: fermented dairy / cream take the drinks sweetener tiers.
            if variant == "dairy" {
                return DairyScoring.s6Credit(p)
            }
            // V5.5: protein bars take the drinks sweetener tiers plus a
            // declared-polyol load dock.
            if variant == "proteinBar", let cfg = rs.proteinBars {
                return ProteinBarScoring.s6Credit(p, cfg: cfg)
            }
            // Legacy path — drinks profile uses DrinksScoring.s6Credit instead.
            let r = DrinksScoring.s6Credit(p); return (r.0, r.1, nil)
        case "S7":
            let r = DrinksScoring.s7Credit(p, rs: rs); return (r.0, r.1, nil)
        case "S8":
            let serving = DrinksScoring.effectiveServing(for: p)
            let r = DrinksScoring.s8Credit(p, serving: serving)
            return (r.0, r.1, r.3 ? String(format: "estimated %.0f mg", r.2) : nil)
        case "S10":
            let r = s10(p, rs: rs); return (r.0, r.1, nil)
        case "S12":
            // M5: dry brew goods (beans, ground, loose tea, instant) will never
            // have a meaningful micronutrient panel — the rule is structurally
            // zero, not evidence of poor quality. Mark it for redistribution.
            if variant == "dryBrew" {
                return (0, false, "dryBrew: no micronutrient basis (weight redistributed)")
            }
            // V5.2: dairy can never earn fiber or FVN (60% of the generic rule),
            // so the dairy variants measure protein + calcium instead.
            if variant == "dairy" {
                let r = s12DairyCredit(p, cfg: rs.s12Dairy)
                return (r.0, r.1, "dairy: protein+calcium basis")
            }
            if variant == "dairyDense" {
                // V5.6 cream: protein declared as exactly 0 is per-tablespoon
                // label rounding, not a measured zero.
                if DairyScoring.form(profileId) == .cream, DairyScoring.creamProteinIsRounding(p) {
                    return (rs.s12DairyDense?.unknownCredit ?? 0.5, false,
                            "dairyDense: protein 0 = serving rounding → unknown")
                }
                let r = s12DairyDenseCredit(p, cfg: rs.s12DairyDense)
                return (r.0, r.1, "dairyDense: protein+calcium basis")
            }
            if variant == "dairyCheese" {
                let r = DairyScoring.s12CheeseCredit(p, cfg: rs.s12DairyCheese)
                return (r.0, r.1, "dairyCheese: protein+calcium basis")
            }
            // V5.3: eggs have no fiber/FVN axis either — protein per 100 g
            // against a reference whole egg; the yolk's micronutrient
            // signature lives in the S13 egg variant.
            if variant == "egg" {
                let r = s12EggCredit(p, cfg: rs.eggs)
                return (r.0, r.1, "egg: protein basis")
            }
            // V5.4: bread has no fruit/veg axis and a flat ~250 kcal, so the
            // grain variant scores fiber per 100 g + protein.
            if variant == "grain", let cfg = rs.bread {
                let r = BreadScoring.s12GrainCredit(p, cfg: cfg)
                return (r.0, r.1, "grain: " + r.2)
            }
            // V5.5: protein bars score protein delivery (amount per serving +
            // share of energy, source quality) and fiber — no fruit/veg axis.
            if variant == "proteinBar", let cfg = rs.proteinBars {
                let r = ProteinBarScoring.s12Credit(p, cfg: cfg)
                return (r.0, r.1, "proteinBar: " + r.2)
            }
            let r = s12(p, variant: variant); return (r.0, r.1, nil)
        case "S13":
            if variant == "egg" { return s13Egg(p, rs: rs) }
            // V5.6: dairy reference prior (B12 / riboflavin / iodine /
            // phosphorus / potassium / calcium matrix) + declared lifts.
            if variant == "dairy", let form = dairyForm, let cfg = dairyCfg {
                return DairyScoring.s13Credit(p, form: form, cfg: cfg)
            }
            let r = s13(p, rs: rs); return (r.0, r.1, nil)
        case "S14":
            // V5.6: salt, cultures, enzymes, rennet, lactase and vitamins are
            // neutral in a dairy list — neither whole food nor a dock.
            if dairyForm != nil, let cfg = dairyCfg {
                let b = IngredientIntegrity.evaluate(ingredientsText: p.ingredientsText,
                                                     neutralTokenKw: cfg.neutralTokens)
                return (b.fraction, b.hadData, nil)
            }
            // V5.5: protein sources are neutral in a protein bar's real-food
            // ratio — neither whole food nor a dock.
            if variant == "proteinBar", let cfg = rs.proteinBars {
                return ProteinBarScoring.s14Credit(p, cfg: cfg)
            }
            let r = s14(p); return (r.0, r.1, nil)
        case "S15":
            return s15(p)
        case "contaminantRisk":
            let r = contaminantRisk(p, rs: rs); return (r.0, r.1, nil)
        case "dairyProcessing":
            if dairyForm != nil, let cfg = dairyCfg {
                return DairyScoring.processingCredit(p, rs: rs, cfg: cfg)
            }
            let r = dairyProcessing(p, rs: rs); return (r.0, r.1, nil)
        case "dairyForm":
            guard let form = dairyForm, let cfg = dairyCfg else { return (0.85, false, nil) }
            return DairyScoring.formCredit(p, form: form, cfg: cfg)
        case "brewMaterial":
            let r = brewMaterial(p, rs: rs); return (r.0, r.1, nil)
        case "sweetenerType":
            let r = kwLookup(haystack(p), rs.sweetenerType,
                             fallback: rs.sweetenerTypeDefault ?? 0.3)
            return (r.0, r.1, nil)
        case "authenticity":
            let r = authenticity(p, rs: rs); return (r.0, r.1, nil)
        case "sweetenerProcessing":
            let r = kwLookup(haystack(p), rs.sweetenerProcessing,
                             fallback: rs.sweetenerProcessingDefault ?? 0.6)
            return (r.0, r.1, nil)
        case "wholeGrain":
            if variant == "bread", let cfg = rs.bread {
                return BreadScoring.wholeGrainCredit(p, cfg: cfg)
            }
            let r = wholeGrain(p, rs: rs); return (r.0, r.1, nil)
        default:
            return (0, false, nil)
        }
    }

    /// Package-visible evaluate for `DrinksScoring` (S1 reuse).
    static func _evaluateForDrinks(_ rule: String, variant: String?, product: Product,
                                   rs: RulesetV4, profileId: String)
    -> (Double, Bool, String?) {
        evaluate(rule, variant: variant, product: product, rs: rs, profileId: profileId)
    }

    // MARK: Phase C category rules

    /// Searchable text for keyword rules: name + categories + labels + ingredients.
    private static func haystack(_ p: Product) -> String {
        ([p.name.lowercased(), p.ingredientsText?.lowercased() ?? ""]
         + (p.categories ?? []) + (p.labels ?? [])).joined(separator: " ")
    }

    /// Common plant-milk crop names used by S10 hero-share detection.
    private static let plantMilkCrops = [
        "coconut", "almond", "hemp", "cashew", "macadamia", "pea",
        "oat", "soy", "soya", "rice", "wheat", "corn",
    ]

    private static func s10(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        guard let hero = (p.ingredientShares ?? []).first(where: { share in
            plantMilkCrops.contains { share.name.contains($0) }
        })
        else { return (0.20, false) }
        // Declared percent wins; OFF's estimate is trusted at 75%.
        guard let pct = hero.percent ?? hero.percentEstimate.map({ $0 * 0.75 })
        else { return (0.20, false) }
        for step in rs.heroCredit ?? [[15, 1.0], [10, 0.8], [5, 0.5], [2, 0.2]]
        where step.count == 2 && pct >= step[0] {
            return (step[1], true)
        }
        return (0.0, true)
    }

    /// Rice arsenic pathway: rice → riceCap; all other crops neutral 1.0.
    private static func contaminantRisk(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        let cap = rs.contaminantRisk?.riceCap ?? 0.4
        let hay = haystack(p)
        if hay.contains("rice") { return (cap, true) }
        return (1.0, true)
    }

    private static func dairyProcessing(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        let tags = Set((p.categories ?? []) + (p.labels ?? []))
        for entry in rs.dairyProcessing ?? [] where tags.contains(entry.match) {
            return (entry.credit, true)
        }
        // Name evidence — word-bounded so "yoghurt" never matches "uht".
        let name = p.name.lowercased()
        for entry in rs.dairyProcessingName ?? [] where matchesWord(entry.kw, in: name) {
            return (entry.credit, true)
        }
        // Default is an assumption (fresh pasteurized), not evidence.
        return (rs.dairyProcessingDefault ?? 0.85, false)
    }

    /// Word-bounded phrase search (case handled by callers passing lowercase).
    static func matchesWord(_ phrase: String, in text: String) -> Bool {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func brewMaterial(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        let hay = haystack(p) + " " + (p.packagingMaterials ?? []).joined(separator: " ")
        for entry in rs.brewMaterial ?? [] where hay.contains(entry.kw) {
            return (entry.credit, true)
        }
        return (rs.brewMaterialDefault ?? 0.40, false)   // unknown bag material
    }

    private static func kwLookup(_ hay: String, _ table: [RulesetV4.KwCredit]?,
                                 fallback: Double) -> (Double, Bool) {
        for entry in table ?? [] where hay.contains(entry.kw) {
            return (entry.credit, true)
        }
        return (fallback, true)   // Tier-1: type is derivable from the label
    }

    private static func authenticity(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        let hay = haystack(p)
        if (rs.authenticityBad ?? []).contains(where: { hay.contains($0) }) {
            return (0.0, true)
        }
        if let shares = p.ingredientShares, shares.count == 1 { return (1.0, true) }
        return (0.6, true)
    }

    /// Qualitative within-category notes for unscored sweeteners (not a score).
    /// At most three plain-language lines derived from the legacy sweetener rules.
    static func sweetenerQualityNotes(_ p: Product, ruleset rs: RulesetV4 = .bundled) -> [String] {
        var notes: [String] = []

        let (typeF, _, _) = evaluate("sweetenerType", variant: nil, product: p, rs: rs)
        if let typeNote = sweetenerTypeNote(for: p, fraction: typeF, rs: rs) {
            notes.append(typeNote)
        }

        let (procF, _, _) = evaluate("sweetenerProcessing", variant: nil, product: p, rs: rs)
        if procF >= 0.95 {
            notes.append("Minimally processed")
        } else if procF <= 0.25 {
            notes.append("Refined")
        }

        let (authF, _, _) = evaluate("authenticity", variant: nil, product: p, rs: rs)
        if authF >= 0.95 {
            notes.append("Single-ingredient product")
        } else if authF <= 0.05 {
            notes.append("Blend")
        }

        return Array(notes.prefix(3))
    }

    private static func sweetenerTypeNote(for p: Product, fraction: Double, rs: RulesetV4) -> String? {
        let hay = haystack(p)
        for entry in rs.sweetenerType ?? [] where hay.contains(entry.kw) {
            switch entry.kw {
            case "raw honey":
                return "Raw honey — one of the less processed options"
            case "manuka":
                return "Manuka honey — one of the less processed options"
            case "maple":
                return "Maple syrup — one of the less processed options"
            case "stevia":
                return "Stevia — a non-nutritive option"
            case "monk fruit":
                return "Monk fruit — a non-nutritive option"
            case "honey":
                return "Honey — among the less refined options"
            case "coconut sugar":
                return "Coconut sugar — less refined than white sugar"
            case "turbinado", "demerara":
                return "Partially refined cane sugar"
            case "brown sugar":
                return "Brown sugar — still a refined sweetener"
            case "agave":
                return "Agave — a more concentrated sweetener"
            case "corn syrup":
                return "Corn syrup — highly processed"
            case "high fructose", "hfcs":
                return "High-fructose corn syrup"
            default:
                break
            }
        }
        if fraction >= 0.85 { return "One of the less processed sweetener options" }
        return nil
    }

    private static func wholeGrain(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        ((rs.wholeGrainKw ?? []).contains { haystack(p).contains($0) } ? 1.0 : 0.0, true)
    }

    // MARK: S1 — ingredient & additive risk

    private static func s1(_ p: Product, rs: RulesetV4,
                           exemptSignals: Set<String> = [],
                           unknownCredit: Double = 0.20) -> (Double, Bool) {
        // Whole-food bypass: NOVA 1–2 + no additives + no textSignals → clean,
        // even when ingredients_text is missing (single-ingredient produce).
        let additivesEmpty = p.additives.isEmpty
        let textHit: Bool = {
            guard let text = p.ingredientsText?.lowercased() else { return false }
            return rs.textSignals.keys.contains { !exemptSignals.contains($0) && text.contains($0) }
        }()
        if (1...2).contains(p.novaGroup), additivesEmpty, !textHit {
            return (1.0, true)
        }

        guard p.additiveIngredientTextMissing != true, p.hasIngredientData else {
            return (unknownCredit, false)
        }

        var penalties: [Double] = []
        var gumsCounted = 0
        for additive in p.additives {
            guard let code = additive.code else { continue }
            guard let fraction = s1Fraction(for: additive, code: code, rs: rs) else { continue }
            if rs.gumCodes.contains(code) {
                guard gumsCounted < 2 else { continue }   // gum cap
                gumsCounted += 1
            }
            penalties.append(fraction)
        }

        // Text-detected signals (HFCS, artificial/natural flavors) — things
        // OFF's additive tagger doesn't cover. One hit per signal.
        if let text = p.ingredientsText?.lowercased() {
            for (needle, tier) in rs.textSignals where !exemptSignals.contains(needle) && text.contains(needle) {
                if let fraction = rs.tierFractions[tier] { penalties.append(fraction) }
            }
        }

        // Dampening: worst hits count in full; after `afterCount`, half.
        penalties.sort(by: >)
        var total = 0.0
        for (i, pen) in penalties.enumerated() {
            total += i < rs.dampening.afterCount ? pen : pen * rs.dampening.factor
        }
        return (max(0, 1 - total), true)
    }

    /// S1 penalty fraction from detector tier, with ruleset code lookup as fallback.
    private static func s1Fraction(for additive: ProductAdditive, code: String,
                                   rs: RulesetV4) -> Double? {
        if let tier = additive.tier {
            switch tier {
            case .major: return rs.tierFractions["A"]
            case .moderate: return rs.tierFractions["B"]
            case .mild: return rs.tierFractions["C"]
            case .soft: return rs.tierFractions["D"]
            case .exempt: return nil
            case .unclassified: return rs.tierFractions["C"]
            }
        }
        if let tier = rs.additiveTiers[code], let fraction = rs.tierFractions[tier] {
            return fraction
        }
        return rs.tierFractions["C"]
    }

    // MARK: S2 — processing level

    private static func s2(_ p: Product) -> (Double, Bool) {
        switch p.novaGroup {
        case 1: return (1.0, true)
        case 2: return (0.75, true)
        case 3: return (0.40, true)
        case 4: return (0.0, true)
        default: break
        }
        // NOVA unknown → ingredient-count fallback (still data-backed when a
        // parsed list exists).
        if let count = p.ingredientShares?.count, count > 0 {
            switch count {
            case 1...3:  return (0.85, true)
            case 4...7:  return (0.55, true)
            case 8...15: return (0.25, true)
            default:     return (0.0, true)
            }
        }
        return (0.40, false)
    }

    // MARK: S3 — added sugar (fvn-discounted fallback; drinks = per-serving Oasis)

    /// Artificial NNS codes used only by the legacy drinks-variant floor on
    /// non-`drinks` profiles that still use `variant: "drinks"` (e.g. plant_milk).
    private static let nnsCodes: Set<String> = [
        "e950", "e951", "e954", "e955", "e957", "e959", "e960", "e961", "e962", "e969",
    ]
    private static let nnsTextMarkers = [
        "stevia", "sucralose", "aspartame", "acesulfame",
    ]

    private static func hasNonNutritiveSweetener(_ p: Product) -> Bool {
        let codes = Set(p.additives.compactMap(\.code))
        if !codes.isDisjoint(with: nnsCodes) { return true }
        let hay = ([p.ingredientsText ?? ""] + DrinksScoring.nonNegatedLabels(p) + [p.name])
            .joined(separator: " ").lowercased()
        return nnsTextMarkers.contains { hay.contains($0) }
    }

    /// Default beverage serving when OFF `serving_size` is missing / unparseable.
    static let defaultDrinkServingMl: Double = 250

    /// Parse OFF free-form serving size into milliliters. Returns inferred=true
    /// when falling back to `defaultDrinkServingMl`.
    static func parseServingMilliliters(_ raw: String?) -> (ml: Double, inferred: Bool) {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (defaultDrinkServingMl, true)
        }
        let s = raw.lowercased()
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "\u{00a0}", with: " ")

        // Prefer liquid units; ignore solid-only servings (g / oz by weight).
        let patterns: [(String, Double)] = [
            (#"(\d+(?:\.\d+)?)\s*(?:fl\.?\s*oz|floz|fluid\s*ounces?)"#, 29.5735),
            (#"(\d+(?:\.\d+)?)\s*ml\b"#, 1.0),
            (#"(\d+(?:\.\d+)?)\s*l\b"#, 1000.0),
            (#"(\d+(?:\.\d+)?)\s*cl\b"#, 10.0),
        ]
        for (pattern, factor) in patterns {
            if let re = try? NSRegularExpression(pattern: pattern),
               let match = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               match.numberOfRanges >= 2,
               let range = Range(match.range(at: 1), in: s),
               let value = Double(s[range]), value > 0 {
                return (value * factor, false)
            }
        }
        return (defaultDrinkServingMl, true)
    }

    private static func s3(_ p: Product, variant: String, rs: RulesetV4,
                           profileId: String) -> (Double, Bool, String?) {
        let fvn = p.nutrients.fvn ?? 0
        let isDrinksProfile = profileId == "drinks" || profileId == "juice_100"
        let isDrinksVariant = variant == "drinks" || variant == "drinksServing"

        // Drinks profile: Oasis-style per-serving thresholds (variant drinksServing).
        if isDrinksProfile {
            let (servingMl, inferred) = parseServingMilliliters(p.servingSize)
            let per100: Double?
            var pathNote: String
            if let added = p.nutrients.addedSugar_g, added > 0 {
                if fvn >= 80, let total = p.nutrients.sugar_g {
                    per100 = max(added, total * 0.70)
                    pathNote = "added+fvn70"
                } else {
                    per100 = added
                    pathNote = "added"
                }
            } else if let total = p.nutrients.sugar_g {
                let discount = min(0.30, fvn / 100)
                per100 = total * (1 - discount)
                pathNote = "total×(1−fvn30)"
            } else {
                return (0.25, false, "S3 drinks: no sugar data")
            }
            let sugarPerServing = per100! * (servingMl / 100)
            let thresholds = rs.s3Thresholds["drinksServing"]
                ?? rs.s3Thresholds[variant]
                ?? [2, 8, 16, 30]
            let result = stepped(sugarPerServing, thresholds: thresholds, unknownCredit: 0.25)
            let note = String(
                format: "S3 drinksServing: %.1f g/serving (%.0f ml%@, %@) → f %.3f",
                sugarPerServing, servingMl, inferred ? " default" : "", pathNote, result.0
            )
            return (result.0, result.1, note)
        }

        // V5.3 eggs: sugars are structurally <1 g/100 g in an egg; an
        // undeclared value on a plain egg is a label omission, not a risk.
        if profileId == "eggs", let cfg = rs.eggs,
           p.nutrients.sugar_g == nil, (p.nutrients.addedSugar_g ?? 0) <= 0 {
            return (cfg.s3UnknownCredit, false, "S3 egg: sugar undeclared → structural prior")
        }

        let thresholds = rs.s3Thresholds[variant] ?? rs.s3Thresholds["foods"]!
        // plant_milk etc. still use per-100 ml `drinks` thresholds.
        let useDrinksFvnCap = isDrinksVariant
        // V5.5 protein bars: date paste / dried fruit is free sugar in the UK
        // (SACN / PHE) definition and at best borderline in WHO's — at least
        // half of it counts, however high the fruit/nut share.
        let isProteinBar = profileId == "protein_bars"
        let fvnDiscountCap: Double = isProteinBar ? (rs.proteinBars?.s3.fvnDiscountCap ?? 0.5) : 1

        let result: (Double, Bool)
        if let added = p.nutrients.addedSugar_g, added > 0 {
            let effective: Double
            if useDrinksFvnCap, fvn >= 80, let total = p.nutrients.sugar_g {
                effective = max(added, total * 0.70)
            } else {
                effective = added
            }
            result = stepped(effective, thresholds: thresholds, unknownCredit: 0.25)
        } else if let total = p.nutrients.sugar_g {
            let discount: Double
            if useDrinksFvnCap {
                discount = min(0.30, fvn / 100)
            } else {
                discount = min(fvnDiscountCap, fvn / 100)
            }
            let effective = total * (1 - discount)
            result = stepped(effective, thresholds: thresholds, unknownCredit: 0.25)
        } else {
            result = (0.25, false)
        }

        var f = result.0
        var note: String? = nil

        // Legacy NNS floor for non-drinks profiles that still use drinks variant
        // (e.g. plant_milk). Drinks profile uses S6 instead — no stack.
        if useDrinksFvnCap, hasNonNutritiveSweetener(p) {
            return (min(f, 0.30), result.1, nil)
        }

        // V5.1.0 — sweetener-substitution cap (foods only). V5.5: not on
        // protein bars — their S6 rule grades the sweetener system itself.
        if rs.isV510, isFoodProfile(profileId), !isDrinksProfile, !isProteinBar {
            let sweets = IngredientIntegrity.sweetenerSystemMatches(
                ingredientsText: p.ingredientsText)
            if !sweets.isEmpty {
                let before = f
                f = min(f, 0.50)
                if f < before - 1e-9 {
                    note = String(
                        format: "S3 sweetenerSubstitutionCap: f %.3f → %.3f (%@)",
                        before, f, sweets.joined(separator: ", ")
                    )
                }
            }
        }

        // V5.1.0 — intrinsic sugar discount for simple whole foods (dairy/fruit/honey).
        if rs.isV510, isFoodProfile(profileId), !isDrinksProfile {
            let q = IngredientIntegrity.qualifiesForIntrinsicSugarDiscount(
                ingredientsText: p.ingredientsText,
                additivesEmpty: p.additives.isEmpty
            )
            if q.ok, let reason = q.reason {
                let before = f
                f = 1 - 0.7 * (1 - f)
                f = min(1, max(0, f))
                let intrinsicNote = "S3 intrinsicDiscount ×0.7 (\(reason))"
                note = note.map { $0 + " · " + intrinsicNote } ?? intrinsicNote
                _ = before
            }
        }

        return (f, result.1, note)
    }

    // MARK: V5.3 — eggs

    enum EggForm: String { case whole, whites, yolk }

    /// Which part of the egg the product is: drives the S13 reference prior.
    /// Order of evidence: category tags → first ingredient / name words →
    /// nutrient envelope (no yolk fat = whites).
    static func eggForm(_ p: Product, rs: RulesetV4) -> EggForm {
        guard let cfg = rs.eggs else { return .whole }
        let tags = Set(p.categories ?? [])
        if !tags.isDisjoint(with: cfg.yolkTags) { return .yolk }
        if !tags.isDisjoint(with: cfg.whitesTags) { return .whites }
        let lead: String = {
            if let text = p.ingredientsText,
               let first = IngredientIntegrity.tokens(from: text).first { return first }
            return p.name.lowercased()
        }()
        if cfg.yolkWords.contains(where: { matchesWord($0, in: lead) }) { return .yolk }
        if cfg.whitesWords.contains(where: { matchesWord($0, in: lead) }) { return .whites }
        let n = p.nutrients
        let env = cfg.whitesEnvelope
        if let sat = n.satFat_g, sat <= env.maxSatFatG,
           let kcal = n.kcal, kcal <= env.maxKcal,
           (n.protein_g ?? 0) >= env.minProteinG {
            return .whites
        }
        return .whole
    }

    private static func isEggPowder(_ p: Product, cfg: RulesetV4.EggConfig) -> Bool {
        guard let kcal = p.nutrients.kcal, kcal >= cfg.powder.kcalTrigger else { return false }
        let hay = (p.name + " " + (p.ingredientsText ?? "")).lowercased()
        return cfg.powder.keywords.contains { hay.contains($0) }
    }

    /// Tag-independent egg evidence: egg word in the name AND as the first
    /// ingredient AND the egg-dominance guard passes.
    static func hasEggEvidence(_ p: Product, rs: RulesetV4) -> Bool {
        guard let cfg = rs.eggs else { return false }
        let name = p.name.lowercased()
        guard cfg.eggWords.contains(where: { matchesWord($0, in: name) }) else { return false }
        guard let text = p.ingredientsText,
              let first = IngredientIntegrity.tokens(from: text).first,
              cfg.eggWords.contains(where: { matchesWord($0, in: first) })
        else { return false }
        return passesEggGuard(p, rs: rs)
    }

    /// Egg-dominance routing guard. OFF's `eggs` tag is inherited by scotch
    /// eggs, egg pasta and egg dishes. With an ingredient list, the first
    /// ingredient must be an egg word; without one, the composition must look
    /// like an egg. Declared protein below a plain egg's floor (egg salad,
    /// quiche) falls through to `general` either way.
    static func passesEggGuard(_ p: Product, rs: RulesetV4) -> Bool {
        guard let cfg = rs.eggs else { return true }
        let n = p.nutrients
        let g = cfg.routingGuard
        if let sugar = n.sugar_g, sugar > g.maxSugarG { return false }
        if let prot = n.protein_g, prot < g.minProteinG { return false }
        if let text = p.ingredientsText,
           let first = IngredientIntegrity.tokens(from: text).first {
            guard cfg.eggWords.contains(where: { matchesWord($0, in: first) }) else { return false }
            if let kcal = n.kcal, kcal > g.yolkMaxKcal, !isEggPowder(p, cfg: cfg) { return false }
            return true
        }
        guard let prot = n.protein_g, prot <= g.maxProteinG else { return false }
        if let kcal = n.kcal, kcal > g.maxKcal { return false }
        return true
    }

    /// V5.3 egg normalization (`eggs` route only).
    /// 1. Egg powders are judged per 100 g as reconstituted (×0.25), like milk
    ///    powders — never as a 48 g-protein / 13 g-sat-fat "food".
    /// 2. Evidence-based NOVA: an ingredient list that is nothing but egg
    ///    words, with no additives, is NOVA 1 by NOVA's own definition
    ///    (pasteurization is allowed in group 1) regardless of the OFF tag;
    ///    a plain egg with no list and no NOVA is treated as NOVA 1 too —
    ///    a fifth of OFF eggs carry no NOVA and were scoring 47 as a result.
    static func eggNormalized(_ p: Product, rs: RulesetV4) -> Product {
        guard let cfg = rs.eggs else { return p }
        var q = p
        if isEggPowder(q, cfg: cfg) {
            let f = cfg.powder.factor
            func scale(_ v: inout Double?) { v = v.map { $0 * f } }
            scale(&q.nutrients.sugar_g); scale(&q.nutrients.sodium_mg)
            scale(&q.nutrients.satFat_g); scale(&q.nutrients.fiber_g)
            scale(&q.nutrients.protein_g); scale(&q.nutrients.calcium_mg)
            scale(&q.nutrients.kcal); scale(&q.nutrients.addedSugar_g)
            scale(&q.nutrients.transFat_g); scale(&q.nutrients.iron_mg)
            scale(&q.nutrients.potassium_mg); scale(&q.nutrients.magnesium_mg)
            scale(&q.nutrients.zinc_mg); scale(&q.nutrients.vitaminC_mg)
            scale(&q.nutrients.vitaminD_ug); scale(&q.nutrients.vitaminB12_ug)
            scale(&q.nutrients.choline_mg); scale(&q.nutrients.selenium_ug)
            scale(&q.nutrients.omega3_g)
        }
        guard q.additives.isEmpty else { return q }
        let tokens = q.ingredientsText.map { IngredientIntegrity.tokens(from: $0) } ?? []
        let plainEggList = !tokens.isEmpty && tokens.allSatisfy { t in
            IngredientIntegrity.isWholeFoodToken(t)
                && cfg.eggWords.contains { matchesWord($0, in: t) }
        }
        if plainEggList, q.novaGroup != 1 {
            q.novaGroup = 1
        } else if tokens.isEmpty, !(1...4).contains(q.novaGroup) {
            q.novaGroup = 1
        }
        return q
    }

    /// S12 `egg` — protein per 100 g against a reference whole egg (absolute,
    /// not per kcal, so whites vs whole stays a micronutrient question).
    private static func s12EggCredit(_ p: Product, cfg: RulesetV4.EggConfig?) -> (Double, Bool) {
        let target = cfg?.proteinTargetG ?? 12.6
        guard let prot = p.nutrients.protein_g else { return (cfg?.s12UnknownCredit ?? 0.5, false) }
        return (min(1, max(0, prot / target)), true)
    }

    /// Declared per-100 g value for an S13 nutrient key (generic + egg extras).
    private static func microValue(_ key: String, _ n: Nutrients) -> Double? {
        switch key {
        case "iron_mg": return n.iron_mg
        case "potassium_mg": return n.potassium_mg
        case "magnesium_mg": return n.magnesium_mg
        case "zinc_mg": return n.zinc_mg
        case "vitaminC_mg": return n.vitaminC_mg
        case "calcium_mg": return n.calcium_mg
        case "vitaminD_ug": return n.vitaminD_ug
        case "vitaminB12_ug": return n.vitaminB12_ug
        case "choline_mg": return n.choline_mg
        case "selenium_ug": return n.selenium_ug
        case "omega3_g": return n.omega3_g
        default: return nil
        }
    }

    /// S13 `egg` — micronutrients from a reference-composition prior plus an
    /// enrichment lift. A whole egg's real panel (choline, selenium, B12,
    /// riboflavin, vitamin D, vitamin A, iron, lutein) clears the generic S13
    /// target outright, but labels rarely declare it — US panels list vitamin
    /// D, calcium, iron, potassium; choline / B12 only on some brands — so a
    /// silent label must not rank below a complete one for the same egg. The
    /// rule therefore starts from a form prior (whole/yolk vs whites, evidenced
    /// by tags / ingredient / composition) and only values at or above an
    /// enrichment threshold (≈2× a reference egg: vitamin D, B12, omega-3,
    /// selenium — what feed programs actually change in the egg) lift it, one
    /// step each, never lower it. The prior sits below full credit on purpose:
    /// an assumption about the category must not outrank declared evidence.
    private static func s13Egg(_ p: Product, rs: RulesetV4) -> (Double, Bool, String?) {
        guard let cfg = rs.eggs else {
            let r = s13(p, rs: rs); return (r.0, r.1, nil)
        }
        let form = eggForm(p, rs: rs)
        let prior = form == .whites ? cfg.s13Prior.whites : cfg.s13Prior.whole
        var hits: [String] = []
        for (key, threshold) in cfg.s13Enrichment.sorted(by: { $0.key < $1.key }) {
            guard threshold > 0, let v = microValue(key, p.nutrients), v >= threshold else { continue }
            hits.append(key)
        }
        let lift = min(cfg.s13EnrichmentMaxLift, cfg.s13EnrichmentStep * Double(hits.count))
        let f = min(1.0, prior + lift)
        let note = hits.isEmpty
            ? String(format: "egg: %@ reference prior %.2f", form.rawValue, prior)
            : String(format: "egg: %@ prior %.2f + enrichment → %.2f (%@)",
                     form.rawValue, prior, f, hits.joined(separator: ", "))
        return (f, true, note)
    }

    // MARK: S12 — nutrient quality

    private static func s12(_ p: Product, variant: String? = nil) -> (Double, Bool) {
        let n = p.nutrients
        let protDens: Double
        if let kcal = n.kcal, kcal < 5 {
            protDens = 0
        } else if let kcal = n.kcal, kcal > 0 {
            protDens = min(1, ((n.protein_g ?? 0) / (kcal / 100)) / 15)
        } else {
            protDens = 0
        }
        let fiber = min(1, (n.fiber_g ?? 0) / 8)
        let fvn = min(1, (n.fvn ?? 0) / 100)
        let f: Double
        if variant == "produce" {
            f = 0.20 * protDens + 0.30 * fiber + 0.50 * fvn
        } else {
            f = 0.40 * protDens + 0.35 * fiber + 0.25 * fvn
        }
        return (f, n.kcal != nil || n.fiber_g != nil || n.fvn != nil)
    }

    /// S12 `dairy` variant — protein and calcium per 100 ml, the axes milk
    /// actually delivers on. Protein per volume (not per kcal) keeps the
    /// whole-vs-skim question out of this rule: fat level is preference, and
    /// saturated fat already has S5. Missing calcium falls back to protein
    /// alone rather than penalizing a sparse label.
    private static func s12DairyCredit(_ p: Product, cfg: RulesetV4.S12Dairy?) -> (Double, Bool) {
        let protTarget = cfg?.proteinTargetG ?? 3.4
        let calTarget = cfg?.calciumTargetMg ?? 125
        let prot = p.nutrients.protein_g.map { min(1, $0 / protTarget) }
        let cal = p.nutrients.calcium_mg.map { min(1, $0 / calTarget) }
        switch (prot, cal) {
        case let (pr?, ca?): return (0.5 * pr + 0.5 * ca, true)
        case let (pr?, nil): return (pr, true)
        case let (nil, ca?): return (ca, true)
        default: return (cfg?.unknownCredit ?? 0.5, false)
        }
    }

    /// S12 `dairyDense` (yogurt/cheese) — protein credit is the mean of the
    /// absolute per-100 g credit and the per-kcal density credit (15 g/100 kcal
    /// = full, same anchor as generic S12). The blend keeps whole vs nonfat
    /// yogurt within a point (fat level is preference) while still ranking
    /// yogurt above cream cheese, which absolute grams alone cannot do.
    private static func s12DairyDenseCredit(_ p: Product, cfg: RulesetV4.S12Dairy?) -> (Double, Bool) {
        let protTarget = cfg?.proteinTargetG ?? 6
        let calTarget = cfg?.calciumTargetMg ?? 150
        let n = p.nutrients
        let protCredit: Double? = n.protein_g.map { prot in
            let abs = min(1, prot / protTarget)
            guard let kcal = n.kcal, kcal > 0 else { return abs }
            let dens = min(1, (prot / (kcal / 100)) / 15)
            return (abs + dens) / 2
        }
        let cal = n.calcium_mg.map { min(1, $0 / calTarget) }
        switch (protCredit, cal) {
        case let (pr?, ca?): return (0.5 * pr + 0.5 * ca, true)
        case let (pr?, nil): return (pr, true)
        case let (nil, ca?): return (ca, true)
        default: return (cfg?.unknownCredit ?? 0.5, false)
        }
    }

    /// S14 — Real Food (ingredient integrity).
    private static func s14(_ p: Product) -> (Double, Bool) {
        let b = IngredientIntegrity.evaluate(ingredientsText: p.ingredientsText)
        return (b.fraction, b.hadData)
    }

    /// S15 — Fat Quality (ingredient-list fat sources).
    private static func s15(_ p: Product) -> (Double, Bool, String?) {
        let b = FatQuality.evaluate(product: p)
        return (b.fraction, b.hadData, b.hadData ? b.note : nil)
    }

    // MARK: S13 — beneficial micronutrient credit (positive-only)

    private static func s13(_ p: Product, rs: RulesetV4) -> (Double, Bool) {
        guard let cfg = rs.micronutrients else { return (0.35, false) }
        let n = p.nutrients
        let present: [String: Double?] = [
            "iron_mg": n.iron_mg, "potassium_mg": n.potassium_mg,
            "magnesium_mg": n.magnesium_mg, "zinc_mg": n.zinc_mg,
            "vitaminC_mg": n.vitaminC_mg, "calcium_mg": n.calcium_mg,
        ]
        var sum = 0.0
        var had = false
        for (key, dv) in cfg.dv {
            guard dv > 0, let v = present[key] ?? nil, v > 0 else { continue }
            had = true
            sum += min(cfg.capPerNutrient, v / dv)   // %DV per 100g, capped
        }
        // No micros reported → neutral, not a penalty; lowers Data Confidence.
        guard had else { return (cfg.unknownCredit, false) }
        let f = min(1.0, sum / cfg.target)
        // V5.2 dataFloor: a declared panel never scores below the unknown
        // credit — otherwise reporting calcium ranked milk under an identical
        // product that stayed silent.
        if cfg.dataFloor == true { return (max(cfg.unknownCredit, f), true) }
        return (f, true)
    }

    // MARK: Shared helpers

    /// Piecewise-linear through anchors. With 3 thresholds: f(t0)=1.0, f(t1)=0.60,
    /// f(t2)=0.30, f(t2·1.5)=0.0. With 4 thresholds (drinksServing): last value is
    /// the explicit zero point (Oasis: 2 / 8 / 16 / 30 g per serving).
    static func stepped(_ value: Double?, thresholds t: [Double],
                        unknownCredit: Double) -> (Double, Bool) {
        guard let v = value else { return (unknownCredit, false) }
        let anchors: [(Double, Double)]
        if t.count == 4 {
            anchors = [
                (t[0], 1.0),
                (t[1], 0.60),
                (t[2], 0.30),
                (t[3], 0.0),
            ]
        } else if t.count == 3 {
            anchors = [
                (t[0], 1.0),
                (t[1], 0.60),
                (t[2], 0.30),
                (t[2] * 1.5, 0.0),
            ]
        } else {
            return (unknownCredit, false)
        }
        if v <= anchors[0].0 { return (1.0, true) }
        if v >= anchors.last!.0 { return (0.0, true) }
        for i in 0..<(anchors.count - 1) {
            let (x0, y0) = anchors[i]
            let (x1, y1) = anchors[i + 1]
            if v <= x1 {
                let span = x1 - x0
                guard span > 0 else { return (y1, true) }
                let tFrac = (v - x0) / span
                return (y0 + (y1 - y0) * tFrac, true)
            }
        }
        return (0.0, true)
    }

    // MARK: - Overview generation payload

    struct OverviewMultiplierSource: Encodable, Equatable {
        let source: String       // "objective" | "goal" | "slider" | "preference"
        let selection: String
        let factor: Double
    }

    struct OverviewRuleInput: Encodable, Equatable {
        let rule: String
        let topic: String
        let weight: Double
        let fraction: Double
        let contribution: Double
        let multiplier: Double?
        /// Provenance of the final multiplier (pre-clamp factors). Empty/nil = none.
        let multiplierSources: [OverviewMultiplierSource]?
        let evidenceTier: String
        let driverKind: String

        init(rule: String, topic: String, weight: Double, fraction: Double,
             contribution: Double, multiplier: Double?,
             multiplierSources: [OverviewMultiplierSource]? = nil,
             evidenceTier: String, driverKind: String) {
            self.rule = rule
            self.topic = topic
            self.weight = weight
            self.fraction = fraction
            self.contribution = contribution
            self.multiplier = multiplier
            self.multiplierSources = multiplierSources
            self.evidenceTier = evidenceTier
            self.driverKind = driverKind
        }
    }

    struct OverviewContributorInput: Encodable, Equatable {
        let topic: String
        let contribution: Double
        let evidenceTier: String
        /// Potential loss = weight × (1 − fraction); used for negative ranking.
        var potentialLoss: Double? = nil
    }

    struct OverviewDeltaDriver: Encodable, Equatable {
        let topic: String
        let direction: String   // "up" | "down"
    }

    struct OverviewHardGate: Encodable, Equatable {
        let kind: String        // "dietConflict" | "avoidList"
        let detail: String
        let cappedTo: Int
        /// "full" | "partial" — partial means tapered (not slammed to minCap).
        let intensity: String
        let bindingCapId: String
        let shortLabel: String
    }

    struct OverviewFiredCap: Encodable, Equatable {
        let id: String
        let value: Int
        let shortLabel: String
        let kind: String
        let intensity: String?
    }

    /// Inputs for `/explain` and the deterministic template fallback.
    struct OverviewContext: Encodable, Equatable {
        let profileId: String
        let productName: String
        let objective: String
        let overall: Int
        let your: Int
        let band: String
        let confidence: Double
        let hasScoreableIngredientSignal: Bool
        let hasNutritionData: Bool
        let hasIngredientData: Bool
        let rules: [OverviewRuleInput]
        let topPositive: [OverviewContributorInput]
        let topNegative: [OverviewContributorInput]
        let nutrientLevels: [String]
        let deltaValue: Int
        let deltaDrivers: [OverviewDeltaDriver]
        let avoidMatches: [String]
        let detectedAdditives: [String]
        let novaGroup: Int?
        let hardGate: OverviewHardGate?
        let bindingCap: OverviewFiredCap?
        let firedCaps: [OverviewFiredCap]
        /// Overall health cap that limited the universal score (freeSugar / transFat / nns).
        let overallBindingCap: OverviewFiredCap?
        let overallFiredCaps: [OverviewFiredCap]
        let knownRuleIds: [String]
        /// Nonzero Your-Score nutrient nudge (build muscle / lose weight).
        let nutrientNudge: Int?
        let nutrientNudgeDriver: String?
    }

    /// Build the structured overview payload from the live v4 scoring path.
    static func overviewContext(for product: Product, profile: UserProfile,
                                ruleset rs: RulesetV4) -> OverviewContext? {
        var product = applyingInferredFVN(to: product)
        guard product.hasMinimumData else { return nil }
        let profileId = route(product, ruleset: rs)
        if profileId == "unsupported" || profileId == "unscored_sweetener" { return nil }
        guard let ruleList = rs.profiles[profileId] else { return nil }
        product = normalizedForRules(product, profileId: profileId, rs: rs)

        let multDetail = profile.personalizeScoring ? ruleMultiplierBreakdown(profile, rs: rs) : [:]
        let (evalResults, _) = evaluatedRules(
            profile: ruleList, profileId: profileId, product: product, rs: rs)
        let usable = activeWeightResults(evalResults)
        // S12's `dairy`/`dairyDense` variants (milk, yogurt, cheese) score
        // protein + calcium — fiber and FVN are structurally absent from dairy,
        // so the generic "protein and fiber" displayName would make the overview
        // (LLM or template) claim a fiber contribution the product cannot have.
        // Relabel S12 to "protein and calcium" for those profiles. Keyed off the
        // profile's rule variant (authoritative) rather than the result note,
        // which the S12 isolate discount can overwrite.
        // V5.3: the egg variant scores protein only → "protein".
        let s12Display: String? = {
            guard let v = ruleList.first(where: { $0.rule == "S12" })?.variant else { return nil }
            if v == "dairy" || v == "dairyDense" { return "protein and calcium" }
            if v == "egg" { return "protein" }
            if v == "grain" { return "fiber and protein" }
            return nil
        }()
        var rules: [OverviewRuleInput] = []
        for r in evalResults {
            guard let baseDisplay = rs.displayName(for: r.rule) else {
                print("overview: missing displayName for rule \(r.rule); excluded from prose payload")
                continue
            }
            let display = (r.rule == "S12" ? s12Display : nil) ?? baseDisplay
            let detail = multDetail[r.rule]
            let sources = detail?.factors.map {
                OverviewMultiplierSource(source: $0.source, selection: $0.selection, factor: $0.factor)
            }
            // Redistributed S14 (no ingredient list) keeps weight 0 in the prose table.
            let weight = usable.contains(where: { $0.rule == r.rule }) ? r.weight : 0
            rules.append(OverviewRuleInput(
                rule: r.rule,
                topic: display,
                weight: weight,
                fraction: r.fraction,
                contribution: weight * r.fraction,
                multiplier: detail.map(\.product),
                multiplierSources: sources,
                evidenceTier: r.hadData ? "data" : "unknown-tier",
                driverKind: rs.isMerit(r.rule) ? "merit" : "hygiene"
            ))
        }

        let totalW = usable.reduce(0) { $0 + $1.weight }
        let backed = usable.filter(\.hadData).reduce(0) { $0 + $1.weight }
        let confidence = adjustedConfidence(
            base: totalW > 0 ? backed / totalW : 0, product: product, results: usable)

        // Positives: merit rules only (never praise "hazard absent" hygiene rules).
        // Exclude S3/S4/S5 when the displayed nutrient badge is HIGH (V5.0.6).
        // Negatives: ranked by potential loss with materiality floor ≥ 2.0 pts.
        // A rule may appear in positives OR negatives, never both — keep the
        // side with the better (lower) rank; ties go to negatives (V5.0.4).
        func nutrientBadgeIsHigh(_ rule: String) -> Bool {
            let n = product.nutrients
            switch rule {
            case "S3": return n.sugar_g.map(NutrientLevels.sugar) == .high
            case "S4": return n.sodium_mg.map(NutrientLevels.sodium) == .high
            case "S5": return n.satFat_g.map(NutrientLevels.satFat) == .high
            default: return false
            }
        }
        let positiveRanked = rules
            .filter {
                $0.driverKind == "merit"
                    && $0.fraction >= 0.55
                    && !nutrientBadgeIsHigh($0.rule)
            }
            .sorted { $0.contribution > $1.contribution }

        let negativeRanked: [(OverviewRuleInput, Double)] = rules.compactMap { r in
            let m = profile.personalizeScoring ? (r.multiplier ?? 1.0) : 1.0
            let loss = r.weight * m * (1 - r.fraction)
            guard loss >= 2.0 else { return nil }
            return (r, loss)
        }
        .sorted { $0.1 > $1.1 }

        var posSide = Set<String>()
        var negSide = Set<String>()
        let posIndex = Dictionary(uniqueKeysWithValues:
            positiveRanked.enumerated().map { ($1.rule, $0) })
        let negIndex = Dictionary(uniqueKeysWithValues:
            negativeRanked.enumerated().map { ($1.0.rule, $0) })
        let allRules = Set(posIndex.keys).union(negIndex.keys)
        for rule in allRules {
            let pIdx = posIndex[rule]
            let nIdx = negIndex[rule]
            switch (pIdx, nIdx) {
            case (let p?, let n?):
                if p < n { posSide.insert(rule) }
                else { negSide.insert(rule) }   // tie → negative
            case (_?, nil): posSide.insert(rule)
            case (nil, _?): negSide.insert(rule)
            default: break
            }
        }

        let positives = positiveRanked
            .filter { posSide.contains($0.rule) }
            .prefix(3)
            .map { OverviewContributorInput(topic: $0.topic, contribution: $0.contribution,
                                          evidenceTier: $0.evidenceTier) }
        let negatives = negativeRanked
            .filter { negSide.contains($0.0.rule) }
            .prefix(3)
            .map { OverviewContributorInput(topic: $0.0.topic, contribution: $0.0.contribution,
                                          evidenceTier: $0.0.evidenceTier,
                                          potentialLoss: $0.1) }

        let baseMean: Double = {
            guard totalW > 0 else { return 0 }
            // Use full rule list contributions for mean (including unnamed rules).
            var earned = 0.0
            for pr in ruleList {
                let (f, _, _) = evaluate(pr.rule, variant: pr.variant, product: product, rs: rs,
                                         profileId: profileId)
                earned += pr.w * f
            }
            return earned / totalW
        }()

        let avoidMatches = avoidListHits(product, profile: profile, rs: rs)
        let activeRestrictions: [Restriction] = {
            if !product.restrictions.isEmpty { return product.restrictions }
            guard profile.autoFlagRestrictions else { return [] }
            return restrictionInputs(profile).compactMap { name in
                evalRestriction(name, product: product, ruleset: rs).map {
                    Restriction(type: $0.type, trigger: $0.trigger)
                }
            }
        }()

        // Preference caps for Your Score hardGate only — never mix overall
        // health caps into "also on your list" (honey freeSugar bug, V5.0.6).
        let prefFiredStored: [ScoreCap] = product.firedCaps ?? {
            let (fired, _, _) = applyCaps(
                weighted: 100,
                restrictions: activeRestrictions,
                avoidHits: avoidMatches,
                nutrients: product.nutrients,
                rs: rs
            )
            return fired
        }()
        let prefBinding = product.bindingCap

        let overallFiredPayload: [OverviewFiredCap] = {
            let fired = product.overallFiredCaps
                ?? applyBaseCaps(base: 100, product: product, rs: rs).fired
            return fired.map {
                OverviewFiredCap(id: $0.id, value: $0.value, shortLabel: $0.shortLabel,
                                 kind: $0.kind, intensity: $0.intensity)
            }
        }()
        let overallBindingPayload: OverviewFiredCap? = {
            let binding = product.overallBindingCap
                ?? applyBaseCaps(base: max(product.overallScore ?? 1, 1), product: product, rs: rs).binding
            return binding.map {
                OverviewFiredCap(id: $0.id, value: $0.value, shortLabel: $0.shortLabel,
                                 kind: $0.kind, intensity: $0.intensity)
            }
        }()

        let firedCapsPayload = prefFiredStored.map {
            OverviewFiredCap(id: $0.id, value: $0.value, shortLabel: $0.shortLabel,
                             kind: $0.kind, intensity: $0.intensity)
        }
        let bindingPayload = prefBinding.map {
            OverviewFiredCap(id: $0.id, value: $0.value, shortLabel: $0.shortLabel,
                             kind: $0.kind, intensity: $0.intensity)
        }

        let hardGate: OverviewHardGate? = {
            // Your Score preference binding only (dietConflict / avoidList).
            guard let b = prefBinding else { return nil }
            let intensity = b.intensity ?? "full"
            let others = prefFiredStored.filter { $0.id != b.id }.map(\.shortLabel)
            var detail: String
            if b.kind == "dietConflict" {
                if intensity == "partial", let sugar = product.nutrients.sugar_g {
                    detail = String(
                        format: "its %.0f g of sugar conflicts with your %@, which limits your score",
                        sugar, b.shortLabel)
                } else {
                    detail = "conflicts with your \(b.shortLabel), which caps Your Score at \(b.value)"
                }
            } else if b.kind == "avoidList" {
                detail = "contains \(b.shortLabel), which is on your avoid list and caps Your Score at \(b.value)"
            } else {
                detail = b.detail ?? "score capped at \(b.value)"
            }
            if !others.isEmpty {
                detail += " (also on your list: \(others.joined(separator: ", ")))"
            }
            return OverviewHardGate(
                kind: b.kind,
                detail: detail,
                cappedTo: b.value,
                intensity: intensity,
                bindingCapId: b.id,
                shortLabel: b.shortLabel
            )
        }()

        let deltaDrivers: [OverviewDeltaDriver] = {
            if let gate = hardGate {
                return [OverviewDeltaDriver(topic: gate.detail, direction: "down")]
            }
            guard profile.personalizeScoring else { return [] }
            var drivers: [OverviewDeltaDriver] = []
            let nudge = nutrientNudge(profile.objective, product.nutrients)
            if nudge != 0 {
                let topic: String
                switch profile.objective.lowercased() {
                case "lose weight":
                    topic = "slightly adjusted for calorie density given your weight-loss goal"
                case "build muscle":
                    topic = "slightly adjusted for protein density given your muscle-building goal"
                default:
                    topic = "slightly adjusted for your nutrition goal"
                }
                drivers.append(OverviewDeltaDriver(
                    topic: topic,
                    direction: nudge > 0 ? "up" : "down"
                ))
            }
            let scored = rules.compactMap { r -> (OverviewDeltaDriver, Double)? in
                let m = r.multiplier ?? 1
                guard abs(m - 1) > 0.01 else { return nil }
                let direction: String
                if r.fraction >= baseMean {
                    direction = m > 1 ? "up" : "down"
                } else {
                    direction = m > 1 ? "down" : "up"
                }
                let pressure = abs(m - 1) * r.weight * abs(r.fraction - baseMean)
                // Prefer preference-sourced phrasing when preference is among
                // the dominant factors on this rule (V5.0.6).
                let topic: String = {
                    let sources = r.multiplierSources ?? []
                    let prefs = sources.filter { $0.source == "preference" }
                    let prefStrength = prefs.map { abs($0.factor - 1) }.max() ?? 0
                    let otherStrength = sources
                        .filter { $0.source != "preference" }
                        .map { abs($0.factor - 1) }.max() ?? 0
                    if let top = prefs.max(by: { abs($0.factor - 1) < abs($1.factor - 1) }),
                       prefStrength + 1e-9 >= otherStrength {
                        return preferenceDriverPhrase(top.selection)
                    }
                    return r.topic
                }()
                return (OverviewDeltaDriver(topic: topic, direction: direction), pressure)
            }
            .sorted { $0.1 > $1.1 }
            drivers.append(contentsOf: scored.prefix(2).map(\.0))
            return Array(drivers.prefix(3))
        }()

        let nudgeVal = nutrientNudge(profile.objective, product.nutrients)
        let nudgeDriver: String? = {
            guard nudgeVal != 0 else { return nil }
            switch profile.objective.lowercased() {
            case "lose weight":
                return "slightly adjusted for calorie density given your weight-loss goal"
            case "build muscle":
                return "slightly adjusted for protein density given your muscle-building goal"
            default:
                return "slightly adjusted for your nutrition goal"
            }
        }()

        let additiveNames = product.additives.map(\.name)

        let overall = product.overallScore ?? 0
        let your = product.yourScore ?? overall
        return OverviewContext(
            profileId: profileId,
            productName: product.name,
            objective: profile.objective,
            overall: overall,
            your: your,
            band: rs.bandLabel(overall),
            confidence: confidence,
            hasScoreableIngredientSignal: product.hasScoreableIngredientSignal,
            hasNutritionData: product.hasNutritionData,
            hasIngredientData: product.hasIngredientData,
            rules: rules,
            topPositive: Array(positives),
            topNegative: Array(negatives),
            nutrientLevels: NutrientLevels.promptLines(product.nutrients),
            deltaValue: your - overall,
            deltaDrivers: deltaDrivers,
            avoidMatches: avoidMatches,
            detectedAdditives: additiveNames,
            novaGroup: product.hasKnownNova ? product.novaGroup : nil,
            hardGate: hardGate,
            bindingCap: bindingPayload,
            firedCaps: firedCapsPayload,
            overallBindingCap: overallBindingPayload,
            overallFiredCaps: overallFiredPayload,
            knownRuleIds: rs.allRuleIds,
            nutrientNudge: nudgeVal == 0 ? nil : nudgeVal,
            nutrientNudgeDriver: nudgeDriver
        )
    }

    /// Weight-backed rule evidence for a product under its routed profile:
    /// `confidence` = Σ(w where the rule had data) / Σw, and `maxUnknownWeight`
    /// is the heaviest rule that fell back to its unknown-tier default (0 when
    /// every rule had data). Nil when the product lacks minimum data, routes to
    /// unsupported/unscored, or the profile is missing from the ruleset.
    ///
    /// Callers apply their own thresholds: the provisional banner flags any
    /// unknown rule ≥ 10, while Top Rated eligibility tolerates systemic
    /// mid-weight unknowns (e.g. `dairyProcessing`, which no label can evidence)
    /// but not an unknown core driver.
    static func evidenceSummary(_ product: Product, ruleset rs: RulesetV4)
    -> (confidence: Double, maxUnknownWeight: Double)? {
        var product = applyingInferredFVN(to: product)
        guard product.hasMinimumData else { return nil }
        let profileId = route(product, ruleset: rs)
        if profileId == "unsupported" || profileId == "unscored_sweetener" { return nil }
        guard let ruleList = rs.profiles[profileId] else { return nil }
        product = normalizedForRules(product, profileId: profileId, rs: rs)
        var totalW = 0.0, backed = 0.0, maxUnknown = 0.0
        for pr in ruleList {
            let (_, had, _) = evaluate(pr.rule, variant: pr.variant, product: product, rs: rs,
                                       profileId: profileId)
            totalW += pr.w
            if had { backed += pr.w }
            else { maxUnknown = max(maxUnknown, pr.w) }
        }
        guard totalW > 0 else { return nil }
        return (backed / totalW, maxUnknown)
    }

    /// Engine confidence + unknown-tier weight gate for the provisional banner.
    /// Independent of personalization — only rule evidence matters.
    static func isProvisionalScore(_ product: Product, ruleset rs: RulesetV4) -> Bool {
        guard applyingInferredFVN(to: product).hasMinimumData else { return true }
        let routed = route(applyingInferredFVN(to: product), ruleset: rs)
        if routed == "unsupported" || routed == "unscored_sweetener" { return false }
        guard let summary = evidenceSummary(product, ruleset: rs) else { return true }
        return summary.confidence < 0.80 || summary.maxUnknownWeight >= 10
    }

    static func isProvisional(_ ctx: OverviewContext) -> Bool {
        if ctx.confidence < 0.80 { return true }
        return ctx.rules.contains { $0.weight >= 10 && $0.evidenceTier == "unknown-tier" }
    }
}

// MARK: - Debug score breakdown (DEBUG builds only)

#if DEBUG
extension ScoringEngineV4 {

    /// Full v5 score audit trail: router, per-rule fractions, multipliers,
    /// nutrient nudge, hard gates, and stored vs computed scores.
    /// (Swift type names remain `ScoringEngineV4` / `RulesetV4` for rename debt.)
    static func debugText(_ product: Product, for profile: UserProfile,
                          ruleset rs: RulesetV4) -> String {
        let fvnResolution = resolvedFVN(product)
        var product = applyingInferredFVN(to: product)
        let n = product.nutrients
        var lines: [String] = []

        func num(_ label: String, _ v: Double?) {
            lines.append("  \(label): \(v.map { String(format: "%.2f", $0) } ?? "—")")
        }

        lines.append("SCORING DEBUG — v5 rule engine")
        lines.append("Product: \(product.name) (\(product.id))")
        lines.append("Engine: \(engineVersion)")
        lines.append("Ruleset: \(rs.version)")
        lines.append("")

        lines.append("GATES")
        lines.append("  hasMinimumData: \(product.hasMinimumData)")
        lines.append("  hasNutritionData: \(product.hasNutritionData)")
        lines.append("  hasScoreableIngredientSignal: \(product.hasScoreableIngredientSignal)")
        let profileId = route(product, ruleset: rs)
        lines.append("  router → \(profileId)")
        if profileId == "unsupported" {
            lines.append("  outcome: unsupported (water / alcohol)")
            return lines.joined(separator: "\n")
        }
        if profileId == "unscored_sweetener" {
            lines.append("  outcome: unscored_sweetener")
            lines.append("")
            lines.append("AMONG SWEETENERS (relative quality — not a health score)")
            for note in sweetenerQualityNotes(product, ruleset: rs) {
                lines.append("  · \(note)")
            }
            if product.restrictions.isEmpty {
                lines.append("  restrictions: none")
            } else {
                lines.append("  restrictions: \(product.restrictions.map { "\($0.type) (\($0.trigger))" }.joined(separator: ", "))")
            }
            return lines.joined(separator: "\n")
        }
        guard product.hasMinimumData, let ruleList = rs.profiles[profileId] else {
            lines.append("  outcome: insufficientData")
            return lines.joined(separator: "\n")
        }
        product = normalizedForRules(product, profileId: profileId, rs: rs)
        lines.append("")

        lines.append("INPUTS (per 100g)")
        num("kcal", n.kcal)
        num("protein_g", n.protein_g)
        num("fiber_g", n.fiber_g)
        num("sugar_g", n.sugar_g)
        num("satFat_g", n.satFat_g)
        num("sodium_mg", n.sodium_mg)
        if let value = fvnResolution.value, let source = fvnResolution.inferredFrom {
            lines.append("  fvn: \(String(format: "%.0f", value)) (inferred: \(source))")
        } else {
            num("fvn", n.fvn)
        }
        lines.append("  nova_group: \(product.novaGroup)")
        lines.append("  categories: \((product.categories ?? []).joined(separator: ", "))")
        lines.append("")

        let (results, _) = evaluatedRules(profile: ruleList, profileId: profileId,
                                          product: product, rs: rs)
        let usable = activeWeightResults(results)
        let totalW = usable.reduce(0) { $0 + $1.weight }
        let earned = usable.reduce(0) { $0 + $1.weight * $1.fraction }
        let backed = usable.filter(\.hadData).reduce(0) { $0 + $1.weight }
        let overall = totalW > 0
            ? max(floorScore, Int((earned / totalW * 100).rounded()))
            : floorScore
        let rawConfidence = totalW > 0 ? backed / totalW : 0
        let confidence = adjustedConfidence(base: rawConfidence, product: product, results: usable)

        lines.append("RULES (profile \(profileId), Σw=\(String(format: "%.0f", totalW)))")
        for r in results {
            let inSum = usable.contains(where: { $0.rule == r.rule })
            let contrib = inSum ? r.weight * r.fraction : 0
            let data = r.hadData ? "data" : "unknown-tier"
            var line = "  · \(r.rule): w \(String(format: "%.0f", r.weight)) × f \(String(format: "%.3f", r.fraction)) = \(String(format: "%.2f", contrib)) (\(data))"
            if !inSum { line += " [redistributed]" }
            if let note = r.note { line += " — \(note)" }
            lines.append(line)
        }
        let s14 = IngredientIntegrity.evaluate(ingredientsText: product.ingredientsText)
        if s14.hadData {
            lines.append("  S14 breakdown: wholeFood \(String(format: "%.2f", s14.wholeFoodRatio)) · count \(String(format: "%.2f", s14.countScore)) · sweetener \(String(format: "%.2f", s14.sweetenerScore)) · isolate \(String(format: "%.2f", s14.isolateScore)) · n=\(s14.ingredientCount)")
            if !s14.sweetenerMatches.isEmpty {
                lines.append("  sweetener system: \(s14.sweetenerMatches.joined(separator: ", "))")
            }
        }
        let s15 = FatQuality.evaluate(product: product)
        if s15.hadData {
            lines.append("  \(s15.note)")
        } else if results.contains(where: { $0.rule == "S15" }) {
            lines.append("  S15 fatQuality: no data (weight redistributed)")
        }
        lines.append("  confidence: \(String(format: "%.1f%%", confidence * 100)) (raw \(String(format: "%.1f%%", rawConfidence * 100)))")
        let baseGate = applyBaseCaps(base: overall, product: product, rs: rs)
        let cappedOverall = baseGate.capped
        lines.append("  overall (base): \(overall)  [raw \(String(format: "%.2f", earned / max(totalW, 1) * 100))]")
        for c in baseGate.fired {
            let mark = baseGate.binding?.id == c.id ? " [binding]" : ""
            lines.append("  overall cap \(c.id): \(overall) → \(min(overall, c.value))\(mark)")
        }
        if baseGate.binding != nil {
            lines.append("  overall (capped): \(cappedOverall)")
        }
        lines.append("  band: \(rs.bandLabel(cappedOverall))")
        lines.append("")

        lines.append("PROFILE")
        lines.append("  objective: \(profile.objective)")
        lines.append("  personalizeScoring: \(profile.personalizeScoring)")
        lines.append("  autoFlagRestrictions: \(profile.autoFlagRestrictions)")
        if let goals = profile.healthGoals, !goals.isEmpty {
            lines.append("  healthGoals: \(goals.joined(separator: ", "))")
        }
        if let diet = profile.dietPattern { lines.append("  dietPattern: \(diet)") }
        if let avoid = profile.avoidList, !avoid.isEmpty {
            lines.append("  avoidList: \(avoid.joined(separator: ", "))")
        }
        lines.append("  restrictions: \(profile.restrictions.isEmpty ? "none" : profile.restrictions.joined(separator: ", "))")
        lines.append("")

        let restrictions = profile.autoFlagRestrictions
            ? restrictionInputs(profile).compactMap { name in
                evalRestriction(name, product: product, ruleset: rs).map {
                    Restriction(type: $0.type, trigger: $0.trigger)
                }
              }
            : []
        if !restrictions.isEmpty {
            lines.append("  active restrictions: \(restrictions.map { "\($0.type) (\($0.trigger))" }.joined(separator: ", "))")
        }

        guard profile.personalizeScoring else {
            lines.append("PERSONALIZATION OFF → yourScore = overall (\(overall))")
            lines.append("  stored overallScore: \(product.overallScore.map(String.init) ?? "—")")
            lines.append("  stored yourScore: \(product.yourScore.map(String.init) ?? "—")")
            return lines.joined(separator: "\n")
        }

        let multDetail = ruleMultiplierBreakdown(profile, rs: rs)
        let mult = multDetail.mapValues(\.product)
        if !multDetail.isEmpty {
            lines.append("MULTIPLIERS")
            for (rule, detail) in multDetail.sorted(by: { $0.key < $1.key })
            where abs(detail.product - 1) > 0.001 {
                let parts = detail.factors.map {
                    "×\(String(format: "%.2f", $0.factor)) (\($0.source))"
                }.joined(separator: " ")
                lines.append("  · \(rule): \(parts) → ×\(String(format: "%.2f", detail.product))")
            }
            lines.append("")
        }
        if !profile.preferences.isEmpty {
            lines.append("PREFERENCES: \(profile.preferences.joined(separator: ", "))")
            lines.append("  organic chip: \(showsOrganicChip(product: product, profile: profile) ? "yes" : "no")")
            lines.append("")
        }

        var yEarned = 0.0, yTotal = 0.0
        lines.append("YOUR SCORE — Σ(w·m·f) / Σ(w·m)")
        for r in usable {
            let m = mult[r.rule] ?? 1.0
            let contrib = r.weight * m * r.fraction
            yEarned += contrib
            yTotal += r.weight * m
            if abs(m - 1) > 0.001 {
                lines.append("  · \(r.rule): w \(String(format: "%.0f", r.weight)) × m \(String(format: "%.2f", m)) × f \(String(format: "%.3f", r.fraction)) = \(String(format: "%.2f", contrib))")
            }
        }
        var your = yTotal > 0 ? max(floorScore, Int((yEarned / yTotal * 100).rounded())) : overall
        lines.append("  weighted raw: \(String(format: "%.2f", yEarned / max(yTotal, 1) * 100)) → \(your)")

        let nudge = nutrientNudge(profile.objective, n)
        if nudge != 0 {
            your = max(floorScore, min(100, your + nudge))
            lines.append("  nutrient nudge (\(profile.objective)): \(nudge > 0 ? "+" : "")\(nudge) → \(your)")
        }

        let avoidHits = avoidListHits(product, profile: profile, rs: rs)
        let (fired, binding, capped) = applyCaps(
            weighted: your, restrictions: restrictions, avoidHits: avoidHits,
            nutrients: product.nutrients, rs: rs)
        for c in fired {
            lines.append("  fired cap \(c.id) (\(c.shortLabel)): ≤\(c.value) [\(c.intensity ?? "full")]")
        }
        if let b = binding {
            lines.append("  bindingCap: \(b.id) ≤\(b.value) → \(capped)")
        } else if !fired.isEmpty {
            lines.append("  caps fired but did not bind (weighted \(your) ≤ effective \(fired.map(\.value).min()!))")
        }
        your = capped

        lines.append("  computed yourScore: \(your)")
        lines.append("  stored overallScore: \(product.overallScore.map(String.init) ?? "—")")
        lines.append("  stored yourScore: \(product.yourScore.map(String.init) ?? "—")")
        if let reason = product.overview {
            lines.append("  overview: \(reason.text)")
        }

        return lines.joined(separator: "\n")
    }
}
#endif
