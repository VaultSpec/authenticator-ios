import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import VaultSpec

struct TOTPTests {
    // RFC 6238 Appendix B test vectors (8 digits)
    private let sha1Key = Data("12345678901234567890".utf8)
    private let sha256Key = Data("12345678901234567890123456789012".utf8)
    private let sha512Key = Data("1234567890123456789012345678901234567890123456789012345678901234".utf8)

    @Test(arguments: [
        (59.0, "94287082", "46119246", "90693936"),
        (1_111_111_109.0, "07081804", "68084774", "25091201"),
        (1_234_567_890.0, "89005924", "91819424", "93441116"),
        (20_000_000_000.0, "65353130", "77737706", "47863826"),
    ])
    func rfc6238Vectors(time: Double, sha1: String, sha256: String, sha512: String) {
        let counter = UInt64(time / 30)
        #expect(TOTP.code(key: sha1Key, counter: counter, digits: 8, algorithm: .sha1) == sha1)
        #expect(TOTP.code(key: sha256Key, counter: counter, digits: 8, algorithm: .sha256) == sha256)
        #expect(TOTP.code(key: sha512Key, counter: counter, digits: 8, algorithm: .sha512) == sha512)
    }

    @Test func accountCodeUsesBase32SecretAndPeriod() {
        let account = Account(issuer: "Test", name: "", secret: Base32.encode(sha1Key), digits: 8)
        #expect(TOTP.code(for: account, at: Date(timeIntervalSince1970: 59)) == "94287082")
    }

    @Test func secondsRemaining() {
        #expect(TOTP.secondsRemaining(period: 30, at: Date(timeIntervalSince1970: 59)) == 1)
        #expect(TOTP.secondsRemaining(period: 30, at: Date(timeIntervalSince1970: 60)) == 30)
    }

    @Test func formatting() {
        #expect(TOTP.formatted("123456") == "123 456")
        #expect(TOTP.formatted("12345678") == "1234 5678")
    }
}

struct Base32Tests {
    @Test func roundTrip() {
        let data = Data("12345678901234567890".utf8)
        let encoded = Base32.encode(data)
        #expect(encoded == "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        #expect(Base32.decode(encoded) == data)
    }

    @Test func toleratesSpacesLowercaseAndPadding() {
        #expect(Base32.decode("gezd gnbv-gy3t qojq====") == Base32.decode("GEZDGNBVGY3TQOJQ"))
    }

    @Test func rejectsInvalidCharacters() {
        #expect(Base32.decode("ABC1") == nil)
        #expect(Base32.decode("") == nil)
    }
}

struct OTPAuthURITests {
    @Test func parsesFullLink() throws {
        let account = try OTPAuthURI.parse(
            "otpauth://totp/GitHub:alex%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA256&digits=8&period=60"
        )
        #expect(account.issuer == "GitHub")
        #expect(account.name == "alex@example.com")
        #expect(account.secret == "JBSWY3DPEHPK3PXP")
        #expect(account.algorithm == .sha256)
        #expect(account.digits == 8)
        #expect(account.period == 60)
    }

    @Test func usesLabelIssuerWhenParameterMissing() throws {
        let account = try OTPAuthURI.parse("otpauth://totp/Proton:me?secret=JBSWY3DPEHPK3PXP")
        #expect(account.issuer == "Proton")
        #expect(account.name == "me")
        #expect(account.digits == 6)
        #expect(account.period == 30)
    }

    @Test func rejectsHOTPAndMissingSecret() {
        #expect(throws: OTPAuthURI.ParseError.notTOTP) { try OTPAuthURI.parse("otpauth://hotp/x?secret=JBSWY3DP&counter=1") }
        #expect(throws: OTPAuthURI.ParseError.missingSecret) { try OTPAuthURI.parse("otpauth://totp/x?issuer=X") }
        #expect(throws: OTPAuthURI.ParseError.invalidSecret) { try OTPAuthURI.parse("otpauth://totp/x?secret=0189") }
    }
}

struct VaultCryptoTests {
    @Test func sealAndOpen() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try VaultCrypto.seal(Data("secret codes".utf8), with: key)
        #expect(try VaultCrypto.open(sealed, with: key) == Data("secret codes".utf8))
        #expect(throws: (any Error).self) { try VaultCrypto.open(sealed, with: SymmetricKey(size: .bits256)) }
    }

    @Test func keyDerivationIsDeterministicAndSaltDependent() throws {
        let salt = Data(repeating: 7, count: 16)
        let a = try VaultCrypto.deriveKey(password: "correct horse", salt: salt, rounds: 1_000)
        let b = try VaultCrypto.deriveKey(password: "correct horse", salt: salt, rounds: 1_000)
        let c = try VaultCrypto.deriveKey(password: "correct horse", salt: Data(repeating: 8, count: 16), rounds: 1_000)
        #expect(a == b)
        #expect(a != c)
    }

    // RFC 7914 / known PBKDF2-HMAC-SHA256 vector: "password" / "salt", 1 iteration
    @Test func pbkdf2KnownVector() throws {
        let key = try VaultCrypto.deriveKey(password: "password", salt: Data("salt".utf8), rounds: 1)
        let hex = key.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
    }
}

struct AppSettingsTests {
    private func fresh() -> AppSettings {
        let defaults = UserDefaults(suiteName: "settings-tests")!
        defaults.removePersistentDomain(forName: "settings-tests")
        return AppSettings(defaults: defaults)
    }

    @Test func defaultsMatchAndroid() {
        let settings = fresh()
        #expect(!settings.allowScreenshots && !settings.tapToReveal && !settings.highlightOnTap)
        #expect(settings.tapToCopy) // iOS has always copied on tap
        #expect(settings.passwordReminderDays == 15 && settings.revealSeconds == 30)
    }

    @Test func passwordReminder() {
        let settings = fresh()
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(!settings.isPasswordReminderDue(at: start)) // never entered: not due, as on Android
        settings.recordPasswordEntry(at: start)
        #expect(!settings.isPasswordReminderDue(at: start.addingTimeInterval(14 * 86_400)))
        #expect(settings.isPasswordReminderDue(at: start.addingTimeInterval(16 * 86_400)))
        settings.passwordReminderDays = 30
        #expect(!settings.isPasswordReminderDue(at: start.addingTimeInterval(16 * 86_400)))
    }

    @Test func settingsPersist() {
        let defaults = UserDefaults(suiteName: "settings-persist")!
        defaults.removePersistentDomain(forName: "settings-persist")
        let first = AppSettings(defaults: defaults)
        first.tapToReveal = true
        first.passwordReminderDays = 7
        let second = AppSettings(defaults: defaults)
        #expect(second.tapToReveal && second.passwordReminderDays == 7)
    }
}

struct ScreenshotShieldTests {
    /// iOS marks a secure text field's canvas layer to be skipped by screenshots and recordings.
    /// This reads that private flag (tests only) so an iOS change that breaks the shield shows up here.
    @Test func shieldContentIsInTheSecureLayer() throws {
        let view = ShieldView(content: AnyView(Text("123 456")))
        let container = try #require(view.subviews.first)
        #expect(String(describing: type(of: container)).contains("Canvas"))

        let flag = { (container.layer.value(forKey: "disableUpdateMask") as? NSNumber)?.intValue ?? 0 }
        view.setProtected(true)
        #expect(flag() != 0)
        view.setProtected(false)
        #expect(flag() == 0)
    }
}
