#if canImport(UIKit)
import AVFoundation
import SwiftUI
import UIKit

/// A `UIView` whose backing layer *is* the camera preview, so it resizes
/// automatically with no manual frame math.
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

/// Live QR scanner. Shows the back camera and emits the decoded string once per
/// "armed" cycle via `onCode`. `armed` is driven by the reducer (true only while
/// the scan phase is idle) so a single QR fires exactly one scan; `flashOn`
/// drives the real torch.
struct CameraPreview: UIViewRepresentable {
    var armed: Bool
    var flashOn: Bool
    var onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        context.coordinator.attach(to: view)
        context.coordinator.start()
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onCode = onCode
        coordinator.setArmed(armed)
        coordinator.setTorch(on: flashOn)
    }

    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    /// Owns the capture graph. `@MainActor` because the LedgerKit package has no
    /// default MainActor isolation, so a bare `NSObject` would otherwise be
    /// `nonisolated` and couldn't safely touch `armed`/`onCode`.
    @MainActor
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: (String) -> Void
        private var armed = true
        private var torchOn = false

        // The capture graph is non-Sendable; it is only ever touched on
        // `sessionQueue` (the lone exception is assigning the preview layer's
        // session on the main thread, once, before the session starts). That
        // confinement is what makes `nonisolated(unsafe)` sound here.
        private let sessionQueue = DispatchQueue(label: "dev.forcetower.ledger.camera.session")
        nonisolated(unsafe) private let session = AVCaptureSession()
        nonisolated(unsafe) private var device: AVCaptureDevice?

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
            super.init()
        }

        func attach(to view: CameraPreviewView) {
            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill
        }

        func setArmed(_ value: Bool) { armed = value }

        func start() {
            sessionQueue.async { [self] in
                configure()
                if !session.isRunning { session.startRunning() }
            }
        }

        func stop() {
            sessionQueue.async { [self] in
                if session.isRunning { session.stopRunning() }
            }
        }

        func setTorch(on: Bool) {
            guard on != torchOn else { return }
            torchOn = on
            sessionQueue.async { [self] in
                guard let device, device.hasTorch, device.isTorchAvailable else { return }
                guard (try? device.lockForConfiguration()) != nil else { return }
                defer { device.unlockForConfiguration() }
                if on {
                    try? device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    device.torchMode = .off
                }
            }
        }

        /// Runs on `sessionQueue`. `nonisolated` so it can legally touch the
        /// non-Sendable graph off the main actor.
        nonisolated private func configure() {
            guard session.inputs.isEmpty else { return }
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            guard
                let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: camera),
                session.canAddInput(input)
            else { return }
            session.addInput(input)
            device = camera

            let metadata = AVCaptureMetadataOutput()
            guard session.canAddOutput(metadata) else { return }
            session.addOutput(metadata)
            // `self` is a @MainActor class (hence Sendable); delivering on `.main`
            // lets the callback read MainActor state via `assumeIsolated`.
            metadata.setMetadataObjectsDelegate(self, queue: .main)
            metadata.metadataObjectTypes =
                metadata.availableMetadataObjectTypes.contains(.qr) ? [.qr] : []
        }

        /// The delegate protocol is `nonisolated`; a `@MainActor` conformer satisfies
        /// it only by marking this `nonisolated`. The delegate queue is `.main`, so
        /// `assumeIsolated` is sound and we can touch `armed`/`onCode` synchronously.
        nonisolated func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard
                let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                object.type == .qr,
                let value = object.stringValue
            else { return }

            MainActor.assumeIsolated {
                guard armed else { return }
                armed = false
                onCode(value)
            }
        }
    }
}
#endif
