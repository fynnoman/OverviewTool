import SwiftUI
import SwiftData
import AppKit

struct LeadsListView: View {
    let workspace: Workspace
    @Environment(\.modelContext) private var modelContext
    @State private var showNewLead = false
    @State private var showInsights = false
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
                        showInsights = true
                    } label: {
                        Label("KI-Analyse", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .disabled(workspace.leads.isEmpty)
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

                ScrollView([.horizontal, .vertical], showsIndicators: false) {
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
        .sheet(isPresented: $showInsights) {
            LeadsInsightsSheet(workspace: workspace) { lead in
                selectedLead = lead
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
    @State private var showNewEmail = false
    @State private var summarizingEmailIDs: Set<UUID> = []
    @State private var draftReplyEmail: LeadEmail?

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
                emailsCard
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
        .sheet(isPresented: $showNewEmail) {
            NewLeadEmailSheet(lead: lead) { newEmail in
                if newEmail.direction == .received {
                    // For received emails the user gets an AI reply draft to copy,
                    // and the source email is discarded afterwards. No need to
                    // pay for a summary call we'll throw away.
                    draftReplyEmail = newEmail
                } else {
                    summarize(email: newEmail)
                }
            }
        }
        .sheet(item: $draftReplyEmail) { sourceEmail in
            ReplyDraftSheet(sourceEmail: sourceEmail, lead: lead) {
                draftReplyEmail = nil
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

    private var sortedEmails: [LeadEmail] {
        lead.emails.sorted { a, b in
            (a.sentAt ?? a.createdAt) > (b.sentAt ?? b.createdAt)
        }
    }

    private var emailsCard: some View {
        Card(
            "E-Mails",
            subtitle: "\(lead.emails.count) hinterlegt · KI-Zusammenfassung"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if lead.emails.isEmpty {
                    Text("Noch keine E-Mails. Füge eine gesendete oder empfangene E-Mail hinzu — die KI fasst dir die wichtigsten Punkte zusammen.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(sortedEmails) { email in
                        LeadEmailRow(
                            email: email,
                            isSummarizing: summarizingEmailIDs.contains(email.id),
                            onRegenerate: { summarize(email: email) },
                            onDelete: { delete(email: email) }
                        )
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        showNewEmail = true
                    } label: {
                        Label("E-Mail hinzufügen", systemImage: "envelope.badge")
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func summarize(email: LeadEmail) {
        guard let workspace = lead.workspace else { return }
        guard let service = OpenAIService(workspace: workspace) else { return }
        let id = email.id
        let subject = email.subject
        let body = email.body
        summarizingEmailIDs.insert(id)
        Task { @MainActor in
            defer { summarizingEmailIDs.remove(id) }
            do {
                let summary = try await service.summarizeEmail(subject: subject, body: body)
                email.summary = summary
                email.summaryUpdatedAt = Date()
                try? modelContext.save()
            } catch {
                // Leave previous summary as-is; user can retry.
            }
            await detectAppointment(in: email, service: service, workspace: workspace)
        }
    }

    /// Side-channel: ask the model whether this email confirms a concrete
    /// appointment and, if so, create an `Appointment` linked to the lead.
    /// Idempotent via `sourceEmailID` so re-summarizing never duplicates.
    @MainActor
    private func detectAppointment(in email: LeadEmail, service: OpenAIService, workspace: Workspace) async {
        let subject = email.subject
        let body = email.body
        let emailID = email.id
        do {
            let extracted = try await service.extractAppointment(subject: subject, body: body)
            guard extracted.accepted,
                  let isoStart = extracted.startsAt,
                  let startDate = AppointmentDateParser.parse(isoStart)
            else { return }

            let existingDescriptor = FetchDescriptor<Appointment>(
                predicate: #Predicate<Appointment> { $0.sourceEmailID == emailID }
            )
            if let already = (try? modelContext.fetch(existingDescriptor))?.first {
                _ = already   // respect user edits — never overwrite
                return
            }

            let endDate: Date? = extracted.endsAt.flatMap { AppointmentDateParser.parse($0) }
            let resolvedTitle: String = {
                let t = extracted.title?.trimmingCharacters(in: .whitespaces) ?? ""
                if !t.isEmpty { return t }
                return "Termin mit \(lead.name)"
            }()

            let appt = Appointment(
                title: resolvedTitle,
                notes: "",
                startsAt: startDate,
                endsAt: endDate,
                location: (extracted.location ?? "").trimmingCharacters(in: .whitespaces),
                isAllDay: extracted.allDay ?? false,
                source: .email,
                sourceEmailID: emailID
            )
            appt.workspace = workspace
            appt.lead = lead
            modelContext.insert(appt)
            try? modelContext.save()
        } catch {
            // Silent — appointment detection is best-effort.
        }
    }

    private func delete(email: LeadEmail) {
        modelContext.delete(email)
        try? modelContext.save()
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
        SoundPlayer.kaching()
        dismiss()
    }
}

struct LeadEmailRow: View {
    let email: LeadEmail
    let isSummarizing: Bool
    let onRegenerate: () -> Void
    let onDelete: () -> Void

    @State private var showOriginal = false

    private var directionColor: Color {
        email.direction == .received ? .blue : .green
    }

    private var dateLabel: String {
        DateFmt.short(email.sentAt ?? email.createdAt)
    }

    private var displaySubject: String {
        email.subject.isEmpty ? "(ohne Betreff)" : email.subject
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(displaySubject)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Spacer()
                StatusPill(text: email.direction.title, color: directionColor)
            }
            Text(dateLabel)
                .font(.caption2).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text("KI-Zusammenfassung")
                        .font(.caption).fontWeight(.medium)
                    if let updated = email.summaryUpdatedAt {
                        Text("· \(DateFmt.short(updated))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if isSummarizing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("KI fasst zusammen…").font(.caption).foregroundStyle(.secondary)
                    }
                } else if email.summary.isEmpty {
                    Text("Noch keine Zusammenfassung. Über „Neu zusammenfassen“ erneut versuchen — OpenAI-Key in den Einstellungen prüfen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    Text(email.summary)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.18))
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))

            DisclosureGroup(isExpanded: $showOriginal) {
                Text(email.body)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } label: {
                Text(showOriginal ? "Original ausblenden" : "Original anzeigen")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    onRegenerate()
                } label: {
                    Label("Neu zusammenfassen", systemImage: "arrow.clockwise")
                }
                .disabled(isSummarizing)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Entfernen", systemImage: "trash")
                }
            }
            .controlSize(.small)
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

struct NewLeadEmailSheet: View {
    let lead: Lead
    let onCreated: (LeadEmail) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var subject = ""
    @State private var bodyText = ""
    @State private var direction: LeadEmailDirection = .sent
    @State private var sentAt: Date = Date()
    @State private var hasDate: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("E-Mail hinzufügen").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }

            Form {
                Section {
                    Picker("Richtung", selection: $direction) {
                        ForEach(LeadEmailDirection.allCases) { d in
                            Text(d.title).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Betreff (optional)", text: $subject)

                    Toggle("Datum angeben", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Datum", selection: $sentAt, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section("E-Mail-Inhalt") {
                    TextEditor(text: $bodyText).frame(minHeight: 200)
                }
            }
            .formStyle(.grouped)

            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                if direction == .received {
                    Text("Beim Speichern erstellt die KI direkt einen Antwort-Entwurf zum Kopieren. Die empfangene E-Mail wird danach wieder entfernt.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Beim Speichern fasst die KI automatisch die wichtigsten Punkte zusammen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Hinzufügen") {
                    let email = LeadEmail(
                        direction: direction,
                        subject: subject.trimmingCharacters(in: .whitespaces),
                        body: bodyText,
                        sentAt: hasDate ? sentAt : nil
                    )
                    email.lead = lead
                    modelContext.insert(email)
                    lead.lastContactAt = Date()
                    try? modelContext.save()
                    onCreated(email)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 640)
    }
}

/// Generates an AI-drafted reply for a received email, lets the user copy it,
/// and discards the source email when the sheet closes — either via the close
/// button or after copying. Nothing about the received email is persisted.
struct ReplyDraftSheet: View {
    let sourceEmail: LeadEmail
    let lead: Lead
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isGenerating = true
    @State private var draftSubject = ""
    @State private var draftBody = ""
    @State private var errorMessage: String?
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                Text("Antwort-Entwurf").font(.headline)
                Spacer()
                Button { close() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }

            Group {
                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("KI verfasst eine Antwort…")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 60)
                } else if let err = errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Konnte keine Antwort generieren", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.callout).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            Task { await generate() }
                        } label: {
                            Label("Erneut versuchen", systemImage: "arrow.clockwise")
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Betreff").font(.caption).foregroundStyle(.secondary)
                        TextField("Betreff", text: $draftSubject)
                            .textFieldStyle(.roundedBorder)

                        Text("Antwort").font(.caption).foregroundStyle(.secondary)
                            .padding(.top, 4)
                        TextEditor(text: $draftBody)
                            .font(.callout)
                            .frame(minHeight: 280)
                            .padding(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.25))
                            )
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text("Die empfangene E-Mail wird beim Schließen automatisch entfernt.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                if didCopy {
                    Label("In Zwischenablage kopiert", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                Spacer()
                Button("Verwerfen", role: .destructive) { close() }
                Button {
                    copyToClipboard()
                } label: {
                    Label("Kopieren", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 600, height: 600)
        .task { await generate() }
    }

    private func close() {
        modelContext.delete(sourceEmail)
        try? modelContext.save()
        onClose()
        dismiss()
    }

    private func copyToClipboard() {
        let subj = draftSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = subj.isEmpty
            ? draftBody
            : "Betreff: \(subj)\n\n\(draftBody)"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(combined, forType: .string)
        didCopy = true
        // Give the user a beat to see the confirmation, then drop the source email.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            close()
        }
    }

    @MainActor
    private func generate() async {
        isGenerating = true
        errorMessage = nil
        guard let workspace = lead.workspace,
              let service = OpenAIService(workspace: workspace) else {
            errorMessage = "Kein OpenAI-Key konfiguriert. Bitte in den Einstellungen hinterlegen."
            isGenerating = false
            return
        }
        do {
            let draft = try await service.draftReply(
                receivedSubject: sourceEmail.subject,
                receivedBody: sourceEmail.body,
                leadName: lead.name,
                leadCompany: lead.company,
                offerDescription: lead.offerDescription
            )
            draftSubject = draft.subject
            draftBody = draft.body
            isGenerating = false
        } catch {
            errorMessage = error.localizedDescription
            isGenerating = false
        }
    }
}
