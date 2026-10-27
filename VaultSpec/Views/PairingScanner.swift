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

    /// Three queues, so nothing waits on anything else: the session is started and stopped on
    /// `sessionQueue`, frames arrive on `frameQueue` and are only copied there, and the slow decoding
    /// runs on `decodeQueue`, which takes the newest frame whenever it's free. (Stopping the session
    /// from the frame callback itself deadlocks: stopRunning waits for that very callback.)
    final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
        private let onToken: (String) -> Void
        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "vaultspec.pairing-scanner.session")
        private let frameQueue = DispatchQueue(label: "vaultspec.pairing-scanner.frames")
        private let decodeQueue = DispatchQueue(label: "vaultspec.pairing-scanner.decode", qos: .utility)
        private let lock = NSLock()
        private var decoding = false
        private var found = false

        init(onToken: @escaping (String) -> Void) { self.onToken = onToken }

        func start(on view: PreviewView) {
            view.previewLayer.session = session
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                sessionQueue.async { self.configure() }
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted { self.sessionQueue.async { self.configure() } }
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
            output.setSampleBufferDelegate(self, queue: frameQueue)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            if (try? camera.lockForConfiguration()) != nil {
                if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
                camera.unlockForConfiguration()
            }
            session.startRunning()
        }

        func stop() {
            sessionQueue.async { [session] in session.stopRunning() }
        }

        /// Copies the luma plane and hands it to the decoder unless it's still busy with an earlier frame.
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            lock.lock()
            let busy = decoding || found
            if !busy { decoding = true }
            lock.unlock()
            guard !busy, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0)
            let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            var luma = [UInt8](repeating: 0, count: rowBytes * height)
            if let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
                luma.withUnsafeMutableBytes { $0.copyMemory(from: UnsafeRawBufferPointer(start: base, count: rowBytes * height)) }
            }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)

            decodeQueue.async { [self] in
                let token = luma.withUnsafeBufferPointer {
                    PairingCode.decode(luma: $0.baseAddress!, width: width, height: height, rowBytes: rowBytes)
                }
                lock.lock()
                decoding = false
                let first = token != nil && !found
                if first { found = true }
                lock.unlock()
                guard first, let token else { return }
                stop()
                DispatchQueue.main.async { self.onToken(token) }
            }
        }
    }
}
