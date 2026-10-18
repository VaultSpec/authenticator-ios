import CryptoKit
import Foundation

/// The encrypted backup document, the same JSON the Android app writes to `.vsbk` files and
/// uploads to VaultSpec Cloud: scrypt parameters, a hex salt, and AES-256-GCM ciphertext.
nonisolated struct BackupPayload: Codable, Sendable {
    struct Params: Codable, Sendable {
        var n = BackupFormat.scryptN
        var r = BackupFormat.scryptR
        var p = BackupFormat.scryptP
        var salt: String // hex
    }

    var version = 1
    var app = "VaultSpec"
    var created: String // ISO-8601 instant
    var params: Params
    var data: String // base64(ciphertext | tag)
    var iv: String // base64(12-byte nonce)
}

/// One account inside a backup. Field names match the Android app.
nonisolated struct BackupEntry: Codable, Sendable {
    var issuer: String
    var accountName: String
    var secret: String
    var algorithm: String
    var digits: Int
    var period: Int
    var category: String
    var icon: String?

    enum CodingKeys: String, CodingKey {
        case issuer, secret, algorithm, digits, period, category, icon
        case accountName = "account_name"
    }
}

nonisolated enum BackupFormat {
    static let scryptN = 32768
    static let scryptR = 8
    static let scryptP = 1
    static let saltLength = 32

    enum FormatError: LocalizedError {
        case wrongPassword, unreadable

        var errorDescription: String? {
            switch self {
            case .wrongPassword: "That vault password doesn't open this backup."
            case .unreadable: "This backup couldn't be read."
            }
        }
    }

    /// A key derived from the vault password, plus the salt it was derived with.
    struct Key: Codable, Sendable {
        let raw: Data
        let saltHex: String

        var symmetricKey: SymmetricKey { SymmetricKey(data: raw) }

        /// Identifies which vault-password generation made a backup without revealing anything
        /// about the key: the first 8 bytes of SHA-256(salt), hex-encoded.
        var keyId: String { Hex.encode(Data(SHA256.hash(data: Hex.decode(saltHex) ?? Data()).prefix(8))) }
    }

    /// Slow (scrypt): call off the main thread.
    static func deriveKey(password: String, saltHex: String? = nil, n: Int = scryptN, r: Int = scryptR, p: Int = scryptP) throws -> Key {
        let saltHex = saltHex ?? Hex.encode(VaultCrypto.randomBytes(saltLength))
        guard let salt = Hex.decode(saltHex) else { throw FormatError.unreadable }
        let raw = Scrypt.derive(password: Data(password.utf8), salt: salt, n: n, r: r, p: p, length: 32)
        return Key(raw: raw, saltHex: saltHex)
    }

    static func encrypt(_ accounts: [Account], with key: Key, now: Date = .now) throws -> BackupPayload {
        let entries = accounts.map {
            BackupEntry(
                issuer: $0.issuer, accountName: $0.name, secret: $0.secret, algorithm: $0.algorithm.rawValue,
                digits: $0.digits, period: $0.period, category: $0.category, icon: nil
            )
        }
        let sealed = try AES.GCM.seal(try JSONEncoder().encode(entries), using: key.symmetricKey)
        return BackupPayload(
            created: now.formatted(.iso8601),
            params: .init(salt: key.saltHex),
            data: (sealed.ciphertext + sealed.tag).base64EncodedString(),
            iv: Data(sealed.nonce).base64EncodedString()
        )
    }

    /// Slow (scrypt): call off the main thread.
    static func decrypt(_ payload: BackupPayload, password: String) throws -> [Account] {
        let p = payload.params
        guard p.n > 1, p.n & (p.n - 1) == 0, p.n <= 1 << 20, (1...32).contains(p.r), (1...16).contains(p.p) else {
            throw FormatError.unreadable
        }
        let key = try deriveKey(password: password, saltHex: p.salt, n: p.n, r: p.r, p: p.p)
        return try decrypt(payload, key: key)
    }

    static func decrypt(_ payload: BackupPayload, key: Key) throws -> [Account] {
        guard let combined = Data(base64Encoded: payload.data), combined.count > 16,
              let iv = Data(base64Encoded: payload.iv), let nonce = try? AES.GCM.Nonce(data: iv)
        else { throw FormatError.unreadable }
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: combined.dropLast(16), tag: combined.suffix(16))
        guard let plain = try? AES.GCM.open(box, using: key.symmetricKey) else { throw FormatError.wrongPassword }
        guard let entries = try? JSONDecoder().decode([BackupEntry].self, from: plain) else { throw FormatError.unreadable }
        return entries.map {
            Account(
                issuer: $0.issuer, name: $0.accountName, secret: Base32.normalize($0.secret),
                algorithm: Account.Algorithm(rawValue: $0.algorithm.uppercased()) ?? .sha1,
                digits: $0.digits, period: $0.period,
                category: $0.category.isEmpty ? Account.defaultCategory : $0.category
            )
        }
    }
}

nonisolated enum Hex {
    static func encode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func decode(_ string: String) -> Data? {
        guard string.count % 2 == 0 else { return nil }
        var data = Data(capacity: string.count / 2)
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
