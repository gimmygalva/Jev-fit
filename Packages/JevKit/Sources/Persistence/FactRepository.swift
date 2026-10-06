import Foundation
import GRDB
import JevCore

/// Scritture e letture dei "fatti" locali (DATA_MODEL §5.1).
///
/// Ogni scrittura:
/// - imposta `updatedAt` (strettamente crescente per record, anche con l'orologio che torna
///   indietro), `originDeviceId` e `syncState = .pending`;
/// - preserva `createdAt` della versione salvata;
/// - accoda il record nell'outbox tramite trigger SQL, nella stessa transazione.
/// Le cancellazioni sono SEMPRE tombstone (`deletedAt`), mai `DELETE`: la sync deve poterle
/// propagare e il server non concede DELETE al client (SECURITY §6.2).
public struct FactRepository: Sendable {
    public let writer: any DatabaseWriter
    public let deviceID: UUID
    public let time: any TimeSource

    public init(store: DataStore, time: any TimeSource = SystemTimeSource()) {
        self.writer = store.writer
        self.deviceID = store.deviceID
        self.time = time
    }

    // MARK: Scrittura

    /// Inserisce o aggiorna il record e restituisce la versione salvata.
    @discardableResult
    public func save<R: SyncedRecord>(_ record: R) throws -> R {
        try writer.write { db in try save(record, in: db) }
    }

    /// Variante da usare dentro una transazione già aperta (più record in modo atomico).
    @discardableResult
    public func save<R: SyncedRecord>(_ record: R, in db: Database) throws -> R {
        var saved = record
        let now = time.now()
        if let existing = try R.fetchOne(db, key: record.id) {
            guard existing.deletedAt == nil else { throw FactRepositoryError.recordDeleted }
            saved.createdAt = existing.createdAt
            saved.updatedAt = FactRepository.nextUpdatedAt(now: now, previous: existing.updatedAt)
        } else {
            saved.updatedAt = now
        }
        saved.deletedAt = nil
        saved.originDeviceId = deviceID
        saved.syncState = .pending
        try saved.save(db)
        return saved
    }

    /// Cancella il record con un tombstone. Idempotente: un record già cancellato non cambia.
    public func delete<R: SyncedRecord>(_ type: R.Type, id: UUID) throws {
        try writer.write { db in try delete(type, id: id, in: db) }
    }

    public func delete<R: SyncedRecord>(_ type: R.Type, id: UUID, in db: Database) throws {
        guard var record = try R.fetchOne(db, key: id) else { throw FactRepositoryError.notFound }
        guard record.deletedAt == nil else { return }
        let now = time.now()
        record.updatedAt = FactRepository.nextUpdatedAt(now: now, previous: record.updatedAt)
        record.deletedAt = record.updatedAt
        record.originDeviceId = deviceID
        record.syncState = .pending
        try record.update(db)
    }

    // MARK: Lettura

    /// Record vivo (non cancellato) con questo id.
    public func fetch<R: SyncedRecord>(_ type: R.Type, id: UUID) throws -> R? {
        try writer.read { db in
            try R.filter(key: id).filter(Column("deleted_at") == nil).fetchOne(db)
        }
    }

    /// Tutti i record vivi della tabella.
    public func fetchAll<R: SyncedRecord>(_ type: R.Type) throws -> [R] {
        try writer.read { db in
            try R.filter(Column("deleted_at") == nil).fetchAll(db)
        }
    }

    /// Il record vivo delle tabelle "una riga per utente" (profilo, impostazioni, preferenze).
    public func fetchSingleton<R: SyncedRecord>(_ type: R.Type) throws -> R? {
        try fetchAll(type).first
    }

    /// `updatedAt` per una modifica: l'istante attuale, ma mai prima della versione salvata
    /// (+1 ms), così last-writer-wins non scarta una modifica se l'orologio torna indietro.
    static func nextUpdatedAt(now: Date, previous: Date) -> Date {
        let minimum = previous.addingTimeInterval(0.001)
        return now > minimum ? now : minimum
    }
}

public enum FactRepositoryError: Error, Equatable {
    case notFound
    /// Un record cancellato (tombstone) non si modifica più: il tombstone vince (DATA_MODEL §5.3).
    case recordDeleted
}
