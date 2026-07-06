import SwiftUI
import SwiftData

/// Unified inbox across every connected `MailAccount` in the workspace.
/// Layout mirrors macOS Mail: account/filter list on the left, message list
/// in the middle, reading pane on the right.
struct MailboxView: View {
    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [MailAccount]
    @Query(sort: \MailMessage.date, order: .reverse) private var messages: [MailMessage]

    @State private var selectedAccountID: UUID?      // nil = alle Accounts
    @State private var selectedMessage: MailMessage?
    @State private var showAddAccount = false
    @State private var isSyncing = false
    @State private var syncError: String?

    init(workspace: Workspace) {
        self.workspace = workspace
        let wsID = workspace.id
        _accounts = Query(
            filter: #Predicate<MailAccount> { $0.workspace?.id == wsID },
            sort: \.createdAt
        )
        _messages = Query(
            filter: #Predicate<MailMessage> { $0.account?.workspace?.id == wsID },
            sort: [SortDescriptor(\.date, order: .reverse)]
        )
    }

    private var filteredMessages: [MailMessage] {
        guard let selectedAccountID else { return messages }
        return messages.filter { $0.account?.id == selectedAccountID }
    }

    var body: some View {
        NavigationSplitView {
            accountList
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } content: {
            messageList
                .navigationSplitViewColumnWidth(min: 300, ideal: 380)
        } detail: {
            if let msg = selectedMessage {
                MailMessageDetailView(message: msg)
            } else {
                ContentUnavailableView(
                    "Keine Nachricht ausgewählt",
                    systemImage: "envelope",
                    description: Text("Wähle links eine E-Mail aus.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await syncAll() }
                } label: {
                    if isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Aktualisieren", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(accounts.isEmpty || isSyncing)

                Button {
                    showAddAccount = true
                } label: {
                    Label("Postfach hinzufügen", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddAccount) {
            AddMailAccountView(workspace: workspace)
        }
        .alert("Sync fehlgeschlagen", isPresented: Binding(
            get: { syncError != nil },
            set: { if !$0 { syncError = nil } }
        )) {
            Button("OK") { syncError = nil }
        } message: {
            Text(syncError ?? "")
        }
        .task {
            // Beim ersten Öffnen einmal automatisch aktualisieren, wenn
            // es Accounts gibt und noch nie synchronisiert wurde.
            if !accounts.isEmpty, messages.isEmpty, !isSyncing {
                await syncAll()
            }
        }
    }

    // MARK: - Sidebar (accounts)

    private var accountList: some View {
        List(selection: $selectedAccountID) {
            Section("Postfach") {
                HStack {
                    Label("Alle Accounts", systemImage: "tray.2")
                    Spacer()
                    Text("\(messages.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .tag(UUID?.none)
                .contentShape(Rectangle())
                .onTapGesture { selectedAccountID = nil }
            }

            if !accounts.isEmpty {
                Section("Verbundene Postfächer") {
                    ForEach(accounts) { account in
                        AccountRow(
                            account: account,
                            unreadCount: messages.filter { $0.account?.id == account.id && !$0.isSeen }.count,
                            onDelete: { delete(account) }
                        )
                        .tag(Optional(account.id))
                        .contentShape(Rectangle())
                        .onTapGesture { selectedAccountID = account.id }
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "Kein Postfach verbunden",
                        systemImage: "envelope.badge",
                        description: Text("Verbinde dein erstes Postfach über den Plus-Button oben rechts.")
                    )
                    .padding(.vertical, 8)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Message list

    private var messageList: some View {
        Group {
            if filteredMessages.isEmpty {
                ContentUnavailableView(
                    "Keine Nachrichten",
                    systemImage: "tray",
                    description: Text(accounts.isEmpty
                        ? "Verbinde zuerst ein Postfach."
                        : "Aktualisiere über den Button oben rechts, um neue E-Mails abzuholen.")
                )
            } else {
                List(selection: $selectedMessage) {
                    ForEach(filteredMessages) { msg in
                        MailListRow(message: msg)
                            .tag(Optional(msg))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMessage = msg
                                if !msg.isSeen {
                                    msg.isSeen = true
                                    try? modelContext.save()
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func syncAll() async {
        isSyncing = true
        defer { isSyncing = false }
        let service = MailSyncService(modelContext: modelContext, workspace: workspace)
        await service.syncAll()
    }

    private func delete(_ account: MailAccount) {
        MailKeychainService.deletePassword(account: account.keychainAccount)
        modelContext.delete(account)
        try? modelContext.save()
        if selectedAccountID == account.id { selectedAccountID = nil }
    }
}

// MARK: - Rows

private struct AccountRow: View {
    let account: MailAccount
    let unreadCount: Int
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: account.provider.symbolName)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(account.emailAddress)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
                if let err = account.lastSyncError, !err.isEmpty {
                    Label("Fehler", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            Spacer()
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .contextMenu {
            Button("Postfach entfernen", role: .destructive, action: onDelete)
        }
    }
}

private struct MailListRow: View {
    let message: MailMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(message.isSeen ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(message.senderDisplay)
                        .font(.system(size: 13, weight: message.isSeen ? .regular : .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(DateFmt.short(message.date))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(message.subject.isEmpty ? "(ohne Betreff)" : message.subject)
                    .font(.system(size: 12, weight: message.isSeen ? .regular : .medium))
                    .foregroundStyle(message.isSeen ? .secondary : .primary)
                    .lineLimit(1)
                Text(message.preview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail

struct MailMessageDetailView: View {
    let message: MailMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(message.subject.isEmpty ? "(ohne Betreff)" : message.subject)
                    .font(.title2).fontWeight(.semibold)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.senderDisplay)
                            .font(.system(size: 13, weight: .medium))
                        if message.senderDisplay != message.fromAddress {
                            Text("<\(message.fromAddress)>")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !message.toRaw.isEmpty {
                            Text("An: \(message.toRaw)")
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if let account = message.account {
                            Text("Postfach: \(account.displayName)")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Text(DateFmt.short(message.date))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.gray.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Divider()

                Text(message.bodyText.isEmpty ? "(kein Textinhalt)" : message.bodyText)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
    }
}

// MARK: - Add account sheet

struct AddMailAccountView: View {
    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var provider: MailProvider = .gmail
    @State private var displayName: String = ""
    @State private var emailAddress: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var imapHost: String = ""
    @State private var imapPort: String = "993"
    @State private var isTesting = false
    @State private var testError: String?
    @State private var testSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Postfach verbinden").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }

            Form {
                Section("Anbieter") {
                    Picker("Anbieter", selection: $provider) {
                        ForEach(MailProvider.allCases) { p in
                            Text(p.title).tag(p)
                        }
                    }
                    .onChange(of: provider) { _, _ in applyPreset() }

                    if let hint = provider.authHint {
                        Label(hint, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Zugang") {
                    TextField("Anzeigename (z. B. „Geschäftlich“)", text: $displayName)
                    TextField("E-Mail-Adresse", text: $emailAddress)
                        .onChange(of: emailAddress) { _, new in
                            if username.isEmpty { username = new }
                            if displayName.isEmpty { displayName = new }
                        }
                    TextField("Benutzername", text: $username)
                    SecureField("Passwort / App-Passwort", text: $password)
                }

                Section("IMAP-Server") {
                    TextField("Server", text: $imapHost)
                        .disabled(provider != .custom)
                    TextField("Port", text: $imapPort)
                        .disabled(provider != .custom)
                    if provider != .custom {
                        Text("Für „\(provider.title)“ automatisch vorausgefüllt.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let err = testError {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if testSuccess {
                    Section {
                        Label("Verbindung erfolgreich", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if isTesting {
                    ProgressView().controlSize(.small)
                    Text("Verbindung wird getestet…")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Verbindung testen") {
                    Task { await runTest() }
                }
                .disabled(!isFormValid || isTesting)
                Button("Verbinden") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isFormValid || isTesting)
            }
        }
        .padding(20)
        .frame(width: 560, height: 600)
        .onAppear { applyPreset() }
    }

    private var isFormValid: Bool {
        !emailAddress.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !imapHost.trimmingCharacters(in: .whitespaces).isEmpty
            && (Int(imapPort) ?? 0) > 0
    }

    private func applyPreset() {
        if let preset = MailProviderPresets.preset(for: provider) {
            imapHost = preset.imapHost
            imapPort = String(preset.imapPort)
        } else if provider == .custom {
            if imapHost.isEmpty { imapHost = "" }
            if imapPort.isEmpty { imapPort = "993" }
        }
    }

    @MainActor
    private func runTest() async {
        isTesting = true
        testError = nil
        testSuccess = false
        defer { isTesting = false }

        let client = IMAPClient(
            host: imapHost.trimmingCharacters(in: .whitespaces),
            port: UInt16(Int(imapPort) ?? 993),
            username: username.trimmingCharacters(in: .whitespaces),
            password: password
        )
        do {
            _ = try await client.fetchRecent(limit: 1)
            testSuccess = true
        } catch {
            testError = error.localizedDescription
        }
    }

    private func save() {
        let account = MailAccount(
            provider: provider,
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            emailAddress: emailAddress.trimmingCharacters(in: .whitespaces),
            imapHost: imapHost.trimmingCharacters(in: .whitespaces),
            imapPort: Int(imapPort) ?? 993,
            imapUseTLS: true,
            username: username.trimmingCharacters(in: .whitespaces)
        )
        account.workspace = workspace
        modelContext.insert(account)
        MailKeychainService.savePassword(password, account: account.keychainAccount)
        try? modelContext.save()
        dismiss()
    }
}
