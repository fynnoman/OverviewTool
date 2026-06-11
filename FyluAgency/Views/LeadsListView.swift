import SwiftUI
import SwiftData

struct LeadsListView: View {
    let workspace: Workspace
    @Environment(\.modelContext) private var modelContext
    @State private var showNewLead = false
    @State private var selectedLead: Lead?

    private var pipelineValue: Double {
        workspace.leads
            .filter { $0.status != .won && $0.status != .lost }
            .compactMap(\.expectedValue)
            .reduce(0, +)
    }

    private var wonValue: Double {
        workspace.leads
            .filter { $0.status == .won }
            .compactMap(\.expectedValue)
            .reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Leads").font(.title2).fontWeight(.semibold)
                        Text("Pipeline: \(Money.format(pipelineValue))  ·  Gewonnen: \(Money.format(wonValue))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        showNewLead = true
                    } label: {
                        Label("Neuer Lead", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)

                Divider()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(LeadStatus.pipelineOrder) { status in
                            KanbanColumn(
                                status: status,
                                leads: workspace.leads.filter { $0.status == status }
                                    .sorted(by: { $0.updatedAt > $1.updatedAt }),
                                onSelect: { lead in selectedLead = lead }
                            )
                            .frame(width: 240)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationDestination(item: $selectedLead) { lead in
                LeadDetailView(lead: lead)
            }
        }
        .sheet(isPresented: $showNewLead) {
            NewLeadSheet(workspace: workspace) { newLead in
                selectedLead = newLead
            }
        }
    }
}

struct KanbanColumn: View {
    let status: LeadStatus
    let leads: [Lead]
    let onSelect: (Lead) -> Void

    private var color: Color {
        switch status {
        case .new, .contacted: .blue
        case .meeting, .proposal: .orange
        case .won: .green
        case .lost: .red
        }
    }

    private var columnValue: Double {
        leads.compactMap(\.expectedValue).reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusPill(text: status.title, color: color)
                Spacer()
                Text("\(leads.count)").font(.caption).foregroundStyle(.secondary)
            }
            Text(Money.format(columnValue))
                .font(.caption).foregroundStyle(.secondary)

            VStack(spacing: 6) {
                if leads.isEmpty {
                    Text("leer")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    ForEach(leads) { lead in
                        Button {
                            onSelect(lead)
                        } label: {
                            LeadCard(lead: lead)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.gray.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct LeadCard: View {
    let lead: Lead
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lead.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
            if !lead.company.isEmpty {
                Text(lead.company).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack {
                if let v = lead.expectedValue {
                    Text(Money.format(v)).font(.caption).fontWeight(.medium)
                } else {
                    Text("—").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(DateFmt.short(lead.lastContactAt ?? lead.createdAt))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.15))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct NewLeadSheet: View {
    let workspace: Workspace
    let onCreated: (Lead) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var company = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var source = ""
    @State private var expectedValueText = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Neuer Lead").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }

            Form {
                Section {
                    TextField("Name *", text: $name)
                    TextField("Firma", text: $company)
                    TextField("E-Mail", text: $email)
                    TextField("Telefon", text: $phone)
                }
                Section("Vertrieb") {
                    TextField("Quelle (Instagram, Empfehlung…)", text: $source)
                    TextField("Geschätzter Wert (€)", text: $expectedValueText)
                }
                Section("Notizen") {
                    TextEditor(text: $notes).frame(minHeight: 120)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Anlegen") {
                    let value = Double(expectedValueText.replacingOccurrences(of: ",", with: "."))
                    let lead = Lead(
                        name: name.trimmingCharacters(in: .whitespaces),
                        company: company,
                        email: email,
                        phone: phone,
                        source: source,
                        expectedValue: value,
                        notes: notes
                    )
                    lead.workspace = workspace
                    modelContext.insert(lead)
                    try? modelContext.save()
                    onCreated(lead)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 600)
    }
}

struct LeadDetailView: View {
    @Bindable var lead: Lead
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var expectedValueText: String = ""
    @State private var showDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(lead.name).font(.title).fontWeight(.semibold)
                Text(lead.company.isEmpty ? (lead.source.isEmpty ? "Lead" : lead.source) : lead.company)
                    .foregroundStyle(.secondary)

                statusCard
                detailsCard
                notesCard
                actionsCard
            }
            .padding(20)
        }
        .onAppear {
            if let v = lead.expectedValue { expectedValueText = String(v) }
        }
        .alert("Lead wirklich löschen?", isPresented: $showDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                modelContext.delete(lead)
                try? modelContext.save()
                dismiss()
            }
        }
    }

    private var statusCard: some View {
        Card("Status", subtitle: "Letzter Kontakt: \(DateFmt.short(lead.lastContactAt ?? lead.createdAt))") {
            HStack(spacing: 6) {
                ForEach(LeadStatus.pipelineOrder) { s in
                    let active = lead.status == s
                    Button {
                        lead.status = s
                        try? modelContext.save()
                    } label: {
                        Text(s.title)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(active ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.08))
                            .foregroundStyle(active ? Color.accentColor : Color.secondary)
                            .overlay(
                                Capsule().stroke(active ? Color.accentColor : Color.gray.opacity(0.2))
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var detailsCard: some View {
        Card("Daten") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledField(label: "Name", text: $lead.name)
                LabeledField(label: "Firma", text: $lead.company)
                LabeledField(label: "E-Mail", text: $lead.email)
                LabeledField(label: "Telefon", text: $lead.phone)
                LabeledField(label: "Quelle", text: $lead.source)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Geschätzter Wert (€)").font(.caption).foregroundStyle(.secondary)
                    TextField("z. B. 1200", text: $expectedValueText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: expectedValueText) { _, new in
                            lead.expectedValue = Double(new.replacingOccurrences(of: ",", with: "."))
                        }
                }
            }
        }
    }

    private var notesCard: some View {
        Card("Notizen") {
            TextEditor(text: $lead.notes)
                .frame(minHeight: 200)
                .border(Color.gray.opacity(0.2))
        }
    }

    private var actionsCard: some View {
        Card("Aktionen") {
            HStack {
                Button {
                    convertToCustomer()
                } label: {
                    Label("Zum Kunden konvertieren", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button(role: .destructive) {
                    showDelete = true
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
        }
    }

    private func convertToCustomer() {
        guard let workspace = lead.workspace else { return }
        let customer = Customer(
            name: lead.name,
            company: lead.company,
            email: lead.email,
            phone: lead.phone,
            notes: lead.notes.isEmpty
                ? "Aus Lead konvertiert. Quelle: \(lead.source.isEmpty ? "—" : lead.source)"
                : "Aus Lead konvertiert. Quelle: \(lead.source.isEmpty ? "—" : lead.source)\n\n\(lead.notes)"
        )
        customer.workspace = workspace
        modelContext.insert(customer)
        lead.status = .won
        try? modelContext.save()
        dismiss()
    }
}
