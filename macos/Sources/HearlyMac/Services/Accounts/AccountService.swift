import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

struct AccountSession: Codable {
    struct User: Codable { let id: String; let email: String? }
    let access_token: String
    let refresh_token: String
    var expires_at: Double?
    let expires_in: Double?
    let user: User
    var backend_url: String?

    var expiration: Double? { expires_at ?? (authJWTPayload(access_token)?["exp"] as? Double) }
    func needsRefresh(at date: Date = Date()) -> Bool {
        guard let expiration else { return true }
        return expiration <= date.timeIntervalSince1970 + 60
    }
}

// This only reads routing/expiration metadata. Supabase validates token signatures server-side.
private func authJWTPayload(_ value: String) -> [String: Any]? {
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
    guard let data = Data(base64Encoded: payload) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

struct BackendConfiguration: Codable {
    var url: String
    var publishableKey: String
    var projectURL: String? {
        guard let components = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil,
              components.fragment == nil, components.path.isEmpty || components.path == "/" else { return nil }
        return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    var valid: Bool {
        guard projectURL != nil, !publishableKey.contains(where: { $0.isWhitespace }) else { return false }
        if publishableKey.hasPrefix("sb_publishable_"), publishableKey.count > 22 { return true }
        // Do not accidentally ship a server-only secret or service_role key in the Mac app.
        return authJWTPayload(publishableKey)?["role"] as? String == "anon"
    }
    static func load() -> Self? {
        if let url = ProcessInfo.processInfo.environment["HEARLY_SUPABASE_URL"],
           let key = ProcessInfo.processInfo.environment["HEARLY_SUPABASE_PUBLISHABLE_KEY"] {
            return Self(url: url, publishableKey: key)
        }
        guard let file = Bundle.main.url(forResource: "Backend", withExtension: "json"),
              let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

struct AccountSessionStore {
    var read: () throws -> Data?
    var write: (Data) throws -> Void
    var remove: () -> Void
    static let keychain = AccountSessionStore(
        read: { try SecureStore.read("session") },
        write: { try SecureStore.write($0, account: "session") },
        remove: { SecureStore.remove("session") }
    )
}

private struct AccountRequestFailure: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class AccountService: NSObject, ASWebAuthenticationPresentationContextProviding {
    let configuration: BackendConfiguration?
    private let urlSession: URLSession
    private let sessionStore: AccountSessionStore
    private var browserSession: ASWebAuthenticationSession?
    private var refreshTask: Task<AccountSession, Error>?
    private var generation = UUID()
    var configured: Bool { configuration?.valid == true }

    init(configuration: BackendConfiguration? = BackendConfiguration.load(), urlSession: URLSession = .shared,
         sessionStore: AccountSessionStore = .keychain) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.sessionStore = sessionStore
        super.init()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
    }

    private func request(_ path: String, body: [String: Any], bearer: String? = nil) async throws -> Data {
        guard configured, let configuration, let root = configuration.projectURL,
              let url = URL(string: root + path) else {
            throw HearlyFailure.message("Connect your Hearly Supabase project to enable account sign-in.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw HearlyFailure.message("The account service returned an invalid response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AccountRequestFailure(status: response.statusCode, message: object?["msg"] as? String ?? object?["error_description"] as? String ?? object?["message"] as? String ?? "The account service could not complete this request.")
        }
        return data
    }

    func sendCode(email: String) async throws {
        _ = try await request("/auth/v1/otp", body: ["email": email, "create_user": true])
    }
    func verify(email: String, code: String) async throws -> AccountSession {
        let expectedGeneration = generation
        let data = try await request("/auth/v1/verify", body: ["email": email, "token": code.trimmingCharacters(in: .whitespacesAndNewlines), "type": "email"])
        guard generation == expectedGeneration else { throw CancellationError() }
        return try save(data)
    }
    func restore() async throws -> AccountSession? {
        guard configured, let root = configuration?.projectURL,
              let data = try sessionStore.read() else { return nil }
        let session = try JSONDecoder().decode(AccountSession.self, from: data)
        // Old sessions may not have a project tag; their issuer must identify this project.
        let matchesProject = session.backend_url.map { $0 == root }
            ?? (authJWTPayload(session.access_token)?["iss"] as? String == root + "/auth/v1")
        guard matchesProject else { return nil }
        if !session.needsRefresh() { return session }
        if let refreshTask { return try await refreshTask.value }
        let expectedGeneration = generation
        let task = Task { @MainActor in
            do {
                let data = try await self.request("/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": session.refresh_token])
                try Task.checkCancellation()
                guard self.generation == expectedGeneration else { throw CancellationError() }
                return try self.save(data)
            } catch {
                // A rejected refresh credential is unusable. Network/server outages must not
                // delete a recoverable session, and old requests must not clear a new login.
                if self.generation == expectedGeneration, let failure = error as? AccountRequestFailure,
                   [400, 401].contains(failure.status) { self.sessionStore.remove() }
                throw error
            }
        }
        refreshTask = task
        defer { if generation == expectedGeneration { refreshTask = nil } }
        return try await task.value
    }
    private func save(_ data: Data) throws -> AccountSession {
        var session = try JSONDecoder().decode(AccountSession.self, from: data)
        guard !session.access_token.isEmpty, !session.refresh_token.isEmpty, !session.user.id.isEmpty else {
            throw HearlyFailure.message("The account service returned an incomplete session. Please sign in again.")
        }
        session.expires_at = session.expiration ?? session.expires_in.map { Date().timeIntervalSince1970 + $0 }
        guard let expiration = session.expires_at, expiration.isFinite, expiration > Date().timeIntervalSince1970 else {
            throw HearlyFailure.message("The account service returned an expired session. Please sign in again.")
        }
        session.backend_url = configuration?.projectURL
        try sessionStore.write(JSONEncoder().encode(session))
        return session
    }
    static func authorizationCode(from callback: URL) throws -> String {
        guard callback.scheme == "hearly", callback.host == "auth", callback.path == "/callback",
              callback.user == nil, callback.password == nil, callback.port == nil, callback.fragment == nil,
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else {
            throw HearlyFailure.message("Sign-in returned an invalid callback URL.")
        }
        if let error = items.first(where: { $0.name == "error_description" || $0.name == "error" })?.value {
            throw HearlyFailure.message(error)
        }
        let codes = items.filter { $0.name == "code" }
        guard codes.count == 1, let code = codes.first?.value, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HearlyFailure.message("Sign-in did not return an authorization code.")
        }
        return code
    }
    func oauth(_ provider: String) async throws -> AccountSession {
        guard configured, let root = configuration?.projectURL else { throw HearlyFailure.message("Connect your Hearly Supabase project to enable \(provider.capitalized) sign-in.") }
        guard ["apple", "google"].contains(provider) else { throw HearlyFailure.message("This sign-in provider is not supported.") }
        guard browserSession == nil else { throw HearlyFailure.message("Finish the current sign-in first.") }
        let expectedGeneration = generation
        defer { browserSession = nil }
        let verifier = UUID().uuidString + UUID().uuidString
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        guard var components = URLComponents(string: root + "/auth/v1/authorize") else { throw HearlyFailure.message("Invalid account service URL.") }
        components.queryItems = [URLQueryItem(name: "provider", value: provider), URLQueryItem(name: "redirect_to", value: "hearly://auth/callback"), URLQueryItem(name: "code_challenge", value: challenge), URLQueryItem(name: "code_challenge_method", value: "s256")]
        guard let url = components.url else { throw HearlyFailure.message("Invalid account sign-in URL.") }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "hearly") { url, error in
                if let error { continuation.resume(throwing: error) }
                else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: HearlyFailure.message("Sign-in was cancelled.")) }
            }
            session.presentationContextProvider = self
            browserSession = session
            if !session.start() { continuation.resume(throwing: HearlyFailure.message("Cannot open account sign-in.")) }
        }
        guard generation == expectedGeneration else { throw CancellationError() }
        let code = try Self.authorizationCode(from: callback)
        let data = try await request("/auth/v1/token?grant_type=pkce", body: ["auth_code": code, "code_verifier": verifier])
        guard generation == expectedGeneration else { throw CancellationError() }
        return try save(data)
    }
    func saveAccount(_ session: AccountSession, displayName: String) async throws {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else { throw HearlyFailure.message("Enter a name between 1 and 100 characters.") }
        // Reload the latest rotated token; an earlier view-model token may have expired.
        guard let current = try await restore(), current.user.id == session.user.id else { throw HearlyFailure.message("Please sign in again to sync your account.") }
        _ = try await request("/rest/v1/rpc/hearly_update_profile", body: ["display_name_input": name], bearer: current.access_token)
    }
    func signOutLocally() {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        browserSession?.cancel()
        sessionStore.remove()
    }
}
