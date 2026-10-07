import JevCore
import JevDomain

/// WorkoutEngine — generazione programma, ExerciseScore, progressive overload, e1RM, plateau (piano §5.5–5.7). Owner: Agent 04.
///
/// Contratto (ADR-003): funzioni pure su value type `Sendable`, nessun I/O, nessun `Date()`
/// interno, soglie lette da `EngineConfig`. M4: generazione programma, ExerciseScore,
/// progressive overload, e1RM, plateau, riepilogo di sessione.
public enum WorkoutEngineInfo {
    /// Versione dell'algoritmo: va incrementata a ogni cambiamento che altera gli output,
    /// insieme a `EngineConfig.version` se cambiano soglie (invalida le cache derivate, ADR-005).
    public static let algorithmVersion = 1

    /// Configurazione con cui l'engine è stato verificato.
    public static let configVersion = EngineConfig.current.version
}
