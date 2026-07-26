import ComposableArchitecture
import Foundation

/// Same reasoning as the photo scan: the server waits on the model, so the client has to outlast it.
private let uploadTimeout: TimeInterval = 75

extension EntryRepository: DependencyKey {
    static let liveValue = EntryRepository(
        interpret: { text, imageData in
            @Dependency(\.apiClient) var apiClient

            var form = MultipartForm()
            if let text, !text.isEmpty {
                form.fields = [(name: "text", value: text)]
            }
            if let imageData {
                guard let file = MultipartFile.imageUpload(from: imageData, filename: "entry.jpg") else {
                    throw EntryScanFailure.invalidInput
                }
                form.files = [file]
            }
            guard !form.isEmpty else { throw EntryScanFailure.invalidInput }

            do {
                return try await apiClient.upload(to: "scan/entry", form: form, timeout: uploadTimeout)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch let error as APIError {
                throw EntryScanFailure(error)
            } catch {
                throw EntryScanFailure.aiUnavailable
            }
        },
        save: { request in
            @Dependency(\.apiClient) var apiClient
            @Dependency(\.database) var database

            let purchase: Purchase
            do {
                purchase = try await apiClient.post(to: "purchases", body: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                throw EntryScanFailure.saveFailed
            }

            try? await MirrorStore(writer: database).save([purchase])
            return purchase
        }
    )
}

private extension EntryScanFailure {
    init(_ error: APIError) {
        switch error {
        case let .server(_, errorCode, _):
            switch errorCode {
            case "invalid_input": self = .invalidInput
            case "not_an_entry": self = .notAnEntry
            case "ai_invalid_output": self = .aiInvalidOutput
            default: self = .aiUnavailable
            }
        case .invalidServerAddress, .invalidResponse, .emptyEnvelope:
            self = .aiUnavailable
        }
    }
}
