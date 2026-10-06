import Foundation
import Testing
@testable import JevCore

@Suite("DayKey — giorno locale, fusi orari, ora legale")
struct DayKeyTests {
    private let rome = TimeZone(identifier: "Europe/Rome")!
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    private func instant(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    @Test("Parsing e formattazione yyyy-MM-dd")
    func parsing() {
        #expect(DayKey("2026-10-05")?.description == "2026-10-05")
        #expect(DayKey("0999-01-01")?.description == "0999-01-01")
        #expect(DayKey(year: 2026, month: 3, day: 9)?.description == "2026-03-09")
    }

    @Test("Date inesistenti e formati errati vengono rifiutati", arguments: [
        "2026-02-29", "2026-02-30", "2026-13-01", "2026-00-10", "2026-04-31",
        "26-10-05", "2026-1-05", "2026/10/05", "", "abcd-ef-gh", "2026-10-05-01",
    ])
    func invalid(_ raw: String) {
        #expect(DayKey(raw) == nil)
    }

    @Test("Anno bisestile")
    func leapYear() {
        #expect(DayKey("2028-02-29") != nil)
        #expect(DayKey("2100-02-29") == nil)
        #expect(DayKey(year: 0, month: 1, day: 1) == nil)
    }

    @Test("Lo stesso istante cade in giorni diversi a seconda del fuso")
    func timeZones() {
        let t = instant("2026-10-05T23:30:00Z")
        #expect(DayKey(date: t, timeZone: rome).description == "2026-10-06")      // UTC+2
        #expect(DayKey(date: t, timeZone: newYork).description == "2026-10-05")   // UTC−4
        #expect(DayKey(date: t, timeZone: tokyo).description == "2026-10-06")     // UTC+9
    }

    @Test("Ora legale: le ore di confine restano nel giorno giusto (Europa/Roma)")
    func daylightSaving() {
        // 29 marzo 2026: alle 02:00 locali si passa alle 03:00.
        #expect(DayKey(date: instant("2026-03-28T23:30:00Z"), timeZone: rome).description == "2026-03-29")
        #expect(DayKey(date: instant("2026-03-29T21:59:00Z"), timeZone: rome).description == "2026-03-29")
        #expect(DayKey(date: instant("2026-03-29T22:00:00Z"), timeZone: rome).description == "2026-03-30")
        // 25 ottobre 2026: alle 03:00 locali si torna alle 02:00 (giorno di 25 ore).
        #expect(DayKey(date: instant("2026-10-25T22:59:00Z"), timeZone: rome).description == "2026-10-25")
        #expect(DayKey(date: instant("2026-10-25T23:00:00Z"), timeZone: rome).description == "2026-10-26")
    }

    @Test("Aritmetica sui giorni attraverso mesi, anni e cambi d'ora")
    func arithmetic() {
        let d = DayKey("2026-03-28")!
        #expect(d.adding(days: 1).description == "2026-03-29")
        #expect(d.adding(days: 2).description == "2026-03-30")
        #expect(d.adding(days: -28).description == "2026-02-28")
        #expect(DayKey("2026-12-31")!.adding(days: 1).description == "2027-01-01")
        #expect(DayKey("2026-01-01")!.days(to: DayKey("2026-12-31")!) == 364)
        #expect(DayKey("2026-10-30")!.days(to: DayKey("2026-10-20")!) == -10)
        #expect(d.days(to: d) == 0)
    }

    @Test("Ordinamento e Codable come stringa")
    func orderingAndCodable() throws {
        let a = DayKey("2026-01-31")!
        let b = DayKey("2026-02-01")!
        #expect(a < b)
        #expect(!(b < a))
        #expect([b, a].sorted() == [a, b])
        let data = try JSONEncoder().encode([a])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-01-31\"]")
        #expect(try JSONDecoder().decode([DayKey].self, from: data) == [a])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([DayKey].self, from: Data("[\"2026-02-30\"]".utf8))
        }
    }
}
