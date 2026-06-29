import SwiftUI
import SwiftData

/// Verkaufs-Maschen und Marketing-Ideen sammeln und dokumentieren,
/// wie gut sie funktionieren. Jede Idee gehört zum Workspace und
/// trackt Versuche, Erfolge und einen freien Notiz-Log.
struct IdeasListView: View {
    let workspace: Workspace
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var statusFilter: StatusFilter = .all

    @State private var newTitle = ""
    @State private var newCategory = ""
    @State private var newDetails = ""

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all, active, working, abandoned
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all:        "Alle"
            case .active:     "Aktiv"
            case .working:    "Funktionieren"
            case .abandoned:  "Verworfen"
            }
        }
    }

    private var allIdeas: [Idea] { workspace.ideas }

    private var filteredIdeas: [Idea] {
        var rows = allIdeas

        switch statusFilter {
        case .all:        break
        case .active:     rows = rows.filter { $0.status == .idea || $0.status == .testing }
        case .working:    rows = rows.filter { $0.status == .working || $0.status == .scaled }
        case .abandoned:  rows = rows.filter { $0.status == .abandoned }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            rows = rows.filter { i in
                i.title.lowercased().contains(q)
                || i.category.lowercased().contains(q)
                || i.details.lowercased().contains(q)
                || i.notes.lowercased().contains(q)
            }
        }

        return rows.sorted { lhs, rhs in
            if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
            if lhs.successRate != rhs.successRate { return lhs.successRate > rhs.successRate }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private var totalCount: Int { allIdeas.count }
    private var workingCount: Int {
        allIdeas.filter { $0.status == .working || $0.status == .scaled }.count
    }
    private var testingCount: Int { allIdeas.filter { $0.status == .testing }.count }
    private var avgSuccessRate: Double {
        let tested = allIdeas.filter { $0.triedCount > 0 }
        guard !tested.isEmpty else { return 0 }
        let sum = tested.reduce(0.0) { $0 + $1.successRate }
        return sum / Double(tested.count)
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
            Text("Ideen & Verkaufs-Maschen").font(.title2).fontWeight(.semibold)
            Text("Sammle neue Outreach-Ideen, Demo-Tricks oder Pricing-Experimente — und dokumentiere, wie gut sie wirklich funktionieren.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiRow: some View {
        HStack(spacing: 12) {
            KpiCard(title: "Gesamt", value: "\(totalCount)", muted: true)
            KpiCard(title: "Im Test", value: "\(testingCount)", accent: true)
            KpiCard(title: "Funktionieren", value: "\(workingCount)")
            KpiCard(
                title: "Ø Erfolgsquote",
                value: String(format: "%.0f %%", avgSuccessRate),
                muted: true
            )
        }
    }

    private var addCard: some View {
        Card("Neue Idee", subtitle: "Was probierst du Neues? Cold-Email-Hook, Demo-Eröffnung, Preis-Anker, …") {
            VStack(spacing: 8) {
                TextField("Titel — z. B. Loom-Personalvideo statt Cold-Mail", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Kategorie — z. B. Cold-Outreach, Demo, Pricing", text: $newCategory)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $newDetails)
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3))
                    )
                    .overlay(alignment: .topLeading) {
                        if newDetails.isEmpty {
                            Text("Beschreibung — wie genau läuft die Masche ab?")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }
                HStack {
                    Spacer()
                    Button {
                        addIdea()
                    } label: {
                        Label("Idee anlegen", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $statusFilter) {
                ForEach(StatusFilter.allCases) { f in
                    Text(f.title).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            TextField("Suchen…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

            Spacer()
        }
    }

    private var list: some View {
        VStack(spacing: 10) {
            if filteredIdeas.isEmpty {
                ContentUnavailableView(
                    "Noch keine Ideen",
                    systemImage: "lightbulb",
                    description: Text("Trag oben deine erste Verkaufs-Masche ein.")
                )
                .padding(.vertical, 40)
            } else {
                ForEach(filteredIdeas) { idea in
                    IdeaRow(idea: idea, onDelete: { delete(idea) })
                }
            }
        }
    }

    private func addIdea() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let idea = Idea(
            title: title,
            category: newCategory.trimmingCharacters(in: .whitespacesAndNewlines),
            details: newDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        idea.workspace = workspace
        modelContext.insert(idea)
        try? modelContext.save()
        newTitle = ""
        newCategory = ""
        newDetails = ""
    }

    private func delete(_ idea: Idea) {
        modelContext.delete(idea)
        try? modelContext.save()
    }
}

// MARK: - Row

private struct IdeaRow: View {
    @Bindable var idea: Idea
    let onDelete: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: title, category badge, status pill, delete
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(idea.title)
                        .font(.headline)
                    if !idea.category.isEmpty {
                        Text(idea.category)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                statusPicker
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }

            // Metrics row: rating, tries, wins, success rate
            HStack(spacing: 16) {
                ratingStars
                metricChip(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Versuche",
                    value: "\(idea.triedCount)"
                )
                metricChip(
                    icon: "checkmark.seal",
                    label: "Erfolge",
                    value: "\(idea.winCount)"
                )
                metricChip(
                    icon: "percent",
                    label: "Quote",
                    value: idea.triedCount > 0
                        ? String(format: "%.0f %%", idea.successRate)
                        : "—"
                )
                Spacer()
                HStack(spacing: 6) {
                    Button {
                        idea.recordTry()
                        try? modelContext.save()
                    } label: {
                        Label("+1 Versuch", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        idea.recordWin()
                        try? modelContext.save()
                    } label: {
                        Label("+1 Erfolg", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            // Expand for details + notes
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if !idea.details.isEmpty || expanded {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Beschreibung").font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $idea.details)
                                .frame(minHeight: 60)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(Color(NSColor.textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.3))
                                )
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notizen / Log").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $idea.notes)
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(Color(NSColor.textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3))
                            )
                            .overlay(alignment: .topLeading) {
                                if idea.notes.isEmpty {
                                    Text("Was hast du beobachtet? Was klappt? Was nicht?")
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 12)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    if let last = idea.lastTriedAt {
                        Text("Zuletzt probiert: \(DateFmt.short(last))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Spacer()
                        Button("Speichern") {
                            idea.statusRaw = idea.status.rawValue   // re-trigger updatedAt logic
                            try? modelContext.save()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 6)
            } label: {
                Text(expanded ? "Details ausblenden" : "Details & Notizen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18))
        )
    }

    private var statusPicker: some View {
        Picker("", selection: Binding(
            get: { idea.status },
            set: { idea.status = $0; try? modelContext.save() }
        )) {
            ForEach(IdeaStatus.pipelineOrder) { s in
                Text(s.title).tag(s)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 150)
    }

    private var ratingStars: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= idea.rating ? "star.fill" : "star")
                    .foregroundStyle(i <= idea.rating ? Color.yellow : Color.secondary)
                    .onTapGesture {
                        idea.rating = (idea.rating == i) ? i - 1 : i
                        idea.updatedAt = Date()
                        try? modelContext.save()
                    }
            }
        }
    }

    private func metricChip(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.caption2)
            }
            .foregroundStyle(.secondary)
            Text(value).font(.subheadline).fontWeight(.semibold)
        }
    }
}
