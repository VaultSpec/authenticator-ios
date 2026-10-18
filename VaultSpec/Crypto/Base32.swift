import Foundation

/// RFC 4648 Base32, as used for authenticator secrets.
nonisolated enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// Upper-cases and strips spaces, dashes and padding so pasted keys still decode.
    static func normalize(_ string: String) -> String {
        string.uppercased().filter { !" -=\n\t".contains($0) }
    }

    static func decode(_ string: String) -> Data? {
        let input = normalize(string)
        guard !input.isEmpty else { return nil }
        var buffer = 0, bits = 0
        var output = Data()
        output.reserveCapacity(input.count * 5 / 8)
        for character in input {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((buffer >> bits) & 0xFF))
            }
        }
        return output
    }

    static func encode(_ data: Data) -> String {
        var output = ""
        var buffer = 0, bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[(buffer >> bits) & 0x1F])
            }
        }
        if bits > 0 { output.append(alphabet[(buffer << (5 - bits)) & 0x1F]) }
        return output
    }
}
