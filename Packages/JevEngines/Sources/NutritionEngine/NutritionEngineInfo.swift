import JevCore
import JevDomain

/// NutritionEngine — trend peso, expenditure adattiva, target calorici, macro (piano §5.1–5.4). Owner: Agent 06.
///
/// Contratto (ADR-003): funzioni pure su value type `Sendable`, nessun I/O, nessun `Date()`
/// interno, soglie lette da `EngineConfig`. Algoritmi: `EnergyModel`, `WeightTrend`,
/// `ExpenditureEstimator`, `CalorieTargets`, `MacroPlanner` (M5).
public enum NutritionEngineInfo {
    /// Versione dell'algoritmo: va incrementata a ogni cambiamento che altera gli output,
    /// insieme a `EngineConfig.version` se cambiano soglie (invalida le cache derivate, ADR-005).
    public static let algorithmVersion = 1

    /// Configurazione con cui l'engine è stato verificato.
    public static let configVersion = EngineConfig.current.version
}
