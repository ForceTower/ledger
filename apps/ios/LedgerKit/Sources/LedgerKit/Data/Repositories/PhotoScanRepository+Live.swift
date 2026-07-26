import ComposableArchitecture
import Foundation

/// The server waits up to CLAUDE_TIMEOUT_MS (60s by default) on the model, so the client has to
/// outlast that rather than the 10s the shared session allows.
private let uploadTimeout: TimeInterval = 75

extension PhotoScanRepository: DependencyKey {
    static let liveValue = PhotoScanRepository(
        identify: { imageData in
            @Dependency(\.apiClient) var apiClient

            guard let file = MultipartFile.imageUpload(from: imageData, filename: "scan.jpg") else {
                throw PhotoScanFailure.invalidImage
            }

            do {
                return try await apiClient.upload(
                    to: "scan/photo",
                    form: MultipartForm(files: [file]),
                    timeout: uploadTimeout
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch let error as APIError {
                throw PhotoScanFailure(error)
            } catch {
                throw PhotoScanFailure.aiUnavailable
            }
        }
    )
}

private extension PhotoScanFailure {
    init(_ error: APIError) {
        switch error {
        case let .server(_, errorCode, _):
            switch errorCode {
            case "invalid_image": self = .invalidImage
            case "ai_invalid_output": self = .aiInvalidOutput
            default: self = .aiUnavailable
            }
        case .invalidServerAddress, .invalidResponse, .emptyEnvelope:
            self = .aiUnavailable
        }
    }
}
