import ComposableArchitecture
import Foundation

private struct ScanBody: Encodable {
    let url: String
}

extension ScanRepository: DependencyKey {
    static let liveValue = ScanRepository(
        scan: { url in
            @Dependency(\.apiClient) var apiClient
            @Dependency(\.database) var database

            let response: ScanResponse
            do {
                response = try await apiClient.post(to: "scan", body: ScanBody(url: url))
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch let error as APIError {
                throw ScanFailure(error)
            } catch {
                throw ScanFailure.unavailable
            }

            try? await MirrorStore(writer: database).save([response.purchase])
            return response
        }
    )
}

private extension ScanFailure {
    init(_ error: APIError) {
        switch error {
        case let .server(_, errorCode, _):
            switch errorCode {
            case "invalid_url": self = .invalidQR
            case "expired": self = .expired
            case "parse_failed": self = .parseFailed
            default: self = .unavailable
            }
        case .invalidServerAddress, .invalidResponse, .emptyEnvelope:
            self = .unavailable
        }
    }
}
