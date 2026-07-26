import ComposableArchitecture
import Foundation

@DependencyClient
struct PurchasesRepository: Sendable {
    var summaries: @Sendable () async throws -> [PurchaseSummary]
    var search: @Sendable (_ query: String) async throws -> [PurchaseSummary]
    var purchase: @Sendable (_ id: String) async throws -> Purchase?
    /// Full purchases for the last `monthCount` calendar months ending at the most
    /// recent purchase, served entirely from the local mirror.
    var recentPurchases: @Sendable (_ monthCount: Int) async throws -> [Purchase]
    var refresh: @Sendable () async throws -> Void
}

extension PurchasesRepository: TestDependencyKey {
    static let testValue = PurchasesRepository()

    static let previewValue = PurchasesRepository(
        summaries: { MockData.summaries },
        search: { query in MockData.summaries.filter { $0.store.localizedCaseInsensitiveContains(query) } },
        purchase: { MockData.purchase(id: $0) },
        recentPurchases: { _ in MockData.purchases },
        refresh: {}
    )
}

extension DependencyValues {
    var purchasesRepository: PurchasesRepository {
        get { self[PurchasesRepository.self] }
        set { self[PurchasesRepository.self] = newValue }
    }
}
