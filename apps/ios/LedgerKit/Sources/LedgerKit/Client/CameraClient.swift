import AVFoundation
import ComposableArchitecture

/// Camera permission and availability, surfaced as a dependency so the reducer
/// stays testable. The live preview itself is not modeled here — it lives in
/// `CameraPreview`. Mirrors `APIClient`: a struct of `@Sendable` closures with a
/// real `liveValue` and authorized stubs for previews/tests.
enum CameraAuthorization: Equatable, Sendable {
    case authorized, denied, restricted, notDetermined

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .denied
        }
    }

    var isAuthorized: Bool { self == .authorized }
}

struct CameraClient: Sendable {
    var authorizationStatus: @Sendable () -> CameraAuthorization
    var requestAccess: @Sendable () async -> Bool
    var isAvailable: @Sendable () -> Bool
}

extension CameraClient: DependencyKey {
    static let liveValue = CameraClient(
        authorizationStatus: { CameraAuthorization(AVCaptureDevice.authorizationStatus(for: .video)) },
        requestAccess: { await AVCaptureDevice.requestAccess(for: .video) },
        isAvailable: { AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil }
    )
    // Previews/tests run without a camera: report authorized + available so the
    // scanner UI renders and flows resolve deterministically (mirrors APIClient.mock).
    static let previewValue = CameraClient(
        authorizationStatus: { .authorized },
        requestAccess: { true },
        isAvailable: { true }
    )
    static let testValue = CameraClient(
        authorizationStatus: { .authorized },
        requestAccess: { true },
        isAvailable: { true }
    )
}

extension DependencyValues {
    var cameraClient: CameraClient {
        get { self[CameraClient.self] }
        set { self[CameraClient.self] = newValue }
    }
}
