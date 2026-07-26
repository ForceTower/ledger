import ComposableArchitecture
import Foundation

/// Reading a transfer receipt and saving it are two calls: the owner reviews the AI's guess in
/// between, correcting the category and deciding whether it pays for a note already in the history.
@DependencyClient
struct TransferScanRepository: Sendable {
    var interpret: @Sendable (_ imageData: Data?, _ text: String?) async throws -> TransferScanResult
    var save: @Sendable (_ request: TransferSaveRequest) async throws -> TransferSaveResult
}

extension TransferScanRepository: TestDependencyKey {
    static let testValue = TransferScanRepository()

    static let previewValue = TransferScanRepository(
        interpret: { _, _ in MockData.transferScan },
        save: { request in
            TransferSaveResult(
                transfer: request.transfer,
                purchase: MockData.pixPurchase(request.transfer, category: request.category)
            )
        }
    )
}

extension DependencyValues {
    var transferScanRepository: TransferScanRepository {
        get { self[TransferScanRepository.self] }
        set { self[TransferScanRepository.self] = newValue }
    }
}
