import CryptoKit
import Foundation

/// Time-based one-time passwords (RFC 6238).
nonisolated enum TOTP {
    static func code(for account: Account, at date: Date = .now) -> String {
        guard let key = Base32.decode(account.secret) else { return String(repeating: "-", count: account.digits) }
        let counter = UInt64(max(0, date.timeIntervalSince1970) / Double(account.period))
        return code(key: key, counter: counter, digits: account.digits, algorithm: account.algorithm)
    }

    static func code(key: Data, counter: UInt64, digits: Int, algorithm: Account.Algorithm) -> String {
        let message = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        let symmetricKey = SymmetricKey(data: key)
        let mac: Data = switch algorithm {
        case .sha1: Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: symmetricKey))
        case .sha256: Data(HMAC<SHA256>.authenticationCode(for: message, using: symmetricKey))
        case .sha512: Data(HMAC<SHA512>.authenticationCode(for: message, using: symmetricKey))
        }
        // Dynamic truncation
        let offset = Int(mac[mac.count - 1] & 0x0F)
        let binary = (UInt32(mac[offset] & 0x7F) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
        let modulus = UInt32(pow(10, Double(digits)))
        let value = String(binary % modulus)
        return String(repeating: "0", count: max(0, digits - value.count)) + value
    }

    /// Whole seconds until the current code changes.
    static func secondsRemaining(period: Int, at date: Date = .now) -> Int {
        period - Int(date.timeIntervalSince1970) % period
    }

    /// "123456" → "123 456", "12345678" → "1234 5678".
    static func formatted(_ code: String) -> String {
        guard code.count >= 6 else { return code }
        let middle = code.index(code.startIndex, offsetBy: code.count / 2)
        return code[..<middle] + " " + code[middle...]
    }
}
