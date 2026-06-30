import ComposableArchitecture

/// App settings: the server endpoint + token (the seam to flip from mock to the
/// real client), a connection probe, camera permission, and theme. Server/token
/// and theme persist; camera authorization is shared live with the scanner.
@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.appStorage("serverAddress")) var serverAddress = "nfce.meucasa.app"
        @Shared(.inMemory("apiToken")) var apiToken = "" // production: Keychain
        @Shared(.inMemory("cameraAuthorized")) var cameraAuthorized = true
        @Shared(.appStorage("theme")) var theme: AppTheme = .system
        var connection: Connection = .idle

        enum Connection: Equatable {
            case idle, testing
            case ok(ConnectionInfo)
            case failed
        }

        var cameraHint: String {
            cameraAuthorized
                ? "O scanner usa a câmera apenas para ler o QR code."
                : "Acesso negado — o scanner não funciona até liberar a câmera."
        }
    }

    enum Action: Equatable {
        case doneTapped
        case testConnectionTapped
        case connectionResult(ConnectionInfo?)
    }

    @Dependency(\.apiClient) var apiClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.dismiss) var dismiss

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .doneTapped:
                return .run { _ in await dismiss() }

            case .testConnectionTapped:
                guard state.connection != .testing else { return .none }
                state.connection = .testing
                return .run { send in
                    try await clock.sleep(for: .seconds(1.4))
                    let info = try? await apiClient.testConnection()
                    await send(.connectionResult(info))
                }

            case let .connectionResult(info):
                state.connection = info.map(State.Connection.ok) ?? .failed
                return .none
            }
        }
    }
}
