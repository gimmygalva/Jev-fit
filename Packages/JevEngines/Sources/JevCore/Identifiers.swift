import Foundation

/// Generatore di UUID versione 7 (RFC 9562): 48 bit di timestamp Unix in millisecondi
/// seguiti da bit casuali. Gli ID sono generati dal client (ADR-005, piano §3.4): l'upsert
/// idempotente sul server rende innocuo l'invio ripetuto dello stesso record, e l'ordinamento
/// per ID approssima l'ordine di creazione.
public enum UUIDv7 {
    /// Crea un UUIDv7 con il timestamp e il generatore casuale indicati (deterministico nei test).
    public static func make(
        timestampMilliseconds: UInt64,
        using generator: inout some RandomNumberGenerator
    ) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        let ms = timestampMilliseconds & 0xFFFF_FFFF_FFFF // 48 bit
        for index in 0..<6 {
            bytes[index] = UInt8(truncatingIfNeeded: ms >> UInt64(8 * (5 - index)))
        }
        for index in 6..<16 {
            bytes[index] = UInt8.random(in: 0...UInt8.max, using: &generator)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x70 // versione 7
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // variante RFC 4122/9562
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Crea un UUIDv7 per l'istante `date` con il generatore casuale di sistema.
    public static func make(at date: Date) -> UUID {
        var generator = SystemRandomNumberGenerator()
        let seconds = max(0, date.timeIntervalSince1970)
        return make(timestampMilliseconds: UInt64(seconds * 1000), using: &generator)
    }

    /// Estrae il timestamp in millisecondi da un UUIDv7 (nil se non è un v7).
    public static func timestampMilliseconds(of uuid: UUID) -> UInt64? {
        let u = uuid.uuid
        guard (u.6 >> 4) == 7 else { return nil }
        let head: [UInt8] = [u.0, u.1, u.2, u.3, u.4, u.5]
        return head.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}

/// Sorgente del tempo iniettabile. Gli engine NON chiamano mai `Date()` (ADR-003):
/// ricevono l'istante come parametro. Questo protocollo serve ai layer che preparano gli input.
public protocol TimeSource: Sendable {
    func now() -> Date
}

public struct SystemTimeSource: TimeSource {
    public init() {}
    public func now() -> Date { Date() }
}

public struct FixedTimeSource: TimeSource {
    public let date: Date
    public init(_ date: Date) { self.date = date }
    public func now() -> Date { date }
}

/// Generatore pseudo-casuale deterministico (SplitMix64) per riproducibilità:
/// stessa seed → stessa sequenza su ogni piattaforma. Usato per la varietà degli esercizi
/// (seed derivata da utente e mesociclo, piano §5.6) e nei test Monte Carlo.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
