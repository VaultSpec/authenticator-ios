import AVFoundation
import SwiftUI

/// The back camera, full screen, reading particle codes (PairingCode) from its frames. Frames are
/// processed in memory and never stored.
struct PairingScanner: UIViewRepresentable {
    /// Receives the token of the first valid code.
    let onToken: (String) -> Void

    static var isSupported: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
        #endif
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.start(on: view)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    static func dismantleUIView(_ view: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onToken: onToken) }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
        private let onToken: (String) -> Void
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "vaultspec.pairing-scanner")
        private var found = false

        init(onToken: @escaping (String) -> Void) { self.onToken = onToken }

        func start(on view: PreviewView) {
            view.previewLayer.session = session
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                queue.async { self.configure() }
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted { self.queue.async { self.configure() } }
                }
            default:
                break
            }
        }

        private func configure() {
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera)
            else { return }
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720
            if session.canAddInput(input) { session.addInput(input) }
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            if (try? camera.lockForConfiguration()) != nil {
                if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
                camera.unlockForConfiguration()
            }
            session.startRunning()
        }

        func stop() {
            queue.async { [session] in session.stopRunning() }
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard !found, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return }
            let token = PairingCode.decode(
                luma: base.assumingMemoryBound(to: UInt8.self),
                width: CVPixelBufferGetWidthOfPlane(buffer, 0),
                height: CVPixelBufferGetHeightOfPlane(buffer, 0),
                rowBytes: CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            )
            guard let token else { return }
            found = true
            session.stopRunning()
            DispatchQueue.main.async { self.onToken(token) }
        }
    }
}
