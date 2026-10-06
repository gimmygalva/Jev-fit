import Foundation
import JevDomain

/// Provider di alimenti intercambiabili (ADR-009). MVP: locale, Open Food Facts, USDA via gateway.
public protocol FoodProvider: Sendable {
    var identifier: String { get }
    /// Vero se funziona offline (il logger mostra sempre per primi i risultati offline).
    var worksOffline: Bool { get }
    func search(_ query: FoodQuery, limit: Int) async throws -> [FoodCandidate]
    func lookup(barcode: String) async throws -> FoodCandidate?
}

/// Un risultato di ricerca: il profilo nutrizionale è per 100 g; al momento del log
/// se ne salva uno snapshot (lo storico non cambia se il provider modifica il prodotto).
public struct FoodCandidate: Sendable, Hashable, Identifiable {
    public var id: String { "\(source):\(sourceID)" }
    public var source: String
    public var sourceID: String
    public var name: String
    public var brand: String?
    public var barcode: String?
    public var per100g: NutrientProfile

    public init(source: String, sourceID: String, name: String, brand: String? = nil, barcode: String? = nil, per100g: NutrientProfile) {
        self.source = source
        self.sourceID = sourceID
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.per100g = per100g
    }
}

/// Query di ricerca normalizzata: minuscole, senza accenti, spazi compattati.
/// "  Pàsta   INTEGRALE " e "pasta integrale" producono la stessa query.
public struct FoodQuery: Sendable, Hashable {
    public let raw: String
    public let normalized: String

    public init(_ raw: String) {
        self.raw = raw
        self.normalized = FoodQuery.normalize(raw)
    }

    public var isEmpty: Bool { normalized.isEmpty }

    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "it_IT"))
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

/// Barcode validi per i prodotti confezionati (EAN-8, UPC-A, EAN-13, GTIN-14) con check digit GS1.
public enum Barcode {
    public static func isValid(_ code: String) -> Bool {
        guard [8, 12, 13, 14].contains(code.count), code.allSatisfy(\.isASCII) else { return false }
        let digits = code.compactMap { $0.wholeNumberValue }
        guard digits.count == code.count else { return false }
        let body = digits.dropLast()
        var sum = 0
        for (offset, digit) in body.reversed().enumerated() {
            sum += digit * (offset.isMultiple(of: 2) ? 3 : 1)
        }
        let check = (10 - sum % 10) % 10
        return check == digits.last
    }
}
