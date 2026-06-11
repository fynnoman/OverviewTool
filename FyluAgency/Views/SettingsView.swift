import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workspace.createdAt) private var workspaces: [Workspace]

    private var workspace: Workspace? {
        workspaces.first(where: { $0.id == appState.activeWorkspaceID })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let workspace {
                    header(workspace: workspace)
                    workspaceManagementCard
                    businessCard(workspace: workspace)
                    bankingCard(workspace: workspace)
                    invoiceCard(workspace: workspace)
                    layoutCard(workspace: workspace)
                    apiKeyCard(workspace: workspace)
                    logoCard(workspace: workspace)
                } else {
                    ContentUnavailableView(
                        "Kein Workspace ausgewählt",
                        systemImage: "rectangle.dashed"
                    )
                }
            }
            .padding(20)
        }
    }

    private func header(workspace: Workspace) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Einstellungen").font(.title2).fontWeight(.semibold)
            Text("Aktiver Workspace: \(workspace.name)")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var workspaceManagementCard: some View {
        Card("Workspaces", subtitle: "Multi-Tenancy") {
            VStack(spacing: 6) {
                ForEach(workspaces) { ws in
                    HStack {
                        Image(systemName: ws.id == appState.activeWorkspaceID ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(ws.id == appState.activeWorkspaceID ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ws.name).fontWeight(.medium)
                            Text("Angelegt \(DateFmt.short(ws.createdAt))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if ws.id != appState.activeWorkspaceID {
                            Button("Wechseln") {
                                appState.switchTo(ws)
                            }
                        }
                        Button(role: .destructive) {
                            deleteWorkspace(ws)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(workspaces.count <= 1)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    private func deleteWorkspace(_ ws: Workspace) {
        guard workspaces.count > 1 else { return }
        KeychainService.deleteAPIKey(account: ws.keychainAccount)
        if ws.id == appState.activeWorkspaceID {
            if let next = workspaces.first(where: { $0.id != ws.id }) {
                appState.switchTo(next)
            }
        }
        modelContext.delete(ws)
        try? modelContext.save()
    }

    private func businessCard(workspace: Workspace) -> some View {
        Card("Firmenangaben") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledField(label: "Name (Workspace)", text: Binding(
                    get: { workspace.name },
                    set: { workspace.name = $0 }
                ))
                LabeledField(label: "Firma (auf Rechnung)", text: Binding(
                    get: { workspace.businessName },
                    set: { workspace.businessName = $0 }
                ))
                LabeledField(label: "E-Mail", text: Binding(
                    get: { workspace.businessEmail },
                    set: { workspace.businessEmail = $0 }
                ))
                LabeledField(label: "Telefon", text: Binding(
                    get: { workspace.businessPhone },
                    set: { workspace.businessPhone = $0 }
                ))
                LabeledField(label: "USt-ID", text: Binding(
                    get: { workspace.taxId },
                    set: { workspace.taxId = $0 }
                ))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Adresse").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: Binding(
                        get: { workspace.businessAddress },
                        set: { workspace.businessAddress = $0 }
                    ))
                    .frame(minHeight: 80)
                    .border(Color.gray.opacity(0.2))
                }
                Button("Speichern") { try? modelContext.save() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func bankingCard(workspace: Workspace) -> some View {
        Card("Bankverbindung") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledField(label: "Bank", text: Binding(
                    get: { workspace.bankName }, set: { workspace.bankName = $0 }
                ))
                LabeledField(label: "IBAN", text: Binding(
                    get: { workspace.iban }, set: { workspace.iban = $0 }
                ))
                LabeledField(label: "BIC", text: Binding(
                    get: { workspace.bic }, set: { workspace.bic = $0 }
                ))
                Button("Speichern") { try? modelContext.save() }
            }
        }
    }

    private func invoiceCard(workspace: Workspace) -> some View {
        Card("Rechnungs-Setup") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MwSt. %").font(.caption).foregroundStyle(.secondary)
                        TextField("19", value: Binding(
                            get: { workspace.vatRate }, set: { workspace.vatRate = $0 }
                        ), format: .number).textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Zahlungsziel (Tage)").font(.caption).foregroundStyle(.secondary)
                        TextField("14", value: Binding(
                            get: { workspace.paymentTermsDays }, set: { workspace.paymentTermsDays = $0 }
                        ), format: .number).textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rechnungs-Präfix").font(.caption).foregroundStyle(.secondary)
                        TextField("RE", text: Binding(
                            get: { workspace.invoiceNumberPrefix }, set: { workspace.invoiceNumberPrefix = $0 }
                        )).textFieldStyle(.roundedBorder)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Footer-Text").font(.caption).foregroundStyle(.secondary)
                    TextField("Vielen Dank…", text: Binding(
                        get: { workspace.invoiceFooter }, set: { workspace.invoiceFooter = $0 }
                    )).textFieldStyle(.roundedBorder)
                }
                Text("Nächste Rechnungs-Nr.: \(workspace.invoiceNumberPrefix)-\(Calendar.current.component(.year, from: Date()))-\(String(format: "%04d", workspace.invoiceNumberCounter))")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Speichern") { try? modelContext.save() }
            }
        }
    }

    private func layoutCard(workspace: Workspace) -> some View {
        Card("Layout-Farben (Rechnungs-PDF)") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Headline-Farbe").font(.caption).foregroundStyle(.secondary)
                    TextField("#0B0B0E", text: Binding(
                        get: { workspace.layoutPrimaryHex }, set: { workspace.layoutPrimaryHex = $0 }
                    )).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Akzent-Farbe").font(.caption).foregroundStyle(.secondary)
                    TextField("#1F2937", text: Binding(
                        get: { workspace.layoutAccentHex }, set: { workspace.layoutAccentHex = $0 }
                    )).textFieldStyle(.roundedBorder)
                }
                Button("Speichern") { try? modelContext.save() }
            }
        }
    }

    @State private var apiKeyEntry = ""
    @State private var apiPingStatus: String?

    private func apiKeyCard(workspace: Workspace) -> some View {
        Card("OpenAI API-Key", subtitle: "Pro Workspace getrennt · in macOS Keychain gespeichert") {
            VStack(alignment: .leading, spacing: 10) {
                if KeychainService.hasAPIKey(account: workspace.keychainAccount) {
                    HStack {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                        Text("Key in Keychain hinterlegt").font(.callout)
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.shield").foregroundStyle(.orange)
                        Text("Kein Key — KI-Features deaktiviert").font(.callout)
                    }
                }

                SecureField("sk-…", text: $apiKeyEntry).textFieldStyle(.roundedBorder)

                HStack {
                    Button("Key speichern") {
                        let trimmed = apiKeyEntry.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            KeychainService.saveAPIKey(trimmed, account: workspace.keychainAccount)
                            apiKeyEntry = ""
                            apiPingStatus = "Gespeichert."
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Verbindung testen") {
                        Task {
                            apiPingStatus = "Teste…"
                            if let service = OpenAIService(workspace: workspace) {
                                let ok = await service.ping()
                                apiPingStatus = ok ? "OpenAI erreichbar ✓" : "Antwort kam — aber Format unerwartet. Modellname prüfen."
                            } else {
                                apiPingStatus = "Kein Key in Keychain."
                            }
                        }
                    }
                    Spacer()
                    Button("Key entfernen", role: .destructive) {
                        KeychainService.deleteAPIKey(account: workspace.keychainAccount)
                        apiPingStatus = "Gelöscht."
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Modell").font(.caption).foregroundStyle(.secondary)
                    TextField("gpt-5.4-mini", text: Binding(
                        get: { workspace.openAIModel }, set: { workspace.openAIModel = $0 }
                    )).textFieldStyle(.roundedBorder)
                }

                if let status = apiPingStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }

                Text("Endpoint: /v1/responses · Structured Output via JSON-Schema")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    @State private var showLogoPicker = false

    private func logoCard(workspace: Workspace) -> some View {
        Card("Logo") {
            VStack(alignment: .leading, spacing: 10) {
                if let data = workspace.logoData, let img = NSImage(data: data) {
                    HStack {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 200, maxHeight: 80)
                            .background(Color.gray.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Spacer()
                    }
                } else {
                    Text("Noch kein Logo. Wird auf jede Rechnung gedruckt.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                HStack {
                    Button("Logo auswählen…") { showLogoPicker = true }
                    if workspace.logoData != nil {
                        Button("Entfernen", role: .destructive) {
                            workspace.logoData = nil
                            workspace.logoFilename = nil
                            try? modelContext.save()
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showLogoPicker,
            allowedContentTypes: [.png, .jpeg],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url), data.count < 5_000_000 {
                workspace.logoData = data
                workspace.logoFilename = url.lastPathComponent
                try? modelContext.save()
            }
        }
    }
}
