#if canImport(UIKit)
import AVFoundation
import SwiftUI
import UIKit

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

@MainActor
final class CameraSessionController: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: (String) -> Void = { _ in }
    private var armed = true
    private var torchOn = false
    private var wantsRunning = false

    private let sessionQueue = DispatchQueue(label: "dev.forcetower.ledger.camera.session")
    nonisolated(unsafe) private let session = AVCaptureSession()
    nonisolated(unsafe) private var device: AVCaptureDevice?

    func attach(to view: CameraPreviewView) {
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
    }

    func setArmed(_ value: Bool) { armed = value }

    func start() {
        guard !wantsRunning else { return }
        wantsRunning = true
        sessionQueue.async { [self] in
            configure()
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        guard wantsRunning else { return }
        wantsRunning = false
        torchOn = false
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
        metadata.setMetadataObjectsDelegate(self, queue: .main)
        metadata.metadataObjectTypes =
            metadata.availableMetadataObjectTypes.contains(.qr) ? [.qr] : []
    }

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

struct CameraPreviewLayerView: UIViewRepresentable {
    let controller: CameraSessionController

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {}
}

struct LiveScannerView: View {
    var isActive: Bool
    var idle: Bool
    var flashOn: Bool
    var onCode: (String) -> Void

    @State private var controller = CameraSessionController()
    @Environment(\.scenePhase) private var scenePhase

    private var shouldRun: Bool { isActive && scenePhase == .active }

    var body: some View {
        CameraPreviewLayerView(controller: controller)
            .onChange(of: shouldRun, initial: true) { _, run in
                if run {
                    controller.onCode = onCode
                    controller.setArmed(idle)
                    controller.start()
                    controller.setTorch(on: flashOn)
                } else {
                    controller.stop()
                }
            }
            .onChange(of: idle) { _, value in controller.setArmed(value) }
            .onChange(of: flashOn) { _, value in controller.setTorch(on: value) }
            .onDisappear { controller.stop() }
    }
}
#endif
