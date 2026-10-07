import Foundation
import JevDomain

/// Alimenti generici inclusi nell'app: funzionano offline e compaiono per primi (ADR-009).
public struct LocalFoodProvider: FoodProvider {
    public static let sourceName = "catalog"

    struct File: Decodable {
        var schemaVersion: Int
        var foods: [Entry]
    }

    struct Entry: Decodable {
        var id: String
        var name: String
        var energyKcal: Double
        var proteinGrams: Double
        var carbohydrateGrams: Double
        var fatGrams: Double
        var fiberGrams: Double?
    }

    public let foods: [FoodCandidate]
    private let index: [(normalized: String, food: FoodCandidate)]

    public init(foods: [FoodCandidate]) {
        self.foods = foods
        self.index = foods.map { (normalized: FoodQuery.normalize($0.name), food: $0) }
    }

    /// Database incluso nel bundle (`foods.json`, generato da tools/food/generate_foods.py).
    public static func bundled() throws -> LocalFoodProvider {
        guard let url = Bundle.module.url(forResource: "foods", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> LocalFoodProvider {
        let file = try JSONDecoder().decode(File.self, from: data)
        let foods = file.foods.map { entry in
            FoodCandidate(
                source: sourceName, sourceID: entry.id, name: entry.name,
                per100g: NutrientProfile(energyKcal: entry.energyKcal, proteinGrams: entry.proteinGrams,
                                         carbohydrateGrams: entry.carbohydrateGrams, fatGrams: entry.fatGrams,
                                         fiberGrams: entry.fiberGrams)
            )
        }
        return LocalFoodProvider(foods: foods)
    }

    public var identifier: String { Self.sourceName }
    public var worksOffline: Bool { true }

    /// Tutte le parole della query devono comparire nel nome; prima chi inizia con la query.
    public func search(_ query: FoodQuery, limit: Int) async throws -> [FoodCandidate] {
        guard !query.isEmpty, limit > 0 else { return [] }
        let words = query.normalized.split(separator: " ").map(String.init)
        let matches = index.filter { item in words.allSatisfy { item.normalized.contains($0) } }
        let ranked = matches.sorted { lhs, rhs in
            let l = lhs.normalized.hasPrefix(query.normalized)
            let r = rhs.normalized.hasPrefix(query.normalized)
            if l != r { return l }
            return lhs.normalized < rhs.normalized
        }
        return Array(ranked.prefix(limit)).map(\.food)
    }

    public func lookup(barcode: String) async throws -> FoodCandidate? { nil }
}

/// Open Food Facts (prodotti confezionati, barcode). Nessuna chiave: API pubblica; si inviano
/// solo il barcode o il testo cercato, mai dati dell'utente (SECURITY §3).
public struct OpenFoodFactsProvider: FoodProvider {
    public static let sourceName = "open_food_facts"
    let session: URLSession
    let baseURL: URL

    public init(session: URLSession = .shared,
                baseURL: URL = URL(string: "https://world.openfoodfacts.org")!) {
        self.session = session
        self.baseURL = baseURL
    }

    public var identifier: String { Self.sourceName }
    public var worksOffline: Bool { false }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("JEVFIT/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        return request
    }

    public func lookup(barcode: String) async throws -> FoodCandidate? {
        guard Barcode.isValid(barcode) else { return nil }
        let url = baseURL.appendingPathComponent("api/v2/product/\(barcode).json")
        let (data, response) = try await session.data(for: request(url))
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil }
        return try Self.parseProduct(data)
    }

    public func search(_ query: FoodQuery, limit: Int) async throws -> [FoodCandidate] {
        guard !query.isEmpty, limit > 0 else { return [] }
        var components = URLComponents(url: baseURL.appendingPathComponent("cgi/search.pl"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: query.raw),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(min(limit, 50))),
        ]
        guard let url = components?.url else { return [] }
        let (data, _) = try await session.data(for: request(url))
        return try Self.parseSearch(data)
    }

    // MARK: Parsing (testabile senza rete)

    struct ProductResponse: Decodable {
        var status: Int?
        var code: String?
        var product: Product?
    }

    struct SearchResponse: Decodable {
        var products: [Product]
    }

    struct Product: Decodable {
        var code: String?
        var product_name: String?
        var product_name_it: String?
        var brands: String?
        var nutriments: [String: FlexibleDouble]?
    }

    /// I nutrienti di Open Food Facts arrivano a volte come numero, a volte come stringa.
    struct FlexibleDouble: Decodable {
        var value: Double?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                value = number
            } else if let text = try? container.decode(String.self) {
                value = Double(text.replacingOccurrences(of: ",", with: "."))
            } else {
                value = nil
            }
        }
    }

    static func parseProduct(_ data: Data) throws -> FoodCandidate? {
        let response = try JSONDecoder().decode(ProductResponse.self, from: data)
        guard response.status != 0, let product = response.product else { return nil }
        return candidate(from: product, fallbackCode: response.code)
    }

    static func parseSearch(_ data: Data) throws -> [FoodCandidate] {
        try JSONDecoder().decode(SearchResponse.self, from: data).products.compactMap { candidate(from: $0, fallbackCode: nil) }
    }

    /// Prodotto utilizzabile solo con nome e valori per 100 g coerenti (kcal 0–900, macro ≤ 100 g).
    static func candidate(from product: Product, fallbackCode: String?) -> FoodCandidate? {
        guard let code = product.code ?? fallbackCode, !code.isEmpty, code.count <= 64 else { return nil }
        let name = (product.product_name_it ?? product.product_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let n = product.nutriments ?? [:]
        func value(_ key: String) -> Double? { n[key]?.value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } }
        let kcal = value("energy-kcal_100g") ?? value("energy_100g").map { $0 / 4.184 }
        guard let energy = kcal, energy <= 900,
              let protein = value("proteins_100g"), let carbs = value("carbohydrates_100g"), let fat = value("fat_100g"),
              protein + carbs + fat <= 100.5 else { return nil }
        let brand = product.brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        return FoodCandidate(
            source: sourceName, sourceID: code, name: String(name.prefix(160)), brand: brand,
            barcode: Barcode.isValid(code) ? code : nil,
            per100g: NutrientProfile(energyKcal: energy, proteinGrams: protein, carbohydrateGrams: carbs,
                                     fatGrams: fat, fiberGrams: value("fiber_100g"))
        )
    }
}

/// Ricerca combinata: prima i provider offline, poi quelli online (se raggiungibili); un
/// provider online che fallisce non blocca i risultati locali.
public struct FoodSearch: Sendable {
    public let providers: [any FoodProvider]

    public init(providers: [any FoodProvider]) {
        self.providers = providers.sorted { $0.worksOffline && !$1.worksOffline }
    }

    public func search(_ text: String, limit: Int = 30, includeOnline: Bool = true) async -> [FoodCandidate] {
        let query = FoodQuery(text)
        guard !query.isEmpty else { return [] }
        var results: [FoodCandidate] = []
        var seen = Set<String>()
        for provider in providers where provider.worksOffline || includeOnline {
            guard results.count < limit else { break }
            let found = (try? await provider.search(query, limit: limit - results.count)) ?? []
            for candidate in found where seen.insert(candidate.id).inserted {
                results.append(candidate)
            }
        }
        return results
    }

    public func lookup(barcode: String) async -> FoodCandidate? {
        guard Barcode.isValid(barcode) else { return nil }
        for provider in providers {
            if let found = try? await provider.lookup(barcode: barcode) { return found }
        }
        return nil
    }
}
