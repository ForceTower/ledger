import ComposableArchitecture
import Foundation

@DependencyClient
struct PhotoScanRepository: Sendable {
    var identify: @Sendable (_ imageData: Data) async throws -> PhotoScanResult
}

extension PhotoScanRepository: TestDependencyKey {
    static let testValue = PhotoScanRepository()

    static let previewValue: PhotoScanRepository = {
        let count = LockIsolated(0)
        return PhotoScanRepository(identify: { _ in
            let n = count.withValue { value in
                defer { value += 1 }
                return value
            }
            switch n % 3 {
            case 0:
                return .identified(MockData.photoScanIdentified)
            case 1:
                return .rejected(PhotoScanRejected(
                    reason: .unclearImage,
                    comment: "A foto está desfocada demais para identificar o produto."
                ))
            default:
                throw PhotoScanFailure.aiUnavailable
            }
        })
    }()
}

extension DependencyValues {
    var photoScanRepository: PhotoScanRepository {
        get { self[PhotoScanRepository.self] }
        set { self[PhotoScanRepository.self] = newValue }
    }
}
