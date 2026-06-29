import SwiftUI
import SwiftData
import Observation

enum SidebarSection: String, Hashable, Identifiable, CaseIterable {
    case dashboard, customers, leads, appointments, quotes, invoices, todos, ideas, costs, taxes, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard:    "Dashboard"
        case .customers:    "Kunden"
        case .leads:        "Leads"
        case .appointments: "Termine"
        case .quotes:       "Angebote"
        case .invoices:     "Rechnungen"
        case .todos:        "Aufgaben"
        case .ideas:        "Ideen"
        case .costs:        "Kosten"
        case .taxes:        "Steuern"
        case .settings:     "Einstellungen"
        }
    }
    var systemImage: String {
        switch self {
        case .dashboard:    "rectangle.grid.2x2"
        case .customers:    "person.2"
        case .leads:        "sparkles"
        case .appointments: "calendar"
        case .quotes:       "doc.badge.plus"
        case .invoices:     "doc.text"
        case .todos:        "checklist"
        case .ideas:        "lightbulb"
        case .costs:        "eurosign.circle"
        case .taxes:        "percent"
        case .settings:     "gearshape"
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
            reconstructFyluCustomers(context: context)
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

        reconstructFyluCustomers(context: context)
    }

    /// Re-creates the 4 customer records whose UUIDs are still recoverable from
    /// the leftover upload folders under `Application Support/FyluAgency/uploads/`.
    /// Strictly additive and idempotent: any Customer matched by `id` is left
    /// untouched, and nothing else in the store is read or modified. Stammdaten
    /// (address, phone, notes, etc.) must be re-entered manually; this only
    /// restores the link between Customer and its surviving upload folder so
    /// the user can re-attach the PDFs.
    @MainActor
    private func reconstructFyluCustomers(context: ModelContext) {
        let wsFetch = FetchDescriptor<Workspace>(
            predicate: #Predicate<Workspace> { $0.name == "Fylu Marketing & Design" }
        )
        guard let fyluWS = (try? context.fetch(wsFetch))?.first else { return }

        struct Stub { let id: String; let name: String; let company: String }
        let stubs: [Stub] = [
            Stub(id: "AC588FA5-D7EA-475D-A54A-C5BD152773D7", name: "Demir", company: ""),
            Stub(id: "7079125E-CF87-4F9C-B8FB-1911B9566FF6", name: "Eifler", company: ""),
            Stub(id: "A6F130B5-13A5-4E54-91D0-A52FA492B498", name: "Portocervo", company: ""),
            Stub(id: "18C683FD-8854-406E-BB26-96574DE42A64", name: "Ramadan Salif", company: "")
        ]

        var inserted = 0
        for stub in stubs {
            guard let uuid = UUID(uuidString: stub.id) else { continue }
            let id = uuid
            let exists = FetchDescriptor<Customer>(
                predicate: #Predicate<Customer> { $0.id == id }
            )
            if (try? context.fetch(exists))?.first != nil { continue }

            let customer = Customer(id: uuid, name: stub.name, company: stub.company)
            customer.workspace = fyluWS
            context.insert(customer)
            inserted += 1
        }
        if inserted > 0 { try? context.save() }
    }

    func switchTo(_ workspace: Workspace) {
        activeWorkspaceID = workspace.id
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(activeWorkspaceID?.uuidString, forKey: activeWorkspaceKey)
    }
}
