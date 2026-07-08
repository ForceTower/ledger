import AVFoundation
import ComposableArchitecture

extension CameraClient: DependencyKey {
    static let liveValue = CameraClient(
        authorizationStatus: { CameraAuthorization(AVCaptureDevice.authorizationStatus(for: .video)) },
        requestAccess: { await AVCaptureDevice.requestAccess(for: .video) },
        isAvailable: { AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil }
    )
}

extension CameraAuthorization {
    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .denied
        }
    }
}
