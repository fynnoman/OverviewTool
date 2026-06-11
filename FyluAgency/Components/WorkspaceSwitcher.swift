import SwiftUI
import SwiftData

struct WorkspaceSwitcher: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workspace.createdAt) private var workspaces: [Workspace]

    @State private var showNewWorkspace = false

    private var active: Workspace? {
        workspaces.first(where: { $0.id == appState.activeWorkspaceID })
    }

    var body: some View {
        Menu {
            ForEach(workspaces) { ws in
                Button {
                    appState.switchTo(ws)
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(ws.name)
                            if !ws.businessName.isEmpty && ws.businessName != ws.name {
                                Text(ws.businessName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: ws.id == appState.activeWorkspaceID
                              ? "checkmark.circle.fill"
                              : "circle")
                    }
                }
            }
            Divider()
            Button("Neuer Workspace…", systemImage: "plus") {
                showNewWorkspace = true
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.gradient)
                        .frame(width: 28, height: 28)
                    Text(active?.name.prefix(1).uppercased() ?? "?")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(active?.name ?? "Kein Workspace")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("Workspace wechseln")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.gray.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showNewWorkspace) {
            NewWorkspaceSheet { name in
                let workspace = Workspace.makeDefault(name: name)
                modelContext.insert(workspace)
                try? modelContext.save()
                appState.switchTo(workspace)
            }
        }
    }
}

struct NewWorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    let onCreate: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Neuer Workspace").font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("z. B. Fylu Marketing & Design", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            Text("Jeder Workspace hat eigene Kunden, Leads, Rechnungen und Stammdaten. Auch der OpenAI-Key kann pro Workspace anders sein.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Anlegen") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onCreate(trimmed)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
