import Foundation
import GRDB
import JevCore
import JevDomain

/// Record di una tabella "fatto" sincronizzata (DATA_MODEL §3–§5).
///
/// I tipi concreti sono GENERATI dallo schema SQL (`SyncedRecords.generated.swift`). Le colonne
/// di sync sono comuni a tutti; `user_id` esiste solo nel cloud (il dispositivo ha un solo
/// proprietario). Le scritture passano da `FactRepository`, che imposta timestamp, dispositivo
/// d'origine e `syncState = .pending` (il trigger SQL accoda il record nell'outbox).
public protocol SyncedRecord: Codable, Sendable, FetchableRecord, PersistableRecord, Identifiable
where ID == UUID {
    var id: UUID { get }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var originDeviceId: UUID? { get set }
    var serverUpdatedAt: Date? { get set }
    var syncState: RecordSyncState { get set }

    /// Colonne della tabella, nell'ordine dei `CodingKeys` (verificate dai test sullo schema).
    static var databaseColumnNames: [String] { get }
}

/// Stato di sincronizzazione di un record locale.
public enum RecordSyncState: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    /// Modificato in locale, in attesa di push (presente nell'outbox).
    case pending
    /// Uguale all'ultima versione confermata dal server.
    case synced
    /// Rifiutato in modo permanente dal server (es. RLS 42501): mai ritentato in automatico
    /// (SECURITY §6.5), richiede un intervento esplicito.
    case conflict
}

// MARK: - Enum di storage (valori raw = valori dei CHECK nello schema SQL)

public enum UnitSystem: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case metric
    case imperial
}

public enum EnergyUnitPreference: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case kcal
    case kj
}

public enum LimitationSeverity: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case mild
    case moderate
}

public enum MeasurementSource: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case manual
    case healthkit
}

public enum WorkoutSource: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case app
    case manual
}

/// Tipo di misura corporea. `bodyFatPct` è in percentuale, le circonferenze in centimetri.
public enum BodyMeasurementType: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case bodyFatPct = "body_fat_pct"
    case waist
    case hips
    case chest
    case arm
    case thigh
    case neck
}

public enum ExerciseMechanics: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case compound
    case isolation
}

public enum ExerciseLaterality: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case bilateral
    case unilateral
}

public enum ProgramStatus: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case active
    case completed
    case archived
}

public enum WorkoutSessionStatus: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case inProgress = "in_progress"
    case completed
    case abandoned
}

public enum RecommendationStatus: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case proposed
    case accepted
    case rejected
    case expired
}

/// Unità con cui l'utente ha digitato un carico (il valore canonico resta in kg).
public enum EnteredMassUnit: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case kg
    case lb
}

public enum ExercisePreferenceKind: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case favorite
    case excluded
    case disliked
}

/// Provenienza di un alimento in diario, ricette e pasti salvati (ADR-009).
public enum FoodSource: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case catalog
    case custom
    case openFoodFacts = "open_food_facts"
    case usda
    case recipe
    case quickAdd = "quick_add"
}

public enum NutritionTargetOrigin: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case onboarding
    case checkIn = "check_in"
    case manual
}

// MARK: - Tipi di JevCore/JevDomain nel database
//
// Gli enum con valore raw String usano l'implementazione predefinita di GRDB per
// RawRepresentable. Conformità retroattive: i tipi stanno in JevEngines, che non dipende da GRDB
// (ADR-003), e GRDB non li conformerà mai di suo.

extension BiologicalSex: @retroactive DatabaseValueConvertible {}
extension ExperienceLevel: @retroactive DatabaseValueConvertible {}
extension ActivityLevel: @retroactive DatabaseValueConvertible {}
extension GoalType: @retroactive DatabaseValueConvertible {}
extension SplitType: @retroactive DatabaseValueConvertible {}
extension MuscleGroup: @retroactive DatabaseValueConvertible {}
extension MuscleRole: @retroactive DatabaseValueConvertible {}
extension LoadType: @retroactive DatabaseValueConvertible {}
extension SetType: @retroactive DatabaseValueConvertible {}
extension PainLevel: @retroactive DatabaseValueConvertible {}
extension MealSlot: @retroactive DatabaseValueConvertible {}
extension MacroMode: @retroactive DatabaseValueConvertible {}
extension NutritionDayStatus: @retroactive DatabaseValueConvertible {}
extension DayType: @retroactive DatabaseValueConvertible {}
extension BodyArea: @retroactive DatabaseValueConvertible {}
extension ConfidenceLabel: @retroactive DatabaseValueConvertible {}

/// `DayKey` è salvato come testo `yyyy-MM-dd`, identico alla colonna `date` del cloud (ADR-010).
extension DayKey: @retroactive DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        description.databaseValue
    }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> DayKey? {
        guard let text = String.fromDatabaseValue(dbValue) else { return nil }
        return DayKey(text)
    }
}
