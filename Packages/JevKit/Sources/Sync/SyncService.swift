import Foundation
import Persistence
import Auth
import PostgREST

/// Sincronizzazione locale ↔ Supabase (piano §3.4, ADR-005, ADR-006).
///
/// Contratto (implementazione in M12):
/// - push dall'outbox con `upsert on conflict (id)`: inviare due volte lo stesso record è innocuo;
/// - pull per tabella con cursore `server_updated_at`;
/// - solo i "fatti" si sincronizzano, mai i derivati;
/// - la sync parte solo con consenso esplicito (SECURITY.md, `user_consent`).
public protocol SyncServicing: Sendable {
    var state: SyncState { get async }
    func syncNow() async throws
}

public enum SyncState: Sendable, Equatable {
    /// Nessun account o consenso alla sync non dato: l'app funziona interamente in locale.
    case disabled
    case idle(lastSyncedAt: Date?)
    case syncing
    case failed(reason: String)
}

/// Implementazione usata finché l'utente non attiva account e sync. Non è un mock:
/// "sync disattivata" è uno stato reale e permanente per chi usa l'app solo in locale.
public struct DisabledSyncService: SyncServicing {
    public init() {}
    public var state: SyncState { get async { .disabled } }
    public func syncNow() async throws {}
}
