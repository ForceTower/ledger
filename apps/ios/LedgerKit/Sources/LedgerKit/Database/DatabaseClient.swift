import ComposableArchitecture
import Foundation
import SwiftData

/// The local purchase mirror. Features read from here first — instantly, and
/// offline — while History's sync writes pages of `GET /purchases` through
/// `save` (see `docs/api-contract.md`).
struct DatabaseClient: Sendable {
    var summaries: @Sendable () async throws -> [PurchaseSummary]
    var search: @Sendable (_ query: String) async throws -> [PurchaseSummary]
    var purchase: @Sendable (_ id: String) async throws -> Purchase?
    var save: @Sendable (_ purchases: [Purchase]) async throws -> Void
}

extension DatabaseClient: DependencyKey {
    static var liveValue: DatabaseClient {
        do {
            let container = try ModelContainer(
                for: PurchaseRecord.self,
                configurations: ModelConfiguration("ledger")
            )
            return .backed(by: container)
        } catch {
            // The mirror is a cache of the server. If the on-disk store can't
            // open, an empty in-memory mirror that sync repopulates beats
            // crashing at launch.
            return .inMemory()
        }
    }

    static var previewValue: DatabaseClient { .inMemory() }
    static var testValue: DatabaseClient { .inMemory() }
}

extension DependencyValues {
    var databaseClient: DatabaseClient {
        get { self[DatabaseClient.self] }
        set { self[DatabaseClient.self] = newValue }
    }
}

extension DatabaseClient {
    static func inMemory() -> DatabaseClient {
        // Creating an in-memory container only fails on schema mistakes, which
        // are programmer errors.
        let container = try! ModelContainer(
            for: PurchaseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return .backed(by: container)
    }

    private static func backed(by container: ModelContainer) -> DatabaseClient {
        let store = PurchaseStore(modelContainer: container)
        return DatabaseClient(
            summaries: { try await store.summaries() },
            search: { try await store.search($0) },
            purchase: { try await store.purchase(id: $0) },
            save: { try await store.save($0) }
        )
    }
}

/// Serializes every read and write on one background `ModelContext`.
@ModelActor
private actor PurchaseStore {
    func summaries() throws -> [PurchaseSummary] {
        try fetchAll().map(\.purchase.summary)
    }

    /// Matches the store name or any item description. The dataset is one
    /// household's purchases, so filtering in memory stays simpler than
    /// pushing string matching into a store predicate.
    func search(_ query: String) throws -> [PurchaseSummary] {
        try fetchAll()
            .filter { record in
                record.storeName.localizedCaseInsensitiveContains(query)
                    || record.items.contains { $0.itemDescription.localizedCaseInsensitiveContains(query) }
            }
            .map(\.purchase.summary)
    }

    func purchase(id: String) throws -> Purchase? {
        try record(slug: id)?.purchase
    }

    func save(_ purchases: [Purchase]) throws {
        let slugs = purchases.map(\.id)
        let stale = try modelContext.fetch(
            FetchDescriptor<PurchaseRecord>(predicate: #Predicate { slugs.contains($0.slug) })
        )
        if !stale.isEmpty {
            stale.forEach { modelContext.delete($0) }
            try modelContext.save()
        }
        for purchase in purchases {
            PurchaseRecord.insert(purchase, into: modelContext)
        }
        try modelContext.save()
    }

    private func fetchAll() throws -> [PurchaseRecord] {
        try modelContext.fetch(
            FetchDescriptor<PurchaseRecord>(
                sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.time, order: .reverse)]
            )
        )
    }

    private func record(slug: String) throws -> PurchaseRecord? {
        var descriptor = FetchDescriptor<PurchaseRecord>(predicate: #Predicate { $0.slug == slug })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
