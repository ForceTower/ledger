import Foundation
import GRDB

struct PurchaseStore: Sendable {
    var writer: any DatabaseWriter

    func summaries() async throws -> [PurchaseSummary] {
        try await writer.read { db in
            try Self.orderedPurchases(db).map { try Self.hydrate($0, db).summary }
        }
    }

    func search(_ query: String) async throws -> [PurchaseSummary] {
        try await writer.read { db in
            try Self.orderedPurchases(db)
                .map { try Self.hydrate($0, db) }
                .filter { purchase in
                    purchase.store.name.localizedCaseInsensitiveContains(query)
                        || purchase.items.contains { $0.description.localizedCaseInsensitiveContains(query) }
                }
                .map(\.summary)
        }
    }

    func purchase(id: String) async throws -> Purchase? {
        try await writer.read { db in
            guard let record = try PurchaseRecord.fetchOne(db, key: id) else { return nil }
            return try Self.hydrate(record, db)
        }
    }

    func save(_ purchases: [Purchase]) async throws {
        try await writer.write { db in
            for purchase in purchases {
                try PurchaseRecord.deleteOne(db, key: purchase.id)
                try PurchaseRecord(purchase).insert(db)
                for item in purchase.items {
                    try PurchaseItemRecord(purchaseSlug: purchase.id, item).insert(db)
                }
                for (seq, payment) in purchase.payments.enumerated() {
                    try PaymentRecord(purchaseSlug: purchase.id, seq: seq, payment).insert(db)
                }
            }
        }
    }

    private static func orderedPurchases(_ db: Database) throws -> [PurchaseRecord] {
        try PurchaseRecord
            .order(Column("date").desc, Column("time").desc)
            .fetchAll(db)
    }

    private static func hydrate(_ record: PurchaseRecord, _ db: Database) throws -> Purchase {
        let items = try PurchaseItemRecord
            .filter(Column("purchaseSlug") == record.slug)
            .order(Column("seq"))
            .fetchAll(db)
        let payments = try PaymentRecord
            .filter(Column("purchaseSlug") == record.slug)
            .order(Column("seq"))
            .fetchAll(db)
        return record.purchase(items: items.map(\.item), payments: payments.map(\.payment))
    }
}
