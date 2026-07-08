import Foundation

enum APIError: Error, Equatable {
    case invalidServerAddress
    case invalidResponse
    case server(status: Int, errorCode: String?, message: String?)
    case emptyEnvelope
}
