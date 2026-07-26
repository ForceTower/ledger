import ComposableArchitecture
import Foundation

private struct ScanBody: Encodable {
    let url: String
}

private struct KeyChallengeBody: Encodable {
    let accessKey: String
}

private struct KeyScanBody: Encodable {
    let challengeId: String
    let captcha: String
}

extension ScanRepository: DependencyKey {
    static let liveValue = ScanRepository(
        scan: { url in
            @Dependency(\.apiClient) var apiClient
            @Dependency(\.database) var database

            let response: ScanResponse = try await mapToScanFailure {
                try await apiClient.post(to: "scan", body: ScanBody(url: url))
            }
            try? await MirrorStore(writer: database).save([response.purchase])
            return response
        },
        startKeyChallenge: { accessKey in
            @Dependency(\.apiClient) var apiClient

            return try await mapToScanFailure {
                try await apiClient.post(to: "scan/key/challenge", body: KeyChallengeBody(accessKey: accessKey))
            }
        },
        completeKeyChallenge: { challengeId, captcha in
            @Dependency(\.apiClient) var apiClient
            @Dependency(\.database) var database

            let response: ScanResponse = try await mapToScanFailure {
                try await apiClient.post(to: "scan/key", body: KeyScanBody(challengeId: challengeId, captcha: captcha))
            }
            try? await MirrorStore(writer: database).save([response.purchase])
            return response
        }
    )
}

private func mapToScanFailure<T>(_ run: () async throws -> T) async throws -> T {
    do {
        return try await run()
    } catch is CancellationError {
        throw CancellationError()
    } catch let error as URLError where error.code == .cancelled {
        throw CancellationError()
    } catch let error as APIError {
        throw ScanFailure(error)
    } catch {
        throw ScanFailure.unavailable
    }
}

private extension ScanFailure {
    init(_ error: APIError) {
        switch error {
        case let .server(_, errorCode, _):
            switch errorCode {
            case "invalid_url": self = .invalidQR
            case "expired": self = .expired
            case "parse_failed": self = .parseFailed
            case "qr_rejected": self = .qrRejected
            case "captcha_rejected": self = .captchaRejected
            case "challenge_expired": self = .challengeExpired
            default: self = .unavailable
            }
        case .invalidServerAddress, .invalidResponse, .emptyEnvelope:
            self = .unavailable
        }
    }
}
