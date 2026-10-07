import Foundation
import GRDB
import JevCore
import JevDomain

/// Sessioni di allenamento (M8): ogni azione è scritta subito nel database locale, quindi una
/// sessione sopravvive alla chiusura forzata dell'app e si riprende dall'ultima serie salvata.
public struct WorkoutRepository: Sendable {
    public let facts: FactRepository

    public init(facts: FactRepository) {
        self.facts = facts
    }

    /// Esercizio da inserire in una nuova sessione, con le serie target già calcolate.
    public struct PlannedExerciseInput: Sendable, Hashable {
        public var exerciseKey: String
        public var sets: [PlannedSet]

        public init(exerciseKey: String, sets: [PlannedSet]) {
            self.exerciseKey = exerciseKey
            self.sets = sets
        }
    }

    public struct PlannedSet: Sendable, Hashable {
        public var type: SetType
        public var targetWeightKg: Double?
        public var targetReps: Int?
        public var targetDurationSeconds: Int?
        public var restSeconds: Int?

        public init(type: SetType = .working, targetWeightKg: Double? = nil, targetReps: Int? = nil,
                    targetDurationSeconds: Int? = nil, restSeconds: Int? = nil) {
            self.type = type
            self.targetWeightKg = targetWeightKg
            self.targetReps = targetReps
            self.targetDurationSeconds = targetDurationSeconds
            self.restSeconds = restSeconds
        }
    }

    public struct ExerciseDetail: Sendable, Equatable, Identifiable {
        public var exercise: WorkoutExerciseRecord
        public var sets: [WorkoutSetRecord]
        public var id: UUID { exercise.id }
    }

    public struct SessionDetail: Sendable, Equatable {
        public var session: WorkoutSessionRecord
        public var exercises: [ExerciseDetail]

        public var completedSets: Int {
            exercises.reduce(0) { $0 + $1.sets.filter { $0.completedAt != nil }.count }
        }
    }

    public enum WorkoutError: Error, Equatable {
        case sessionAlreadyActive
        case sessionNotActive
        case setNotFound
        case invalidValue
    }

    // MARK: Sessione

    public func activeSession() throws -> WorkoutSessionRecord? {
        try facts.writer.read { db in
            try WorkoutSessionRecord
                .filter(Column("status") == WorkoutSessionStatus.inProgress.rawValue && Column("deleted_at") == nil)
                .order(Column("started_at").desc)
                .fetchOne(db)
        }
    }

    /// Crea sessione, esercizi e serie pianificate in un'unica transazione.
    @discardableResult
    public func startSession(
        exercises: [PlannedExerciseInput], programID: UUID? = nil, timeZone: TimeZone = .current
    ) throws -> UUID {
        let now = facts.time.now()
        return try facts.writer.write { db in
            let active = try WorkoutSessionRecord
                .filter(Column("status") == WorkoutSessionStatus.inProgress.rawValue && Column("deleted_at") == nil)
                .fetchCount(db)
            guard active == 0 else { throw WorkoutError.sessionAlreadyActive }
            let session = WorkoutSessionRecord(
                id: UUIDv7.make(at: now), programId: programID, startedAt: now, status: .inProgress,
                dayKey: DayKey(date: now, timeZone: timeZone), tz: timeZone.identifier, createdAt: now, updatedAt: now
            )
            try facts.save(session, in: db)
            for (position, planned) in exercises.enumerated() {
                let exercise = WorkoutExerciseRecord(
                    id: UUIDv7.make(at: now), sessionId: session.id, exerciseKey: planned.exerciseKey,
                    position: position, createdAt: now, updatedAt: now
                )
                try facts.save(exercise, in: db)
                for (index, set) in planned.sets.enumerated() {
                    try facts.save(WorkoutSetRecord(
                        id: UUIDv7.make(at: now), workoutExerciseId: exercise.id, setIndex: index, setType: set.type,
                        durationS: nil, restS: set.restSeconds, targetWeightKg: set.targetWeightKg,
                        targetReps: set.targetReps ?? set.targetDurationSeconds, painLevel: .none,
                        createdAt: now, updatedAt: now
                    ), in: db)
                }
            }
            return session.id
        }
    }

    public func detail(sessionID: UUID) throws -> SessionDetail? {
        try facts.writer.read { db in try Self.detail(sessionID: sessionID, db: db) }
    }

    static func detail(sessionID: UUID, db: Database) throws -> SessionDetail? {
        guard let session = try WorkoutSessionRecord.fetchOne(db, key: sessionID), session.deletedAt == nil else {
            return nil
        }
        let exercises = try WorkoutExerciseRecord
            .filter(Column("session_id") == sessionID && Column("deleted_at") == nil)
            .order(Column("position"))
            .fetchAll(db)
        var details: [ExerciseDetail] = []
        for exercise in exercises {
            let sets = try WorkoutSetRecord
                .filter(Column("workout_exercise_id") == exercise.id && Column("deleted_at") == nil)
                .order(Column("set_index"))
                .fetchAll(db)
            details.append(ExerciseDetail(exercise: exercise, sets: sets))
        }
        return SessionDetail(session: session, exercises: details)
    }

    // MARK: Serie

    /// Registra una serie eseguita. Valori fuori dai limiti del database → `invalidValue`
    /// (la UI li blocca prima: questo è l'ultimo argine).
    @discardableResult
    public func completeSet(
        setID: UUID, weightKg: Double?, reps: Int?, rir: Double?, durationSeconds: Int? = nil,
        enteredUnit: EnteredMassUnit? = nil, painLevel: PainLevel = .none
    ) throws -> WorkoutSetRecord {
        if let weightKg, !(0...1000).contains(weightKg) || !weightKg.isFinite { throw WorkoutError.invalidValue }
        if let reps, !(0...200).contains(reps) { throw WorkoutError.invalidValue }
        if let rir, !(0...10).contains(rir) || !rir.isFinite { throw WorkoutError.invalidValue }
        if let durationSeconds, !(0...36_000).contains(durationSeconds) { throw WorkoutError.invalidValue }
        let now = facts.time.now()
        return try facts.writer.write { db in
            guard var set = try WorkoutSetRecord.fetchOne(db, key: setID), set.deletedAt == nil else {
                throw WorkoutError.setNotFound
            }
            try Self.requireActive(exerciseID: set.workoutExerciseId, db: db)
            set.weightKg = weightKg
            set.reps = reps
            set.rir = rir
            set.durationS = durationSeconds
            if let unit = enteredUnit, let kg = weightKg {
                set.enteredUnit = unit
                set.enteredValue = unit == .kg ? kg : Mass(kilograms: kg).pounds
            } else {
                set.enteredUnit = nil
                set.enteredValue = nil
            }
            set.painLevel = painLevel
            set.completedAt = now
            return try facts.save(set, in: db)
        }
    }

    /// Aggiunge una serie in coda all'esercizio, con gli stessi target dell'ultima.
    @discardableResult
    public func addSet(exerciseID: UUID, type: SetType = .working) throws -> WorkoutSetRecord {
        let now = facts.time.now()
        return try facts.writer.write { db in
            try Self.requireActive(exerciseID: exerciseID, db: db)
            let last = try WorkoutSetRecord
                .filter(Column("workout_exercise_id") == exerciseID && Column("deleted_at") == nil)
                .order(Column("set_index").desc)
                .fetchOne(db)
            let maxIndex = try Int.fetchOne(db, sql: "SELECT MAX(set_index) FROM workout_set WHERE workout_exercise_id = ?",
                                            arguments: [exerciseID]) ?? -1
            guard maxIndex < 100 else { throw WorkoutError.invalidValue }
            return try facts.save(WorkoutSetRecord(
                id: UUIDv7.make(at: now), workoutExerciseId: exerciseID, setIndex: maxIndex + 1, setType: type,
                restS: last?.restS, targetWeightKg: last?.targetWeightKg, targetReps: last?.targetReps,
                painLevel: .none, createdAt: now, updatedAt: now
            ), in: db)
        }
    }

    public func deleteSet(_ setID: UUID) throws {
        try facts.writer.write { db in
            guard let set = try WorkoutSetRecord.fetchOne(db, key: setID) else { throw WorkoutError.setNotFound }
            try Self.requireActive(exerciseID: set.workoutExerciseId, db: db)
            try facts.delete(WorkoutSetRecord.self, id: setID, in: db)
        }
    }

    /// Chiude la sessione: completata se c'è almeno una serie eseguita, altrimenti abbandonata.
    @discardableResult
    public func finish(sessionID: UUID) throws -> WorkoutSessionRecord {
        let now = facts.time.now()
        return try facts.writer.write { db in
            guard let detail = try Self.detail(sessionID: sessionID, db: db),
                  detail.session.status == .inProgress else { throw WorkoutError.sessionNotActive }
            var session = detail.session
            session.endedAt = now
            session.status = detail.completedSets > 0 ? .completed : .abandoned
            return try facts.save(session, in: db)
        }
    }

    public func abandon(sessionID: UUID) throws {
        let now = facts.time.now()
        try facts.writer.write { db in
            guard var session = try WorkoutSessionRecord.fetchOne(db, key: sessionID),
                  session.status == .inProgress, session.deletedAt == nil else { throw WorkoutError.sessionNotActive }
            session.endedAt = now
            session.status = .abandoned
            try facts.save(session, in: db)
        }
    }

    static func requireActive(exerciseID: UUID, db: Database) throws {
        guard let exercise = try WorkoutExerciseRecord.fetchOne(db, key: exerciseID),
              let session = try WorkoutSessionRecord.fetchOne(db, key: exercise.sessionId),
              session.status == .inProgress, session.deletedAt == nil else {
            throw WorkoutError.sessionNotActive
        }
    }

    // MARK: Storico

    /// Sessioni completate, dalla più recente.
    public func history(limit: Int = 50) throws -> [WorkoutSessionRecord] {
        try facts.writer.read { db in
            try WorkoutSessionRecord
                .filter(Column("status") == WorkoutSessionStatus.completed.rawValue && Column("deleted_at") == nil)
                .order(Column("started_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func completedSessionCount() throws -> Int {
        try facts.writer.read { db in
            try WorkoutSessionRecord
                .filter(Column("status") == WorkoutSessionStatus.completed.rawValue && Column("deleted_at") == nil)
                .fetchCount(db)
        }
    }

    /// Esposizione passata di un esercizio: serie eseguite in una sessione completata.
    public struct Exposure: Sendable, Equatable {
        public var sessionID: UUID
        public var date: Date
        public var sets: [WorkoutSetRecord]
    }

    /// Ultime esposizioni dell'esercizio (dalla più vecchia alla più recente), solo serie eseguite.
    public func exposures(exerciseKey: String, limit: Int = 12) throws -> [Exposure] {
        try facts.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT s.id AS session_id, s.started_at AS started_at, e.id AS exercise_id
                FROM workout_exercise e JOIN workout_session s ON s.id = e.session_id
                WHERE e.exercise_key = ? AND e.deleted_at IS NULL AND s.deleted_at IS NULL AND s.status = 'completed'
                ORDER BY s.started_at DESC LIMIT ?
                """, arguments: [exerciseKey, limit])
            var result: [Exposure] = []
            for row in rows {
                let exerciseID: UUID = row["exercise_id"]
                let sets = try WorkoutSetRecord
                    .filter(Column("workout_exercise_id") == exerciseID && Column("deleted_at") == nil
                            && Column("completed_at") != nil)
                    .order(Column("set_index"))
                    .fetchAll(db)
                guard !sets.isEmpty else { continue }
                result.append(Exposure(sessionID: row["session_id"], date: row["started_at"], sets: sets))
            }
            return result.reversed()
        }
    }
}
