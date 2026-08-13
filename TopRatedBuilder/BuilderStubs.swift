import Foundation

// Minimal types required to compile the scoring sources into the TopRatedBuilder
// macOS tool without pulling SwiftUI / Vision app targets.

enum ScoreTier: String {
    case excellent, good, poor, bad
}

struct BackendProductImage: Codable, Equatable, Sendable {
    let url: String?
    let thumbUrl: String?
    let source: String?
    let isFrontImage: Bool?
    let isLowQuality: Bool?
}

enum BackendService {
    static let defaultBaseURL = URL(string: "https://sage-backend.sage-app1710.workers.dev")!
    static let imageCacheVersion = 4

    static func productImageURL(barcode: String) -> String {
        let base = defaultBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(base)/images/\(code)?v=\(imageCacheVersion)"
    }
}
