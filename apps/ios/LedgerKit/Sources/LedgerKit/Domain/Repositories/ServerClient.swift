import ComposableArchitecture

@DependencyClient
struct ServerClient: Sendable {
    var testConnection: @Sendable () async throws -> ConnectionInfo
}

extension ServerClient: TestDependencyKey {
    static let testValue = ServerClient()

    static let previewValue: ServerClient = {
        struct ConnectionFailure: Error {}
        let count = LockIsolated(0)
        return ServerClient(testConnection: {
            let n = count.withValue { value in
                defer { value += 1 }
                return value
            }
            guard n.isMultiple(of: 2) else { throw ConnectionFailure() }
            return ConnectionInfo(serverVersion: "0.1.0", purchaseCount: 23)
        })
    }()
}

extension DependencyValues {
    var serverClient: ServerClient {
        get { self[ServerClient.self] }
        set { self[ServerClient.self] = newValue }
    }
}
