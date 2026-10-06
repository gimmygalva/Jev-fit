import JevCore
import JevDomain

/// RecoveryEngine — recupero per gruppo muscolare e JEV READINESS (piano §5.8–5.9). Owner: Agent 05.
///
/// Contratto (ADR-003): funzioni pure su value type `Sendable`, nessun I/O, nessun `Date()`
/// interno, soglie lette da `EngineConfig`. M1 contiene solo i metadati del modulo; gli
/// algoritmi arrivano nella rispettiva milestone.
public enum RecoveryEngineInfo {
    /// Versione dell'algoritmo: va incrementata a ogni cambiamento che altera gli output,
    /// insieme a `EngineConfig.version` se cambiano soglie (invalida le cache derivate, ADR-005).
    public static let algorithmVersion = 0

    /// Configurazione con cui l'engine è stato verificato.
    public static let configVersion = EngineConfig.current.version
}
