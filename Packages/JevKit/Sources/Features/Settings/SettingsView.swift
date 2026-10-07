import AuthenticationServices
import CryptoKit
import DesignSystem
import Foundation
import Sync
import SwiftUI

/// Impostazioni (SCR-ST-01): account con Sign in with Apple, consensi espliciti per la sync nel
/// cloud e per JEV online, sincronizzazione manuale. Senza account l'app funziona in locale.
public struct SettingsView: View {
    let account: AccountService
    let sync: CloudSyncService
    @State private var signedIn = false
    @State private var cloudSync = false
    @State private var aiOnline = false
    @State private var status: String?
    @State private var nonce = ""
    @State private var busy = false
    @State private var confirmDelete = false

    public init(account: AccountService, sync: CloudSyncService) {
        self.account = account
        self.sync = sync
    }

    public var body: some View {
        List {
            Section {
                if signedIn {
                    Text("Account collegato")
                    Button("Esci", role: .destructive) {
                        account.signOut()
                        signedIn = false
                        cloudSync = false
                        aiOnline = false
                    }
                    Button("Elimina account", role: .destructive) { confirmDelete = true }
                        .accessibilityIdentifier("settings.delete")
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        nonce = Self.randomNonce()
                        request.requestedScopes = []
                        request.nonce = Self.sha256(nonce)
                    } onCompletion: { result in
                        let token = Self.identityToken(result)
                        Task { await handle(token) }
                    }
                    .frame(height: 48)
                    .accessibilityIdentifier("settings.signin")
                    Text("Senza account i dati restano solo su questo iPhone.")
                        .font(.caption)
                        .foregroundStyle(JevColor.textSecondary)
                }
            } header: {
                Text("Account")
            }
            if signedIn {
                Section {
                    Toggle("Sincronizzazione nel cloud", isOn: Binding(get: { cloudSync }, set: { value in
                        Task { await setConsent(.cloudSync, value) }
                    }))
                    Toggle("JEV online", isOn: Binding(get: { aiOnline }, set: { value in
                        Task { await setConsent(.aiOnline, value) }
                    }))
                    Button("Sincronizza ora") { Task { await syncNow() } }
                        .disabled(!cloudSync || busy)
                        .accessibilityIdentifier("settings.sync")
                } header: {
                    Text("Consensi")
                } footer: {
                    Text("I dati di Salute (sonno, frequenza cardiaca, HRV) non lasciano mai l'iPhone. JEV online riceve solo valori già calcolati, mai dati identificativi.")
                }
            }
            if let status {
                Section { Text(verbatim: status).font(.caption).foregroundStyle(JevColor.textSecondary) }
            }
        }
        .navigationTitle("Impostazioni")
        .task { await refresh() }
        .confirmationDialog("Eliminare l'account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina account e dati nel cloud", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("L'account e tutti i dati sincronizzati vengono eliminati in modo definitivo. I dati su questo iPhone restano finché non elimini l'app.")
        }
    }

    private func refresh() async {
        signedIn = account.isSignedIn
        guard signedIn else { return }
        cloudSync = (try? await account.hasConsent(.cloudSync)) ?? false
        aiOnline = (try? await account.hasConsent(.aiOnline)) ?? false
    }

    static func identityToken(_ result: Result<ASAuthorization, any Error>) -> String? {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func handle(_ token: String?) async {
        guard let token else {
            status = String(localized: "Accesso non completato.")
            return
        }
        do {
            try await account.signInWithApple(idToken: token, nonce: nonce)
            status = nil
        } catch {
            status = String(localized: "Accesso non riuscito. Riprova più tardi.")
        }
        await refresh()
    }

    private func setConsent(_ consent: AccountService.Consent, _ value: Bool) async {
        busy = true
        defer { busy = false }
        do {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            if value { try await account.grant(consent, appVersion: version) } else { try await account.revoke(consent) }
        } catch {
            status = String(localized: "Impossibile aggiornare il consenso. Controlla la connessione.")
        }
        await refresh()
        if consent == .cloudSync && cloudSync { await syncNow() }
    }

    private func deleteAccount() async {
        busy = true
        defer { busy = false }
        do {
            try await account.deleteAccount()
            status = String(localized: "Account eliminato.")
        } catch {
            status = String(localized: "Eliminazione non riuscita. Controlla la connessione e riprova.")
        }
        await refresh()
    }

    private func syncNow() async {
        busy = true
        defer { busy = false }
        do {
            try await sync.syncNow()
            status = String(localized: "Sincronizzazione completata.")
        } catch {
            status = String(localized: "Sincronizzazione non riuscita: i dati restano sull'iPhone e si riprova più tardi.")
        }
    }

    static func randomNonce() -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<32).map { _ in characters.randomElement(using: &generator)! })
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
