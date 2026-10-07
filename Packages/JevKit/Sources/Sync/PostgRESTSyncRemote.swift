import Foundation

/// `SyncRemote` sull'API REST di Supabase (PostgREST), con il token dell'utente: valgono RLS e
/// consenso `cloud_sync` (SECURITY §6). Nel client c'è solo la chiave pubblicabile.
public struct PostgRESTSyncRemote: SyncRemote {
    public typealias TokenProvider = @Sendable () async -> String?

    let baseURL: URL
    let publishableKey: String
    let accessToken: TokenProvider
    let session: URLSession

    public init(projectURL: URL, publishableKey: String, session: URLSession = .shared, accessToken: @escaping TokenProvider) {
        self.baseURL = projectURL.appendingPathComponent("rest/v1")
        self.publishableKey = publishableKey
        self.session = session
        self.accessToken = accessToken
    }

    struct PostgRESTError: Decodable {
        var code: String?
    }

    private func request(_ url: URL, method: String) async throws -> URLRequest {
        guard let token = await accessToken() else { throw SyncRemoteError.permanent("not_authenticated") }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncRemoteError.transient("network")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Self.map(status: status, body: data) }
        return data
    }

    /// Codici PostgREST/Postgres → errori della sync (DATA_MODEL §5.2).
    static func map(status: Int, body: Data) -> SyncRemoteError {
        let code = (try? JSONDecoder().decode(PostgRESTError.self, from: body))?.code ?? "http_\(status)"
        if code == "23505" { return .uniqueViolation }
        if status == 429 || status >= 500 || status == 408 { return .transient(code) }
        return .permanent(code)
    }

    public func upsert(table: String, row: [String: Any]) async throws -> Date? {
        var components = URLComponents(url: baseURL.appendingPathComponent(table), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "on_conflict", value: "id"),
                                  URLQueryItem(name: "select", value: "server_updated_at")]
        guard let url = components?.url else { throw SyncRemoteError.permanent("url") }
        var request = try await request(url, method: "POST")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [row])
        let data = try await send(request)
        let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        return (rows?.first?["server_updated_at"] as? String).flatMap(SyncDate.parse)
    }

    public func changes(table: String, since: Date?, limit: Int) async throws -> [[String: Any]] {
        var components = URLComponents(url: baseURL.appendingPathComponent(table), resolvingAgainstBaseURL: false)
        var items = [URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "order", value: "server_updated_at.asc"),
                     URLQueryItem(name: "limit", value: String(limit))]
        if let since { items.append(URLQueryItem(name: "server_updated_at", value: "gt.\(SyncDate.format(since))")) }
        components?.queryItems = items
        // "+" del fuso orario va codificato, altrimenti diventa uno spazio.
        components?.percentEncodedQuery = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components?.url else { throw SyncRemoteError.permanent("url") }
        let data = try await send(try await request(url, method: "GET"))
        return ((try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]) ?? []
    }

    public func singleton(table: String) async throws -> [String: Any]? {
        var components = URLComponents(url: baseURL.appendingPathComponent(table), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "deleted_at", value: "is.null"),
                                  URLQueryItem(name: "limit", value: "1")]
        guard let url = components?.url else { throw SyncRemoteError.permanent("url") }
        let data = try await send(try await request(url, method: "GET"))
        return (((try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]) ?? []).first
    }
}
