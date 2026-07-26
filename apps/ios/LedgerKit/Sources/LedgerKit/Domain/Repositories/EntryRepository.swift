import ComposableArchitecture
import Foundation

/// Drafting a lançamento and saving it are two calls: the owner corrects the AI's reading in
/// between — the items, their prices, the date and where the money went.
@DependencyClient
struct EntryRepository: Sendable {
    var interpret: @Sendable (_ text: String?, _ imageData: Data?) async throws -> EntryDraft
    var save: @Sendable (_ request: PurchaseCreateRequest) async throws -> Purchase
}

extension EntryRepository: TestDependencyKey {
    static let testValue = EntryRepository()

    static let previewValue = EntryRepository(
        interpret: { _, _ in MockData.entryDraft },
        save: { request in MockData.manualPurchase(request) }
    )
}

extension DependencyValues {
    var entryRepository: EntryRepository {
        get { self[EntryRepository.self] }
        set { self[EntryRepository.self] = newValue }
    }
}
