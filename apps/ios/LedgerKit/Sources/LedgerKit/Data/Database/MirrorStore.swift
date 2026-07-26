import Foundation
import GRDB

struct MirrorStore: Sendable {
    var writer: any DatabaseWriter

    func summaries() async throws -> [PurchaseSummary] {
        try await writer.read { db in
            let categories = try Self.categoryCounts(db)
            return try Self.orderedPurchases(db).map { Self.summary(of: $0, categories: categories[$0.slug] ?? [:]) }
        }
    }

    func search(_ query: String) async throws -> [PurchaseSummary] {
        try await writer.read { db in
            // Matching stays in Swift: SQLite LIKE only case-folds ASCII, and the
            // pt-BR data needs "açúcar" to match "Pão de Açúcar".
            var descriptions: [String: [String]] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT purchaseSlug, itemDescription FROM purchaseItems") {
                descriptions[row["purchaseSlug"], default: []].append(row["itemDescription"])
            }
            let categories = try Self.categoryCounts(db)
            return try Self.orderedPurchases(db)
                .filter { record in
                    record.storeName.localizedCaseInsensitiveContains(query)
                        || (descriptions[record.slug] ?? []).contains { $0.localizedCaseInsensitiveContains(query) }
                }
                .map { Self.summary(of: $0, categories: categories[$0.slug] ?? [:]) }
        }
    }

    func purchase(id: String) async throws -> Purchase? {
        try await writer.read { db in
            guard let record = try PurchaseRecord.fetchOne(db, key: id) else { return nil }
            return try Self.hydrate(record, db)
        }
    }

    /// Full purchases for the window of `monthCount` calendar months ending at the
    /// most recent purchase — the slice Insights aggregates over.
    func recentPurchases(monthCount: Int) async throws -> [Purchase] {
        try await writer.read { db in
            guard let latest = try PurchaseRecord.order(Column("date").desc).fetchOne(db)?.date else { return [] }
            let since = Self.monthStart(monthsBefore: monthCount - 1, of: latest)
            let records = try PurchaseRecord
                .filter(Column("date") >= since)
                .order(Column("date").desc, Column("time").desc)
                .fetchAll(db)
            let slugs = records.map(\.slug)
            let items = try Dictionary(
                grouping: PurchaseItemRecord
                    .filter(slugs.contains(Column("purchaseSlug")))
                    .order(Column("seq"))
                    .fetchAll(db),
                by: \.purchaseSlug
            )
            let payments = try Dictionary(
                grouping: PaymentRecord
                    .filter(slugs.contains(Column("purchaseSlug")))
                    .order(Column("seq"))
                    .fetchAll(db),
                by: \.purchaseSlug
            )
            return records.map { record in
                record.purchase(
                    items: (items[record.slug] ?? []).map(\.item),
                    payments: (payments[record.slug] ?? []).map(\.payment)
                )
            }
        }
    }

    /// First day of the month `monthsBefore` months before the given ISO date,
    /// e.g. ("2026-03-26", 5) → "2025-10-01".
    static func monthStart(monthsBefore: Int, of dateISO: String) -> String {
        let year = Int(dateISO.prefix(4)) ?? 0
        let month = Int(dateISO.dropFirst(5).prefix(2)) ?? 1
        let index = year * 12 + month - 1 - monthsBefore
        return String(format: "%04d-%02d-01", index / 12, index % 12 + 1)
    }

    /// Removes purchases the server no longer returns, e.g. rows re-slugged by
    /// a server-side re-import. Items and payments follow via cascade.
    func prune(keepingSlugs slugs: Set<String>) async throws {
        try await writer.write { db in
            _ = try PurchaseRecord.filter(!slugs.contains(Column("slug"))).deleteAll(db)
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

    /// slug → item count per category, aggregated in SQL. Unknown raw categories
    /// fold into `.other` with `+=`, matching `PurchaseItemRecord.item`.
    private static func categoryCounts(_ db: Database) throws -> [String: [Category: Int]] {
        var counts: [String: [Category: Int]] = [:]
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT purchaseSlug, category, COUNT(*) AS count FROM purchaseItems GROUP BY purchaseSlug, category"
        )
        for row in rows {
            let category = Category(rawValue: row["category"]) ?? .other
            counts[row["purchaseSlug"], default: [:]][category, default: 0] += row["count"] as Int
        }
        return counts
    }

    private static func summary(of record: PurchaseRecord, categories: [Category: Int]) -> PurchaseSummary {
        PurchaseSummary(
            id: record.slug,
            store: record.storeName,
            date: record.date,
            time: record.time,
            totalPaid: record.totalPaid,
            itemCount: record.itemCount,
            categories: categories
        )
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
