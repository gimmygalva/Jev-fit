import Foundation

/// Giorno di calendario locale dell'utente (`yyyy-MM-dd`), indipendente dal fuso orario.
///
/// ADR-010: ogni pesata, log alimentare e sessione salva il `DayKey` calcolato nel fuso orario
/// in cui l'utente si trovava al momento della registrazione. Così un viaggio o un cambio di
/// ora legale non sposta i dati da un giorno all'altro. L'aritmetica (aggiungere giorni,
/// distanza tra giorni) avviene sul calendario gregoriano in UTC, dove ogni giorno dura 24 h.
public struct DayKey: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Crea un giorno validato (rifiuta ad es. 2026-02-30).
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = DayKey.utcCalendar.date(from: components) else { return nil }
        let check = DayKey.utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Interpreta una stringa `yyyy-MM-dd`.
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// Giorno locale in cui cade l'istante `date` nel fuso `timeZone`.
    public init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        // I componenti provengono da un calendario gregoriano valido: non possono essere nil.
        self.year = c.year!
        self.month = c.month!
        self.day = c.day!
    }

    public var description: String {
        "\(DayKey.pad(year, to: 4))-\(DayKey.pad(month, to: 2))-\(DayKey.pad(day, to: 2))"
    }

    /// Zero padding senza `String(format:)` (comportamento identico su Darwin e Linux).
    private static func pad(_ value: Int, to width: Int) -> String {
        let digits = String(value)
        return digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
    }

    /// Mezzanotte UTC del giorno: usata solo come ancora aritmetica, non rappresenta un istante reale.
    var utcAnchor: Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return DayKey.utcCalendar.date(from: components)!
    }

    public func adding(days: Int) -> DayKey {
        let date = DayKey.utcCalendar.date(byAdding: .day, value: days, to: utcAnchor)!
        return DayKey(date: date, timeZone: DayKey.utc)
    }

    /// Numero di giorni da `self` a `other` (positivo se `other` è successivo).
    public func days(to other: DayKey) -> Int {
        DayKey.utcCalendar.dateComponents([.day], from: utcAnchor, to: other.utcAnchor).day!
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // Codable come stringa `yyyy-MM-dd`, identica a quella salvata nel database.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = DayKey(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "DayKey non valido: \(raw)")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    static let utc = TimeZone(identifier: "UTC")!

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }()
}
