import Foundation

#if DEBUG
/// Debug-only capture of the exact drinks scorer inputs for a live scan.
/// Not used in scoring. Enable by calling `DrinksScanDebug.log(...)` after map/score.
enum DrinksScanDebug {

    struct Snapshot {
        var barcode: String
        var productName: String
        var rawQuantity: String
        var rawServingSize: String?
        var sugarPer100g: Double?
        var addedSugarPer100g: Double?
        var caffeinePer100Mg: Double?
        var nutrimentKeysPresent: [String]
        var categories: [String]
        var effectiveServingMl: Double
        var estimatedServing: Bool
        var usedWholeContainer: Bool
        var sugarPerServingG: Double?
        var caffeinePerServingMg: Double?
        var caffeineEstimated: Bool
        var profileId: String
        var sugarCurveNote: String
        var rules: [(id: String, weight: Double, fraction: Double)]
        var sugarCap: Int
        var caffeineCap: Int
        var sweetenerCap: Int
        var bindingCapId: String?
        var weightedScore: Int
        var stackingDrag: Int
        var finalScore: Int
    }

    /// Last live-scan snapshot (tests and console).
    static var last: Snapshot?

    struct RerailEvent: Equatable {
        let productId: String
        let productName: String
        let attempted: String
        let used: String
        let thresholdsFired: [String]
    }

    /// Last routing plausibility rerail (Fix 4).
    static var lastRerail: RerailEvent?

    static func logRerail(
        productId: String,
        productName: String,
        attempted: String,
        used: String,
        thresholdsFired: [String]
    ) {
        let event = RerailEvent(
            productId: productId,
            productName: productName,
            attempted: attempted,
            used: used,
            thresholdsFired: thresholdsFired
        )
        lastRerail = event
        print("=== ROUTING RERAIL ===")
        print("product=\(productName) id=\(productId)")
        print("attempted=\(attempted) → used=\(used)")
        print("thresholdsFired=\(thresholdsFired.joined(separator: "; "))")
    }

    static func logMappedProduct(_ p: Product, barcode: String, nutrimentKeys: [String] = []) {
        // Partial — filled further by `logScore`.
        last = Snapshot(
            barcode: barcode,
            productName: p.name,
            rawQuantity: p.size,
            rawServingSize: p.servingSize,
            sugarPer100g: p.nutrients.sugar_g,
            addedSugarPer100g: p.nutrients.addedSugar_g,
            caffeinePer100Mg: p.caffeine_mg,
            nutrimentKeysPresent: nutrimentKeys,
            categories: p.categories ?? [],
            effectiveServingMl: 0,
            estimatedServing: false,
            usedWholeContainer: false,
            sugarPerServingG: nil,
            caffeinePerServingMg: nil,
            caffeineEstimated: false,
            profileId: "",
            sugarCurveNote: "",
            rules: [],
            sugarCap: 100,
            caffeineCap: 100,
            sweetenerCap: 100,
            bindingCapId: nil,
            weightedScore: 0,
            stackingDrag: 0,
            finalScore: 0
        )
    }

    static func logScore(product: Product, profileId: String, bd: DrinksScoreBreakdown?) {
        guard var snap = last, snap.barcode == product.id || snap.productName == product.name else {
            // Still emit a self-contained snapshot when map wasn't logged.
            var s = Snapshot(
                barcode: product.id,
                productName: product.name,
                rawQuantity: product.size,
                rawServingSize: product.servingSize,
                sugarPer100g: product.nutrients.sugar_g,
                addedSugarPer100g: product.nutrients.addedSugar_g,
                caffeinePer100Mg: product.caffeine_mg,
                nutrimentKeysPresent: [],
                categories: product.categories ?? [],
                effectiveServingMl: bd?.effectiveServingMl ?? 0,
                estimatedServing: bd?.estimatedServing ?? false,
                usedWholeContainer: false,
                sugarPerServingG: bd?.sugarPerServingG,
                caffeinePerServingMg: bd?.caffeinePerServingMg,
                caffeineEstimated: bd?.caffeineEstimated ?? false,
                profileId: profileId,
                sugarCurveNote: sugarCurveNote(bd: bd, profileId: profileId),
                rules: (bd?.rules ?? []).map { ($0.rule, $0.weight, $0.fraction) },
                sugarCap: bd?.sugarCap ?? 100,
                caffeineCap: bd?.caffeineCap ?? 100,
                sweetenerCap: bd?.sweetenerCap ?? 100,
                bindingCapId: bd?.bindingCapId,
                weightedScore: bd?.weightedScore ?? 0,
                stackingDrag: bd?.stackingDrag ?? 0,
                finalScore: bd?.finalScore ?? product.overallScore ?? 0
            )
            if let bd {
                let es = DrinksScoring.effectiveServing(for: product)
                s.usedWholeContainer = es.usedWholeContainer
                s.estimatedServing = bd.estimatedServing
            }
            last = s
            print(format(s))
            return
        }
        if let bd {
            let es = DrinksScoring.effectiveServing(for: product)
            snap.effectiveServingMl = bd.effectiveServingMl
            snap.estimatedServing = bd.estimatedServing
            snap.usedWholeContainer = es.usedWholeContainer
            snap.sugarPerServingG = bd.sugarPerServingG
            snap.caffeinePerServingMg = bd.caffeinePerServingMg
            snap.caffeineEstimated = bd.caffeineEstimated
            snap.sugarCap = bd.sugarCap
            snap.caffeineCap = bd.caffeineCap
            snap.sweetenerCap = bd.sweetenerCap
            snap.bindingCapId = bd.bindingCapId
            snap.weightedScore = bd.weightedScore
            snap.stackingDrag = bd.stackingDrag
            snap.finalScore = bd.finalScore
            snap.rules = bd.rules.map { ($0.rule, $0.weight, $0.fraction) }
            snap.sugarCurveNote = sugarCurveNote(bd: bd, profileId: profileId)
        }
        snap.profileId = profileId
        snap.sugarPer100g = product.nutrients.sugar_g
        snap.addedSugarPer100g = product.nutrients.addedSugar_g
        snap.caffeinePer100Mg = product.caffeine_mg
        snap.rawQuantity = product.size
        snap.rawServingSize = product.servingSize
        last = snap
        print(format(snap))
    }

    private static func sugarCurveNote(bd: DrinksScoreBreakdown?, profileId: String) -> String {
        guard let g = bd?.sugarPerServingG else { return "sugar missing" }
        if profileId == "juice_100" {
            if g <= 6 { return "juice S3 ≤6 → 1.0" }
            if g >= 18 { return "juice S3 ≥18 → 0" }
            return String(format: "juice S3 mid (%.1fg)", g)
        }
        if g <= 2 { return "drinks S3 ≤2 → 1.0" }
        if g >= 30 { return "drinks S3 ≥30 → 0" }
        return String(format: "drinks S3 mid (%.1fg)", g)
    }

    static func format(_ s: Snapshot) -> String {
        var lines: [String] = []
        lines.append("=== DRINKS SCAN DEBUG ===")
        lines.append("barcode=\(s.barcode) name=\(s.productName)")
        lines.append("raw quantity=\(s.rawQuantity) serving_size=\(s.rawServingSize ?? "nil")")
        lines.append(String(format: "per100 sugar=%@ added=%@ caffeine_mg=%@",
                            fmt(s.sugarPer100g), fmt(s.addedSugarPer100g), fmt(s.caffeinePer100Mg)))
        if !s.nutrimentKeysPresent.isEmpty {
            lines.append("nutrimentKeys=\(s.nutrimentKeysPresent.joined(separator: ","))")
        }
        lines.append("categories=\(s.categories.prefix(8).joined(separator: ","))")
        lines.append(String(format: "effectiveServing=%.1fml wholeContainer=%@ estimated=%@",
                            s.effectiveServingMl,
                            String(s.usedWholeContainer),
                            String(s.estimatedServing)))
        lines.append(String(format: "perServing sugarG=%@ cafMg=%@ cafEst=%@",
                            fmt(s.sugarPerServingG), fmt(s.caffeinePerServingMg),
                            String(s.caffeineEstimated)))
        lines.append("profile=\(s.profileId) sugarCurve=\(s.sugarCurveNote)")
        for r in s.rules {
            lines.append(String(format: "  %@ w=%.1f f=%.3f contrib=%.1f",
                                r.id, r.weight, r.fraction, r.weight * r.fraction))
        }
        lines.append("caps sugar=\(s.sugarCap) caf=\(s.caffeineCap) sweet=\(s.sweetenerCap) bind=\(s.bindingCapId ?? "nil")")
        lines.append("weighted=\(s.weightedScore) drag=\(s.stackingDrag) final=\(s.finalScore)")
        return lines.joined(separator: "\n")
    }

    private static func fmt(_ v: Double?) -> String {
        guard let v else { return "nil" }
        return String(format: "%.3f", v)
    }
}
#endif
