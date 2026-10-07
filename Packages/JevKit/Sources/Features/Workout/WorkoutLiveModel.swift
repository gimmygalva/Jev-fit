import ExerciseCatalog
import Foundation
import JevCore
import JevDomain
import Observation
import Persistence
import WorkoutEngine

/// Stato della sessione in corso (SCR-WK-02). Tutto ciò che conta è nel database: il modello
/// ricarica da lì dopo ogni azione, quindi la chiusura forzata dell'app non perde nulla e il
/// timer di recupero (derivato dall'ultima serie completata) riparte da dove era.
@MainActor
@Observable
public final class WorkoutLiveModel {
    public let sessionID: UUID
    public private(set) var detail: WorkoutRepository.SessionDetail?
    /// Fine del recupero dopo l'ultima serie completata.
    public private(set) var restEndsAt: Date?
    /// Carico suggerito per le serie restanti dopo la prima serie (aggiustamento live §5.7).
    public private(set) var suggestedLoadKg: [UUID: Double] = [:]
    public private(set) var summary: PerformanceAnalysis.SessionSummary?
    public private(set) var lastError: WorkoutRepository.WorkoutError?

    private let repository: WorkoutRepository
    private let catalog: ExerciseCatalog
    private let targetRIR: Int

    public init(sessionID: UUID, repository: WorkoutRepository, catalog: ExerciseCatalog, targetRIR: Int = 2) {
        self.sessionID = sessionID
        self.repository = repository
        self.catalog = catalog
        self.targetRIR = targetRIR
        reload()
    }

    public var isActive: Bool { detail?.session.status == .inProgress }

    public func exerciseName(_ detail: WorkoutRepository.ExerciseDetail) -> String {
        detail.exercise.exerciseKey.flatMap { catalog[$0]?.name } ?? detail.exercise.exerciseKey ?? "—"
    }

    public func loadType(_ detail: WorkoutRepository.ExerciseDetail) -> LoadType {
        detail.exercise.exerciseKey.flatMap { catalog[$0]?.loadType } ?? .external
    }

    public func reload() {
        detail = try? repository.detail(sessionID: sessionID)
        restEndsAt = Self.restEnd(detail)
    }

    static func restEnd(_ detail: WorkoutRepository.SessionDetail?) -> Date? {
        let completed = detail?.exercises.flatMap(\.sets).filter { $0.completedAt != nil } ?? []
        guard let last = completed.max(by: { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }),
              let at = last.completedAt, let rest = last.restS, rest > 0 else { return nil }
        return at.addingTimeInterval(Double(rest))
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            lastError = nil
        } catch let error as WorkoutRepository.WorkoutError {
            lastError = error
        } catch {
            lastError = .invalidValue
        }
        reload()
    }

    public func complete(setID: UUID, weightKg: Double?, reps: Int?, rir: Double?, durationSeconds: Int? = nil,
                         painLevel: PainLevel = .none) {
        perform {
            let saved = try repository.completeSet(setID: setID, weightKg: weightKg, reps: reps, rir: rir,
                                                   durationSeconds: durationSeconds, painLevel: painLevel)
            updateSuggestion(after: saved)
        }
    }

    /// Dopo la prima serie working: se il RIR devia di ≥ 2 dal target, carico corretto per le altre.
    private func updateSuggestion(after set: WorkoutSetRecord) {
        guard let exercise = try? repository.detail(sessionID: sessionID)?.exercises
            .first(where: { $0.exercise.id == set.workoutExerciseId }),
              let key = exercise.exercise.exerciseKey, let catalogExercise = catalog[key] else { return }
        let working = exercise.sets.filter { $0.setType.countsAsWorkingSet && $0.completedAt != nil }
        guard working.count == 1, let first = working.first, let load = first.weightKg, let rir = first.rir else { return }
        let prescription = Progression.Prescription(
            loadType: catalogExercise.loadType, incrementKg: catalogExercise.loadIncrementKg,
            repRange: 1...100, targetRIR: targetRIR
        )
        let adjusted = Progression.liveAdjustedLoad(firstSetLoadKg: load, firstSetRIR: rir, prescription: prescription)
        if adjusted != load { suggestedLoadKg[exercise.exercise.id] = adjusted }
    }

    public func addSet(to exerciseID: UUID) {
        perform { _ = try repository.addSet(exerciseID: exerciseID) }
    }

    public func deleteSet(_ setID: UUID) {
        perform { try repository.deleteSet(setID) }
    }

    /// Chiude la sessione e calcola il riepilogo (volume, serie per muscolo, record).
    public func finish(bodyweightKg: Double? = nil) {
        guard let before = detail else { return }
        perform { _ = try repository.finish(sessionID: sessionID) }
        guard detail?.session.status == .completed else { return }
        var session: [String: [PerformedSet]] = [:]
        var history: [String: [ExerciseExposure]] = [:]
        for exercise in before.exercises {
            guard let key = exercise.exercise.exerciseKey else { continue }
            let done = exercise.sets.filter { $0.completedAt != nil }
            session[key, default: []] += TrainingPlanService.performed(done)
            let past = (try? repository.exposures(exerciseKey: key, limit: 12)) ?? []
            history[key] = past.filter { $0.sessionID != sessionID }.map {
                ExerciseExposure(date: $0.date, sets: TrainingPlanService.performed($0.sets))
            }
        }
        summary = PerformanceAnalysis.summarize(session: session, catalog: catalog, history: history,
                                                bodyweightKg: bodyweightKg)
    }

    public func abandon() {
        perform { try repository.abandon(sessionID: sessionID) }
    }
}
