import ComposableArchitecture
import Foundation

@DependencyClient
struct ScanRepository: Sendable {
    var scan: @Sendable (_ url: String) async throws -> ScanResponse
    /// Open a SEFAZ access-key consultation — the fallback when a scan fails with `.qrRejected`.
    var startKeyChallenge: @Sendable (_ accessKey: String) async throws -> KeyScanChallenge
    /// Answer the challenge's captcha; success saves the purchase exactly like `scan`.
    var completeKeyChallenge: @Sendable (_ challengeId: String, _ captcha: String) async throws -> ScanResponse
}

extension ScanRepository: TestDependencyKey {
    static let testValue = ScanRepository()

    static let previewValue: ScanRepository = {
        let count = LockIsolated(0)
        return ScanRepository(
            scan: { _ in
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
                    let kinds: [ScanFailure] = [.expired, .invalidQR, .unavailable, .qrRejected]
                    throw kinds[(n / 4) % kinds.count]
                }
            },
            startKeyChallenge: { _ in
                KeyScanChallenge(challengeId: "preview", captchaImage: "", expiresIn: 300)
            },
            completeKeyChallenge: { _, _ in
                ScanResponse(status: .saved, purchase: MockData.atacadao, warnings: [])
            }
        )
    }()
}

extension DependencyValues {
    var scanRepository: ScanRepository {
        get { self[ScanRepository.self] }
        set { self[ScanRepository.self] = newValue }
    }
}
