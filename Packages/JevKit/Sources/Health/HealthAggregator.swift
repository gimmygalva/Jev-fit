import Foundation
import JevCore

/// Aggregazione pura dei campioni di Salute in valori giornalieri (§5.9, ADR-012).
/// Nessun accesso a HealthKit: testabile con dati sintetici.
public enum HealthAggregator {
    public struct DailySummary: Sendable, Hashable {
        public var dayKey: DayKey
        public var steps: Int?
        public var activeKcal: Double?
        public var sleepMinutes: Double?
        public var restingHeartRate: Double?
        /// Media dei campioni notturni di SDNN (ms) di una sola sorgente.
        public var hrvSDNNMilliseconds: Double?

        public init(dayKey: DayKey, steps: Int? = nil, activeKcal: Double? = nil, sleepMinutes: Double? = nil,
                    restingHeartRate: Double? = nil, hrvSDNNMilliseconds: Double? = nil) {
            self.dayKey = dayKey
            self.steps = steps
            self.activeKcal = activeKcal
            self.sleepMinutes = sleepMinutes
            self.restingHeartRate = restingHeartRate
            self.hrvSDNNMilliseconds = hrvSDNNMilliseconds
        }

        public var isEmpty: Bool {
            steps == nil && activeKcal == nil && sleepMinutes == nil && restingHeartRate == nil && hrvSDNNMilliseconds == nil
        }
    }

    /// Limiti plausibili, uguali ai CHECK di `health_metric_daily`: fuori range il valore è scartato.
    static let stepsRange = 0...200_000
    static let activeKcalRange = 0.0...20_000
    static let sleepRange = 0.0...1_440
    static let restingHRRange = 20.0...250
    static let hrvRange = 0.0...500

    /// Le notturne finiscono entro questa ora locale (campioni HRV "notturni").
    static let nightEndHour = 8

    /// Minuti di sonno per notte, attribuiti al giorno del risveglio. Le fasi di sonno di più
    /// sorgenti (iPhone, Watch, app terze) si uniscono senza contare due volte le sovrapposizioni;
    /// se in una notte ci sono solo intervalli "a letto" (dispositivi vecchi) si usano quelli.
    public static func sleepMinutesByNight(_ intervals: [SleepInterval], timeZone: TimeZone) -> [DayKey: Double] {
        var asleep: [DayKey: [(Date, Date)]] = [:]
        var inBed: [DayKey: [(Date, Date)]] = [:]
        for interval in intervals where interval.end > interval.start {
            let day = DayKey(date: interval.end, timeZone: timeZone)
            switch interval.stage {
            case .asleep: asleep[day, default: []].append((interval.start, interval.end))
            case .inBed: inBed[day, default: []].append((interval.start, interval.end))
            case .awake: break
            }
        }
        var result: [DayKey: Double] = [:]
        for day in Set(asleep.keys).union(inBed.keys) {
            let ranges = asleep[day] ?? inBed[day] ?? []
            let minutes = unionDuration(ranges) / 60
            result[day] = min(minutes, sleepRange.upperBound)
        }
        return result
    }

    /// Durata dell'unione degli intervalli, in secondi.
    static func unionDuration(_ ranges: [(Date, Date)]) -> TimeInterval {
        let sorted = ranges.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for range in sorted {
            if let open = current, range.0 <= open.1 {
                current = (open.0, max(open.1, range.1))
            } else {
                if let open = current { total += open.1.timeIntervalSince(open.0) }
                current = range
            }
        }
        if let open = current { total += open.1.timeIntervalSince(open.0) }
        return total
    }

    /// HRV notturna: campioni tra mezzanotte e le 8 locali, una sola sorgente (quella con più
    /// campioni nel periodo: mescolare dispositivi diversi falserebbe la baseline), media per giorno.
    public static func nightlyHRV(_ samples: [HealthQuantitySample], timeZone: TimeZone) -> [DayKey: Double] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let nightly = samples.filter { sample in
            sample.value.isFinite && hrvRange.contains(sample.value)
                && calendar.component(.hour, from: sample.date) < nightEndHour
        }
        let counts = Dictionary(grouping: nightly, by: \.sourceID).mapValues(\.count)
        guard let source = counts.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value })?.key else {
            return [:]
        }
        return dailyMean(nightly.filter { $0.sourceID == source }, timeZone: timeZone)
    }

    /// FC a riposo: media dei campioni del giorno (di solito uno, calcolato da Salute).
    public static func dailyRestingHeartRate(_ samples: [HealthQuantitySample], timeZone: TimeZone) -> [DayKey: Double] {
        dailyMean(samples.filter { $0.value.isFinite && restingHRRange.contains($0.value) }, timeZone: timeZone)
    }

    static func dailyMean(_ samples: [HealthQuantitySample], timeZone: TimeZone) -> [DayKey: Double] {
        let grouped = Dictionary(grouping: samples) { DayKey(date: $0.date, timeZone: timeZone) }
        return grouped.mapValues { values in values.reduce(0) { $0 + $1.value } / Double(values.count) }
    }

    /// Unisce le fonti in una riga per giorno, ordinata; i giorni senza alcun dato non compaiono.
    public static func summaries(
        activity: [DayKey: DailyActivity], sleepMinutes: [DayKey: Double], restingHeartRate: [DayKey: Double],
        hrv: [DayKey: Double]
    ) -> [DailySummary] {
        let days = Set(activity.keys).union(sleepMinutes.keys).union(restingHeartRate.keys).union(hrv.keys)
        return days.sorted().compactMap { day in
            let summary = DailySummary(
                dayKey: day,
                steps: activity[day]?.steps.flatMap { stepsRange.contains($0) ? $0 : nil },
                activeKcal: activity[day]?.activeKcal.flatMap { $0.isFinite && activeKcalRange.contains($0) ? $0 : nil },
                sleepMinutes: sleepMinutes[day].flatMap { sleepRange.contains($0) ? $0 : nil },
                restingHeartRate: restingHeartRate[day],
                hrvSDNNMilliseconds: hrv[day]
            )
            return summary.isEmpty ? nil : summary
        }
    }
}
