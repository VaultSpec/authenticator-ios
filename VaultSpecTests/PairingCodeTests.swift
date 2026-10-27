import CoreGraphics
import Testing
@testable import VaultSpec

/// Renders the real particle code, then distorts it the way a camera would and checks the decoder reads it back.
@MainActor
struct PairingCodeTests {
    private let token = "q1w2e3r4t5y6u7i8"

    /// Decodes the way the camera does: from an 8-bit luma frame.
    private func decodeFrame(_ g: PairingCode.Gray) -> String? {
        let bytes = g.pixels.map { UInt8(min(255, max(0, $0 * 255))) }
        return bytes.withUnsafeBufferPointer { PairingCode.decode(luma: $0.baseAddress!, width: g.width, height: g.height, rowBytes: g.width) }
    }

    /// The cloud [side] pixels wide in a camera-sized [frame], after rotating, moving, blurring and adding noise.
    private func frame(side: CGFloat, rotation: Double, time: Double, frame: CGSize, offset: CGPoint, blur: Double, noise: Double,
                       brightness: Double = 1, dark: Bool = false) -> PairingCode.Gray {
        let art = PairingCodeArt.composite(token: token, pixels: 990, dark: dark, codeRotation: rotation, hazeRotation: -rotation * 0.6)
        let w = Int(frame.width), h = Int(frame.height)
        var pixels = [UInt8](repeating: 20, count: w * h)
        let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: dark ? 0.02 : 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setAlpha(brightness)
        ctx.draw(art, in: CGRect(x: (frame.width - side) / 2 + offset.x, y: (frame.height - side) / 2 + offset.y, width: side, height: side))
        var image = pixels.map { Double($0) / 255 }
        var gray = PairingCode.Gray(width: w, height: h, pixels: image)
        if blur > 0 { gray = gray.boxBlurred(radius: Int(blur)) }
        var rng = SystemRandomNumberGenerator()
        image = gray.pixels.map { min(1, max(0, $0 + Double.random(in: -noise...noise, using: &rng))) }
        return PairingCode.Gray(width: w, height: h, pixels: image)
    }

    @Test func roundTripsTokenBits() {
        let dots = PairingCode.dots(token: token)!
        #expect(dots.count == PairingCode.bitCount)
        #expect(PairingCode.dots(token: "short") == nil)
    }

    @Test(arguments: [
        (540.0, 0.0, 0.0, 0.0, 0.0),
        (540.0, 1.3, 20.0, 1.0, 0.03),
        (460.0, 4.0, -30.0, 1.0, 0.05),
        (380.0, 2.2, 15.0, 1.0, 0.04),
        (620.0, 5.9, 10.0, 2.0, 0.06),
    ])
    func decodesCameraLikeFrames(side: Double, rotation: Double, shift: Double, blur: Double, noise: Double) {
        // A camera sees ~30 frames a second of the moving cloud; most of any 5 in a row must read
        let read = (0..<5).filter { k in
            let t = rotation + Double(k) * 0.1
            let image = frame(side: side, rotation: t, time: t * 3, frame: CGSize(width: 1280, height: 720),
                              offset: CGPoint(x: shift, y: -shift / 2), blur: blur, noise: noise)
            return decodeFrame(image) == token
        }.count
        #expect(read >= 3, "read \(read) of 5 frames")
    }

    @Test func decodesTheDarkModeCloud() {
        let image = frame(side: 520, rotation: 2.4, time: 3, frame: CGSize(width: 1280, height: 720), offset: CGPoint(x: -12, y: 8), blur: 1, noise: 0.04, dark: true)
        #expect(decodeFrame(image) == token)
    }

    @Test func decodesADimScreen() {
        let image = frame(side: 500, rotation: 0.7, time: 1, frame: CGSize(width: 1280, height: 720), offset: .zero, blur: 1, noise: 0.03, brightness: 0.45)
        #expect(decodeFrame(image) == token)
    }

    @Test func rejectsAnEmptyFrame() {
        let image = PairingCode.Gray(width: 480, height: 360, pixels: (0..<480 * 360).map { _ in Double.random(in: 0...0.3) })
        #expect(PairingCode.decode(image) == nil)
    }
}
