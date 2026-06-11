import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workspace.createdAt) private var workspaces: [Workspace]

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            detail
        }
        .navigationTitle(activeWorkspace?.name ?? "Fylu Agency")
    }

    private var activeWorkspace: Workspace? {
        workspaces.first(where: { $0.id == appState.activeWorkspaceID })
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        @Bindable var state = appState
        return VStack(spacing: 0) {
            WorkspaceSwitcher()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            List(selection: $state.selection) {
                Section {
                    ForEach(SidebarSection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                appState.selection = .invoices
                appState.requestNewInvoice = true
            } label: {
                Label("Neue Rechnung", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(12)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let workspace = activeWorkspace {
            switch appState.selection {
            case .dashboard:  DashboardView(workspace: workspace)
            case .customers:  CustomersListView(workspace: workspace)
            case .leads:      LeadsListView(workspace: workspace)
            case .invoices:   InvoicesListView(workspace: workspace)
            case .settings:   SettingsView()
            }
        } else {
            ContentUnavailableView(
                "Kein Workspace",
                systemImage: "rectangle.dashed",
                description: Text("Lege einen Workspace in den Einstellungen an, um loszulegen.")
            )
        }
    }
}
