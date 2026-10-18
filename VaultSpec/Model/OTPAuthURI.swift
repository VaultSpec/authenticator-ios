import Foundation

/// Parses `otpauth://totp/Issuer:name?secret=...&issuer=...` links from QR codes.
nonisolated enum OTPAuthURI {
    enum ParseError: LocalizedError {
        case notTOTP, missingSecret, invalidSecret

        var errorDescription: String? {
            switch self {
            case .notTOTP: "This QR code isn't a time-based (TOTP) authenticator code."
            case .missingSecret: "This QR code doesn't contain a secret key."
            case .invalidSecret: "The secret key in this QR code isn't valid."
            }
        }
    }

    static func parse(_ string: String) throws -> Account {
        guard let components = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "otpauth",
              components.host?.lowercased() == "totp"
        else { throw ParseError.notTOTP }

        let query = Dictionary(
            (components.queryItems ?? []).compactMap { item in item.value.map { (item.name.lowercased(), $0) } },
            uniquingKeysWith: { first, _ in first }
        )

        guard let rawSecret = query["secret"], !rawSecret.isEmpty else { throw ParseError.missingSecret }
        let secret = Base32.normalize(rawSecret)
        guard Base32.decode(secret) != nil else { throw ParseError.invalidSecret }

        // Label is "Issuer:name" or just "name"
        let label = String(components.path.drop(while: { $0 == "/" })).removingPercentEncoding ?? ""
        let labelParts = label.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let labelIssuer = labelParts.count == 2 ? labelParts[0] : ""
        let name = labelParts.last ?? ""

        var account = Account(issuer: query["issuer"] ?? labelIssuer, name: name, secret: secret)
        if let algorithm = query["algorithm"].flatMap({ Account.Algorithm(rawValue: $0.uppercased()) }) {
            account.algorithm = algorithm
        }
        if let digits = query["digits"].flatMap(Int.init), [6, 7, 8].contains(digits) {
            account.digits = digits
        }
        if let period = query["period"].flatMap(Int.init), period > 0 {
            account.period = period
        }
        return account
    }
}
