import ComposableArchitecture
import Foundation

@DependencyClient
struct ScanRepository: Sendable {
    var scan: @Sendable (_ url: String) async throws -> ScanResponse
}

extension ScanRepository: TestDependencyKey {
    static let testValue = ScanRepository()

    static let previewValue: ScanRepository = {
        let count = LockIsolated(0)
        return ScanRepository(scan: { _ in
            let n = count.withValue { value in
                defer { value += 1 }
                return value
            }
            switch n % 4 {
            case 0:
                return ScanResponse(status: .saved, purchase: MockData.atacadao, warnings: [])
            case 1:
                return ScanResponse(status: .duplicate, purchase: MockData.atacadao, warnings: [])
            case 2:
                return ScanResponse(
                    status: .saved,
                    purchase: MockData.atacadao,
                    warnings: ["A soma dos itens não bate com o total"]
                )
            default:
                let kinds: [ScanFailure] = [.expired, .invalidQR, .unavailable]
                throw kinds[(n / 4) % kinds.count]
            }
        })
    }()
}

extension DependencyValues {
    var scanRepository: ScanRepository {
        get { self[ScanRepository.self] }
        set { self[ScanRepository.self] = newValue }
    }
}
