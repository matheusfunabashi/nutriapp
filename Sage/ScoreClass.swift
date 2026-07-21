import Foundation
import CryptoKit

/// The minimal projection of a user profile that actually affects the personalized
/// score + explanation. Two users with the same `ScoreClass` get the same
/// explanation for the same product, so its `hash` is the shared-cache bucket key
/// the app sends to the backend (`exp:<version>:<barcode>:<classHash>`).
///
/// Deliberately excludes identity, body metrics, and **allergies** (those are
/// matched deterministically and never enter the LLM prompt), which keeps the
/// number of distinct buckets — and LLM calls — small.
struct ScoreClass: Equatable {
    let objective: String
    let preferences: [String]     // canonicalized: lowercased, deduped, sorted
    let restrictions: [String]    // scoring-relevant only, canonicalized
    let goals: [String]           // v4 health goals, canonicalized
    let dietPattern: String       // v4 single diet pattern ("" when none)
    let avoidList: [String]       // v4 avoid-list, canonicalized
    let sliders: String           // v4 priority sliders as a compact signature
    let personalized: Bool
    let autoFlag: Bool

    init(_ p: UserProfile) {
        objective = p.objective.lowercased()
        preferences = Self.canon(p.preferences)
        restrictions = Self.canon((p.restrictions).filter {
            Self.scoringRestrictions.contains($0.lowercased())
        })
        goals = Self.canon(p.healthGoals ?? [])
        dietPattern = (p.dietPattern ?? "").lowercased()
        avoidList = Self.canon(p.avoidList ?? [])
        // Only non-default (≠ balanced/1) sliders change the score → the bucket.
        sliders = [("c", p.sliderCleanIngredients), ("n", p.sliderNutrition)]
            .compactMap { key, v in (v != nil && v != 1) ? "\(key)\(v!)" : nil }
            .joined(separator: "")
        personalized = p.personalizeScoring
        autoFlag = p.autoFlagRestrictions
    }

    /// Restrictions the ScoringEngine actually acts on (others, e.g. pescatarian,
    /// don't change the score, so they don't change the bucket).
    private static let scoringRestrictions: Set<String> = [
        "vegan", "vegetarian", "low-sugar diet", "low-sodium diet",
        "gluten-free", "dairy-free",
    ]

    private static func canon(_ arr: [String]) -> [String] {
        Array(Set(arr.map { $0.lowercased() })).sorted()
    }

    /// Stable, order-independent string form.
    var signature: String {
        "o=\(objective)" +
        "|p=\(preferences.joined(separator: ","))" +
        "|r=\(restrictions.joined(separator: ","))" +
        "|g=\(goals.joined(separator: ","))" +
        "|d=\(dietPattern)" +
        "|av=\(avoidList.joined(separator: ","))" +
        "|s=\(sliders)" +
        "|pz=\(personalized ? 1 : 0)|af=\(autoFlag ? 1 : 0)"
    }

    /// Short, opaque, PII-free hash used as the cache-bucket key (16 hex chars).
    var hash: String {
        SHA256.hash(data: Data(signature.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
