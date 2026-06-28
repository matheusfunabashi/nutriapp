import Foundation
import SwiftData

// MARK: - SwiftData records
//
// We persist domain values as JSON snapshots inside lightweight @Model records.
// This keeps the value-type domain models (Product, UserProfile, …) that the UI
// already uses untouched, while giving us durable on-device storage.

/// Single-row record holding the current user's profile.
@Model
final class ProfileRecord {
    var data: Data

    init(data: Data) {
        self.data = data
    }
}

/// One record per scanned/looked-up product. Stores a full snapshot so past
/// scans keep their data and scores even if the source product changes later.
@Model
final class ProductRecord {
    @Attribute(.unique) var id: String   // barcode / product id
    var data: Data
    var updatedAt: Date

    init(id: String, data: Data, updatedAt: Date = .now) {
        self.id = id
        self.data = data
        self.updatedAt = updatedAt
    }
}

/// One record per scan event, pointing at a ProductRecord by id.
@Model
final class HistoryRecord {
    @Attribute(.unique) var id: UUID
    var productId: String
    var when: String          // human label, e.g. "Just now"
    var dateLabel: String      // "MMM d · h:mm a" — drives day/time grouping
    var scannedAt: Date

    init(id: UUID = UUID(),
         productId: String,
         when: String,
         dateLabel: String,
         scannedAt: Date = .now) {
        self.id = id
        self.productId = productId
        self.when = when
        self.dateLabel = dateLabel
        self.scannedAt = scannedAt
    }
}
