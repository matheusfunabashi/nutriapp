import Foundation

/// Bundled static knowledge base for food additives (no runtime LLM).
enum AdditiveKnowledgeBase {

    struct LocalizedString: Codable, Equatable {
        let en: String
        var ptBR: String? = nil

        enum CodingKeys: String, CodingKey {
            case en
            case ptBR = "pt-BR"
        }

        func resolved(locale: Locale = .current) -> String {
            let id = locale.identifier.lowercased()
            if id.hasPrefix("pt"), let pt = ptBR, !pt.isEmpty { return pt }
            return en
        }
    }

    struct Entry: Codable, Equatable {
        let code: String
        let name: LocalizedString
        let function: LocalizedString
        let summary: LocalizedString
        let detail: LocalizedString
        let tier: String
        var sources: [String] = []

        var risk: RiskLevel {
            RiskLevel(rawValue: tier) ?? .unrated
        }

        var displayName: String {
            let n = name.resolved()
            return "\(n) (\(code.uppercased()))"
        }
    }

    private final class BundleToken {}

    /// Keyed by normalized code ("e452").
    static let entries: [String: Entry] = {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "AdditiveKnowledgeBase", withExtension: "json")
                ?? Bundle.main.url(forResource: "AdditiveKnowledgeBase", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return dict
    }()

    static func entry(for codeOrTag: String) -> Entry? {
        let key = AdditiveCatalog.normalize(codeOrTag)
        if let e = entries[key] { return e }
        // Parent collapse: e452i → e452
        let parent = AdditiveDetector.parentENumber("E" + key.dropFirst())
        let parentKey = AdditiveCatalog.normalize(parent)
        return entries[parentKey]
    }
}
