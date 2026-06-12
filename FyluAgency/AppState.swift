import SwiftUI
import SwiftData
import Observation

enum SidebarSection: String, Hashable, Identifiable, CaseIterable {
    case dashboard, customers, leads, invoices, todos, costs, taxes, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .customers: "Kunden"
        case .leads:     "Leads"
        case .invoices:  "Rechnungen"
        case .todos:     "Aufgaben"
        case .costs:     "Kosten"
        case .taxes:     "Steuern"
        case .settings:  "Einstellungen"
        }
    }
    var systemImage: String {
        switch self {
        case .dashboard: "rectangle.grid.2x2"
        case .customers: "person.2"
        case .leads:     "sparkles"
        case .invoices:  "doc.text"
        case .todos:     "checklist"
        case .costs:     "eurosign.circle"
        case .taxes:     "percent"
        case .settings:  "gearshape"
        }
    }
}

/// Global app state — tracks the currently-active workspace plus
/// transient UI requests (deep-link to "new invoice", etc.).
@Observable
final class AppState {
    var selection: SidebarSection = .dashboard
    var activeWorkspaceID: UUID?
    var requestNewInvoice: Bool = false

    private let activeWorkspaceKey = "ActiveWorkspaceID"

    /// Pulls the last-used workspace from UserDefaults. If no workspaces
    /// exist (first launch) we create a default one named "Fylu Marketing
    /// & Design" so the user can start immediately.
    @MainActor
    func bootstrap(context: ModelContext) async {
        let descriptor = FetchDescriptor<Workspace>(sortBy: [SortDescriptor(\.createdAt)])
        let existing = (try? context.fetch(descriptor)) ?? []

        if existing.isEmpty {
            let first = Workspace.makeDefault(name: "Fylu Marketing & Design")
            context.insert(first)
            try? context.save()
            activeWorkspaceID = first.id
            persist()
            return
        }

        if let stored = UserDefaults.standard.string(forKey: activeWorkspaceKey),
           let uuid = UUID(uuidString: stored),
           existing.contains(where: { $0.id == uuid }) {
            activeWorkspaceID = uuid
        } else {
            activeWorkspaceID = existing.first?.id
            persist()
        }
    }

    func switchTo(_ workspace: Workspace) {
        activeWorkspaceID = workspace.id
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(activeWorkspaceID?.uuidString, forKey: activeWorkspaceKey)
    }
}
