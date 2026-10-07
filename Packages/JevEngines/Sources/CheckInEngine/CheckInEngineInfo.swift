import JevCore
import JevDomain
import NutritionEngine
import RecoveryEngine
import WorkoutEngine

/// CheckInEngine — decisioni settimanali con priorità e isteresi (piano §5.10). Owner: Agent 00 + 09.
/// Unico responsabile della progressione del volume tra le settimane di programma (QA-11).
public enum CheckInEngineInfo {
    public static let algorithmVersion = 1

    /// Versioni degli engine da cui dipendono le metriche del check-in: salvate nello snapshot
    /// `weekly_check_in.engine_version` per rendere ogni decisione riproducibile.
    public static var upstreamAlgorithmVersions: [String: Int] {
        [
            "workout": WorkoutEngineInfo.algorithmVersion,
            "nutrition": NutritionEngineInfo.algorithmVersion,
            "recovery": RecoveryEngineInfo.algorithmVersion,
        ]
    }
}

/// Le decisioni possibili del weekly check-in (brief, PS-CI-*). Raw value stabili: finiscono nel DB.
public enum CheckInDecisionType: String, Sendable, Codable, CaseIterable {
    case keep
    case increaseCalories = "increase_calories"
    case decreaseCalories = "decrease_calories"
    case changeMacros = "change_macros"
    case reduceTrainingLoad = "reduce_training_load"
    case increaseTrainingLoad = "increase_training_load"
    case deload
    case changeExercise = "change_exercise"
    case noAction = "no_action"

    /// Area a cui appartiene la decisione (una decisione nutrizionale e una di allenamento
    /// possono coesistere nello stesso check-in).
    public var area: CheckInArea {
        switch self {
        case .increaseCalories, .decreaseCalories, .changeMacros: .nutrition
        case .reduceTrainingLoad, .increaseTrainingLoad, .deload, .changeExercise: .training
        case .keep, .noAction: .any
        }
    }
}

public enum CheckInArea: String, Sendable, Codable, CaseIterable {
    case nutrition
    case training
    case any
}
