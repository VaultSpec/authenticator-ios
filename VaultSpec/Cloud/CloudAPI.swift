import Foundation

/// Client for the VaultSpec Cloud API (the same service the Android app uses).
///
/// Sign-in is two steps: the account password triggers an emailed six-digit code, and the
/// password plus that code returns a short-lived access token and a single-use refresh token.
/// The session is kept in the Keychain on this device only.
actor CloudAPI {
    nonisolated struct Session: Codable, Sendable {
        var email: String
        var accessToken: String
        var refreshToken: String
    }

    nonisolated struct BackupMeta: Codable, Sendable {
        let id: String
        let keyId: String
        let sizeBytes: Int
        let createdAt: String
    }

    nonisolated struct RemoteBackup: Codable, Sendable {
        let id: String
        let keyId: String
        let createdAt: String
        let payload: String
    }

    nonisolated struct Failure: LocalizedError, Sendable {
        let code: String
        let message: String
        var errorDescription: String? { message }

        static let offline = Failure(code: "offline", message: "Can't reach VaultSpec Cloud. Check your connection and try again.")
        static let signedOut = Failure(code: "unauthorized", message: "Your session has ended. Sign in again.")
    }

    nonisolated static let baseURL: URL = {
        #if DEBUG
        // `-cloudBaseURL http://127.0.0.1:8080` points a debug build at a local server
        if let override = UserDefaults.standard.string(forKey: "cloudBaseURL"), let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: "https://api.vaultspec.in")!
    }()

    private let baseURL: URL
    private let urlSession: URLSession
    private(set) var session: Session?

    init(baseURL: URL = CloudAPI.baseURL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        urlSession = URLSession(configuration: configuration)
        session = Keychain.read(.cloudSession).flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
    }

    var email: String? { session?.email }

    // MARK: Account

    /// Creates the account and emails a code. The response is the same if the email is taken.
    func register(email: String, password: String) async throws {
        _ = try await send("POST", "/v1/auth/register", body: ["email": email, "password": password])
    }

    /// Sign-in step 1: checks the password and emails a code.
    func requestCode(email: String, password: String) async throws {
        _ = try await send("POST", "/v1/auth/login", body: ["email": email, "password": password])
    }

    /// Sign-in step 2: exchanges the password and the emailed code for a session.
    @discardableResult
    func verify(email: String, password: String, code: String, deviceName: String) async throws -> Session {
        struct Response: Decodable { let email: String?; let accessToken: String; let refreshToken: String }
        let data = try await send("POST", "/v1/auth/login/verify", body: [
            "email": email, "password": password, "code": code, "deviceName": deviceName,
        ])
        let response = try decode(Response.self, data)
        let session = Session(email: response.email ?? email, accessToken: response.accessToken, refreshToken: response.refreshToken)
        store(session)
        return session
    }

    func forgotPassword(email: String) async throws {
        _ = try await send("POST", "/v1/auth/forgot", body: ["email": email])
    }

    /// Signs out locally even when the server can't be reached.
    func signOut() async {
        if let refreshToken = session?.refreshToken {
            _ = try? await send("POST", "/v1/auth/logout", body: ["refreshToken": refreshToken])
        }
        store(nil)
    }

    /// Deletes the account and every backup in it.
    func deleteAccount(password: String) async throws {
        _ = try await authorized("DELETE", "/v1/account", body: ["password": password])
        store(nil)
    }

    // MARK: Backups

    func upload(keyId: String, payload: String) async throws -> BackupMeta {
        try decode(BackupMeta.self, try await authorized("POST", "/v1/backups", body: ["keyId": keyId, "payload": payload]))
    }

    func listBackups() async throws -> [BackupMeta] {
        struct Response: Decodable { let backups: [BackupMeta] }
        return try decode(Response.self, try await authorized("GET", "/v1/backups")).backups
    }

    /// The newest backup, or nil when the account has none.
    func latestBackup() async throws -> RemoteBackup? {
        do {
            return try decode(RemoteBackup.self, try await authorized("GET", "/v1/backups/latest"))
        } catch let failure as Failure where failure.code == "not_found" {
            return nil
        }
    }

    // MARK: Scan & Connect

    nonisolated struct Pairing: Codable, Sendable {
        let id: String
        let token: String
        let expiresAt: String
    }

    /// Uploads a one-time snapshot for a new device and returns the token to show as a QR code.
    func startPairing(keyId: String, payload: String) async throws -> Pairing {
        try decode(Pairing.self, try await authorized("POST", "/v1/pairing", body: ["keyId": keyId, "payload": payload]))
    }

    /// "pending", "claimed" or "expired".
    func pairingStatus(id: String) async throws -> String {
        struct Response: Decodable { let status: String }
        return try decode(Response.self, try await authorized("GET", "/v1/pairing/\(id)")).status
    }

    func cancelPairing(id: String) async {
        _ = try? await authorized("DELETE", "/v1/pairing/\(id)")
    }

    /// The new device: claims the scanned token, signs in to the same account and returns the snapshot.
    func claimPairing(token: String, deviceName: String) async throws -> String {
        struct Response: Decodable { let email: String; let payload: String; let accessToken: String; let refreshToken: String }
        let response = try decode(Response.self, try await send("POST", "/v1/pairing/claim", body: ["token": token, "deviceName": deviceName]))
        store(Session(email: response.email, accessToken: response.accessToken, refreshToken: response.refreshToken))
        return response.payload
    }

    // MARK: Transport

    private func store(_ session: Session?) {
        self.session = session
        if let session, let data = try? JSONEncoder().encode(session) {
            try? Keychain.save(data, as: .cloudSession)
        } else {
            Keychain.delete(.cloudSession)
        }
    }

    /// Sends with the access token, refreshing it once if the server says it expired.
    private func authorized(_ method: String, _ path: String, body: [String: String]? = nil) async throws -> Data {
        guard let current = session else { throw Failure.signedOut }
        do {
            return try await send(method, path, body: body, token: current.accessToken)
        } catch let failure as Failure where failure.code == "unauthorized" {
            let refreshed = try await refresh(current)
            return try await send(method, path, body: body, token: refreshed.accessToken)
        }
    }

    private func refresh(_ stale: Session) async throws -> Session {
        // Another call may already have rotated the token while this one waited
        if let session, session.refreshToken != stale.refreshToken { return session }
        struct Response: Decodable { let accessToken: String; let refreshToken: String }
        do {
            let response = try decode(Response.self, try await send("POST", "/v1/auth/refresh", body: ["refreshToken": stale.refreshToken]))
            let session = Session(email: stale.email, accessToken: response.accessToken, refreshToken: response.refreshToken)
            store(session)
            return session
        } catch let failure as Failure where failure.code == "unauthorized" {
            store(nil)
            throw Failure.signedOut
        }
    }

    private func send(_ method: String, _ path: String, body: [String: String]? = nil, token: String? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw Failure.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            struct ErrorBody: Decodable { let error: String?; let message: String? }
            let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data)
            if status == 401, parsed?.error == nil || parsed?.error == "unauthorized" { throw Failure.signedOut }
            throw Failure(
                code: parsed?.error ?? "http_\(status)",
                message: parsed?.message ?? "VaultSpec Cloud returned an error (\(status)). Try again."
            )
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw Failure(code: "bad_response", message: "VaultSpec Cloud sent a response this version can't read.")
        }
    }
}
