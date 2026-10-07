import CoachKit
import Foundation

/// Provider di JEV via gateway Supabase (Edge Function `coach`, M11). Il client non conosce
/// modelli né chiavi dei provider AI: invia solo fatti già minimizzati e riceve una bozza che il
/// `CoachService` valida di nuovo. Senza sessione utente o senza consenso → `notAuthorized`
/// e JEV usa i template offline.
public struct GatewayAIProvider: AIProvider {
    public typealias TokenProvider = @Sendable () async -> String?

    let endpoint: URL
    let publishableKey: String
    let accessToken: TokenProvider
    let session: URLSession

    public init(projectURL: URL, publishableKey: String, session: URLSession = .shared, accessToken: @escaping TokenProvider) {
        self.endpoint = projectURL.appendingPathComponent("functions/v1/coach")
        self.publishableKey = publishableKey
        self.session = session
        self.accessToken = accessToken
    }

    public var identifier: String { "gateway" }

    struct Response: Decodable {
        var draft: CoachDraft
    }

    public func draft(for request: CoachRequest) async throws -> CoachDraft {
        guard let token = await accessToken() else { throw AIProviderError.notAuthorized }
        var urlRequest = URLRequest(url: endpoint, timeoutInterval: 30)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(publishableKey, forHTTPHeaderField: "apikey")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw AIProviderError.unavailable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
                throw AIProviderError.invalidResponse
            }
            return decoded.draft
        case 401, 403: throw AIProviderError.notAuthorized
        case 429: throw AIProviderError.rateLimited
        case 422: throw AIProviderError.groundingFailed
        default: throw AIProviderError.unavailable
        }
    }
}
