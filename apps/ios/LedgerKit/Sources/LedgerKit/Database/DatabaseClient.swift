import ComposableArchitecture
import Foundation

struct DatabaseClient: Sendable {
    var summaries: @Sendable () async throws -> [PurchaseSummary]
    var search: @Sendable (_ query: String) async throws -> [PurchaseSummary]
    var purchase: @Sendable (_ id: String) async throws -> Purchase?
    var save: @Sendable (_ purchases: [Purchase]) async throws -> Void
}

extension DatabaseClient: DependencyKey {
    static var liveValue: DatabaseClient {
        DatabaseClient(
            summaries: {
                @Dependency(\.database) var database
                return try await PurchaseStore(writer: database).summaries()
            },
            search: { query in
                @Dependency(\.database) var database
                return try await PurchaseStore(writer: database).search(query)
            },
            purchase: { id in
                @Dependency(\.database) var database
                return try await PurchaseStore(writer: database).purchase(id: id)
            },
            save: { purchases in
                @Dependency(\.database) var database
                try await PurchaseStore(writer: database).save(purchases)
            }
        )
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
        let store = try! PurchaseStore(writer: inMemoryDatabase())
        return DatabaseClient(
            summaries: { try await store.summaries() },
            search: { try await store.search($0) },
            purchase: { try await store.purchase(id: $0) },
            save: { try await store.save($0) }
        )
    }
}
