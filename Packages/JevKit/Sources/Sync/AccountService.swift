import Foundation
import Security

/// Configurazione pubblica del backend: URL del progetto e chiave pubblicabile (SECURITY §3:
/// nessun segreto nel client; le chiavi `sb_publishable_` sono pensate per stare nelle app).
public struct BackendConfig: Sendable, Equatable {
    public var projectURL: URL
    public var publishableKey: String

    public init(projectURL: URL, publishableKey: String) {
        self.projectURL = projectURL
        self.publishableKey = publishableKey
    }

    /// Da Info.plist (`JEVSupabaseURL`, `JEVSupabasePublishableKey`); nil se mancano.
    public static func fromBundle(_ bundle: Bundle = .main) -> BackendConfig? {
        guard let text = bundle.object(forInfoDictionaryKey: "JEVSupabaseURL") as? String, let url = URL(string: text),
              let key = bundle.object(forInfoDictionaryKey: "JEVSupabasePublishableKey") as? String,
              key.hasPrefix("sb_publishable_") else { return nil }
        return BackendConfig(projectURL: url, publishableKey: key)
    }
}

/// Sessione Supabase Auth.
public struct AuthSession: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userID: String
}

/// Dove si conserva la sessione: Portachiavi sul dispositivo, memoria nei test.
public protocol SessionStore: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession?)
}

/// Portachiavi, accessibile solo dopo il primo sblocco e mai sincronizzato su iCloud.
public struct KeychainSessionStore: SessionStore {
    let service = "fit.jev.auth"
    let account = "session"

    public init() {}

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func load() -> AuthSession? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    public func save(_ session: AuthSession?) {
        SecItemDelete(query as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?
    public init(_ session: AuthSession? = nil) { self.session = session }
    public func load() -> AuthSession? { lock.withLock { session } }
    public func save(_ session: AuthSession?) { lock.withLock { self.session = session } }
}

public enum AccountError: Error, Equatable, Sendable {
    case notSignedIn
    case network
    case rejected(Int)
}

/// Account e consensi (M12): Sign in with Apple → Supabase Auth, token con refresh, consensi
/// `cloud_sync` e `ai_online` registrati sul server (SECURITY §6.6). Solo URLSession: nessun
/// segreto, nessun SDK aggiuntivo.
public struct AccountService: Sendable {
    public enum Consent: String, Sendable, CaseIterable {
        case cloudSync = "cloud_sync"
        case aiOnline = "ai_online"
    }

    public static let policyVersion = "2026-10"

    public let config: BackendConfig
    let store: any SessionStore
    let session: URLSession
    let now: @Sendable () -> Date

    public init(config: BackendConfig, store: any SessionStore = KeychainSessionStore(), session: URLSession = .shared,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.store = store
        self.session = session
        self.now = now
    }

    public var isSignedIn: Bool { store.load() != nil }

    // MARK: Auth

    struct TokenResponse: Decodable {
        struct User: Decodable { var id: String }
        var access_token: String
        var refresh_token: String
        var expires_in: Double
        var user: User
    }

    static func session(from data: Data, now: Date) throws -> AuthSession {
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return AuthSession(accessToken: token.access_token, refreshToken: token.refresh_token,
                           expiresAt: now.addingTimeInterval(token.expires_in), userID: token.user.id)
    }

    private func authRequest(grant: String, body: [String: String]) async throws -> AuthSession {
        var components = URLComponents(url: config.projectURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: grant)]
        guard let url = components?.url else { throw AccountError.network }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AccountError.network
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw AccountError.rejected(status) }
        let result = try Self.session(from: data, now: now())
        store.save(result)
        return result
    }

    /// Accesso con l'identity token di Sign in with Apple (con il nonce in chiaro usato per la richiesta).
    @discardableResult
    public func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession {
        try await authRequest(grant: "id_token", body: ["provider": "apple", "id_token": idToken, "nonce": nonce])
    }

    /// Token valido (rinnovato se scade entro un minuto); nil senza account.
    public func accessToken() async -> String? {
        guard let current = store.load() else { return nil }
        if current.expiresAt > now().addingTimeInterval(60) { return current.accessToken }
        return try? await authRequest(grant: "refresh_token", body: ["refresh_token": current.refreshToken]).accessToken
    }

    public func signOut() {
        store.save(nil)
    }

    // MARK: Consensi

    private func rest(_ path: String, query: [URLQueryItem], method: String, body: Any?) async throws -> Data {
        guard let token = await accessToken() else { throw AccountError.notSignedIn }
        var components = URLComponents(url: config.projectURL.appendingPathComponent("rest/v1/\(path)"), resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let url = components?.url else { throw AccountError.network }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AccountError.network
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AccountError.rejected(status) }
        return data
    }

    public func hasConsent(_ consent: Consent) async throws -> Bool {
        let data = try await rest("user_consent", query: [
            URLQueryItem(name: "select", value: "id"), URLQueryItem(name: "kind", value: "eq.\(consent.rawValue)"),
            URLQueryItem(name: "revoked_at", value: "is.null"),
        ], method: "GET", body: nil)
        return !(((try? JSONSerialization.jsonObject(with: data)) as? [Any]) ?? []).isEmpty
    }

    /// Consenso esplicito (mai attivato in automatico).
    public func grant(_ consent: Consent, appVersion: String?) async throws {
        var row: [String: Any] = ["kind": consent.rawValue, "policy_version": Self.policyVersion]
        if let appVersion { row["app_version"] = String(appVersion.prefix(32)) }
        _ = try await rest("user_consent", query: [], method: "POST", body: row)
    }

    public func revoke(_ consent: Consent) async throws {
        _ = try await rest("user_consent", query: [
            URLQueryItem(name: "kind", value: "eq.\(consent.rawValue)"), URLQueryItem(name: "revoked_at", value: "is.null"),
        ], method: "PATCH", body: ["revoked_at": SyncDate.format(now())])
    }
}
