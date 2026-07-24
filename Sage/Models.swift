import Foundation

// MARK: - Domain models

enum RiskLevel: String, Codable { case low, moderate, high, unrated }

struct ProductAdditive: Identifiable, Hashable, Codable {
    var id = UUID()
    let name: String
    let risk: RiskLevel
    /// One-line summary from the knowledge base (or legacy note).
    var note: String? = nil
    /// Normalized E-number ("e452") — scoring v4 looks tiers up by code.
    /// Optional for back-compat with snapshots saved before Phase B.
    var code: String? = nil
    /// Tier from AdditiveDetector when available; drives S1 and v3 additive penalties.
    var tier: AdditiveTier? = nil
    /// Subtype / alias codes merged into this parent (e.g. ["E452i", "E452vi"]).
    var detectedAs: [String]? = nil
}

struct Restriction: Identifiable, Hashable, Codable {
    var id = UUID()
    let type: String
    let trigger: String
}

/// A personalization ceiling that can fire (and optionally bind) on Your Score.
struct ScoreCap: Hashable, Codable, Equatable {
    /// Stable id: "dietConflictCap" | "avoidListCap" | "seedOilCap"
    let id: String
    let value: Int
    /// Chip label fragment, e.g. "low-sugar diet" / "seed oils".
    let shortLabel: String
    /// "dietConflict" | "avoidList"
    let kind: String
    /// For diet tapers: "full" (at minCap) | "partial" (between start/end).
    let intensity: String?
    let detail: String?
}

struct Nutrients: Hashable, Codable {
    var sugar_g: Double?
    var sodium_mg: Double?
    var satFat_g: Double?
    var fiber_g: Double?
    var protein_g: Double?
    var calcium_mg: Double?
    /// Energy in kcal per 100g (drives protein-density + calorie features in scoring v2).
    var kcal: Double? = nil
    /// Fruit/veg/nuts estimate 0–100 from ingredients (Nutri-Score field); discounts
    /// natural fruit/veg sugar and rewards whole-food content. Optional for back-compat.
    var fvn: Double? = nil
    /// Added sugars per 100g — mostly US labels; scoring v4's S3 prefers it and
    /// falls back to fvn-discounted total sugars. Optional for back-compat.
    var addedSugar_g: Double? = nil
    /// Trans fat per 100g/ml. Card / flag requires strictly > 0 (nil or 0 → no flag).
    var transFat_g: Double? = nil
    // Beneficial micronutrients per 100g (mg) — drive scoring v4's S13 credit
    // and the Iron/Potassium breakdown rows. Optional for back-compat; most
    // products report none, in which case S13 falls back to a neutral credit.
    var iron_mg: Double? = nil
    var potassium_mg: Double? = nil
    var magnesium_mg: Double? = nil
    var zinc_mg: Double? = nil
    var vitaminC_mg: Double? = nil
}

/// One parsed ingredient with its declared or estimated recipe share.
/// Drives the v4 hero-ingredient rule (S10 — "the 2% almond problem").
struct IngredientShare: Hashable, Codable {
    /// Normalized OFF id without the language prefix, e.g. "oats".
    let name: String
    /// Declared on the pack (high trust).
    let percent: Double?
    /// OFF's heuristic estimate (v4 rules trust it at 75%).
    let percentEstimate: Double?
}

struct DeltaReason: Hashable, Codable {
    enum Tone: String, Codable { case positive, negative }
    let tone: Tone
    let text: String
}

/// Stored overview paragraph shown in the OVERVIEW section.
typealias ProductOverview = DeltaReason

/// Whether Sage assigned a 0–100 health score or declined to score.
enum ProductScoreState: Hashable, Codable, Equatable {
    case scored
    /// Sage withheld a health score. `reasonKey` is stable for UI/copy (e.g. "sweetener").
    case unscored(reasonKey: String)

    var isUnscored: Bool {
        if case .unscored = self { return true }
        return false
    }

    var reasonKey: String? {
        if case .unscored(let key) = self { return key }
        return nil
    }
}

struct Product: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let brand: String
    let size: String
    let glyph: String
    // Scores and their explanations are filled in by the ScoringEngine, so they're mutable.
    /// Nil when `scoreState` is unscored — never display a sentinel 0.
    var overallScore: Int?
    var yourScore: Int?
    /// Scored vs declined-to-score. Nil / absent in legacy snapshots → treated as scored.
    var scoreState: ProductScoreState? = nil
    /// LLM- or template-generated product overview (formerly deltaReason).
    var overview: ProductOverview?
    /// When true, stored overview is stale and should regenerate on next open.
    var overviewStale: Bool? = nil
    let nutriGrade: String
    let novaGroup: Int
    var nutrients: Nutrients
    var bonuses: [String]
    /// Derived at ingest: true only when `nutrients.transFat_g > 0` (strict).
    let transFats: Bool
    let caffeine_mg: Double?
    let sweeteners: [String]
    let seedOils: Bool
    let additives: [ProductAdditive]
    var restrictions: [Restriction]
    /// Preference caps (diet/avoid) whose conditions were met for Your Score.
    var firedCaps: [ScoreCap]? = nil
    /// Tightest preference cap that actually limited Your Score. Nil if none bind.
    var bindingCap: ScoreCap? = nil
    /// Health overall caps (freeSugar / transFat / nns) that fired. Separate from Your Score.
    var overallFiredCaps: [ScoreCap]? = nil
    /// Overall-score binding health cap, if it actually limited Overall.
    var overallBindingCap: ScoreCap? = nil
    /// Normalized dietary signals from Open Food Facts (e.g. "non-vegan", "gluten",
    /// "milk"), used by the ScoringEngine to flag profile restrictions. Optional for
    /// backward-compatible decoding of older snapshots.
    var dietFlags: [String]? = nil
    /// Normalized Open Food Facts allergen tags (e.g. "milk", "peanuts"), used for
    /// deterministic allergen matching. Optional for backward-compatible decoding.
    var allergenTags: [String]? = nil
    /// Raw ingredient text from Open Food Facts, used as a fallback for allergen
    /// keyword matching. Optional for backward-compatible decoding.
    var ingredientsText: String? = nil
    /// Product photo URL for detail (backend `/images/{barcode}` or OFF front).
    /// nil = no image, a first-class state rendered as the glyph placeholder.
    /// Optional for backward-compatible decoding of older snapshots.
    var imageURL: String? = nil
    /// Smaller list/grid URL. Optional; UI falls back to `imageURL`.
    var imageThumbURL: String? = nil
    /// True when the source image is too small / soft to show or process.
    var imageIsLowQuality: Bool? = nil
    /// Backend image provenance: `"kroger"` | `"off"`. Nil on legacy snapshots.
    var imageSource: String? = nil
    /// True when the resolved shot is front-of-pack.
    var imageIsFrontImage: Bool? = nil

    // MARK: Scoring-v4 data foundation (SCORING_V4.md §2) — all optional so
    // snapshots saved before Phase A keep decoding.

    /// Normalized label/certification tags (e.g. "organic", "fair-trade").
    /// Tier-1 signals: absence means "not claimed", never "unknown".
    var labels: [String]? = nil
    /// Normalized packaging materials (e.g. "glass", "pet", "aluminium").
    var packagingMaterials: [String]? = nil
    /// Normalized origin tags (e.g. "united-kingdom").
    var origins: [String]? = nil
    /// Parsed ingredients with recipe shares (S10 hero-ingredient rule).
    var ingredientShares: [IngredientShare]? = nil
    /// Environmental grade "a"–"e" (Eco-Score); nil when unknown/not applicable.
    var ecoGrade: String? = nil
    /// Raw serving size text (free-form; per-100g stays primary in scoring).
    var servingSize: String? = nil
    /// OFF's own 0–1 completeness estimate for this record.
    var completeness: Double? = nil
    /// When the OFF record last changed (staleness display: "updated X ago").
    var lastModified: Date? = nil
    /// Markets the product is sold in (sibling-inheritance guard, v4.1).
    var countries: [String]? = nil
    /// Normalized category tags (e.g. "beverages", "salty-snacks") — drives
    /// the v4 category router. Optional for back-compat.
    var categories: [String]? = nil
    /// True when AdditiveDetector suspects OFF under-counted additives.
    var additiveUndercountSuspected: Bool? = nil
    /// True when no ingredient text was available to verify additive detection.
    var additiveIngredientTextMissing: Bool? = nil
    /// Backend data provenance from the Worker's `_source` field: "usda" or
    /// "off+usda" when USDA supplied the nutrition table, nil for pure OFF.
    /// Dev/observability only — surfaced in the DEBUG score breakdown.
    var dataSource: String? = nil
}

// MARK: - Data confidence (SCORING_V4.md §3.2–3.3)

enum DataConfidence: String, Codable {
    case high, medium, low
}

extension Product {
    /// True when Sage declined a 0–100 health score for this product.
    var isUnscored: Bool { scoreState?.isUnscored == true }

    /// Stable reason key when unscored (e.g. "sweetener"); nil when scored.
    var unscoredReasonKey: String? { scoreState?.reasonKey }

    /// Prefer glyph / user-scan photo over a soft OFF community shot.
    var prefersGlyphOverRemoteImage: Bool {
        imageIsLowQuality == true && (imageSource == "off" || imageSource == nil)
    }

    /// List/grid image — prefers thumb; nil when missing or soft OFF (glyph fallback).
    var listImageURL: String? {
        guard !prefersGlyphOverRemoteImage else { return nil }
        return imageThumbURL ?? imageURL
    }

    /// Detail-screen image — nil when missing or soft OFF (glyph / user photo fallback).
    var detailImageURL: String? {
        guard !prefersGlyphOverRemoteImage else { return nil }
        return imageURL
    }

    /// Run on-device cutout processing for this product's remote photo.
    var shouldProcessCutout: Bool {
        !prefersGlyphOverRemoteImage && (listImageURL != nil || detailImageURL != nil)
    }

    var hasIngredientData: Bool {
        (ingredientsText?.isEmpty == false) || !(ingredientShares ?? []).isEmpty
    }

    /// A real nutrition table: at least three of the six core per-100g fields
    /// present (not a single stray macro like protein alone).
    var hasNutritionData: Bool {
        let n = nutrients
        let core: [Double?] = [n.kcal, n.sugar_g, n.satFat_g, n.sodium_mg, n.protein_g, n.fiber_g]
        return core.compactMap { $0 }.count >= 3
    }

    /// Known NOVA group (1–4) from Open Food Facts.
    var hasKnownNova: Bool { (1...4).contains(novaGroup) }

    /// Ingredient-side signal strong enough to score without a nutrition table:
    /// known processing level or at least one AdditiveDetector hit.
    var hasScoreableIngredientSignal: Bool {
        hasKnownNova || !additives.isEmpty
    }

    /// Scoreable only with a real nutrition table OR a scoreable ingredient signal.
    /// Ingredient text alone is never sufficient.
    var hasMinimumData: Bool { hasNutritionData || hasScoreableIngredientSignal }

    /// Trans-fat warning card: requires a strictly positive amount (nil/0 → hide).
    var showsTransFatFlag: Bool {
        if let g = nutrients.transFat_g { return g > 0 }
        return transFats
    }

    /// Provisional Phase-A confidence: a presence checklist over the signals
    /// scoring uses. Phase B replaces this with the rule-weight-backed version
    /// once the v4 engine lands; thresholds (0.8 / 0.5) already match the spec.
    var dataConfidenceScore: Double {
        let n = nutrients
        let core: [Double?] = [n.kcal, n.sugar_g, n.satFat_g, n.sodium_mg, n.protein_g, n.fiber_g]
        let nutritionFraction = Double(core.filter { $0 != nil }.count) / Double(core.count)

        var score = 0.0
        if hasIngredientData { score += 0.30 }
        score += 0.30 * nutritionFraction
        if (1...4).contains(novaGroup) { score += 0.15 }
        if !(packagingMaterials ?? []).isEmpty { score += 0.15 }
        if let g = ecoGrade, ("a"..."e").contains(g) { score += 0.05 }
        if !(origins ?? []).isEmpty { score += 0.05 }
        if additiveUndercountSuspected == true { score -= 0.20 }
        return max(0, score)
    }

    var dataConfidence: DataConfidence {
        let s = dataConfidenceScore
        if additiveUndercountSuspected == true { return s >= 0.8 ? .medium : .low }
        if s >= 0.8 { return .high }
        if s >= 0.5 { return .medium }
        return .low
    }
}

struct HistoryEntry: Identifiable, Hashable {
    let id = UUID()
    let productId: String
    let when: String
    let dateLabel: String
    let scannedAt: Date

    var day: String { dateLabel.components(separatedBy: " · ").first ?? "" }
    var time: String { dateLabel.components(separatedBy: " · ").last ?? "" }

    /// Relative scan time for list subtitles, e.g. "Scanned 4 days ago".
    static func scannedAgoLabel(since date: Date, now: Date = .now) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 3600 {
            let minutes = max(1, Int(elapsed / 60))
            let unit = minutes == 1 ? "minute" : "minutes"
            return "Scanned \(minutes) \(unit) ago"
        }
        if elapsed < 86_400 {
            let hours = Int(elapsed / 3600)
            let unit = hours == 1 ? "hour" : "hours"
            return "Scanned \(hours) \(unit) ago"
        }
        let days = Int(elapsed / 86_400)
        let unit = days == 1 ? "day" : "days"
        return "Scanned \(days) \(unit) ago"
    }
}

struct UserProfile: Codable {
    var name: String
    var handle: String
    var age: Int
    var sex: String
    var dob: String
    var heightIn: Int
    var weightLb: Int
    var goalWeightLb: Int
    var dailyStepGoal: Int
    var objective: String
    var restrictions: [String]
    var preferences: [String]
    /// Optional for backward-compatible decoding of profiles saved before allergens existed.
    var allergies: [String]? = nil
    var unitSystem: String
    var subscriptionStatus: String
    var subscriptionDaysLeft: Int
    var goalsCalories: Int
    var goalsProtein: Int
    var goalsCarbs: Int
    var goalsFat: Int
    var appearance: String
    var badgeCelebrations: Bool
    var liveActivity: Bool
    var autoFlagRestrictions: Bool
    var saveScansToHistory: Bool
    var personalizeScoring: Bool
    var appleHealth: Bool

    // MARK: Scoring-v4 personalization inputs (SCORING_V4.md §7.1)
    // All discrete + optional so ScoreClass cardinality stays small and older
    // profiles decode unchanged. nil is treated as the neutral default.

    /// Multi-select health goals: "blood sugar", "heart", "gut health",
    /// "pregnancy", "young child".
    var healthGoals: [String]? = nil
    /// Single diet pattern: "vegan", "vegetarian", "low-sodium", "keto", "none".
    var dietPattern: String? = nil
    /// Fixed-vocabulary ingredients to avoid (caps Your Score when present).
    var avoidList: [String]? = nil
    /// Priority sliders, 0 = de-emphasize · 1 = balanced (default) · 2 = emphasize.
    var sliderCleanIngredients: Int? = nil
    var sliderNutrition: Int? = nil
    var sliderEnvironment: Int? = nil
    var sliderAnimalWelfare: Int? = nil
}
