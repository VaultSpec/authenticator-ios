import Foundation
import Testing
@testable import VaultSpec

struct ScryptTests {
    private func hex(_ string: String) -> Data { Hex.decode(string.replacingOccurrences(of: " ", with: ""))! }

    // RFC 7914 section 12 test vectors
    @Test func rfc7914EmptyVector() {
        let derived = Scrypt.derive(password: Data(), salt: Data(), n: 16, r: 1, p: 1, length: 64)
        #expect(derived == hex("77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906"))
    }

    @Test func rfc7914PasswordVector() {
        let derived = Scrypt.derive(password: Data("password".utf8), salt: Data("NaCl".utf8), n: 1024, r: 8, p: 16, length: 64)
        #expect(derived == hex("fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b3731622eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640"))
    }
}

struct BackupFormatTests {
    /// Written by Python's hashlib.scrypt + AES-GCM using the Android app's format and field names.
    private let androidPayload = #"{"version": 1, "app": "VaultSpec", "created": "2026-10-18T09:41:00Z", "params": {"n": 32768, "r": 8, "p": 1, "salt": "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"}, "data": "VTFFyGGAK+1kTV6LCeUsLYKc2QFIEsI6H89qahikfhCprvpoKwjYD2/L1snQeOK8QXogmlMliLus8poFJWwcu4fCfONCEiYVcT4rZCw31103anQpbWDvcKMwMc7vY91pQNlJRPsRbh9Xx2yDNz5bPsB1LjNdrVKJ12aztyiNnlX8HCS0xxTxcrkE36b/DAJ17ZrKyEy0n1t1SwXjcuH+DJr/R6uP/FszqdDXG1oSb8ck4DoDxa8ayIIqCGitIoAGpBIXlbwPOHQNpqPKXNb7l4Q9kSPoLFX0QRkK16aZbcU+R6cy0x4Iwket2HqLaQ7R/pEH5dlbseuyuPgux7I5Lsj8817JHC7MdUXKhNKRyfN4fZ2/xK8g1EZqMEuEgHQW1DrOgIjUSgU4ujinNGb1g7e9HDgGB9Vr3pDSS0NE5xrRfTNOQiDj1V4ZMHVIWnw/Pslk8v4W", "iv": "ZGVmZ2hpamtsbW5v"}"#
    private let androidPassword = "correct horse battery"

    private func decode(_ json: String) throws -> BackupPayload {
        try JSONDecoder().decode(BackupPayload.self, from: Data(json.utf8))
    }

    @Test func opensAndroidBackup() throws {
        let accounts = try BackupFormat.decrypt(try decode(androidPayload), password: androidPassword)
        #expect(accounts.count == 2)
        #expect(accounts[0].issuer == "GitHub" && accounts[0].name == "alex-dev")
        #expect(accounts[0].secret == "JBSWY3DPEHPK3PXP" && accounts[0].algorithm == .sha1 && accounts[0].category == "Work")
        #expect(accounts[1].algorithm == .sha256 && accounts[1].digits == 8 && accounts[1].period == 60)
    }

    @Test func derivesTheSameKeyAndKeyIdAsAndroid() throws {
        let key = try BackupFormat.deriveKey(password: androidPassword, saltHex: try decode(androidPayload).params.salt)
        #expect(Hex.encode(key.raw) == "ea5876e314bba2c4b147c6a3fb494474908429268a8bfe556032e98bbd88c30f")
        #expect(key.keyId == "630dcd2966c43366")
    }

    @Test func wrongPasswordIsRejected() throws {
        #expect(throws: BackupFormat.FormatError.self) {
            try BackupFormat.decrypt(try decode(androidPayload), password: "wrong password")
        }
    }

    @Test func roundTripUsesAndroidFieldNames() throws {
        let key = try BackupFormat.deriveKey(password: "round trip")
        let original = [
            Account(issuer: "Google", name: "alex@example.com", secret: "JBSWY3DPEHPK3PXP", category: "Personal"),
            Account(issuer: "", name: "server", secret: "KRSXG5CTMVRXEZLU", algorithm: .sha512, digits: 8),
        ]
        let payload = try BackupFormat.encrypt(original, with: key)
        let json = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        #expect(json.contains(#""params":{"#) && json.contains(#""app":"VaultSpec""#))
        #expect(payload.params.salt.count == 64 && key.keyId.count == 16)

        let restored = try BackupFormat.decrypt(try decode(json), key: key)
        #expect(restored.map(\.identity) == original.map(\.identity))
        #expect(restored[1].algorithm == .sha512 && restored[1].digits == 8)
    }
}

/// End to end against a running backend. Start one with a review account and run with
/// `TEST_RUNNER_VAULTSPEC_CLOUD_TEST_URL=http://127.0.0.1:8080` (see README).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["VAULTSPEC_CLOUD_TEST_URL"] != nil), .serialized)
struct CloudIntegrationTests {
    private let env = ProcessInfo.processInfo.environment
    private var url: URL { URL(string: env["VAULTSPEC_CLOUD_TEST_URL"]!)! }
    private var email: String { env["VAULTSPEC_CLOUD_TEST_EMAIL"] ?? "ios-test@vaultspec.local" }
    private var code: String { env["VAULTSPEC_CLOUD_TEST_CODE"] ?? "246810" }
    private let password = "ios-test-account"

    @Test func backupRestoreRekeyAndDelete() async throws {
        let api = CloudAPI(baseURL: url)
        let defaults = UserDefaults(suiteName: "cloud-integration")!
        defaults.removePersistentDomain(forName: "cloud-integration")
        let cloud = CloudStore(api: api, defaults: defaults)

        try await cloud.register(email: email, password: password)
        try await cloud.verify(email: email, password: password, code: code)
        #expect(cloud.email == email)

        let accounts = [
            Account(issuer: "GitHub", name: "alex-dev", secret: "JBSWY3DPEHPK3PXP", category: "Work"),
            Account(issuer: "Proton", name: "alex@proton.me", secret: "KRSXG5CTMVRXEZLU"),
        ]
        try await cloud.enable(vaultPassword: "first vault password", accounts: accounts, replaceExisting: true)
        #expect(cloud.isEnabled && !cloud.isPending && cloud.lastBackupAt != nil)

        // A second device would be warned before replacing the backup
        await #expect(throws: CloudStore.CloudError.self) {
            try await cloud.enable(vaultPassword: "other vault", accounts: [], replaceExisting: false)
        }

        let latest = try #require(try await cloud.fetchLatest())
        let restored = try await cloud.decrypt(latest.payload, vaultPassword: "first vault password")
        #expect(restored.map(\.identity) == accounts.map(\.identity))

        // Retention: only the newest three are kept
        for _ in 0..<3 { try await cloud.backupNow(accounts) }
        #expect(try await api.listBackups().count == 3)

        // A new vault password leaves exactly one backup, which the old password can't open
        await cloud.vaultPasswordChanged(to: "second vault password", accounts: accounts)
        #expect(try await api.listBackups().count == 1)
        let rekeyed = try #require(try await cloud.fetchLatest())
        await #expect(throws: BackupFormat.FormatError.self) {
            try await cloud.decrypt(rekeyed.payload, vaultPassword: "first vault password")
        }
        #expect(try await cloud.decrypt(rekeyed.payload, vaultPassword: "second vault password").count == 2)

        try await cloud.deleteAccount(password: password)
        #expect(!cloud.isSignedIn && !cloud.isEnabled)
    }
}
