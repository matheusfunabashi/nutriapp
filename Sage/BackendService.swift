import Foundation

// MARK: - Sage backend client (Cloudflare Worker proxy)

/// Typed client for the deployed Worker. `/lookup` proxies Open Food Facts
/// (with the shared KV cache and, for premium, the Go-UPC fallback) and returns
/// the raw OFF-shaped product, so the existing `OpenFoodFactsService` mapper
/// stays the single source of truth for parsing. `/explain` returns the
/// bucketed LLM sentence for the user's score class, or nil when the backend
/// skipped it (small delta / no key) — the app then keeps its rule-based text.
struct BackendService {
    enum LookupError: Error, Equatable {
        case notFound
        case dailyLimitReached
        case unauthorized
        case network
        case decoding
    }

    private let session: URLSession
    private let baseURL: URL
    private let apiKey: String

    init(session: URLSession = .shared,
         baseURL: URL = URL(string: "https://sage-backend.sage-app1710.workers.dev")!,
         apiKey: String = Secrets.sageAPIKey) {
        self.session = session
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    /// Stable per-install label sent with lookups so dev-phase paid calls
    /// (Go-UPC trial quota) are attributable per device in the backend
    /// `fetch_log`. Replaced by a validated DeviceCheck identity later.
    static let clientTag: String = {
        let key = "sage.clientTag"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let tag = "ios-" + UUID().uuidString.prefix(8).lowercased()
        UserDefaults.standard.set(tag, forKey: key)
        return tag
    }()

    // MARK: /lookup

    private struct LookupBody: Encodable {
        let barcode: String
        let isPremium: Bool
        let clientTag: String
    }

    func lookup(barcode: String) async throws -> Product {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LookupError.network }

        // isPremium is stubbed true until StoreKit receipt validation lands;
        // the free-tier limit also needs DeviceCheck, so nothing enforces yet.
        let body = LookupBody(barcode: trimmed, isPremium: true, clientTag: Self.clientTag)
        let (data, status) = try await post(path: "lookup", body: body)

        switch status {
        case 200:
            do {
                // The /lookup response `{source, product}` carries the raw OFF
                // product under the same `product` key the OFF decoder reads.
                return try OpenFoodFactsService.makeProduct(from: data, barcode: trimmed)
            } catch OpenFoodFactsService.LookupError.notFound {
                throw LookupError.notFound
            } catch {
                throw LookupError.decoding
            }
        case 404: throw LookupError.notFound
        case 429: throw LookupError.dailyLimitReached
        case 401: throw LookupError.unauthorized
        default:  throw LookupError.network
        }
    }

    // MARK: /search

    /// One typeahead result. `code` is the barcode — selecting a hit re-enters
    /// the normal scan pipeline (/lookup → score → /explain).
    struct SearchHit: Decodable, Identifiable, Equatable {
        let code: String
        let name: String
        let brand: String
        let quantity: String?
        let imageURL: String?
        var id: String { code }
    }

    private struct SearchBody: Encodable { let query: String }
    struct SearchResponse: Decodable { let results: [SearchHit] }

    enum SearchError: Error, Equatable {
        case network
        case unauthorized
    }

    /// Free-text name/brand search against OFF via the Worker (KV-cached).
    /// Empty array = genuinely no matches ("Product not available.").
    func search(_ query: String) async throws -> [SearchHit] {
        let data: Data
        let status: Int
        do {
            (data, status) = try await post(path: "search", body: SearchBody(query: query))
        } catch {
            throw SearchError.network
        }
        switch status {
        case 200:
            guard let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) else {
                throw SearchError.network
            }
            return decoded.results
        case 401: throw SearchError.unauthorized
        default:  throw SearchError.network
        }
    }

    // MARK: /explain

    struct ExplainPayload: Encodable {
        let barcode: String
        let classHash: String
        let productName: String
        let objective: String
        let overall: Int
        let your: Int
        let factors: [String]
    }

    private struct ExplainResponse: Decodable {
        let explanation: String?
    }

    /// Fire-and-forget by design: any failure returns nil and the app keeps
    /// the rule-based deltaReason it already rendered.
    func explain(_ payload: ExplainPayload) async -> String? {
        guard let (data, status) = try? await post(path: "explain", body: payload),
              status == 200,
              let decoded = try? JSONDecoder().decode(ExplainResponse.self, from: data),
              let text = decoded.explanation?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }
        return text
    }

    // MARK: /ruleset (scoring-v4 remote config)

    private struct RulesetVersionResponse: Decodable { let version: String }

    /// Tiny edge-cached probe — the background refresh checks this first.
    func rulesetVersion() async -> String? {
        guard let (data, status) = try? await get(path: "ruleset/version"), status == 200,
              let decoded = try? JSONDecoder().decode(RulesetVersionResponse.self, from: data)
        else { return nil }
        return decoded.version
    }

    /// Full ruleset; returns the raw bytes too so the store can persist
    /// exactly what it validated.
    func fetchRuleset() async -> (Data, RulesetV4)? {
        guard let (data, status) = try? await get(path: "ruleset"), status == 200,
              let rs = try? JSONDecoder().decode(RulesetV4.self, from: data)
        else { return nil }
        return (data, rs)
    }

    // MARK: Transport

    private func get(path: String) async throws -> (Data, Int) {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.setValue(apiKey, forHTTPHeaderField: "X-Sage-Key")
        req.setValue("Sage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func post(path: String, body: some Encodable) async throws -> (Data, Int) {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "X-Sage-Key")
        req.setValue("Sage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw LookupError.network
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }
}
