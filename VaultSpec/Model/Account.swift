import Foundation

/// One two-factor account: everything needed to generate its codes.
nonisolated struct Account: Identifiable, Codable, Hashable, Sendable {
    enum Algorithm: String, Codable, CaseIterable, Sendable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }

    var id = UUID()
    var issuer: String
    var name: String
    /// Base32 secret, upper-cased, without spaces or padding.
    var secret: String
    var algorithm: Algorithm = .sha1
    var digits: Int = 6
    var period: Int = 30
    var category: String = Account.defaultCategory
    var createdAt = Date()

    /// The home screen's "everything" filter; an account saved with it has no category of its own.
    static let defaultCategory = "All"
    static let categories = ["All", "Personal", "Work", "Social"]

    /// Shown in lists: the issuer, or the account name when the issuer is empty.
    var title: String { issuer.isEmpty ? name : issuer }

    /// Two entries for the same login, used to skip duplicates when restoring.
    var identity: String { "\(issuer.lowercased())|\(name.lowercased())|\(secret)" }
}
