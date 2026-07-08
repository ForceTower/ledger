import ComposableArchitecture

enum CameraAuthorization: Equatable, Sendable {
    case authorized, denied, restricted, notDetermined

    var isAuthorized: Bool { self == .authorized }
}

struct CameraClient: Sendable {
    var authorizationStatus: @Sendable () -> CameraAuthorization
    var requestAccess: @Sendable () async -> Bool
    var isAvailable: @Sendable () -> Bool
}

extension CameraClient: TestDependencyKey {
    static let previewValue = CameraClient(
        authorizationStatus: { .authorized },
        requestAccess: { true },
        isAvailable: { true }
    )
    static let testValue = previewValue
}

extension DependencyValues {
    var cameraClient: CameraClient {
        get { self[CameraClient.self] }
        set { self[CameraClient.self] = newValue }
    }
}
