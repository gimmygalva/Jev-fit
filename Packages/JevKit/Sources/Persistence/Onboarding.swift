import Foundation
import GRDB
import JevCore
import JevDomain

/// Risposte dell'onboarding raccolte finora (UF-01, PS-ON-01).
///
/// La bozza si salva a ogni step, così chiudendo l'app a metà si riparte dallo stesso punto con
/// i valori già inseriti. Contiene dati sanitari (peso, altezza, gravidanza): vive nel database
/// principale (`schema_meta`), protetto come il resto, mai in `UserDefaults` (SEC-LS-07).
/// Al termine `OnboardingRepository.complete` la trasforma nei record "fatto" e la cancella.
public struct OnboardingDraft: Codable, Sendable, Equatable {
    /// Versione del formato: se cambia in modo incompatibile, una bozza vecchia viene scartata.
    public static let currentFormatVersion = 1

    public var formatVersion: Int = OnboardingDraft.currentFormatVersion
    /// Identificativo dello step corrente (lo interpreta la UI).
    public var currentStep: String?

    public var goal: GoalType?
    public var experience: ExperienceLevel?
    public var weightKg: Double?
    public var heightCm: Double?
    public var ageYears: Int?
    public var sex: BiologicalSex?
    public var pregnancyOrLactation: Bool = false
    public var bodyFatPercent: Double?
    public var activityLevel: ActivityLevel = .moderate
    public var targetWeightKg: Double?
    public var targetRatePercentPerWeek: Double?
    public var daysPerWeek: Int?
    public var preferredWeekdays: [Int] = []
    public var sessionMinutes: Int = 60
    public var equipment: [Equipment] = []
    /// `nil` = "Lascia decidere a JEV".
    public var splitPreference: SplitType?
    public var limitations: [Limitation] = []
    public var musclePriority: [MuscleGroup] = []
    public var macroMode: MacroMode = .auto
    public var unitSystem: UnitSystem = .metric
    public var energyUnit: EnergyUnitPreference = .kcal
    /// 1 = lunedì … 7 = domenica.
    public var checkInWeekday: Int = 1

    public struct Limitation: Codable, Sendable, Equatable, Hashable {
        public var area: BodyArea
        public var severity: LimitationSeverity
        public var note: String?

        public init(area: BodyArea, severity: LimitationSeverity, note: String? = nil) {
            self.area = area
            self.severity = severity
            self.note = note
        }
    }

    public init() {}
}

/// Carica e salva la bozza dell'onboarding e la conclude scrivendo i record.
public struct OnboardingRepository: Sendable {
    static let draftKey = "onboarding_draft"
    static let completedKey = "onboarding_completed_at"

    public let writer: any DatabaseWriter
    let facts: FactRepository
    let time: any TimeSource

    public init(store: DataStore, time: any TimeSource = SystemTimeSource()) {
        self.writer = store.writer
        self.facts = FactRepository(store: store, time: time)
        self.time = time
    }

    /// `true` dopo `complete`, oppure se esiste già un profilo (es. ripristinato da un backup).
    public func isCompleted() throws -> Bool {
        try writer.read { db in
            if try String.fetchOne(db, sql: "SELECT value FROM schema_meta WHERE key = ?", arguments: [Self.completedKey]) != nil {
                return true
            }
            return try UserProfileRecord.filter(Column("deleted_at") == nil).fetchCount(db) > 0
        }
    }

    /// La bozza salvata, oppure `nil` se non c'è o è di un formato incompatibile.
    public func loadDraft() throws -> OnboardingDraft? {
        let json = try writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM schema_meta WHERE key = ?", arguments: [Self.draftKey])
        }
        guard let json, let data = json.data(using: .utf8),
              let draft = try? JSONDecoder().decode(OnboardingDraft.self, from: data),
              draft.formatVersion == OnboardingDraft.currentFormatVersion
        else { return nil }
        return draft
    }

    public func saveDraft(_ draft: OnboardingDraft) throws {
        let data = try JSONEncoder().encode(draft)
        let json = String(decoding: data, as: UTF8.self)
        try writer.write { db in
            try db.execute(
                sql: "INSERT INTO schema_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [Self.draftKey, json]
            )
        }
    }

    /// Scrive profilo, obiettivo, impostazioni, preferenze, limitazioni e prima pesata in una
    /// sola transazione, poi cancella la bozza. Se un dato obbligatorio manca o un vincolo del
    /// database fallisce, non viene scritto nulla.
    public func complete(_ draft: OnboardingDraft, timeZone: TimeZone = .current) throws {
        let input = try CompletedOnboarding(draft)
        let now = time.now()
        try writer.write { db in
            try facts.save(
                UserProfileRecord(
                    id: UUIDv7.make(at: now),
                    birthYear: input.birthYear(now: now, timeZone: timeZone),
                    heightCm: input.heightCm,
                    sex: draft.sex,
                    experience: input.experience,
                    activityLevel: draft.activityLevel,
                    unitSystem: draft.unitSystem,
                    energyUnit: draft.energyUnit,
                    pregnancyOrLactation: draft.sex == .male ? nil : draft.pregnancyOrLactation,
                    createdAt: now,
                    updatedAt: now
                ),
                in: db
            )
            try facts.save(
                GoalRecord(
                    id: UUIDv7.make(at: now),
                    type: input.goal,
                    targetWeightKg: draft.targetWeightKg,
                    targetRatePctWeek: GoalSafety.rateLimits(for: input.goal) == nil
                        ? nil
                        : GoalSafety.clampRate(draft.targetRatePercentPerWeek ?? .nan, for: input.goal),
                    startedAt: now,
                    createdAt: now,
                    updatedAt: now
                ),
                in: db
            )
            try facts.save(
                AppSettingsRecord(
                    id: UUIDv7.make(at: now),
                    macroMode: draft.macroMode,
                    checkInWeekday: draft.checkInWeekday,
                    createdAt: now,
                    updatedAt: now
                ),
                in: db
            )
            try facts.save(
                TrainingPreferencesRecord(
                    id: UUIDv7.make(at: now),
                    daysPerWeek: input.daysPerWeek,
                    preferredWeekdays: draft.preferredWeekdays.sorted(),
                    sessionMinutes: draft.sessionMinutes,
                    splitPreference: draft.splitPreference,
                    equipment: input.equipment,
                    musclePriority: draft.musclePriority,
                    createdAt: now,
                    updatedAt: now
                ),
                in: db
            )
            for limitation in draft.limitations {
                let note = limitation.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                try facts.save(
                    LimitationRecord(
                        id: UUIDv7.make(at: now),
                        bodyArea: limitation.area,
                        severity: limitation.severity,
                        note: (note?.isEmpty ?? true) ? nil : note,
                        createdAt: now,
                        updatedAt: now
                    ),
                    in: db
                )
            }
            try facts.save(
                WeightEntryRecord(
                    id: UUIDv7.make(at: now),
                    measuredAt: now,
                    dayKey: DayKey(date: now, timeZone: timeZone),
                    tz: timeZone.identifier,
                    weightKg: input.weightKg,
                    source: .manual,
                    createdAt: now,
                    updatedAt: now
                ),
                in: db
            )
            if let bodyFat = draft.bodyFatPercent {
                try facts.save(
                    BodyMeasurementRecord(
                        id: UUIDv7.make(at: now),
                        type: .bodyFatPct,
                        value: bodyFat,
                        measuredAt: now,
                        dayKey: DayKey(date: now, timeZone: timeZone),
                        tz: timeZone.identifier,
                        source: .manual,
                        createdAt: now,
                        updatedAt: now
                    ),
                    in: db
                )
            }
            try db.execute(sql: "DELETE FROM schema_meta WHERE key = ?", arguments: [Self.draftKey])
            try db.execute(
                sql: "INSERT INTO schema_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [Self.completedKey, ISO8601DateFormatter().string(from: now)]
            )
        }
    }
}

public enum OnboardingError: Error, Equatable {
    /// Manca un dato obbligatorio (PS-ON-02).
    case missing(String)
    /// L'obiettivo non è consentito per questa persona (GoalSafety).
    case goalNotAllowed(GoalSafety.BlockReason)
}

/// Dati obbligatori estratti e verificati dalla bozza.
struct CompletedOnboarding {
    let goal: GoalType
    let experience: ExperienceLevel
    let weightKg: Double
    let heightCm: Double
    let ageYears: Int
    let daysPerWeek: Int
    let equipment: [Equipment]

    init(_ draft: OnboardingDraft) throws {
        guard let goal = draft.goal else { throw OnboardingError.missing("goal") }
        guard let experience = draft.experience else { throw OnboardingError.missing("experience") }
        guard let weight = draft.weightKg else { throw OnboardingError.missing("weight") }
        guard let height = draft.heightCm else { throw OnboardingError.missing("height") }
        guard let age = draft.ageYears else { throw OnboardingError.missing("age") }
        guard let days = draft.daysPerWeek else { throw OnboardingError.missing("days_per_week") }
        let person = GoalSafety.Person(
            ageYears: age, weightKg: weight, heightCm: height,
            pregnancyOrLactation: draft.pregnancyOrLactation
        )
        if let reason = GoalSafety.block(for: goal, person: person) {
            throw OnboardingError.goalNotAllowed(reason)
        }
        self.goal = goal
        self.experience = experience
        self.weightKg = weight
        self.heightCm = height
        self.ageYears = age
        self.daysPerWeek = days
        // Nessuna attrezzatura selezionata → corpo libero (UF-01, edge case).
        self.equipment = draft.equipment.isEmpty ? [.bodyweight] : draft.equipment
    }

    /// Anno di nascita stimato dall'età dichiarata (la data esatta non serve agli engine).
    func birthYear(now: Date, timeZone: TimeZone) -> Int {
        DayKey(date: now, timeZone: timeZone).year - ageYears
    }
}
