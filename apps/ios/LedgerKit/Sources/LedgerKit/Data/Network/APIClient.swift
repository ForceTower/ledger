import ComposableArchitecture
import Foundation

struct APIRequest: Sendable {
    var method = "GET"
    var path: String
    var query: [URLQueryItem] = []
    var body: Data?
    var contentType: String?
    /// Overrides the session default, which is too short for calls that wait on the AI.
    var timeout: TimeInterval?
}

@DependencyClient
struct APIClient: Sendable {
    var send: @Sendable (_ request: APIRequest) async throws -> Data
}

private struct APIEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let message: String?
    let data: T?
    let errorCode: String?
}

extension APIClient {
    func get<T: Decodable>(
        _ type: T.Type = T.self,
        from path: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        try Self.unwrap(await send(APIRequest(path: path, query: query)))
    }

    func post<T: Decodable>(
        _ type: T.Type = T.self,
        to path: String,
        body: some Encodable & Sendable
    ) async throws -> T {
        let request = APIRequest(
            method: "POST",
            path: path,
            body: try JSONEncoder().encode(body),
            contentType: "application/json"
        )
        return try Self.unwrap(await send(request))
    }

    func upload<T: Decodable>(
        _ type: T.Type = T.self,
        to path: String,
        form: MultipartForm,
        timeout: TimeInterval
    ) async throws -> T {
        let boundary = "ledger-\(UUID().uuidString)"
        let request = APIRequest(
            method: "POST",
            path: path,
            body: form.body(boundary: boundary),
            contentType: "multipart/form-data; boundary=\(boundary)",
            timeout: timeout
        )
        return try Self.unwrap(await send(request))
    }

    private static func unwrap<T: Decodable>(_ data: Data) throws -> T {
        let envelope = try JSONDecoder().decode(APIEnvelope<T>.self, from: data)
        guard envelope.ok, let payload = envelope.data else {
            throw APIError.emptyEnvelope
        }
        return payload
    }
}

extension APIClient: DependencyKey {
    static let liveValue = APIClient.live()
    static let testValue = APIClient()
}

extension DependencyValues {
    var apiClient: APIClient {
        get { self[APIClient.self] }
        set { self[APIClient.self] = newValue }
    }
}

extension APIClient {
    static func live(session: URLSession = .api) -> APIClient {
        APIClient(send: { apiRequest in
            @Shared(.serverAddress) var serverAddress
            @Shared(.apiToken) var apiToken

            guard let url = endpoint(address: serverAddress, path: apiRequest.path, query: apiRequest.query) else {
                throw APIError.invalidServerAddress
            }
            var request = URLRequest(url: url)
            request.httpMethod = apiRequest.method
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = apiRequest.body
            if let contentType = apiRequest.contentType {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
            if let timeout = apiRequest.timeout {
                request.timeoutInterval = timeout
            }

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard 200..<300 ~= http.statusCode else {
                let envelope = try? JSONDecoder().decode(APIEnvelope<Bool>.self, from: data)
                throw APIError.server(
                    status: http.statusCode,
                    errorCode: envelope?.errorCode,
                    message: envelope?.message
                )
            }
            return data
        })
    }

    static func endpoint(address: String, path: String, query: [URLQueryItem]) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var components = URLComponents(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)") else {
            return nil
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = "\(basePath)/\(path)"
        if !query.isEmpty { components.queryItems = query }
        return components.url
    }
}

extension URLSession {
    static let api: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()
}
