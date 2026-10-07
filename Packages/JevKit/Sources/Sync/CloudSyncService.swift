import Foundation
import Persistence

/// Sync reale (M12): parte solo con account e consenso `cloud_sync` esplicito; senza, lo stato
/// è `disabled` e l'app resta interamente locale.
public actor CloudSyncService: SyncServicing {
    let account: AccountService
    let store: DataStore
    private var current: SyncState = .disabled
    private var lastSyncedAt: Date?

    public init(account: AccountService, store: DataStore) {
        self.account = account
        self.store = store
    }

    public var state: SyncState { current }

    public func syncNow() async throws {
        guard account.isSignedIn, try await account.hasConsent(.cloudSync) else {
            current = .disabled
            return
        }
        guard current != .syncing else { return }
        current = .syncing
        let account = self.account
        let remote = PostgRESTSyncRemote(projectURL: account.config.projectURL, publishableKey: account.config.publishableKey,
                                         accessToken: { await account.accessToken() })
        do {
            _ = try await SyncEngine(store: store, remote: remote).sync()
            lastSyncedAt = Date()
            current = .idle(lastSyncedAt: lastSyncedAt)
        } catch {
            current = .failed(reason: "sync_failed")
            throw error
        }
    }
}
