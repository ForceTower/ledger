import ComposableArchitecture
import Foundation

/// Same reasoning as the photo scan: the server waits on the model, so the client has to outlast it.
private let uploadTimeout: TimeInterval = 75

extension TransferScanRepository: DependencyKey {
    static let liveValue = TransferScanRepository(
        interpret: { imageData, text in
            @Dependency(\.apiClient) var apiClient

            var form = MultipartForm()
            if let imageData {
                guard let file = MultipartFile.imageUpload(from: imageData, filename: "transfer.jpg") else {
                    throw TransferScanFailure.invalidInput
                }
                form.files = [file]
            }
            if let text, !text.isEmpty {
                form.fields = [(name: "text", value: text)]
            }
            guard !form.isEmpty else { throw TransferScanFailure.invalidInput }

            do {
                return try await apiClient.upload(to: "scan/transfer", form: form, timeout: uploadTimeout)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch let error as APIError {
                throw TransferScanFailure(error)
            } catch {
                throw TransferScanFailure.aiUnavailable
            }
        },
        save: { request in
            @Dependency(\.apiClient) var apiClient
            @Dependency(\.database) var database

            let result: TransferSaveResult
            do {
                result = try await apiClient.post(to: "transfers", body: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                throw TransferScanFailure.saveFailed
            }

            try? await MirrorStore(writer: database).save([result.purchase])
            return result
        }
    )
}

private extension TransferScanFailure {
    init(_ error: APIError) {
        switch error {
        case let .server(_, errorCode, _):
            switch errorCode {
            case "invalid_input": self = .invalidInput
            case "not_a_transfer": self = .notATransfer
            case "ai_invalid_output": self = .aiInvalidOutput
            default: self = .aiUnavailable
            }
        case .invalidServerAddress, .invalidResponse, .emptyEnvelope:
            self = .aiUnavailable
        }
    }
}
