import ComposableArchitecture

private struct HealthPayload: Decodable {
    let version: String
    let purchaseCount: Int
}

extension ServerClient: DependencyKey {
    static let liveValue = ServerClient(
        testConnection: {
            @Dependency(\.apiClient) var apiClient
            let health: HealthPayload = try await apiClient.get(from: "health")
            return ConnectionInfo(serverVersion: health.version, purchaseCount: health.purchaseCount)
        }
    )
}
