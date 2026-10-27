import AVFoundation
import CoreGraphics
import Testing
@testable import VaultSpec

/// Drives the scanner the way the camera does: a 1280x720 biplanar frame delivered on a background
/// queue. A main-actor `captureOutput` traps here, which is how the scanner froze on a real iPad.
@MainActor
struct PairingScannerTests {
    private func cameraFrame(token: String) -> CMSampleBuffer {
        let w = 1280, h = 720
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &pixelBuffer)
        let buffer = pixelBuffer!
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: rowBytes,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let art = PairingCodeArt.composite(token: token, pixels: 990, dark: false, codeRotation: 0.8, hazeRotation: 2)
        ctx.draw(art, in: CGRect(x: 370, y: 90, width: 540, height: 540))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample)
        return sample!
    }

    @Test func readsAFrameDeliveredOnABackgroundQueue() async {
        let token = "q1w2e3r4t5y6u7i8"
        let frame = cameraFrame(token: token)
        let received: String? = await withCheckedContinuation { continuation in
            // Called through the delegate protocol, as AVFoundation does, so no compile-time isolation check applies
            nonisolated(unsafe) let delegate: any AVCaptureVideoDataOutputSampleBufferDelegate =
                PairingScanner.Coordinator { continuation.resume(returning: $0) }
            nonisolated(unsafe) let output = AVCaptureVideoDataOutput()
            nonisolated(unsafe) let connection = AVCaptureConnection(inputPorts: [], output: output)
            nonisolated(unsafe) let frame = frame
            DispatchQueue.global().async {
                delegate.captureOutput?(output, didOutput: frame, from: connection)
            }
        }
        #expect(received == token)
    }
}
