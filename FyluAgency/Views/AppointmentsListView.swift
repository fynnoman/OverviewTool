import SwiftUI
import SwiftData

struct AppointmentsListView: View {
    let workspace: Workspace
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Appointment.startsAt) private var allAppointments: [Appointment]

    @State private var showNew = false
    @State private var editing: Appointment?
    @State private var showPast = false
    @State private var scanProgress: ScanProgress?
    @State private var scanResult: String?
    @State private var scanError: String?

    // MARK: Derived data

    private var appointments: [Appointment] {
        let ws = workspace.id
        return allAppointments.filter { $0.workspace?.id == ws }
    }

    private var upcoming: [Appointment] {
        let now = Date()
        return appointments
            .filter { ($0.endsAt ?? $0.startsAt) >= now }
            .sorted { $0.startsAt < $1.startsAt }
    }

    private var past: [Appointment] {
        let now = Date()
        return appointments
            .filter { ($0.endsAt ?? $0.startsAt) < now }
            .sorted { $0.startsAt > $1.startsAt }
    }

    private var todayCount: Int {
        let cal = Calendar.current
        return appointments.filter { cal.isDateInToday($0.startsAt) }.count
    }

    private var thisWeekCount: Int {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return appointments.filter { interval.contains($0.startsAt) }.count
    }

    private var fromEmailCount: Int {
        appointments.filter { $0.source == .email }.count
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    scanBanner
                    kpiRow

                    if appointments.isEmpty {
                        emptyState
                    } else {
                        upcomingSection
                        pastSection
                    }
                }
                .padding(20)
            }
        }
        .sheet(isPresented: $showNew) {
            AppointmentSheet(workspace: workspace, appointment: nil)
        }
        .sheet(item: $editing) { appt in
            AppointmentSheet(workspace: workspace, appointment: appt)
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Termine").font(.title2).fontWeight(.semibold)
                Text("\(upcoming.count) kommend · \(appointments.count) gesamt")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                scanAllEmails()
            } label: {
                if scanProgress != nil {
                    Label("Scannt…", systemImage: "sparkles")
                } else {
                    Label("Alle E-Mails scannen", systemImage: "sparkles")
                }
            }
            .buttonStyle(.bordered)
            .disabled(scanProgress != nil)

            Button {
                showNew = true
            } label: {
                Label("Neuer Termin", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var scanBanner: some View {
        if let p = scanProgress {
            HStack(spacing: 10) {
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 240)
                Text("KI prüft \(p.done)/\(p.total) E-Mails · \(p.foundNew) neu")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.25))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let msg = scanResult {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                Text(msg).font(.callout)
                Spacer()
                Button {
                    scanResult = nil
                } label: {
                    Image(systemName: "xmark").font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.green.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.25))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let err = scanError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
                Text(err).font(.callout)
                Spacer()
                Button {
                    scanError = nil
                } label: {
                    Image(systemName: "xmark").font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.orange.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.25))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var kpiRow: some View {
        HStack(spacing: 12) {
            KpiCard(title: "Heute", value: "\(todayCount)", accent: todayCount > 0)
            KpiCard(title: "Diese Woche", value: "\(thisWeekCount)")
            KpiCard(title: "Aus E-Mail erkannt", value: "\(fromEmailCount)", muted: fromEmailCount == 0)
            KpiCard(title: "Gesamt", value: "\(appointments.count)", muted: true)
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        Card("Kommende Termine", subtitle: upcoming.isEmpty ? "nichts geplant" : "\(upcoming.count)") {
            if upcoming.isEmpty {
                Text("Noch keine kommenden Termine — leg den nächsten oben an oder lass die KI aus den Lead-E-Mails extrahieren.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(upcoming) { appt in
                        AppointmentRow(
                            appointment: appt,
                            onOpen: { editing = appt },
                            onDelete: { delete(appt) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pastSection: some View {
        if !past.isEmpty {
            Card("Vergangene Termine", subtitle: "\(past.count)") {
                VStack(spacing: 8) {
                    DisclosureGroup(isExpanded: $showPast) {
                        VStack(spacing: 8) {
                            ForEach(past) { appt in
                                AppointmentRow(
                                    appointment: appt,
                                    onOpen: { editing = appt },
                                    onDelete: { delete(appt) },
                                    dimmed: true
                                )
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text(showPast ? "Verbergen" : "Anzeigen")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("Noch keine Termine")
                .font(.headline)
            Text("Trag manuell einen Termin ein oder lass die KI in den Leads automatisch erkennen, wenn eine E-Mail einen Termin bestätigt.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
            Button {
                showNew = true
            } label: {
                Label("Neuer Termin", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.gray.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15))
        )
    }

    // MARK: Actions

    private func delete(_ appt: Appointment) {
        modelContext.delete(appt)
        try? modelContext.save()
    }

    /// One-shot: walk every LeadEmail in this workspace, ask the model whether
    /// it confirms an appointment, and create one if so. Skips emails that
    /// already produced an Appointment (via `sourceEmailID`) so the scan is
    /// idempotent and safe to re-run.
    @MainActor
    private func scanAllEmails() {
        guard scanProgress == nil else { return }
        guard let service = OpenAIService(workspace: workspace) else {
            scanError = "Kein OpenAI-Key hinterlegt — bitte in den Einstellungen ergänzen."
            scanResult = nil
            return
        }
        let emails = workspace.leads.flatMap { $0.emails }
        guard !emails.isEmpty else {
            scanResult = "Keine E-Mails zum Scannen gefunden."
            scanError = nil
            return
        }

        scanError = nil
        scanResult = nil
        scanProgress = ScanProgress(total: emails.count, done: 0, foundNew: 0, skipped: 0)

        Task { @MainActor in
            var foundNew = 0
            var skipped = 0
            for email in emails {
                let outcome = await scanOne(email: email, service: service)
                switch outcome {
                case .created:  foundNew += 1
                case .skipped:  skipped += 1
                case .none:     break
                }
                scanProgress?.done += 1
                scanProgress?.foundNew = foundNew
                scanProgress?.skipped = skipped
            }
            scanProgress = nil
            scanResult = "Scan fertig: \(foundNew) neue Termine erkannt · \(skipped) E-Mails übersprungen (schon eingetragen)."
        }
    }

    private enum ScanOutcome { case created, skipped, none }

    @MainActor
    private func scanOne(email: LeadEmail, service: OpenAIService) async -> ScanOutcome {
        let emailID = email.id
        let existingDescriptor = FetchDescriptor<Appointment>(
            predicate: #Predicate<Appointment> { $0.sourceEmailID == emailID }
        )
        if (try? modelContext.fetch(existingDescriptor))?.first != nil {
            return .skipped
        }
        let subject = email.subject
        let body = email.body
        do {
            let extracted = try await service.extractAppointment(subject: subject, body: body)
            guard extracted.accepted,
                  let isoStart = extracted.startsAt,
                  let startDate = AppointmentDateParser.parse(isoStart)
            else { return .none }

            let endDate: Date? = extracted.endsAt.flatMap { AppointmentDateParser.parse($0) }
            let leadName = email.lead?.name ?? ""
            let resolvedTitle: String = {
                let t = extracted.title?.trimmingCharacters(in: .whitespaces) ?? ""
                if !t.isEmpty { return t }
                return leadName.isEmpty ? "Termin (aus E-Mail)" : "Termin mit \(leadName)"
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
            appt.lead = email.lead
            modelContext.insert(appt)
            try? modelContext.save()
            return .created
        } catch {
            return .none
        }
    }
}

struct ScanProgress {
    var total: Int
    var done: Int
    var foundNew: Int
    var skipped: Int
}

// MARK: - Row

struct AppointmentRow: View {
    let appointment: Appointment
    let onOpen: () -> Void
    let onDelete: () -> Void
    var dimmed: Bool = false

    @State private var confirmDelete = false

    private var isToday: Bool {
        Calendar.current.isDateInToday(appointment.startsAt)
    }

    private var dateBlock: some View {
        VStack(spacing: 2) {
            Text(AppointmentFmt.weekdayShort.string(from: appointment.startsAt).uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Calendar.current.component(.day, from: appointment.startsAt))")
                .font(.title3).fontWeight(.semibold)
                .foregroundStyle(isToday ? Color.accentColor : .primary)
            Text(monthShort)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 48)
        .padding(.vertical, 8)
        .background(isToday ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var monthShort: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "MMM"
        return f.string(from: appointment.startsAt).replacingOccurrences(of: ".", with: "")
    }

    private var timeLine: String {
        if appointment.isAllDay { return "Ganztägig" }
        let start = AppointmentFmt.timeShort.string(from: appointment.startsAt)
        if let end = appointment.endsAt {
            return "\(start) – \(AppointmentFmt.timeShort.string(from: end)) Uhr"
        }
        return "\(start) Uhr"
    }

    private var accentColor: Color? {
        guard let hex = appointment.colorHex, !hex.isEmpty else { return nil }
        return Color(hex: hex)
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 0) {
                if let accent = accentColor {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accent)
                        .frame(width: 4)
                        .padding(.trailing, 8)
                }
                HStack(alignment: .top, spacing: 12) {
                    dateBlock
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            if let accent = accentColor {
                                Circle()
                                    .fill(accent)
                                    .frame(width: 8, height: 8)
                            }
                            Text(appointment.title.isEmpty ? "(ohne Titel)" : appointment.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Spacer()
                            StatusPill(
                                text: appointment.source.title,
                                color: appointment.source == .email ? .blue : .gray
                            )
                        }
                        Text(timeLine)
                            .font(.caption).foregroundStyle(.secondary)

                        if let lead = appointment.lead {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(lead.company.isEmpty ? lead.name : "\(lead.name) · \(lead.company)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        if let customer = appointment.customer {
                            HStack(spacing: 4) {
                                Image(systemName: "person.crop.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(customer.company.isEmpty ? customer.name : "\(customer.name) · \(customer.company)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        if !appointment.location.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(appointment.location)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        if !appointment.notes.isEmpty {
                            Text(appointment.notes)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .padding(.top, 2)
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        accentColor?.opacity(0.5)
                            ?? (isToday ? Color.accentColor.opacity(0.4) : Color.gray.opacity(0.15))
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(dimmed ? 0.65 : 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Bearbeiten", systemImage: "pencil") { onOpen() }
            Divider()
            Button("Löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
        }
        .alert("Termin löschen?", isPresented: $confirmDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Sheet (create + edit)

struct AppointmentSheet: View {
    let workspace: Workspace
    /// `nil` → new appointment; otherwise edit mode.
    let appointment: Appointment?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Lead.name) private var allLeads: [Lead]
    @Query(sort: \Customer.name) private var allCustomers: [Customer]

    @State private var title = ""
    @State private var notes = ""
    @State private var startsAt = Date()
    @State private var hasEnd = false
    @State private var endsAt = Date().addingTimeInterval(3600)
    @State private var location = ""
    @State private var isAllDay = false
    @State private var leadID: UUID? = nil
    @State private var customerID: UUID? = nil
    @State private var colorHex: String? = nil
    @State private var showDelete = false

    private var leadsInWorkspace: [Lead] {
        let ws = workspace.id
        return allLeads.filter { $0.workspace?.id == ws }
    }

    private var customersInWorkspace: [Customer] {
        let ws = workspace.id
        return allCustomers.filter { $0.workspace?.id == ws && $0.archivedAt == nil }
    }

    private var isEditing: Bool { appointment != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(isEditing ? "Termin bearbeiten" : "Neuer Termin").font(.headline)
                Spacer()
                if let appt = appointment, appt.source == .email {
                    StatusPill(text: "Aus E-Mail erkannt", color: .blue)
                }
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }

            Form {
                Section {
                    TextField("Titel *", text: $title)
                    Picker("Lead (optional)", selection: $leadID) {
                        Text("— kein Lead —").tag(UUID?.none)
                        ForEach(leadsInWorkspace) { lead in
                            Text(lead.company.isEmpty ? lead.name : "\(lead.name) · \(lead.company)")
                                .tag(Optional(lead.id))
                        }
                    }
                    Picker("Kunde (optional)", selection: $customerID) {
                        Text("— kein Kunde —").tag(UUID?.none)
                        ForEach(customersInWorkspace) { customer in
                            Text(customer.company.isEmpty ? customer.name : "\(customer.name) · \(customer.company)")
                                .tag(Optional(customer.id))
                        }
                    }
                }
                Section("Farbe") {
                    AppointmentColorPicker(selectedHex: $colorHex)
                }
                Section("Zeit") {
                    Toggle("Ganztägig", isOn: $isAllDay)
                    if isAllDay {
                        DatePicker("Datum", selection: $startsAt, displayedComponents: [.date])
                    } else {
                        DatePicker("Start", selection: $startsAt, displayedComponents: [.date, .hourAndMinute])
                        Toggle("Endzeit angeben", isOn: $hasEnd)
                        if hasEnd {
                            DatePicker("Ende", selection: $endsAt, in: startsAt..., displayedComponents: [.date, .hourAndMinute])
                        }
                    }
                }
                Section("Ort / Link (optional)") {
                    TextField("Adresse, Zoom-Link, Telefon…", text: $location)
                }
                Section("Notizen") {
                    TextEditor(text: $notes).frame(minHeight: 100)
                }
            }
            .formStyle(.grouped)

            HStack {
                if isEditing {
                    Button(role: .destructive) {
                        showDelete = true
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button(isEditing ? "Speichern" : "Anlegen") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 640)
        .onAppear { loadInitial() }
        .alert("Termin wirklich löschen?", isPresented: $showDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                if let appt = appointment {
                    modelContext.delete(appt)
                    try? modelContext.save()
                }
                dismiss()
            }
        }
    }

    private func loadInitial() {
        guard let appt = appointment else { return }
        title = appt.title
        notes = appt.notes
        startsAt = appt.startsAt
        if let end = appt.endsAt {
            hasEnd = true
            endsAt = end
        }
        location = appt.location
        isAllDay = appt.isAllDay
        leadID = appt.lead?.id
        customerID = appt.customer?.id
        colorHex = appt.colorHex
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let resolvedLead: Lead? = leadID.flatMap { id in
            leadsInWorkspace.first { $0.id == id }
        }
        let resolvedCustomer: Customer? = customerID.flatMap { id in
            customersInWorkspace.first { $0.id == id }
        }

        if let appt = appointment {
            appt.title = trimmedTitle
            appt.notes = notes
            appt.startsAt = startsAt
            appt.endsAt = (isAllDay || !hasEnd) ? nil : endsAt
            appt.location = location.trimmingCharacters(in: .whitespaces)
            appt.isAllDay = isAllDay
            appt.lead = resolvedLead
            appt.customer = resolvedCustomer
            appt.colorHex = colorHex
            appt.updatedAt = Date()
        } else {
            let new = Appointment(
                title: trimmedTitle,
                notes: notes,
                startsAt: startsAt,
                endsAt: (isAllDay || !hasEnd) ? nil : endsAt,
                location: location.trimmingCharacters(in: .whitespaces),
                isAllDay: isAllDay,
                source: .manual,
                colorHex: colorHex
            )
            new.workspace = workspace
            new.lead = resolvedLead
            new.customer = resolvedCustomer
            modelContext.insert(new)
        }
        try? modelContext.save()
    }
}

// MARK: - Color picker

private struct AppointmentColorPicker: View {
    @Binding var selectedHex: String?

    private let columns = [GridItem(.adaptive(minimum: 36), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            noneSwatch
            ForEach(AppointmentColor.allCases) { color in
                swatch(for: color)
            }
        }
        .padding(.vertical, 4)
    }

    private var noneSwatch: some View {
        Button {
            selectedHex = nil
        } label: {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.08))
                Image(systemName: "slash.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 28, height: 28)
            .overlay(
                Circle().stroke(
                    selectedHex == nil ? Color.accentColor : Color.gray.opacity(0.3),
                    lineWidth: selectedHex == nil ? 2 : 1
                )
            )
        }
        .buttonStyle(.plain)
        .help("Keine Farbe")
    }

    private func swatch(for color: AppointmentColor) -> some View {
        let isSelected = (selectedHex?.lowercased() == color.hex.lowercased())
        return Button {
            selectedHex = color.hex
        } label: {
            Circle()
                .fill(Color(hex: color.hex))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle().stroke(
                        isSelected ? Color.accentColor : Color.black.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1
                    )
                )
        }
        .buttonStyle(.plain)
        .help(color.title)
    }
}
