import Foundation
import SwiftData

/// Orchestrates IMAP syncs across every enabled `MailAccount` in the given
/// workspace. Runs one account at a time (so a slow server doesn't monopolise
/// the connection budget), persists results to SwiftData, and never throws —
/// per-account errors land on the account's `lastSyncError` field so the UI
/// can render them next to the offending row.
@MainActor
final class MailSyncService {
    let modelContext: ModelContext
    let workspace: Workspace
    /// Newest N messages per account, per sync. Sensible default that keeps
    /// initial sync snappy; can be raised in Settings later.
    let messageLimit: Int

    init(modelContext: ModelContext, workspace: Workspace, messageLimit: Int = 50) {
        self.modelContext = modelContext
        self.workspace = workspace
        self.messageLimit = messageLimit
    }

    /// Sync every enabled account. Progress is reflected on each account's
    /// `lastSyncAt` / `lastSyncError` fields as we go.
    func syncAll() async {
        let accounts = fetchEnabledAccounts()
        for account in accounts {
            await sync(account: account)
        }
    }

    func sync(account: MailAccount) async {
        guard let password = MailKeychainService.loadPassword(account: account.keychainAccount),
              !password.isEmpty else {
            account.lastSyncError = "Kein Passwort im Schlüsselbund. Bitte Postfach erneut verbinden."
            try? modelContext.save()
            return
        }

        let client = IMAPClient(
            host: account.imapHost,
            port: UInt16(account.imapPort),
            username: account.username,
            password: password
        )

        do {
            let fetched = try await client.fetchRecent(limit: messageLimit)
            persist(fetched, into: account)
            account.lastSyncAt = Date()
            account.lastSyncError = nil
            try? modelContext.save()
        } catch {
            account.lastSyncError = error.localizedDescription
            try? modelContext.save()
        }
    }

    private func fetchEnabledAccounts() -> [MailAccount] {
        let wsID = workspace.id
        let descriptor = FetchDescriptor<MailAccount>(
            predicate: #Predicate<MailAccount> { $0.workspace?.id == wsID && $0.isEnabled }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Insert-or-update by (accountID, remoteUID). We deliberately keep local
    /// edits (`isSeen`, `isFlagged`) untouched on re-sync — the source of
    /// truth for read state is currently local until we add UID STORE support.
    private func persist(_ messages: [IMAPFetchedMessage], into account: MailAccount) {
        let accountID = account.id
        for m in messages {
            let uid = m.remoteUID
            let existing = FetchDescriptor<MailMessage>(
                predicate: #Predicate<MailMessage> {
                    $0.account?.id == accountID && $0.remoteUID == uid
                }
            )
            if (try? modelContext.fetch(existing))?.first != nil { continue }

            let preview = String(m.bodyText.prefix(500))
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let msg = MailMessage(
                remoteUID: m.uid,
                subject: m.subject,
                fromName: m.fromName,
                fromAddress: m.fromAddress,
                toRaw: m.toList.joined(separator: ", "),
                date: m.date,
                preview: preview,
                bodyText: m.bodyText,
                isSeen: m.isSeen,
                isFlagged: m.isFlagged
            )
            msg.account = account
            modelContext.insert(msg)
        }
    }
}

extension IMAPFetchedMessage {
    /// Named accessor to keep the persist call site readable when we reach
    /// for the remote UID under a different variable name.
    var remoteUID: UInt32 { uid }
}
