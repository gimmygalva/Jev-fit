// GENERATO da tools/codegen/generate_records.py a partire da Persistence/Migrations/*.sql.
// NON MODIFICARE A MANO: cambia la migrazione (nuova versione) e rigenera.
// swiftlint:disable all

import Foundation
import GRDB
import JevCore
import JevDomain

/// Riga della tabella `user_profile` (fatto sincronizzato).
public struct UserProfileRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "user_profile"

    public var id: UUID
    public var birthYear: Int
    public var heightCm: Double
    public var sex: BiologicalSex?
    public var experience: ExperienceLevel
    public var activityLevel: ActivityLevel
    public var unitSystem: UnitSystem
    public var energyUnit: EnergyUnitPreference
    public var pregnancyOrLactation: Bool?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        birthYear: Int,
        heightCm: Double,
        sex: BiologicalSex? = nil,
        experience: ExperienceLevel,
        activityLevel: ActivityLevel,
        unitSystem: UnitSystem = .metric,
        energyUnit: EnergyUnitPreference = .kcal,
        pregnancyOrLactation: Bool? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.birthYear = birthYear
        self.heightCm = heightCm
        self.sex = sex
        self.experience = experience
        self.activityLevel = activityLevel
        self.unitSystem = unitSystem
        self.energyUnit = energyUnit
        self.pregnancyOrLactation = pregnancyOrLactation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case birthYear = "birth_year"
        case heightCm = "height_cm"
        case sex
        case experience
        case activityLevel = "activity_level"
        case unitSystem = "unit_system"
        case energyUnit = "energy_unit"
        case pregnancyOrLactation = "pregnancy_or_lactation"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `goal` (fatto sincronizzato).
public struct GoalRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "goal"

    public var id: UUID
    public var type: GoalType
    public var targetWeightKg: Double?
    public var targetRatePctWeek: Double?
    public var startedAt: Date
    public var endedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        type: GoalType,
        targetWeightKg: Double? = nil,
        targetRatePctWeek: Double? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.type = type
        self.targetWeightKg = targetWeightKg
        self.targetRatePctWeek = targetRatePctWeek
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case type
        case targetWeightKg = "target_weight_kg"
        case targetRatePctWeek = "target_rate_pct_week"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `app_settings` (fatto sincronizzato).
public struct AppSettingsRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "app_settings"

    public var id: UUID
    public var macroMode: MacroMode
    public var checkInWeekday: Int
    public var calorieCyclingEnabled: Bool
    public var notifications: String
    public var display: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        macroMode: MacroMode = .auto,
        checkInWeekday: Int = 1,
        calorieCyclingEnabled: Bool = false,
        notifications: String = "{}",
        display: String = "{}",
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.macroMode = macroMode
        self.checkInWeekday = checkInWeekday
        self.calorieCyclingEnabled = calorieCyclingEnabled
        self.notifications = notifications
        self.display = display
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case macroMode = "macro_mode"
        case checkInWeekday = "check_in_weekday"
        case calorieCyclingEnabled = "calorie_cycling_enabled"
        case notifications
        case display
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `training_preferences` (fatto sincronizzato).
public struct TrainingPreferencesRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "training_preferences"

    public var id: UUID
    public var daysPerWeek: Int
    public var preferredWeekdays: [Int]
    public var sessionMinutes: Int
    public var splitPreference: SplitType?
    public var equipment: [Equipment]
    public var musclePriority: [MuscleGroup]
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        daysPerWeek: Int,
        preferredWeekdays: [Int] = [],
        sessionMinutes: Int,
        splitPreference: SplitType? = nil,
        equipment: [Equipment] = [],
        musclePriority: [MuscleGroup] = [],
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.daysPerWeek = daysPerWeek
        self.preferredWeekdays = preferredWeekdays
        self.sessionMinutes = sessionMinutes
        self.splitPreference = splitPreference
        self.equipment = equipment
        self.musclePriority = musclePriority
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case daysPerWeek = "days_per_week"
        case preferredWeekdays = "preferred_weekdays"
        case sessionMinutes = "session_minutes"
        case splitPreference = "split_preference"
        case equipment
        case musclePriority = "muscle_priority"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `limitation` (fatto sincronizzato).
public struct LimitationRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "limitation"

    public var id: UUID
    public var bodyArea: BodyArea
    public var severity: LimitationSeverity
    public var note: String?
    public var active: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        bodyArea: BodyArea,
        severity: LimitationSeverity,
        note: String? = nil,
        active: Bool = true,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.bodyArea = bodyArea
        self.severity = severity
        self.note = note
        self.active = active
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case bodyArea = "body_area"
        case severity
        case note
        case active
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `weight_entry` (fatto sincronizzato).
public struct WeightEntryRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "weight_entry"

    public var id: UUID
    public var measuredAt: Date
    public var dayKey: DayKey
    public var tz: String
    public var weightKg: Double
    public var source: MeasurementSource
    public var hkUuid: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        measuredAt: Date,
        dayKey: DayKey,
        tz: String,
        weightKg: Double,
        source: MeasurementSource,
        hkUuid: UUID? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.measuredAt = measuredAt
        self.dayKey = dayKey
        self.tz = tz
        self.weightKg = weightKg
        self.source = source
        self.hkUuid = hkUuid
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case measuredAt = "measured_at"
        case dayKey = "day_key"
        case tz
        case weightKg = "weight_kg"
        case source
        case hkUuid = "hk_uuid"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `body_measurement` (fatto sincronizzato).
public struct BodyMeasurementRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "body_measurement"

    public var id: UUID
    public var type: BodyMeasurementType
    public var value: Double
    public var measuredAt: Date
    public var dayKey: DayKey
    public var tz: String
    public var source: MeasurementSource
    public var hkUuid: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        type: BodyMeasurementType,
        value: Double,
        measuredAt: Date,
        dayKey: DayKey,
        tz: String,
        source: MeasurementSource,
        hkUuid: UUID? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.type = type
        self.value = value
        self.measuredAt = measuredAt
        self.dayKey = dayKey
        self.tz = tz
        self.source = source
        self.hkUuid = hkUuid
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case type
        case value
        case measuredAt = "measured_at"
        case dayKey = "day_key"
        case tz
        case source
        case hkUuid = "hk_uuid"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `subjective_check` (fatto sincronizzato).
public struct SubjectiveCheckRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "subjective_check"

    public var id: UUID
    public var dayKey: DayKey
    public var sleepQuality: Int?
    public var energy: Int?
    public var soreness: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        dayKey: DayKey,
        sleepQuality: Int? = nil,
        energy: Int? = nil,
        soreness: Int? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.dayKey = dayKey
        self.sleepQuality = sleepQuality
        self.energy = energy
        self.soreness = soreness
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case dayKey = "day_key"
        case sleepQuality = "sleep_quality"
        case energy
        case soreness
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `custom_exercise` (fatto sincronizzato).
public struct CustomExerciseRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "custom_exercise"

    public var id: UUID
    public var name: String
    public var loadType: LoadType
    public var equipment: [Equipment]
    public var mechanics: ExerciseMechanics?
    public var laterality: ExerciseLaterality?
    public var bodyweightFraction: Double?
    public var loadIncrementKg: Double?
    public var contraindicatedAreas: [BodyArea]
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        name: String,
        loadType: LoadType,
        equipment: [Equipment] = [],
        mechanics: ExerciseMechanics? = nil,
        laterality: ExerciseLaterality? = nil,
        bodyweightFraction: Double? = nil,
        loadIncrementKg: Double? = nil,
        contraindicatedAreas: [BodyArea] = [],
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.name = name
        self.loadType = loadType
        self.equipment = equipment
        self.mechanics = mechanics
        self.laterality = laterality
        self.bodyweightFraction = bodyweightFraction
        self.loadIncrementKg = loadIncrementKg
        self.contraindicatedAreas = contraindicatedAreas
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case name
        case loadType = "load_type"
        case equipment
        case mechanics
        case laterality
        case bodyweightFraction = "bodyweight_fraction"
        case loadIncrementKg = "load_increment_kg"
        case contraindicatedAreas = "contraindicated_areas"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `custom_exercise_muscle` (fatto sincronizzato).
public struct CustomExerciseMuscleRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "custom_exercise_muscle"

    public var id: UUID
    public var customExerciseId: UUID
    public var muscle: MuscleGroup
    public var role: MuscleRole
    public var contribution: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        customExerciseId: UUID,
        muscle: MuscleGroup,
        role: MuscleRole,
        contribution: Double,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.customExerciseId = customExerciseId
        self.muscle = muscle
        self.role = role
        self.contribution = contribution
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case customExerciseId = "custom_exercise_id"
        case muscle
        case role
        case contribution
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `exercise_preference` (fatto sincronizzato).
public struct ExercisePreferenceRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "exercise_preference"

    public var id: UUID
    public var exerciseKey: String?
    public var customExerciseId: UUID?
    public var kind: ExercisePreferenceKind
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        exerciseKey: String? = nil,
        customExerciseId: UUID? = nil,
        kind: ExercisePreferenceKind,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.exerciseKey = exerciseKey
        self.customExerciseId = customExerciseId
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case exerciseKey = "exercise_key"
        case customExerciseId = "custom_exercise_id"
        case kind
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `recovery_calibration` (fatto sincronizzato).
public struct RecoveryCalibrationRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "recovery_calibration"

    public var id: UUID
    public var muscle: MuscleGroup
    public var userTauMultiplier: Double
    public var nObservations: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        muscle: MuscleGroup,
        userTauMultiplier: Double,
        nObservations: Int = 0,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.muscle = muscle
        self.userTauMultiplier = userTauMultiplier
        self.nObservations = nObservations
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case muscle
        case userTauMultiplier = "user_tau_multiplier"
        case nObservations = "n_observations"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `training_program` (fatto sincronizzato).
public struct TrainingProgramRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "training_program"

    public var id: UUID
    public var split: SplitType
    public var mesocycleIndex: Int
    public var weekIndex: Int
    public var scheme: String
    public var status: ProgramStatus
    public var engineVersion: Int
    public var startedAt: Date
    public var endedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        split: SplitType,
        mesocycleIndex: Int = 0,
        weekIndex: Int = 0,
        scheme: String = "{}",
        status: ProgramStatus,
        engineVersion: Int,
        startedAt: Date,
        endedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.split = split
        self.mesocycleIndex = mesocycleIndex
        self.weekIndex = weekIndex
        self.scheme = scheme
        self.status = status
        self.engineVersion = engineVersion
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case split
        case mesocycleIndex = "mesocycle_index"
        case weekIndex = "week_index"
        case scheme
        case status
        case engineVersion = "engine_version"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `workout_template` (fatto sincronizzato).
public struct WorkoutTemplateRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "workout_template"

    public var id: UUID
    public var programId: UUID?
    public var sequenceIndex: Int
    public var name: String
    public var focusMuscles: [MuscleGroup]
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        programId: UUID? = nil,
        sequenceIndex: Int = 0,
        name: String,
        focusMuscles: [MuscleGroup] = [],
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.programId = programId
        self.sequenceIndex = sequenceIndex
        self.name = name
        self.focusMuscles = focusMuscles
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case programId = "program_id"
        case sequenceIndex = "sequence_index"
        case name
        case focusMuscles = "focus_muscles"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `workout_template_exercise` (fatto sincronizzato).
public struct WorkoutTemplateExerciseRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "workout_template_exercise"

    public var id: UUID
    public var templateId: UUID
    public var exerciseKey: String?
    public var customExerciseId: UUID?
    public var position: Int
    public var sets: Int
    public var repMin: Int
    public var repMax: Int
    public var targetRir: Int?
    public var restS: Int?
    public var supersetGroup: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        templateId: UUID,
        exerciseKey: String? = nil,
        customExerciseId: UUID? = nil,
        position: Int,
        sets: Int,
        repMin: Int,
        repMax: Int,
        targetRir: Int? = nil,
        restS: Int? = nil,
        supersetGroup: Int? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.templateId = templateId
        self.exerciseKey = exerciseKey
        self.customExerciseId = customExerciseId
        self.position = position
        self.sets = sets
        self.repMin = repMin
        self.repMax = repMax
        self.targetRir = targetRir
        self.restS = restS
        self.supersetGroup = supersetGroup
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case templateId = "template_id"
        case exerciseKey = "exercise_key"
        case customExerciseId = "custom_exercise_id"
        case position
        case sets
        case repMin = "rep_min"
        case repMax = "rep_max"
        case targetRir = "target_rir"
        case restS = "rest_s"
        case supersetGroup = "superset_group"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `workout_session` (fatto sincronizzato).
public struct WorkoutSessionRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "workout_session"

    public var id: UUID
    public var templateId: UUID?
    public var programId: UUID?
    public var startedAt: Date
    public var endedAt: Date?
    public var status: WorkoutSessionStatus
    public var dayKey: DayKey
    public var tz: String
    public var notes: String?
    public var source: WorkoutSource
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        templateId: UUID? = nil,
        programId: UUID? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        status: WorkoutSessionStatus,
        dayKey: DayKey,
        tz: String,
        notes: String? = nil,
        source: WorkoutSource = .app,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.templateId = templateId
        self.programId = programId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.dayKey = dayKey
        self.tz = tz
        self.notes = notes
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case templateId = "template_id"
        case programId = "program_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case status
        case dayKey = "day_key"
        case tz
        case notes
        case source
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `workout_exercise` (fatto sincronizzato).
public struct WorkoutExerciseRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "workout_exercise"

    public var id: UUID
    public var sessionId: UUID
    public var exerciseKey: String?
    public var customExerciseId: UUID?
    public var position: Int
    public var replacedFromExerciseKey: String?
    public var replacedFromCustomExerciseId: UUID?
    public var supersetGroup: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        sessionId: UUID,
        exerciseKey: String? = nil,
        customExerciseId: UUID? = nil,
        position: Int,
        replacedFromExerciseKey: String? = nil,
        replacedFromCustomExerciseId: UUID? = nil,
        supersetGroup: Int? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.sessionId = sessionId
        self.exerciseKey = exerciseKey
        self.customExerciseId = customExerciseId
        self.position = position
        self.replacedFromExerciseKey = replacedFromExerciseKey
        self.replacedFromCustomExerciseId = replacedFromCustomExerciseId
        self.supersetGroup = supersetGroup
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case sessionId = "session_id"
        case exerciseKey = "exercise_key"
        case customExerciseId = "custom_exercise_id"
        case position
        case replacedFromExerciseKey = "replaced_from_exercise_key"
        case replacedFromCustomExerciseId = "replaced_from_custom_exercise_id"
        case supersetGroup = "superset_group"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `workout_set` (fatto sincronizzato).
public struct WorkoutSetRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "workout_set"

    public var id: UUID
    public var workoutExerciseId: UUID
    public var setIndex: Int
    public var setType: SetType
    public var weightKg: Double?
    public var enteredValue: Double?
    public var enteredUnit: EnteredMassUnit?
    public var addedLoadKg: Double?
    public var reps: Int?
    public var rir: Double?
    public var rpe: Double?
    public var durationS: Int?
    public var restS: Int?
    public var completedAt: Date?
    public var targetWeightKg: Double?
    public var targetReps: Int?
    public var painLevel: PainLevel
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        workoutExerciseId: UUID,
        setIndex: Int,
        setType: SetType,
        weightKg: Double? = nil,
        enteredValue: Double? = nil,
        enteredUnit: EnteredMassUnit? = nil,
        addedLoadKg: Double? = nil,
        reps: Int? = nil,
        rir: Double? = nil,
        rpe: Double? = nil,
        durationS: Int? = nil,
        restS: Int? = nil,
        completedAt: Date? = nil,
        targetWeightKg: Double? = nil,
        targetReps: Int? = nil,
        painLevel: PainLevel = .none,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.workoutExerciseId = workoutExerciseId
        self.setIndex = setIndex
        self.setType = setType
        self.weightKg = weightKg
        self.enteredValue = enteredValue
        self.enteredUnit = enteredUnit
        self.addedLoadKg = addedLoadKg
        self.reps = reps
        self.rir = rir
        self.rpe = rpe
        self.durationS = durationS
        self.restS = restS
        self.completedAt = completedAt
        self.targetWeightKg = targetWeightKg
        self.targetReps = targetReps
        self.painLevel = painLevel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case workoutExerciseId = "workout_exercise_id"
        case setIndex = "set_index"
        case setType = "set_type"
        case weightKg = "weight_kg"
        case enteredValue = "entered_value"
        case enteredUnit = "entered_unit"
        case addedLoadKg = "added_load_kg"
        case reps
        case rir
        case rpe
        case durationS = "duration_s"
        case restS = "rest_s"
        case completedAt = "completed_at"
        case targetWeightKg = "target_weight_kg"
        case targetReps = "target_reps"
        case painLevel = "pain_level"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `pain_report` (fatto sincronizzato).
public struct PainReportRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "pain_report"

    public var id: UUID
    public var dayKey: DayKey
    public var bodyArea: BodyArea
    public var level: PainLevel
    public var exerciseKey: String?
    public var customExerciseId: UUID?
    public var workoutSetId: UUID?
    public var acknowledgedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        dayKey: DayKey,
        bodyArea: BodyArea,
        level: PainLevel,
        exerciseKey: String? = nil,
        customExerciseId: UUID? = nil,
        workoutSetId: UUID? = nil,
        acknowledgedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.dayKey = dayKey
        self.bodyArea = bodyArea
        self.level = level
        self.exerciseKey = exerciseKey
        self.customExerciseId = customExerciseId
        self.workoutSetId = workoutSetId
        self.acknowledgedAt = acknowledgedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case dayKey = "day_key"
        case bodyArea = "body_area"
        case level
        case exerciseKey = "exercise_key"
        case customExerciseId = "custom_exercise_id"
        case workoutSetId = "workout_set_id"
        case acknowledgedAt = "acknowledged_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `custom_food` (fatto sincronizzato).
public struct CustomFoodRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "custom_food"

    public var id: UUID
    public var name: String
    public var brand: String?
    public var barcode: String?
    public var energyKcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var fiberG: Double?
    public var sugarG: Double?
    public var satFatG: Double?
    public var sodiumMg: Double?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        name: String,
        brand: String? = nil,
        barcode: String? = nil,
        energyKcal: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double? = nil,
        sugarG: Double? = nil,
        satFatG: Double? = nil,
        sodiumMg: Double? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.energyKcal = energyKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.satFatG = satFatG
        self.sodiumMg = sodiumMg
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case name
        case brand
        case barcode
        case energyKcal = "energy_kcal"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sugarG = "sugar_g"
        case satFatG = "sat_fat_g"
        case sodiumMg = "sodium_mg"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `custom_food_serving` (fatto sincronizzato).
public struct CustomFoodServingRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "custom_food_serving"

    public var id: UUID
    public var customFoodId: UUID
    public var label: String
    public var grams: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        customFoodId: UUID,
        label: String,
        grams: Double,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.customFoodId = customFoodId
        self.label = label
        self.grams = grams
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case customFoodId = "custom_food_id"
        case label
        case grams
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `recipe` (fatto sincronizzato).
public struct RecipeRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "recipe"

    public var id: UUID
    public var name: String
    public var yieldGrams: Double?
    public var servings: Double?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        name: String,
        yieldGrams: Double? = nil,
        servings: Double? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.name = name
        self.yieldGrams = yieldGrams
        self.servings = servings
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case name
        case yieldGrams = "yield_grams"
        case servings
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `recipe_ingredient` (fatto sincronizzato).
public struct RecipeIngredientRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "recipe_ingredient"

    public var id: UUID
    public var recipeId: UUID
    public var position: Int
    public var foodSource: FoodSource
    public var foodSourceId: String
    public var foodName: String
    public var grams: Double
    public var energyKcal100g: Double
    public var proteinG100g: Double
    public var carbsG100g: Double
    public var fatG100g: Double
    public var fiberG100g: Double?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        recipeId: UUID,
        position: Int = 0,
        foodSource: FoodSource,
        foodSourceId: String,
        foodName: String,
        grams: Double,
        energyKcal100g: Double,
        proteinG100g: Double,
        carbsG100g: Double,
        fatG100g: Double,
        fiberG100g: Double? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.recipeId = recipeId
        self.position = position
        self.foodSource = foodSource
        self.foodSourceId = foodSourceId
        self.foodName = foodName
        self.grams = grams
        self.energyKcal100g = energyKcal100g
        self.proteinG100g = proteinG100g
        self.carbsG100g = carbsG100g
        self.fatG100g = fatG100g
        self.fiberG100g = fiberG100g
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case recipeId = "recipe_id"
        case position
        case foodSource = "food_source"
        case foodSourceId = "food_source_id"
        case foodName = "food_name"
        case grams
        case energyKcal100g = "energy_kcal_100g"
        case proteinG100g = "protein_g_100g"
        case carbsG100g = "carbs_g_100g"
        case fatG100g = "fat_g_100g"
        case fiberG100g = "fiber_g_100g"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `saved_meal` (fatto sincronizzato).
public struct SavedMealRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "saved_meal"

    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `saved_meal_item` (fatto sincronizzato).
public struct SavedMealItemRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "saved_meal_item"

    public var id: UUID
    public var savedMealId: UUID
    public var position: Int
    public var foodSource: FoodSource
    public var foodSourceId: String
    public var foodName: String
    public var grams: Double
    public var energyKcal100g: Double
    public var proteinG100g: Double
    public var carbsG100g: Double
    public var fatG100g: Double
    public var fiberG100g: Double?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        savedMealId: UUID,
        position: Int = 0,
        foodSource: FoodSource,
        foodSourceId: String,
        foodName: String,
        grams: Double,
        energyKcal100g: Double,
        proteinG100g: Double,
        carbsG100g: Double,
        fatG100g: Double,
        fiberG100g: Double? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.savedMealId = savedMealId
        self.position = position
        self.foodSource = foodSource
        self.foodSourceId = foodSourceId
        self.foodName = foodName
        self.grams = grams
        self.energyKcal100g = energyKcal100g
        self.proteinG100g = proteinG100g
        self.carbsG100g = carbsG100g
        self.fatG100g = fatG100g
        self.fiberG100g = fiberG100g
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case savedMealId = "saved_meal_id"
        case position
        case foodSource = "food_source"
        case foodSourceId = "food_source_id"
        case foodName = "food_name"
        case grams
        case energyKcal100g = "energy_kcal_100g"
        case proteinG100g = "protein_g_100g"
        case carbsG100g = "carbs_g_100g"
        case fatG100g = "fat_g_100g"
        case fiberG100g = "fiber_g_100g"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `food_log_entry` (fatto sincronizzato).
public struct FoodLogEntryRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "food_log_entry"

    public var id: UUID
    public var dayKey: DayKey
    public var tz: String
    public var mealSlot: MealSlot
    public var loggedAt: Date
    public var foodSource: FoodSource
    public var foodSourceId: String?
    public var foodName: String?
    public var grams: Double?
    public var servings: Double?
    public var servingLabel: String?
    public var energyKcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var fiberG: Double?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        dayKey: DayKey,
        tz: String,
        mealSlot: MealSlot,
        loggedAt: Date,
        foodSource: FoodSource,
        foodSourceId: String? = nil,
        foodName: String? = nil,
        grams: Double? = nil,
        servings: Double? = nil,
        servingLabel: String? = nil,
        energyKcal: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.dayKey = dayKey
        self.tz = tz
        self.mealSlot = mealSlot
        self.loggedAt = loggedAt
        self.foodSource = foodSource
        self.foodSourceId = foodSourceId
        self.foodName = foodName
        self.grams = grams
        self.servings = servings
        self.servingLabel = servingLabel
        self.energyKcal = energyKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case dayKey = "day_key"
        case tz
        case mealSlot = "meal_slot"
        case loggedAt = "logged_at"
        case foodSource = "food_source"
        case foodSourceId = "food_source_id"
        case foodName = "food_name"
        case grams
        case servings
        case servingLabel = "serving_label"
        case energyKcal = "energy_kcal"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `weekly_check_in` (fatto sincronizzato).
public struct WeeklyCheckInRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "weekly_check_in"

    public var id: UUID
    public var weekStart: DayKey
    public var metrics: String
    public var decisions: String
    public var responses: String
    public var engineVersion: Int
    public var completedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        weekStart: DayKey,
        metrics: String = "{}",
        decisions: String = "[]",
        responses: String = "{}",
        engineVersion: Int,
        completedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.weekStart = weekStart
        self.metrics = metrics
        self.decisions = decisions
        self.responses = responses
        self.engineVersion = engineVersion
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case weekStart = "week_start"
        case metrics
        case decisions
        case responses
        case engineVersion = "engine_version"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `nutrition_day` (fatto sincronizzato).
public struct NutritionDayRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "nutrition_day"

    public var id: UUID
    public var dayKey: DayKey
    public var status: NutritionDayStatus
    public var dayType: DayType
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        dayKey: DayKey,
        status: NutritionDayStatus = .open,
        dayType: DayType = .rest,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.dayKey = dayKey
        self.status = status
        self.dayType = dayType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case dayKey = "day_key"
        case status
        case dayType = "day_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `nutrition_target` (fatto sincronizzato).
public struct NutritionTargetRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "nutrition_target"

    public var id: UUID
    public var effectiveFrom: DayKey
    public var mode: MacroMode
    public var kcalTraining: Double
    public var kcalRest: Double
    public var weeklyAvgKcal: Double
    public var origin: NutritionTargetOrigin
    public var checkInId: UUID?
    public var engineVersion: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        effectiveFrom: DayKey,
        mode: MacroMode,
        kcalTraining: Double,
        kcalRest: Double,
        weeklyAvgKcal: Double,
        origin: NutritionTargetOrigin,
        checkInId: UUID? = nil,
        engineVersion: Int,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.effectiveFrom = effectiveFrom
        self.mode = mode
        self.kcalTraining = kcalTraining
        self.kcalRest = kcalRest
        self.weeklyAvgKcal = weeklyAvgKcal
        self.origin = origin
        self.checkInId = checkInId
        self.engineVersion = engineVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case effectiveFrom = "effective_from"
        case mode
        case kcalTraining = "kcal_training"
        case kcalRest = "kcal_rest"
        case weeklyAvgKcal = "weekly_avg_kcal"
        case origin
        case checkInId = "check_in_id"
        case engineVersion = "engine_version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `macro_target` (fatto sincronizzato).
public struct MacroTargetRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "macro_target"

    public var id: UUID
    public var nutritionTargetId: UUID
    public var dayType: DayType
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var fiberG: Double?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        nutritionTargetId: UUID,
        dayType: DayType,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.nutritionTargetId = nutritionTargetId
        self.dayType = dayType
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case nutritionTargetId = "nutrition_target_id"
        case dayType = "day_type"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Riga della tabella `ai_recommendation` (fatto sincronizzato).
public struct AiRecommendationRecord: SyncedRecord, Equatable {
    public static let databaseTableName = "ai_recommendation"

    public var id: UUID
    public var kind: String
    public var payload: String
    public var text: String?
    public var provider: String?
    public var model: String?
    public var confidence: ConfidenceLabel?
    public var status: RecommendationStatus
    public var checkInId: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceId: UUID?
    public var serverUpdatedAt: Date?
    public var syncState: RecordSyncState

    public init(
        id: UUID,
        kind: String,
        payload: String = "{}",
        text: String? = nil,
        provider: String? = nil,
        model: String? = nil,
        confidence: ConfidenceLabel? = nil,
        status: RecommendationStatus,
        checkInId: UUID? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceId: UUID? = nil,
        serverUpdatedAt: Date? = nil,
        syncState: RecordSyncState = .pending
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.text = text
        self.provider = provider
        self.model = model
        self.confidence = confidence
        self.status = status
        self.checkInId = checkInId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceId = originDeviceId
        self.serverUpdatedAt = serverUpdatedAt
        self.syncState = syncState
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case kind
        case payload
        case text
        case provider
        case model
        case confidence
        case status
        case checkInId = "check_in_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case originDeviceId = "origin_device_id"
        case serverUpdatedAt = "server_updated_at"
        case syncState = "sync_state"
    }

    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\.rawValue) }
}

/// Tutti i tipi di record sincronizzati, nell'ordine di creazione delle tabelle
/// (i genitori prima dei figli: è anche l'ordine di push e pull, DATA_MODEL §5).
public enum SyncedTables {
    public static let all: [any SyncedRecord.Type] = [
        UserProfileRecord.self,
        GoalRecord.self,
        AppSettingsRecord.self,
        TrainingPreferencesRecord.self,
        LimitationRecord.self,
        WeightEntryRecord.self,
        BodyMeasurementRecord.self,
        SubjectiveCheckRecord.self,
        CustomExerciseRecord.self,
        CustomExerciseMuscleRecord.self,
        ExercisePreferenceRecord.self,
        RecoveryCalibrationRecord.self,
        TrainingProgramRecord.self,
        WorkoutTemplateRecord.self,
        WorkoutTemplateExerciseRecord.self,
        WorkoutSessionRecord.self,
        WorkoutExerciseRecord.self,
        WorkoutSetRecord.self,
        PainReportRecord.self,
        CustomFoodRecord.self,
        CustomFoodServingRecord.self,
        RecipeRecord.self,
        RecipeIngredientRecord.self,
        SavedMealRecord.self,
        SavedMealItemRecord.self,
        FoodLogEntryRecord.self,
        WeeklyCheckInRecord.self,
        NutritionDayRecord.self,
        NutritionTargetRecord.self,
        MacroTargetRecord.self,
        AiRecommendationRecord.self
    ]
}
