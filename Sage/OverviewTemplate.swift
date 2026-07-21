import Foundation

// MARK: - Deterministic Overview fallback (mirrors backend template)

enum OverviewTemplate {

    /// Safe overview text when the LLM is unavailable or fails validation.
    static func generate(_ ctx: ScoringEngineV4.OverviewContext) -> String {
        var parts: [String] = []

        let limited = !ctx.hasScoreableIngredientSignal || ctx.confidence < 0.80
            || ctx.rules.contains { $0.weight >= 10 && $0.evidenceTier == "unknown-tier" }
        if limited {
            parts.append("Label data is limited, so treat this score as provisional.")
        }

        if let overallCap = ctx.overallBindingCap,
           let lead = overallCapLead(overallCap) {
            parts.append(lead)
            let negatives = ctx.topNegative.map(\.topic)
            if !negatives.isEmpty {
                let phrases = negatives.map { negativePhrase($0, ctx: ctx) }
                parts.append("Secondary factors include \(englishList(phrases)).")
            }
        } else {
            let positives = ctx.topPositive.map(\.topic)
            let negatives = ctx.topNegative.map(\.topic)

            if !positives.isEmpty {
                parts.append("It scores well on \(englishList(positives)).")
            }

            if negatives.isEmpty {
                parts.append("Nothing major held the overall score back in the data we have.")
            } else {
                let phrases = negatives.map { negativePhrase($0, ctx: ctx) }
                parts.append("The score is held back mainly by \(englishList(phrases)).")
            }
        }

        if let nova = ctx.novaGroup, nova >= 4,
           !(ctx.topNegative.contains(where: { $0.topic.contains("processing") })) {
            parts.append("It's ultra-processed (NOVA \(nova)).")
        }

        if !ctx.avoidMatches.isEmpty {
            let items = englishList(ctx.avoidMatches.map { $0.lowercased() })
            parts.append("It also contains \(items), which \(ctx.avoidMatches.count == 1 ? "is" : "are") on your avoid list.")
        }

        if !ctx.detectedAdditives.isEmpty, ctx.hasScoreableIngredientSignal {
            let n = ctx.detectedAdditives.count
            let label = n == 1
                ? "one additive (\(ctx.detectedAdditives[0]))"
                : "\(n) additives"
            parts.append("\(label.prefix(1).uppercased() + label.dropFirst()) detected.")
        }

        let overallPara = parts.joined(separator: " ")
        return (overallPara + " " + personalSentence(ctx)).trimmingCharacters(in: .whitespaces)
    }

    static func overallCapLead(_ cap: ScoringEngineV4.OverviewFiredCap) -> String? {
        switch cap.kind {
        case "freeSugar":
            return "As a concentrated sugar, its score is capped at \(cap.value)."
        case "transFat":
            return "It contains industrial trans fat, which caps the overall score at \(cap.value)."
        case "nns":
            return "As a non-nutritive sweetener, its score is capped at \(cap.value)."
        default:
            return "A health cap limits the overall score at \(cap.value)."
        }
    }

    static func personalSentence(_ ctx: ScoringEngineV4.OverviewContext) -> String {
        let delta = ctx.deltaValue
        if delta == 0 {
            return "Your score matches the overall because your profile didn't change the outcome."
        }
        let points = pointPhrase(abs(delta))
        let direction = delta < 0 ? "below" : "above"

        // Binding preference cap only — never attribute a non-binding fired cap.
        if let gate = ctx.hardGate, delta < 0 {
            if gate.intensity == "partial" {
                return "Your score is \(points) \(direction) the overall because \(gate.detail)."
            }
            return "Your score is \(points) \(direction) the overall because this product \(gate.detail)."
        }

        let drivers = ctx.deltaDrivers
        let goal = ctx.objective
        if drivers.isEmpty {
            return "Your score is \(points) \(direction) the overall from how your \"\(goal)\" goal reweights the rules."
        }
        let down = drivers.filter { $0.direction == "down" }.map(\.topic)
        let up = drivers.filter { $0.direction == "up" }.map(\.topic)

        let variant = abs(delta + ctx.overall + ctx.your) % 3
        if delta < 0, !down.isEmpty {
            switch variant {
            case 0:
                return "Your score is \(points) \(direction) the overall: your \"\(goal)\" goal puts more weight on \(englishList(down)), which pulls this product down."
            case 1:
                return "Relative to overall, you're \(points) \(direction) because \"\(goal)\" emphasizes \(englishList(down))."
            default:
                return "The \(points) drop vs overall comes from \"\(goal)\" stressing \(englishList(down)), where this product loses ground."
            }
        }
        if delta > 0, !up.isEmpty {
            switch variant {
            case 0:
                return "Your score is \(points) \(direction) the overall because \"\(goal)\" emphasizes \(englishList(up)), where this product does better."
            case 1:
                return "You're \(points) \(direction) overall: \"\(goal)\" boosts \(englishList(up)) for this product."
            default:
                return "The \(points) lift vs overall tracks \"\(goal)\" and stronger \(englishList(up))."
            }
        }
        let topics = drivers.map(\.topic)
        return "Your score is \(points) \(direction) the overall because your \"\(goal)\" goal weighs \(englishList(topics)) differently."
    }

    static func pointPhrase(_ n: Int) -> String {
        n == 1 ? "1 point" : "\(n) points"
    }

    private static func negativePhrase(_ topic: String, ctx: ScoringEngineV4.OverviewContext) -> String {
        if let rule = ctx.rules.first(where: { $0.topic == topic }),
           rule.evidenceTier == "unknown-tier" {
            if topic == "additives" || rule.rule == "S1" {
                return "missing ingredient data (the engine can't verify additives, so it assumes uncertainty)"
            }
            if topic == "packaging" || rule.rule == "S7" {
                return "missing packaging data"
            }
            if rule.rule == "S13" || topic.localizedCaseInsensitiveContains("micronutrient") {
                return "micronutrient data is missing"
            }
            return "\(topic) data is missing"
        }
        if topic == "degree of processing" {
            if let nova = ctx.novaGroup, nova >= 4 {
                return "degree of processing (ultra-processed, NOVA \(nova))"
            }
            return "degree of processing"
        }
        if topic == "quality labels" { return "no quality certification labels on file" }
        if topic == "certifications" { return "no certification labels on file" }
        if topic == "protein and fiber" {
            let n = ctx.nutrientLevels
            let proteinGood = n.contains(where: { $0.lowercased().contains("protein") && $0.lowercased().contains("high") })
                || n.contains(where: { $0.lowercased().contains("protein") && $0.lowercased().contains("good") })
            // Prefer density phrasing when badges are good (V5.0.6 nuts case).
            // nutrientLevels lines look like "protein: high (20g)" / "fiber: high".
            let fiberGood = n.contains(where: {
                $0.lowercased().hasPrefix("fiber") &&
                ($0.lowercased().contains("high") || $0.lowercased().contains("good"))
            })
            let proteinOk = n.contains(where: {
                $0.lowercased().hasPrefix("protein") &&
                ($0.lowercased().contains("high") || $0.lowercased().contains("good")
                 || $0.lowercased().contains("moderate"))
            })
            if fiberGood && proteinOk {
                return "protein and fiber are diluted by calorie density"
            }
            // Also check via rules + levels heuristics from prompt lines.
            if proteinGood || fiberGood {
                return "protein and fiber are diluted by calorie density"
            }
            return "limited protein and fiber credit"
        }
        return topic
    }

    private static func englishList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            return items.dropLast().joined(separator: ", ") + ", and \(items.last!)"
        }
    }
}
