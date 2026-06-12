import SwiftUI
import SwiftData

struct LeadsListView: View {
    let workspace: Workspace
    @Environment(\.modelContext) private var modelContext
    @State private var showNewLead = false
    @State private var selectedLead: Lead?

    private var openLeads: [Lead] {
        workspace.leads.filter { $0.status != .won && $0.status != .lost }
    }

    private var pipelineValue: Double {
        openLeads.compactMap(\.expectedValue).reduce(0, +)
    }

    private var wonValue: Double {
        workspace.leads.filter { $0.status == .won }.compactMap(\.expectedValue).reduce(0, +)
    }

    private var lostValue: Double {
        workspace.leads.filter { $0.status == .lost }.compactMap(\.expectedValue).reduce(0, +)
    }

    private var allOffersValue: Double {
        workspace.leads.compactMap(\.expectedValue).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Leads").font(.title2).fontWeight(.semibold)
                        Text("\(workspace.leads.count) Leads · alle Angebote zusammen \(Money.format(allOffersValue))")
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
                .padding(.horizontal, 20).padding(.top, 20)

                HStack(spacing: 12) {
                    KpiCard(
                        title: "Pipeline · offen",
                        value: Money.format(pipelineValue),
                        accent: true
                    )
                    KpiCard(
                        title: "Gewonnen",
                        value: Money.format(wonValue),
                        tone: wonValue > 0 ? .positive : .neutral
                    )
                    KpiCard(
                        title: "Verloren",
                        value: Money.format(lostValue),
                        tone: lostValue > 0 ? .danger : .neutral
                    )
                    KpiCard(
                        title: "Leads gesamt",
                        value: "\(workspace.leads.count)",
                        muted: true
                    )
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)

                if pipelineValue > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill").foregroundStyle(Color.orange)
                        Text("Wenn alle offenen Leads zu Kunden werden, kommen erstmal \(Money.format(pipelineValue)) rein.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 12)
                }

                Divider()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(LeadStatus.pipelineOrder) { status in
                            KanbanColumn(
                                status: status,
                                leads: workspace.leads.filter { $0.status == status }
                                    .sorted(by: { $0.updatedAt > $1.updatedAt }),
                                onSelect: { lead in selectedLead = lead },
                                onDelete: { lead in deleteLead(lead) }
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

    private func deleteLead(_ lead: Lead) {
        if selectedLead?.id == lead.id { selectedLead = nil }
        modelContext.delete(lead)
        try? modelContext.save()
    }
}

struct KanbanColumn: View {
    let status: LeadStatus
    let leads: [Lead]
    let onSelect: (Lead) -> Void
    let onDelete: (Lead) -> Void

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
                        .contextMenu {
                            Button("Öffnen") { onSelect(lead) }
                            Divider()
                            Button("Löschen", role: .destructive) { onDelete(lead) }
                        }
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
            if let offer = lead.offerDescription, !offer.isEmpty {
                Text(offer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
            HStack(alignment: .firstTextBaseline) {
                if let v = lead.expectedValue {
                    Text(Money.format(v))
                        .font(.callout).fontWeight(.semibold)
                        .foregroundStyle(Color.green)
                } else {
                    Text("—").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(DateFmt.short(lead.lastContactAt ?? lead.createdAt))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 2)
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
    @State private var offerDescription = ""
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
                    TextField("Wofür ist das Angebot? (z. B. Website + SEO)", text: $offerDescription)
                    TextField("Angebotswert (€)", text: $expectedValueText)
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
                        offerDescription: offerDescription,
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
    @State private var newWishTitle = ""
    @State private var newWishPrice = ""
    @State private var newWishDesc = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(lead.name).font(.title).fontWeight(.semibold)
                Text(lead.company.isEmpty ? (lead.source.isEmpty ? "Lead" : lead.source) : lead.company)
                    .foregroundStyle(.secondary)

                statusCard
                wishesCard
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

    private var openWishesCount: Int {
        lead.issues.filter { !$0.done }.count
    }

    private var wishesCard: some View {
        Card("Wünsche & Anforderungen", subtitle: "\(openWishesCount) offen · \(lead.issues.filter(\.done).count) erledigt") {
            VStack(spacing: 0) {
                ForEach(lead.issues.sorted(by: { ($0.done ? 1 : 0) < ($1.done ? 1 : 0) || ($0.createdAt > $1.createdAt) })) { issue in
                    IssueRow(issue: issue)
                }
                if lead.issues.isEmpty {
                    Text("Was wünscht sich der Lead — was muss er bekommen, was kostet das?")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                }
                Divider().padding(.vertical, 6)
                VStack(spacing: 6) {
                    HStack {
                        TextField("Wunsch / Anforderung", text: $newWishTitle)
                            .textFieldStyle(.roundedBorder)
                        TextField("€", text: $newWishPrice)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Button { addWish() } label: { Image(systemName: "plus") }
                            .disabled(newWishTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    TextField("Beschreibung (optional)", text: $newWishDesc)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func addWish() {
        let title = newWishTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let price = Double(newWishPrice.replacingOccurrences(of: ",", with: "."))
        let issue = Issue(
            title: title,
            details: newWishDesc,
            price: price
        )
        issue.lead = lead
        modelContext.insert(issue)
        try? modelContext.save()
        newWishTitle = ""
        newWishPrice = ""
        newWishDesc = ""
    }

    private var detailsCard: some View {
        Card("Daten") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledField(label: "Name", text: $lead.name)
                LabeledField(label: "Firma", text: $lead.company)
                LabeledField(label: "E-Mail", text: $lead.email)
                LabeledField(label: "Telefon", text: $lead.phone)
                LabeledField(label: "Quelle", text: $lead.source)
                LabeledField(
                    label: "Angebot wofür?",
                    text: Binding(
                        get: { lead.offerDescription ?? "" },
                        set: { lead.offerDescription = $0.isEmpty ? nil : $0 }
                    )
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text("Angebotswert (€)").font(.caption).foregroundStyle(.secondary)
                    TextField("z. B. 800", text: $expectedValueText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: expectedValueText) { _, new in
                            lead.expectedValue = Double(new.replacingOccurrences(of: ",", with: "."))
                        }
                    if let v = lead.expectedValue, v > 0 {
                        Text("→ \(Money.format(v)) wenn der Lead zum Kunden wird")
                            .font(.caption).foregroundStyle(Color.green)
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

        // Migrate wishes/issues over to the new customer so nothing is lost.
        for wish in lead.issues {
            let copied = Issue(
                title: wish.title,
                details: wish.details,
                price: wish.price,
                done: wish.done,
                order: wish.order
            )
            copied.customer = customer
            modelContext.insert(copied)
        }

        lead.status = .won
        try? modelContext.save()
        dismiss()
    }
}
