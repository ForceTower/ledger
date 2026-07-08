import ComposableArchitecture
#if canImport(UIKit)
import UIKit
#endif

@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.serverAddress) var serverAddress
        @Shared(.apiToken) var apiToken
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
                : "Acesso negado — toque para abrir os Ajustes e liberar a câmera."
        }
    }

    enum Action: Equatable {
        case onAppear
        case doneTapped
        case testConnectionTapped
        case connectionResult(ConnectionInfo?)
        case openCameraSettingsTapped
    }

    @Dependency(\.serverClient) var serverClient
    @Dependency(\.cameraClient) var cameraClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.dismiss) var dismiss
    @Dependency(\.openURL) var openURL

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let authorized = cameraClient.authorizationStatus().isAuthorized
                state.$cameraAuthorized.withLock { $0 = authorized }
                return .none

            case .doneTapped:
                return .run { _ in await dismiss() }

            case .testConnectionTapped:
                guard state.connection != .testing else { return .none }
                state.connection = .testing
                return .run { send in
                    try await clock.sleep(for: .seconds(1.4))
                    let info = try? await serverClient.testConnection()
                    await send(.connectionResult(info))
                }

            case let .connectionResult(info):
                state.connection = info.map(State.Connection.ok) ?? .failed
                return .none

            case .openCameraSettingsTapped:
                return .run { _ in
                    #if canImport(UIKit)
                    await openURL(URL(string: UIApplication.openSettingsURLString)!)
                    #endif
                }
            }
        }
    }
}
