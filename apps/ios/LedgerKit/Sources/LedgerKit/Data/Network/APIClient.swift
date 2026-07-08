import ComposableArchitecture
import Foundation

struct APIRequest: Sendable {
    var method = "GET"
    var path: String
    var query: [URLQueryItem] = []
    var body: Data?
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
        try Self.unwrap(await send(APIRequest(method: "POST", path: path, body: JSONEncoder().encode(body))))
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
            if let body = apiRequest.body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
