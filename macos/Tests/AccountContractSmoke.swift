import Foundation

/// Offline contract tests. Does not access Keychain, send email, or call Supabase.
@main
struct AccountContractSmoke {
    @MainActor
    static func main() throws {
        let root = "https://hlwzcklxskvfdmohyzxg.supabase.co"
        let clientKey = "sb_publishable_offline_test_only"
        let valid = BackendConfiguration(url: root + "/", publishableKey: clientKey)
        precondition(valid.valid && valid.projectURL == root)
        for invalid in ["", "not a URL", "http://example.com", "https://user:password@example.com", root + "/auth/v1", root + "?token=anything", root + "#fragment"] {
            precondition(!BackendConfiguration(url: invalid, publishableKey: clientKey).valid)
        }
        for invalid in ["", "YOUR_PUBLISHABLE_OR_ANON_KEY", "sb_secret_offline_test_only", "sb_publishable_has whitespace"] {
            precondition(!BackendConfiguration(url: root, publishableKey: invalid).valid)
        }
        func jwt(_ claims: [String: Any]) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: claims)
            let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            return "header.\(payload).signature"
        }
        let anonKey = try jwt(["role": "anon"])
        let serviceRoleKey = try jwt(["role": "service_role"])
        precondition(BackendConfiguration(url: root, publishableKey: anonKey).valid)
        precondition(!BackendConfiguration(url: root, publishableKey: serviceRoleKey).valid)

        let sessionData = try JSONSerialization.data(withJSONObject: [
            "access_token": jwt(["exp": 5000, "iss": root + "/auth/v1"]),
            "refresh_token": "offline-only", "expires_in": 3600,
            "user": ["id": "offline-user", "email": "nobody@example.invalid"]
        ])
        let session = try JSONDecoder().decode(AccountSession.self, from: sessionData)
        precondition(session.expiration == 5000)
        precondition(!session.needsRefresh(at: Date(timeIntervalSince1970: 4900)))
        precondition(session.needsRefresh(at: Date(timeIntervalSince1970: 4940)))
        precondition(session.needsRefresh(at: Date(timeIntervalSince1970: 6000)))
        let roundTrip = try JSONDecoder().decode(AccountSession.self, from: JSONEncoder().encode(session))
        precondition(roundTrip.expiration == session.expiration)

        let code = try AccountService.authorizationCode(from: URL(string: "hearly://auth/callback?code=expected-code")!)
        precondition(code == "expected-code")
        for invalid in ["https://auth/callback?code=x", "hearly://wrong/callback?code=x", "hearly://auth/wrong?code=x", "hearly://auth/callback?code=", "hearly://auth/callback?error_description=Access%20denied"] {
            do {
                _ = try AccountService.authorizationCode(from: URL(string: invalid)!)
                preconditionFailure("Accepted an invalid callback")
            } catch {
                precondition(!error.localizedDescription.isEmpty)
            }
        }
        print("PASS: account configuration, client-key safety, session expiration/round-trip, OAuth callback contracts (offline).")
    }
}
