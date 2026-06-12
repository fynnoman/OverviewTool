import SwiftUI
import SwiftData

/// Persönliche Aufgaben-Liste — *nicht* die Kundenwünsche/Aufgaben aus
/// der Kundenakte. Jedes To-do gehört zum Workspace und kann optional
/// einem Kunden zugeordnet werden (z. B. „Claude Cowork nutzen für
/// Gianluca").
struct TodoListView: View {
    let workspace: Workspace
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var customerFilterID: UUID?
    @State private var statusFilter: StatusFilter = .open

    @State private var newTitle = ""
    @State private var newDesc = ""
    @State private var newCustomerID: UUID?
    @State private var newDueDate: Date = Date()
    @State private var newHasDueDate = false

    enum StatusFilter: String, CaseIterable, Identifiable {
        case open, done, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .open: "Offen"
            case .done: "Erledigt"
            case .all:  "Alle"
            }
        }
    }

    private var customers: [Customer] {
        workspace.customers.sorted(by: { $0.name < $1.name })
    }

    private var allTodos: [Todo] { workspace.todos }

    private var filteredTodos: [Todo] {
        var rows = allTodos

        switch statusFilter {
        case .open: rows = rows.filter { !$0.done }
        case .done: rows = rows.filter { $0.done }
        case .all:  break
        }

        if let id = customerFilterID {
            if id == UUID(uuidString: "00000000-0000-0000-0000-000000000000") {
                // Spezial-Sentinel "Ohne Kunde"
                rows = rows.filter { $0.customer == nil }
            } else {
                rows = rows.filter { $0.customer?.id == id }
            }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            rows = rows.filter { t in
                t.title.lowercased().contains(q)
                || t.details.lowercased().contains(q)
                || (t.customer?.name.lowercased().contains(q) ?? false)
                || (t.customer?.company.lowercased().contains(q) ?? false)
            }
        }

        return rows.sorted { lhs, rhs in
            if lhs.done != rhs.done { return !lhs.done && rhs.done }
            // Offene mit Fälligkeit zuerst
            if let l = lhs.dueDate, let r = rhs.dueDate { return l < r }
            if lhs.dueDate != nil { return true }
            if rhs.dueDate != nil { return false }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var openCount: Int { allTodos.filter { !$0.done }.count }
    private var doneCount: Int { allTodos.filter { $0.done }.count }
    private var overdueCount: Int {
        let now = Date()
        return allTodos.filter { !$0.done && ($0.dueDate.map { $0 < now } ?? false) }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                kpiRow
                addCard
                filterBar
                list
            }
            .padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Meine Aufgaben").font(.title2).fontWeight(.semibold)
            Text("Deine eigene To-Do-Liste — nicht zu verwechseln mit den Wünschen der Kunden in der Kundenakte.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiRow: some View {
        HStack(spacing: 12) {
            KpiCard(title: "Offen", value: "\(openCount)", accent: true)
            KpiCard(title: "Überfällig",
                    value: "\(overdueCount)",
                    tone: overdueCount > 0 ? .danger : .neutral)
            KpiCard(title: "Erledigt", value: "\(doneCount)", muted: true)
            KpiCard(title: "Gesamt", value: "\(allTodos.count)", muted: true)
        }
    }

    private var addCard: some View {
        Card("Neue Aufgabe", subtitle: "Nur für dich — optional einem Kunden zugeordnet") {
            VStack(spacing: 8) {
                HStack {
                    TextField("Was musst du tun? (z. B. Claude Cowork nutzen für Gianluca)", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                    Picker("Kunde", selection: $newCustomerID) {
                        Text("— ohne Kunde —").tag(Optional<UUID>.none)
                        ForEach(customers) { c in
                            Text(c.name).tag(Optional(c.id))
                        }
                    }
                    .frame(width: 180)
                    Toggle("fällig", isOn: $newHasDueDate).labelsHidden()
                    if newHasDueDate {
                        DatePicker("", selection: $newDueDate, displayedComponents: .date)
                            .labelsHidden().frame(width: 130)
                    }
                    Button {
                        addTodo()
                    } label: {
                        Label("Anlegen", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                TextField("Notiz (optional)", text: $newDesc).textFieldStyle(.roundedBorder)
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Suche Aufgabe oder Kunde…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Picker("Status", selection: $statusFilter) {
                    ForEach(StatusFilter.allCases) { s in Text(s.title).tag(s) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

                Picker("Kunde", selection: $customerFilterID) {
                    Text("Alle Kunden").tag(Optional<UUID>.none)
                    Text("— Ohne Kunde —").tag(Optional(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!))
                    Divider()
                    ForEach(customers) { c in Text(c.name).tag(Optional(c.id)) }
                }
                .frame(width: 220)

                Spacer()

                if customerFilterID != nil || statusFilter != .open || !searchText.isEmpty {
                    Button("Filter zurücksetzen") {
                        searchText = ""
                        customerFilterID = nil
                        statusFilter = .open
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            if filteredTodos.isEmpty {
                ContentUnavailableView(
                    "Keine Aufgaben",
                    systemImage: "checklist",
                    description: Text("Lege oben neue Aufgaben an oder ändere den Filter.")
                )
                .frame(minHeight: 200)
            } else {
                ForEach(filteredTodos) { todo in
                    TodoRowView(todo: todo)
                    Divider()
                }
            }
        }
        .background(Color.gray.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func addTodo() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let todo = Todo(
            title: title,
            details: newDesc,
            dueDate: newHasDueDate ? newDueDate : nil
        )
        todo.workspace = workspace
        if let cid = newCustomerID,
           let c = customers.first(where: { $0.id == cid }) {
            todo.customer = c
        }
        modelContext.insert(todo)
        try? modelContext.save()

        newTitle = ""
        newDesc = ""
        newHasDueDate = false
        newDueDate = Date()
    }
}

private struct TodoRowView: View {
    @Bindable var todo: Todo
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                todo.toggle()
                try? modelContext.save()
            } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.done ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title)
                    .strikethrough(todo.done)
                    .foregroundStyle(todo.done ? .secondary : .primary)
                    .font(.callout).fontWeight(.medium)
                HStack(spacing: 6) {
                    if let customer = todo.customer {
                        StatusPill(text: customer.name, color: .blue)
                    } else {
                        StatusPill(text: "Allgemein", color: .gray)
                    }
                    if let due = todo.dueDate {
                        let overdue = !todo.done && due < Date()
                        Text("fällig \(DateFmt.short(due))")
                            .font(.caption)
                            .foregroundStyle(overdue ? Color.red : .secondary)
                    }
                    if !todo.details.isEmpty {
                        Text(todo.details)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Spacer()

            Button {
                modelContext.delete(todo)
                try? modelContext.save()
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}
