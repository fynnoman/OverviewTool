import SwiftUI
import SwiftData

/// Unified inbox across every connected `MailAccount` in the workspace.
/// Layout mirrors macOS Mail: account/filter list on the left, message list
/// in the middle, reading pane on the right.
struct MailboxView: View {
    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [MailAccount]

    @State private var selectedAccountID: UUID?      // nil = alle Accounts
    @State private var selectedMessage: MailMessage?
    @State private var showAddAccount = false
    @State private var isSyncing = false
    @State private var syncError: String?
    // Default: sidebar ausgeblendet — der Postfach-Wechsler wird über den
    // Sidebar-Toggle in der Toolbar wieder eingeklappt, ohne dass man am
    // Divider ziehen muss (Ziehen konnte man die Sidebar bisher zu weit
    // nach links schieben und nicht mehr zurückholen).
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    init(workspace: Workspace) {
        self.workspace = workspace
        let wsID = workspace.id
        // Only accounts get a direct @Query — messages are pulled through the
        // account relation to avoid chained-optional predicates, which the
        // SwiftData SQL compiler cannot translate (NSSQLGenerator crash).
        _accounts = Query(
            filter: #Predicate<MailAccount> { $0.workspace?.id == wsID },
            sort: \.createdAt
        )
    }

    private var messages: [MailMessage] {
        accounts.flatMap { $0.messages }.sorted { $0.date > $1.date }
    }

    private var filteredMessages: [MailMessage] {
        guard let selectedAccountID else { return messages }
        return messages.filter { $0.account?.id == selectedAccountID }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation {
                        columnVisibility = columnVisibility == .all ? .doubleColumn : .all
                    }
                } label: {
                    Label("Postfächer", systemImage: "sidebar.left")
                }
                .help("Postfach-Liste ein-/ausblenden")
            }
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
            // Bei jedem Öffnen der Ansicht neu synchronisieren, damit neue
            // Mails auftauchen. Vorher gab's die Bedingung "nur wenn leer" —
            // dadurch kamen neue Nachrichten nach dem ersten Sync nie
            // automatisch rein.
            if !accounts.isEmpty, !isSyncing {
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
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(message.senderDisplay)
                    .font(.system(size: 13, weight: message.isSeen ? .regular : .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(DateFmt.short(message.date))
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            Text(message.subject.isEmpty ? "(ohne Betreff)" : message.subject)
                .font(.system(size: 12, weight: message.isSeen ? .regular : .medium))
                .foregroundStyle(message.isSeen ? .secondary : .primary)
                .lineLimit(1)
            Text(message.displayPreview)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .padding(.leading, 14)
        .overlay(alignment: .topLeading) {
            // Unread indicator as overlay so all three text rows start at the
            // same leading edge instead of getting shoved right by the dot.
            Circle()
                .fill(message.isSeen ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 8)
                .padding(.leading, 2)
        }
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
                    Spacer(minLength: 4)
                    Text(DateFmt.short(message.date))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }
                .padding(10)
                .background(Color.gray.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Divider()

                let cleanedBody = message.displayBody
                Text(cleanedBody.isEmpty ? "(kein Textinhalt)" : cleanedBody)
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
                }

                if !provider.setupSteps.isEmpty {
                    Section("So verbindest du dein \(provider.title)-Konto") {
                        ForEach(Array(provider.setupSteps.enumerated()), id: \.offset) { idx, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(idx + 1)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Color.accentColor)
                                    .clipShape(Circle())
                                Text(step)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                        }
                        if let url = provider.setupURL {
                            Link(destination: url) {
                                Label("Anleitung im Browser öffnen", systemImage: "arrow.up.right.square")
                            }
                            .padding(.top, 4)
                        }
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

        // Clamp to valid TCP port range — an over-large value would otherwise
        // trap the UInt16 conversion and crash the whole app while the user
        // is still filling out the sheet.
        let portInt = Int(imapPort.trimmingCharacters(in: .whitespaces)) ?? 993
        let safePort = UInt16(clamping: max(1, min(portInt, 65535)))

        let client = IMAPClient(
            host: imapHost.trimmingCharacters(in: .whitespaces),
            port: safePort,
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
        let portInt = Int(imapPort.trimmingCharacters(in: .whitespaces)) ?? 993
        let safePort = max(1, min(portInt, 65535))
        let account = MailAccount(
            provider: provider,
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            emailAddress: emailAddress.trimmingCharacters(in: .whitespaces),
            imapHost: imapHost.trimmingCharacters(in: .whitespaces),
            imapPort: safePort,
            imapUseTLS: true,
            username: username.trimmingCharacters(in: .whitespaces)
        )
        // Insert first, THEN wire up the relationship — assigning
        // `.workspace` on an un-inserted @Model can leave SwiftData in an
        // inconsistent state and abort on the next save().
        modelContext.insert(account)
        account.workspace = workspace
        MailKeychainService.savePassword(password, account: account.keychainAccount)
        try? modelContext.save()
        dismiss()
    }
}
