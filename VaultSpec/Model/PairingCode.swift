import Foundation

/// The particle code shown by Scan & Connect: a 12-byte pairing token drawn as dots on rings, read back
/// from camera frames by `decode`. The Android app implements the same format (PairingCode.kt).
///
/// Geometry, in units of R (the radius of the reference ring), angles clockwise in image coordinates:
/// - a bright disk at the centre, radius 0.2 (finds the centre and the scale)
/// - the reference ring at radius 1, with a 24° gap centred on the orientation angle φ
/// - 112 data positions on four rings (radii 0.42, 0.57, 0.72, 0.87; 16, 24, 32 and 40 positions).
///   Position j of ring k sits at φ + 2π(j + 0.5)/count. A dot means 1.
/// - the bits are the token followed by its CRC-16/CCITT-FALSE, most significant bit first.
nonisolated enum PairingCode {
    static let tokenLength = 12
    static let centerRadius = 0.2
    static let ringWidth = 0.05
    static let gap = 24.0 * .pi / 180
    static let dotDiameter = 0.085
    static let rings: [(radius: Double, count: Int)] = [(0.42, 16), (0.57, 24), (0.72, 32), (0.87, 40)]
    static var bitCount: Int { rings.reduce(0) { $0 + $1.count } }

    /// One data position: its place relative to the centre (unit R, before rotation by φ) and whether it shows a dot.
    struct Dot {
        let radius: Double
        let angle: Double
        let on: Bool
    }

    /// The dots for a token given as base64url text, or nil if it isn't a 12-byte token.
    static func dots(token: String) -> [Dot]? {
        guard let bytes = base64URLDecode(token), bytes.count == tokenLength else { return nil }
        let bits = bitsOf(bytes + crc16(bytes))
        var dots: [Dot] = []
        var index = 0
        for ring in rings {
            for j in 0..<ring.count {
                dots.append(Dot(radius: ring.radius, angle: 2 * .pi * (Double(j) + 0.5) / Double(ring.count), on: bits[index]))
                index += 1
            }
        }
        return dots
    }

    // MARK: Decoding

    /// Reads a code from an 8-bit luma frame (a camera's Y plane), light on dark or dark on light, assuming it is roughly in the middle
    /// and facing the camera. Returns the token as base64url, or nil if no valid code was found.
    static func decode(luma: UnsafePointer<UInt8>, width: Int, height: Int, rowBytes: Int) -> String? {
        let image = Gray.downsample(luma: luma, width: width, height: height, rowBytes: rowBytes, target: 360)
        return decode(image)
    }

    /// Tries the frame as it is (a light code on a dark screen) and inverted (a dark cloud on a light screen).
    static func decode(_ g: Gray) -> String? {
        decodeLight(g) ?? decodeLight(Gray(width: g.width, height: g.height, pixels: g.pixels.map { 1 - $0 }))
    }

    private static func decodeLight(_ frame: Gray) -> String? {
        // Merge the cloud's specks into solid shapes, as a slightly soft camera would
        let soft = frame.boxBlurred(radius: max(1, min(frame.width, frame.height) / 180))
        // Keep only detail smaller than the code's centre: smooth shading (the artwork behind the code,
        // glare, vignetting) drops out
        let broad = soft.boxBlurred(radius: max(4, min(frame.width, frame.height) / 18))
        let g = Gray(width: soft.width, height: soft.height,
                     pixels: zip(soft.pixels, broad.pixels).map { min(1, max(0, 0.5 + 2 * ($0 - $1))) })
        let minSide = Double(min(g.width, g.height))
        let blurred = g.boxBlurred(radius: max(2, Int(minSide * 0.02)))

        // The centre disk is the brightest large blob near the middle of the frame
        let search = Int(minSide * 0.3)
        var best = (x: g.width / 2, y: g.height / 2, v: -1.0)
        for y in max(0, g.height / 2 - search)..<min(g.height, g.height / 2 + search) {
            for x in max(0, g.width / 2 - search)..<min(g.width, g.width / 2 + search) where blurred[x, y] > best.v {
                best = (x, y, blurred[x, y])
            }
        }
        let background = g.percentile(0.2, around: (best.x, best.y), radius: search)
        let peak = g.maxValue(around: (best.x, best.y), radius: 3)
        guard peak - background > 0.12 else { return nil }
        let threshold = (peak + background) / 2

        guard let disk = g.blob(from: (best.x, best.y), above: threshold, maxRadius: Int(minSide * 0.2)) else { return nil }
        let r0 = (Double(disk.area) / .pi).squareRoot()
        guard r0 >= 3 else { return nil }

        // Refine the centre and the scale on the reference ring
        var center = disk.centroid
        var radius = r0 / centerRadius
        var bestScore = -1.0
        let c0 = center, rEstimate = radius
        for dy in stride(from: -2.0, through: 2.0, by: 1) {
            for dx in stride(from: -2.0, through: 2.0, by: 1) {
                for scale in stride(from: 0.85, through: 1.15, by: 0.01) {
                    let c = (x: c0.x + dx, y: c0.y + dy), r = rEstimate * scale
                    var sum = 0.0
                    for i in 0..<120 {
                        let a = Double(i) / 120 * 2 * .pi
                        sum += g.sample(c.x + r * cos(a), c.y + r * sin(a))
                    }
                    if sum > bestScore { bestScore = sum; center = c; radius = r }
                }
            }
        }
        guard radius < minSide * 0.6 else { return nil }

        // Orientation: the gap in the reference ring
        let steps = 360
        var ring = [Double](repeating: 0, count: steps)
        for i in 0..<steps {
            let a = Double(i) / Double(steps) * 2 * .pi
            ring[i] = [0.96, 1.0, 1.04].map { g.sample(center.x + radius * $0 * cos(a), center.y + radius * $0 * sin(a)) }.max()!
        }
        let window = 20
        var gapStart = 0, gapSum = Double.infinity
        for start in 0..<steps {
            let sum = (0..<window).reduce(0.0) { $0 + ring[(start + $1) % steps] }
            if sum < gapSum { gapSum = sum; gapStart = start }
        }
        let phi = (Double(gapStart) + Double(window - 1) / 2) / Double(steps) * 2 * .pi

        // Fine-tune the rotation until the dots read most clearly, then read them
        var bestPhi = phi, bestClarity = -1.0
        for step in -8...8 {
            let candidate = phi + Double(step) * 0.5 * .pi / 180
            let clarity = sampleBits(g, center: center, radius: radius, phi: candidate).reduce(0.0) { $0 + abs($1 - 0.5) }
            if clarity > bestClarity { bestClarity = clarity; bestPhi = candidate }
        }
        let values = sampleBits(g, center: center, radius: radius, phi: bestPhi)
        // Each ring gets its own threshold, so shading that differs from ring to ring doesn't matter
        var thresholds: [Double] = []
        var start = 0
        for ring in rings {
            let t = otsu(Array(values[start..<start + ring.count]))
            thresholds += Array(repeating: t, count: ring.count)
            start += ring.count
        }
        return readBits(values, thresholds: thresholds)
    }

    /// The cut that best separates [values] into two groups (Otsu's method).
    private static func otsu(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        var best = (sorted.first! + sorted.last!) / 2, bestScore = -1.0
        for k in 1..<sorted.count {
            let low = sorted[..<k], high = sorted[k...]
            let m0 = low.reduce(0, +) / Double(low.count), m1 = high.reduce(0, +) / Double(high.count)
            let score = Double(low.count * high.count) * (m1 - m0) * (m1 - m0)
            if score > bestScore { bestScore = score; best = (sorted[k - 1] + sorted[k]) / 2 }
        }
        return best
    }

    /// The mean brightness at every data position.
    private static func sampleBits(_ g: Gray, center: (x: Double, y: Double), radius: Double, phi: Double) -> [Double] {
        var values: [Double] = []
        values.reserveCapacity(bitCount)
        for ring in rings {
            let step = 2 * .pi / Double(ring.count)
            for j in 0..<ring.count {
                let a = phi + step * (Double(j) + 0.5)
                var sum = 0.0
                for dr in [-0.015, 0.0, 0.015] {
                    for da in [-0.1, 0.0, 0.1] {
                        let r = radius * (ring.radius + dr), angle = a + da * step
                        sum += g.sample(center.x + r * cos(angle), center.y + r * sin(angle))
                    }
                }
                values.append(sum / 9)
            }
        }
        return values
    }

    /// Thresholds the dots and checks the CRC. If it fails, retries with the least certain bits flipped
    /// (up to 6 of them), which recovers a few misread dots; the CRC still rejects anything wrong.
    private static func readBits(_ values: [Double], thresholds: [Double]) -> String? {
        let bits = values.indices.map { values[$0] > thresholds[$0] }
        let doubtful = values.indices.sorted { abs(values[$0] - thresholds[$0]) < abs(values[$1] - thresholds[$1]) }.prefix(6)
        for mask in 0..<(1 << doubtful.count) {
            var attempt = bits
            for (k, index) in doubtful.enumerated() where mask & (1 << k) != 0 { attempt[index].toggle() }
            let bytes = bytesOf(attempt)
            let token = Array(bytes.prefix(tokenLength))
            if Array(bytes.suffix(2)) == crc16(token) { return base64URLEncode(token) }
        }
        return nil
    }

    // MARK: Bits and bytes

    static func crc16(_ bytes: [UInt8]) -> [UInt8] {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 { crc = crc & 0x8000 != 0 ? (crc << 1) ^ 0x1021 : crc << 1 }
        }
        return [UInt8(crc >> 8), UInt8(crc & 0xFF)]
    }

    private static func bitsOf(_ bytes: [UInt8]) -> [Bool] {
        bytes.flatMap { byte in (0..<8).map { byte & (0x80 >> $0) != 0 } }
    }

    private static func bytesOf(_ bits: [Bool]) -> [UInt8] {
        stride(from: 0, to: bits.count, by: 8).map { start in
            (0..<8).reduce(UInt8(0)) { $0 | (bits[start + $1] ? 0x80 >> $1 : 0) }
        }
    }

    static func base64URLEncode(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ text: String) -> [UInt8]? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64).map { [UInt8]($0) }
    }

    // MARK: Image

    /// A small grayscale image, values 0...1.
    struct Gray {
        let width: Int
        let height: Int
        var pixels: [Double]

        subscript(x: Int, y: Int) -> Double { pixels[y * width + x] }

        /// Averages blocks so the shorter side is about [target] pixels.
        static func downsample(luma: UnsafePointer<UInt8>, width: Int, height: Int, rowBytes: Int, target: Int) -> Gray {
            let f = max(1, min(width, height) / target)
            let w = width / f, h = height / f
            var pixels = [Double](repeating: 0, count: w * h)
            let scale = 1 / (255 * Double(f * f))
            for y in 0..<h {
                for x in 0..<w {
                    var sum = 0
                    for yy in 0..<f {
                        let row = luma + (y * f + yy) * rowBytes + x * f
                        for xx in 0..<f { sum += Int(row[xx]) }
                    }
                    pixels[y * w + x] = Double(sum) * scale
                }
            }
            return Gray(width: w, height: h, pixels: pixels)
        }

        /// Bilinear sample; 0 outside the image.
        func sample(_ x: Double, _ y: Double) -> Double {
            guard x >= 0, y >= 0, x < Double(width - 1), y < Double(height - 1) else { return 0 }
            let x0 = Int(x), y0 = Int(y), fx = x - Double(x0), fy = y - Double(y0)
            let top = self[x0, y0] * (1 - fx) + self[x0 + 1, y0] * fx
            let bottom = self[x0, y0 + 1] * (1 - fx) + self[x0 + 1, y0 + 1] * fx
            return top * (1 - fy) + bottom * fy
        }

        func boxBlurred(radius: Int) -> Gray {
            // Integral image
            var integral = [Double](repeating: 0, count: (width + 1) * (height + 1))
            for y in 0..<height {
                var row = 0.0
                for x in 0..<width {
                    row += self[x, y]
                    integral[(y + 1) * (width + 1) + x + 1] = integral[y * (width + 1) + x + 1] + row
                }
            }
            var out = [Double](repeating: 0, count: width * height)
            for y in 0..<height {
                let y0 = max(0, y - radius), y1 = min(height, y + radius + 1)
                for x in 0..<width {
                    let x0 = max(0, x - radius), x1 = min(width, x + radius + 1)
                    let sum = integral[y1 * (width + 1) + x1] - integral[y0 * (width + 1) + x1]
                        - integral[y1 * (width + 1) + x0] + integral[y0 * (width + 1) + x0]
                    out[y * width + x] = sum / Double((x1 - x0) * (y1 - y0))
                }
            }
            return Gray(width: width, height: height, pixels: out)
        }

        func percentile(_ p: Double, around c: (Int, Int), radius: Int) -> Double {
            var values: [Double] = []
            for y in stride(from: max(0, c.1 - radius), to: min(height, c.1 + radius), by: 2) {
                for x in stride(from: max(0, c.0 - radius), to: min(width, c.0 + radius), by: 2) { values.append(self[x, y]) }
            }
            values.sort()
            return values.isEmpty ? 0 : values[Int(Double(values.count - 1) * p)]
        }

        func maxValue(around c: (Int, Int), radius: Int) -> Double {
            var best = 0.0
            for y in max(0, c.1 - radius)...min(height - 1, c.1 + radius) {
                for x in max(0, c.0 - radius)...min(width - 1, c.0 + radius) { best = max(best, self[x, y]) }
            }
            return best
        }

        /// The connected bright region containing [start]: its pixel count and centroid.
        func blob(from start: (Int, Int), above threshold: Double, maxRadius: Int) -> (area: Int, centroid: (x: Double, y: Double))? {
            guard self[start.0, start.1] > threshold else { return nil }
            var seen = [Bool](repeating: false, count: width * height)
            var stack = [start]
            seen[start.1 * width + start.0] = true
            var area = 0, sx = 0, sy = 0
            while let (x, y) = stack.popLast() {
                area += 1; sx += x; sy += y
                guard abs(x - start.0) < maxRadius, abs(y - start.1) < maxRadius else { return nil }
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] where nx >= 0 && ny >= 0 && nx < width && ny < height {
                    let i = ny * width + nx
                    if !seen[i], self[nx, ny] > threshold { seen[i] = true; stack.append((nx, ny)) }
                }
            }
            return (area, (Double(sx) / Double(area), Double(sy) / Double(area)))
        }
    }
}
