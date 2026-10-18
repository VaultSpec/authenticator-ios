import CryptoKit
import Foundation

/// scrypt (RFC 7914). Cloud backups derive their key with it, with the same parameters as the
/// Android app, so a backup made on either platform opens on the other.
nonisolated enum Scrypt {
    /// Slow and memory-hard on purpose (32 MB at N = 32768, r = 8): call off the main thread.
    static func derive(password: Data, salt: Data, n: Int, r: Int, p: Int, length: Int) -> Data {
        precondition(n > 1 && n & (n - 1) == 0, "N must be a power of two")
        let words = 32 * r // one 128·r-byte block as 32-bit words

        let initial = pbkdf2SHA256(password: password, salt: salt, length: p * 128 * r)
        let b = UnsafeMutablePointer<UInt32>.allocate(capacity: p * words)
        let v = UnsafeMutablePointer<UInt32>.allocate(capacity: n * words)
        let xy = UnsafeMutablePointer<UInt32>.allocate(capacity: 2 * words)
        defer {
            b.deallocate()
            v.update(repeating: 0, count: n * words)
            v.deallocate()
            xy.deallocate()
        }

        initial.withUnsafeBytes { raw in
            for i in 0..<(p * words) {
                b[i] = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self))
            }
        }
        for i in 0..<p {
            roMix(b + i * words, r: r, n: n, v: v, xy: xy)
        }
        var mixed = Data(count: p * words * 4)
        mixed.withUnsafeMutableBytes { raw in
            for i in 0..<(p * words) {
                raw.storeBytes(of: b[i].littleEndian, toByteOffset: i * 4, as: UInt32.self)
            }
        }
        b.update(repeating: 0, count: p * words)
        return pbkdf2SHA256(password: password, salt: mixed, length: length)
    }

    /// PBKDF2-HMAC-SHA256 with one iteration, which is all scrypt needs.
    private static func pbkdf2SHA256(password: Data, salt: Data, length: Int) -> Data {
        let key = SymmetricKey(data: password)
        var output = Data(capacity: length)
        var block: UInt32 = 1
        while output.count < length {
            var message = salt
            withUnsafeBytes(of: block.bigEndian) { message.append(contentsOf: $0) }
            output.append(contentsOf: HMAC<SHA256>.authenticationCode(for: message, using: key))
            block += 1
        }
        return output.prefix(length)
    }

    private static func roMix(_ b: UnsafeMutablePointer<UInt32>, r: Int, n: Int,
                              v: UnsafeMutablePointer<UInt32>, xy: UnsafeMutablePointer<UInt32>) {
        let words = 32 * r
        var x = xy
        var y = xy + words
        x.update(from: b, count: words)
        for i in 0..<n {
            (v + i * words).update(from: x, count: words)
            blockMix(x, into: y, r: r)
            swap(&x, &y)
        }
        for _ in 0..<n {
            let j = Int(x[(2 * r - 1) * 16] & UInt32(n - 1))
            let vj = v + j * words
            for k in 0..<words { x[k] ^= vj[k] }
            blockMix(x, into: y, r: r)
            swap(&x, &y)
        }
        b.update(from: x, count: words)
    }

    private static func blockMix(_ input: UnsafeMutablePointer<UInt32>, into output: UnsafeMutablePointer<UInt32>, r: Int) {
        var t = (input + (2 * r - 1) * 16).withMemoryRebound(to: SIMD16<UInt32>.self, capacity: 1) { $0.pointee }
        for i in 0..<(2 * r) {
            t ^= (input + i * 16).withMemoryRebound(to: SIMD16<UInt32>.self, capacity: 1) { $0.pointee }
            t = salsa20_8(t)
            // Even blocks go to the first half of the output, odd blocks to the second
            let slot = i % 2 == 0 ? i / 2 : r + i / 2
            (output + slot * 16).withMemoryRebound(to: SIMD16<UInt32>.self, capacity: 1) { $0.pointee = t }
        }
    }

    @inline(__always)
    private static func rotl(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value &<< amount) | (value &>> (32 &- amount))
    }

    private static func salsa20_8(_ input: SIMD16<UInt32>) -> SIMD16<UInt32> {
        var x0 = input[0], x1 = input[1], x2 = input[2], x3 = input[3]
        var x4 = input[4], x5 = input[5], x6 = input[6], x7 = input[7]
        var x8 = input[8], x9 = input[9], x10 = input[10], x11 = input[11]
        var x12 = input[12], x13 = input[13], x14 = input[14], x15 = input[15]
        for _ in 0..<4 {
            // Columns
            x4 ^= rotl(x0 &+ x12, 7); x8 ^= rotl(x4 &+ x0, 9); x12 ^= rotl(x8 &+ x4, 13); x0 ^= rotl(x12 &+ x8, 18)
            x9 ^= rotl(x5 &+ x1, 7); x13 ^= rotl(x9 &+ x5, 9); x1 ^= rotl(x13 &+ x9, 13); x5 ^= rotl(x1 &+ x13, 18)
            x14 ^= rotl(x10 &+ x6, 7); x2 ^= rotl(x14 &+ x10, 9); x6 ^= rotl(x2 &+ x14, 13); x10 ^= rotl(x6 &+ x2, 18)
            x3 ^= rotl(x15 &+ x11, 7); x7 ^= rotl(x3 &+ x15, 9); x11 ^= rotl(x7 &+ x3, 13); x15 ^= rotl(x11 &+ x7, 18)
            // Rows
            x1 ^= rotl(x0 &+ x3, 7); x2 ^= rotl(x1 &+ x0, 9); x3 ^= rotl(x2 &+ x1, 13); x0 ^= rotl(x3 &+ x2, 18)
            x6 ^= rotl(x5 &+ x4, 7); x7 ^= rotl(x6 &+ x5, 9); x4 ^= rotl(x7 &+ x6, 13); x5 ^= rotl(x4 &+ x7, 18)
            x11 ^= rotl(x10 &+ x9, 7); x8 ^= rotl(x11 &+ x10, 9); x9 ^= rotl(x8 &+ x11, 13); x10 ^= rotl(x9 &+ x8, 18)
            x12 ^= rotl(x15 &+ x14, 7); x13 ^= rotl(x12 &+ x15, 9); x14 ^= rotl(x13 &+ x12, 13); x15 ^= rotl(x14 &+ x13, 18)
        }
        return input &+ SIMD16(x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15)
    }
}
