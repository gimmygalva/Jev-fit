import CoachKit
import Foundation
import Testing
@testable import Sync

/// Risposte HTTP finte per URLSession (nessuna rete nei test).
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let (status, data) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }
}

@Suite("Account: sessione, refresh, consensi, gateway (M12)", .serialized)
struct AccountServiceTests {
    let config = BackendConfig(projectURL: URL(string: "https://example.supabase.co")!, publishableKey: "sb_publishable_test")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let tokenJSON = Data(#"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"user":{"id":"u1"}}"#.utf8)

    @Test("Configurazione: solo chiavi pubblicabili; senza Info.plist nessun backend")
    func missingConfig() {
        #expect(BackendConfig.fromBundle(Bundle(for: StubProtocol.self)) == nil)
    }

    @Test("Senza sessione nessun token; con sessione valida il token è quello salvato")
    func tokens() async {
        let store = InMemorySessionStore()
        let account = AccountService(config: config, store: store, session: StubProtocol.session(), now: { [now] in now })
        #expect(!account.isSignedIn)
        #expect(await account.accessToken() == nil)
        store.save(AuthSession(accessToken: "a", refreshToken: "r", expiresAt: now + 3600, userID: "u"))
        #expect(await account.accessToken() == "a")
        account.signOut()
        #expect(!account.isSignedIn)
    }

    @Test("Token in scadenza: refresh e nuova sessione salvata")
    func refresh() async {
        StubProtocol.requests = []
        let json = tokenJSON
        StubProtocol.handler = { _ in (200, json) }
        let store = InMemorySessionStore(AuthSession(accessToken: "old", refreshToken: "r", expiresAt: now + 10, userID: "u"))
        let account = AccountService(config: config, store: store, session: StubProtocol.session(), now: { [now] in now })
        #expect(await account.accessToken() == "new-access")
        #expect(store.load()?.refreshToken == "new-refresh")
        let url = StubProtocol.requests.last?.url?.absoluteString ?? ""
        #expect(url.contains("auth/v1/token") && url.contains("grant_type=refresh_token"))
        #expect(StubProtocol.requests.last?.value(forHTTPHeaderField: "apikey") == "sb_publishable_test")
    }

    @Test("Sign in with Apple: id token e nonce al server, sessione salvata; rifiuto gestito")
    func signIn() async throws {
        let json = tokenJSON
        StubProtocol.handler = { _ in (200, json) }
        let store = InMemorySessionStore()
        let account = AccountService(config: config, store: store, session: StubProtocol.session(), now: { [now] in now })
        let session = try await account.signInWithApple(idToken: "apple-token", nonce: "n")
        #expect(session.userID == "u1" && session.expiresAt == now + 3600)
        StubProtocol.handler = { _ in (400, Data()) }
        await #expect(throws: AccountError.rejected(400)) {
            try await AccountService(config: config, store: InMemorySessionStore(), session: StubProtocol.session())
                .signInWithApple(idToken: "x", nonce: "y")
        }
    }

    @Test("Consensi: lettura, concessione e revoca via REST con il token dell'utente")
    func consents() async throws {
        StubProtocol.requests = []
        StubProtocol.handler = { request in
            request.httpMethod == "GET" ? (200, Data(#"[{"id":"c1"}]"#.utf8)) : (201, Data())
        }
        let store = InMemorySessionStore(AuthSession(accessToken: "tok", refreshToken: "r", expiresAt: now + 3600, userID: "u"))
        let account = AccountService(config: config, store: store, session: StubProtocol.session(), now: { [now] in now })
        #expect(try await account.hasConsent(.cloudSync))
        try await account.grant(.aiOnline, appVersion: "1.0")
        try await account.revoke(.aiOnline)
        let methods = StubProtocol.requests.map { $0.httpMethod ?? "" }
        #expect(methods == ["GET", "POST", "PATCH"])
        #expect(StubProtocol.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer tok" })
        await #expect(throws: AccountError.notSignedIn) {
            try await AccountService(config: config, store: InMemorySessionStore()).hasConsent(.cloudSync)
        }
    }

    @Test("Eliminazione dell'account: conferma esplicita al server, poi uscita; errore gestito")
    func deleteAccount() async throws {
        StubProtocol.requests = []
        StubProtocol.handler = { _ in (200, Data(#"{"deleted":true}"#.utf8)) }
        let store = InMemorySessionStore(AuthSession(accessToken: "tok", refreshToken: "r", expiresAt: now + 3600, userID: "u"))
        let account = AccountService(config: config, store: store, session: StubProtocol.session(), now: { [now] in now })
        try await account.deleteAccount()
        #expect(!account.isSignedIn)
        let request = try #require(StubProtocol.requests.last)
        #expect(request.url?.path == "/functions/v1/account-delete")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        let failing = AccountService(config: config, store: InMemorySessionStore(store.load() ?? AuthSession(
            accessToken: "tok", refreshToken: "r", expiresAt: now + 3600, userID: "u")), session: StubProtocol.session(),
            now: { [now] in now })
        StubProtocol.handler = { _ in (502, Data()) }
        await #expect(throws: AccountError.rejected(502)) { try await failing.deleteAccount() }
        #expect(failing.isSignedIn, "Se il server fallisce l'account resta collegato")
        await #expect(throws: AccountError.notSignedIn) { try await account.deleteAccount() }
    }

    @Test("Gateway di JEV: senza sessione notAuthorized, risposte mappate")
    func gateway() async throws {
        let request = CoachRequest(tier: .routine, purpose: "today_card", facts: [], reasonCodes: [])
        let anonymous = GatewayAIProvider(projectURL: config.projectURL, publishableKey: config.publishableKey,
                                          session: StubProtocol.session(), accessToken: { nil })
        await #expect(throws: AIProviderError.notAuthorized) { _ = try await anonymous.draft(for: request) }
        let body = Data(#"{"draft":{"headline":"Ok","body":"{{fact:x}}","why":[],"dataUsed":["x"]},"provider":"anthropic","model":"m"}"#.utf8)
        StubProtocol.handler = { _ in (200, body) }
        let gateway = GatewayAIProvider(projectURL: config.projectURL, publishableKey: config.publishableKey,
                                        session: StubProtocol.session(), accessToken: { "tok" })
        #expect(try await gateway.draft(for: request).body == "{{fact:x}}")
        StubProtocol.handler = { _ in (429, Data()) }
        await #expect(throws: AIProviderError.rateLimited) { _ = try await gateway.draft(for: request) }
        StubProtocol.handler = { _ in (403, Data()) }
        await #expect(throws: AIProviderError.notAuthorized) { _ = try await gateway.draft(for: request) }
    }
}
