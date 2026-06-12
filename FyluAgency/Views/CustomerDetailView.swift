import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CustomerDetailView: View {
    @Bindable var customer: Customer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var showInvoiceImporter = false
    @State private var importStatus: String?

    private var workspace: Workspace? { customer.workspace }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                kpiRow

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        issuesCard
                        costsCard
                        invoicesCard
                        uploadsCard
                        cashIncomeCard
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 16) {
                        stammdatenCard
                        notesCard
                    }
                    .frame(width: 360)
                }
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Kunde löschen", systemImage: "trash") {
                    showDeleteConfirm = true
                }
                .foregroundStyle(.red)
            }
        }
        .alert("Kunde wirklich löschen?", isPresented: $showDeleteConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                modelContext.delete(customer)
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("Alle Aufgaben, Kosten und Rechnungen werden ebenfalls gelöscht.")
        }
        .task(id: customer.id) {
            syncParsedUploads()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(customer.name).font(.title).fontWeight(.semibold)
            Text(customer.company.isEmpty ? (customer.email.isEmpty ? "Kunde" : customer.email) : customer.company)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                KpiCard(title: "Umsatz brutto (steuerpflichtig)",
                        value: Money.format(customer.totalInvoiced), accent: true)
                KpiCard(title: "Bar (ohne Rechnung)",
                        value: Money.format(customer.totalCashIncome),
                        tone: customer.totalCashIncome > 0 ? .positive : .neutral)
                KpiCard(title: "Kosten",
                        value: Money.format(customer.totalCosts), muted: true)
                KpiCard(
                    title: "Gewinn",
                    value: Money.format(customer.profit),
                    tone: customer.profit < 0 ? .danger : (customer.profit > 0 ? .positive : .neutral)
                )
            }
            HStack(spacing: 12) {
                KpiCard(title: "MwSt. (aus Rechnungen)",
                        value: Money.format(customer.totalVatInvoiced), muted: true)
                KpiCard(title: "Netto (aus Rechnungen)",
                        value: Money.format(customer.totalNetInvoiced), muted: true)
                KpiCard(
                    title: "Offene Wünsche",
                    value: "\(customer.openIssuesCount)"
                        + (customer.openIssuesValue > 0 ? "  (\(Money.format(customer.openIssuesValue)))" : ""),
                    tone: customer.openIssuesValue > 0 ? .positive : .neutral
                )
                KpiCard(title: "Eingang gesamt",
                        value: Money.format(customer.totalIncomeAll), muted: true)
            }
        }
    }

    // MARK: Issues

    @State private var newIssueTitle = ""
    @State private var newIssuePrice = ""
    @State private var newIssueDesc = ""

    private var issuesCard: some View {
        Card("Wünsche & Anforderungen des Kunden", subtitle: "\(customer.openIssuesCount) offen · \(customer.issues.filter(\.done).count) fertig — getrennt von deiner Todo-Liste") {
            VStack(spacing: 0) {
                ForEach(customer.issues.sorted(by: { ($0.done ? 1 : 0) < ($1.done ? 1 : 0) || ($0.createdAt > $1.createdAt) })) { issue in
                    IssueRow(issue: issue)
                }
                if customer.issues.isEmpty {
                    Text("Keine Aufgaben — leg unten welche an.")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                }
                Divider().padding(.vertical, 6)
                VStack(spacing: 6) {
                    HStack {
                        TextField("Neue Aufgabe / Wunsch", text: $newIssueTitle)
                            .textFieldStyle(.roundedBorder)
                        TextField("€", text: $newIssuePrice)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Button {
                            addIssue()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(newIssueTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    TextField("Beschreibung (optional)", text: $newIssueDesc)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func addIssue() {
        let title = newIssueTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let price = Double(newIssuePrice.replacingOccurrences(of: ",", with: "."))
        let issue = Issue(
            title: title,
            details: newIssueDesc,
            price: price
        )
        issue.customer = customer
        modelContext.insert(issue)
        try? modelContext.save()
        newIssueTitle = ""
        newIssuePrice = ""
        newIssueDesc = ""
    }

    // MARK: Costs

    @State private var newCostDesc = ""
    @State private var newCostAmount = ""
    @State private var newCostFreq: CostFrequency = .once
    @State private var newCostDue: Date = Date()
    @State private var newCostHasDue = false

    private var costsCard: some View {
        Card("Kosten", subtitle: "\(customer.costs.count) Einträge") {
            VStack(spacing: 0) {
                ForEach(customer.costs.sorted(by: { $0.createdAt > $1.createdAt })) { cost in
                    CostRow(cost: cost)
                }
                if customer.costs.isEmpty {
                    Text("Noch keine Kosten — Domain, Hosting, Lizenzen etc.")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                }
                Divider().padding(.vertical, 6)
                HStack {
                    TextField("Beschreibung", text: $newCostDesc).textFieldStyle(.roundedBorder)
                    TextField("€", text: $newCostAmount).textFieldStyle(.roundedBorder).frame(width: 90)
                    Picker("", selection: $newCostFreq) {
                        ForEach(CostFrequency.allCases) { f in
                            Text(f.title).tag(f)
                        }
                    }
                    .frame(width: 110)
                    Toggle("fällig", isOn: $newCostHasDue).labelsHidden()
                    if newCostHasDue {
                        DatePicker("", selection: $newCostDue, displayedComponents: .date).labelsHidden().frame(width: 130)
                    }
                    Button { addCost() } label: { Image(systemName: "plus") }
                        .disabled(newCostDesc.isEmpty || Double(newCostAmount.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
        }
    }

    private func addCost() {
        let amt = Double(newCostAmount.replacingOccurrences(of: ",", with: ".")) ?? 0
        let cost = Cost(
            details: newCostDesc,
            amount: amt,
            frequency: newCostFreq,
            dueDate: newCostHasDue ? newCostDue : nil
        )
        cost.customer = customer
        modelContext.insert(cost)
        try? modelContext.save()
        newCostDesc = ""
        newCostAmount = ""
    }

    // MARK: Invoices

    @State private var invoiceToDelete: Invoice?

    private var invoicesCard: some View {
        Card("Rechnungen", subtitle: "\(customer.invoices.count)") {
            VStack(spacing: 0) {
                if customer.invoices.isEmpty {
                    Text("Keine Rechnungen.")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                } else {
                    ForEach(customer.invoices.sorted(by: { $0.date > $1.date })) { inv in
                        HStack(spacing: 8) {
                            NavigationLink {
                                InvoiceDetailView(invoice: inv)
                            } label: {
                                HStack {
                                    Text(inv.number).font(.system(.callout, design: .monospaced))
                                    Text(DateFmt.short(inv.date)).foregroundStyle(.secondary)
                                    Spacer()
                                    StatusPill(text: inv.status.title, color: invStatusColor(inv.status))
                                    Text(Money.format(inv.total)).monospacedDigit().bold()
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)

                            Button {
                                invoiceToDelete = inv
                            } label: {
                                Image(systemName: "trash").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Rechnung löschen")
                        }
                        Divider()
                    }
                }
            }
        }
        .alert("Rechnung wirklich löschen?",
               isPresented: Binding(
                get: { invoiceToDelete != nil },
                set: { if !$0 { invoiceToDelete = nil } }
               )) {
            Button("Abbrechen", role: .cancel) { invoiceToDelete = nil }
            Button("Löschen", role: .destructive) {
                if let inv = invoiceToDelete {
                    deleteInvoice(inv)
                }
                invoiceToDelete = nil
            }
        } message: {
            if let inv = invoiceToDelete {
                Text("Rechnung \(inv.number) über \(Money.format(inv.total)) wird gelöscht.")
            }
        }
    }

    private func deleteInvoice(_ invoice: Invoice) {
        // If this invoice was generated from an upload, detach the upload's
        // link so we don't immediately re-create it on next sync.
        for up in customer.uploadedInvoices where up.invoiceID == invoice.id {
            up.invoiceID = nil
        }
        modelContext.delete(invoice)
        try? modelContext.save()
    }

    private func invStatusColor(_ s: InvoiceStatus) -> Color {
        switch s {
        case .draft: .gray
        case .sent: .blue
        case .paid: .green
        case .overdue: .red
        }
    }

    // MARK: Uploads

    private var uploadsCard: some View {
        Card("Rechnungen hochladen", subtitle: "OCR + KI erkennen Brutto/MwSt./Datum") {
            VStack(spacing: 8) {
                Button {
                    showInvoiceImporter = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.doc")
                        Text("PDF auswählen…")
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                if let status = importStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }

                ForEach(customer.uploadedInvoices.sorted(by: { $0.uploadedAt > $1.uploadedAt })) { up in
                    HStack {
                        Image(systemName: "doc.text.fill").foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(up.filename).font(.system(.callout, design: .monospaced))
                            HStack(spacing: 8) {
                                Text(DateFmt.short(up.extractedDate)).font(.caption).foregroundStyle(.secondary)
                                if let total = up.extractedTotal {
                                    Text("Brutto \(Money.format(total))").font(.caption).foregroundStyle(.green)
                                }
                                if let vat = up.extractedVat {
                                    Text("MwSt. \(Money.format(vat))").font(.caption).foregroundStyle(.secondary)
                                }
                                if up.status == .manual {
                                    Text("Manuell prüfen").font(.caption).foregroundStyle(.orange)
                                }
                                if let linked = linkedInvoice(for: up) {
                                    Text("→ \(linked.number)")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        Spacer()
                        if let url = up.fileURL {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Image(systemName: "eye")
                            }
                            .buttonStyle(.borderless)
                            .help("PDF öffnen")
                        }
                        Button {
                            deleteUpload(up)
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Upload und zugehörige Rechnung löschen")
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
        .fileImporter(
            isPresented: $showInvoiceImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImport(result: result) }
        }
    }

    @MainActor
    private func handleImport(result: Result<[URL], Error>) async {
        guard case .success(let urls) = result, let url = urls.first else { return }
        importStatus = "Lese PDF…"
        guard url.startAccessingSecurityScopedResource() else {
            importStatus = "Kein Zugriff auf Datei."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let savedURL = try saveUploadedFile(data: data, originalName: url.lastPathComponent, customer: customer)
            importStatus = "OCR läuft…"
            let (text, usedOCR) = try await OCRService.extractText(from: data)
            importStatus = usedOCR ? "Text per OCR extrahiert. KI erkennt Beträge…" : "Text aus PDF gelesen. KI erkennt Beträge…"

            var extractedTotal: Double?, extractedNet: Double?, extractedVat: Double?
            var extractedDate: Date?
            if let workspace, let service = OpenAIService(workspace: workspace) {
                if let parsed = try? await service.extractTotals(fromOCRText: text) {
                    extractedTotal = parsed.total
                    extractedNet = parsed.net
                    extractedVat = parsed.vat
                    if let s = parsed.date {
                        let f = DateFormatter()
                        f.dateFormat = "yyyy-MM-dd"
                        extractedDate = f.date(from: s)
                    }
                }
            }

            let parseStatus: UploadedInvoice.ParseStatus = extractedTotal != nil ? .parsed : .manual
            let up = UploadedInvoice(
                filename: url.lastPathComponent,
                fileURL: savedURL,
                extractedTotal: extractedTotal,
                extractedNet: extractedNet,
                extractedVat: extractedVat,
                extractedDate: extractedDate,
                extractedRaw: String(text.prefix(4000)),
                status: parseStatus
            )
            up.customer = customer
            modelContext.insert(up)

            // Mirror successful uploads into a real Invoice so they
            // show up in KPIs and the global list.
            if parseStatus == .parsed {
                createInvoice(from: up)
            }

            try? modelContext.save()
            importStatus = parseStatus == .parsed ? "Erkannt: Brutto \(Money.format(extractedTotal ?? 0)) — als Rechnung übernommen." : "Beträge nicht erkannt. Bitte manuell prüfen."
        } catch {
            importStatus = "Fehler: \(error.localizedDescription)"
        }
    }

    private func linkedInvoice(for upload: UploadedInvoice) -> Invoice? {
        guard let id = upload.invoiceID else { return nil }
        return customer.invoices.first(where: { $0.id == id })
    }

    private func deleteUpload(_ upload: UploadedInvoice) {
        if let inv = linkedInvoice(for: upload) {
            modelContext.delete(inv)
        }
        if let url = upload.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(upload)
        try? modelContext.save()
    }

    /// Generate an `Invoice` from an already-parsed upload. Idempotent:
    /// returns early if the upload already has a linked invoice.
    @discardableResult
    private func createInvoice(from upload: UploadedInvoice) -> Invoice? {
        if upload.invoiceID != nil { return nil }
        guard let total = upload.extractedTotal else { return nil }

        let net: Double
        let vat: Double
        let vatRate: Double
        if let n = upload.extractedNet, let v = upload.extractedVat, n > 0 {
            net = n
            vat = v
            vatRate = (vat / net * 100).rounded()
        } else if let n = upload.extractedNet {
            net = n
            vat = (total - n).rounded2()
            vatRate = n > 0 ? (vat / n * 100).rounded() : (workspace?.vatRate ?? 19)
        } else if let v = upload.extractedVat {
            vat = v
            net = (total - v).rounded2()
            vatRate = net > 0 ? (vat / net * 100).rounded() : (workspace?.vatRate ?? 19)
        } else {
            let rate = workspace?.vatRate ?? 19
            net = (total / (1 + rate / 100)).rounded2()
            vat = (total - net).rounded2()
            vatRate = rate
        }

        let number = "IMP-\(upload.id.uuidString.prefix(8))"
        let invoice = Invoice(
            number: number,
            date: upload.extractedDate ?? Date(),
            dueDate: nil,
            status: .paid,
            subtotal: net,
            vatRate: vatRate,
            vatAmount: vat,
            total: total,
            notes: "Importiert aus Upload: \(upload.filename)"
        )
        invoice.customer = customer

        let item = InvoiceItem(
            details: "Importierte Rechnung: \(upload.filename)",
            quantity: 1,
            unitPrice: net,
            order: 0
        )
        item.invoice = invoice
        invoice.items.append(item)

        modelContext.insert(invoice)
        modelContext.insert(item)
        upload.invoiceID = invoice.id
        return invoice
    }

    /// Pull-forward fix for uploads that exist from before the auto-create
    /// behavior was added. Runs once when the customer view appears.
    private func syncParsedUploads() {
        var changed = false
        for up in customer.uploadedInvoices where up.invoiceID == nil && up.status == .parsed {
            if createInvoice(from: up) != nil { changed = true }
        }
        if changed { try? modelContext.save() }
    }

    // MARK: Cash income (off-the-books)

    @State private var newCashDesc = ""
    @State private var newCashAmount = ""
    @State private var newCashDate = Date()
    @State private var newCashNotes = ""

    private var cashIncomeCard: some View {
        Card("Bareinnahmen (ohne Rechnung)",
             subtitle: customer.cashIncomes.isEmpty
                 ? "Nur für deine eigene Übersicht — fließt in Umsatz brutto ein"
                 : "\(customer.cashIncomes.count) Einträge · \(Money.format(customer.totalCashIncome))") {
            VStack(spacing: 0) {
                ForEach(customer.cashIncomes.sorted(by: { $0.date > $1.date })) { cash in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cash.details).fontWeight(.medium)
                            HStack(spacing: 6) {
                                Text(DateFmt.short(cash.date))
                                    .font(.caption).foregroundStyle(.secondary)
                                if !cash.notes.isEmpty {
                                    Text(cash.notes)
                                        .font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer()
                        Text(Money.format(cash.amount)).monospacedDigit().fontWeight(.medium)
                        Button {
                            modelContext.delete(cash)
                            try? modelContext.save()
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
                if customer.cashIncomes.isEmpty {
                    Text("Noch keine Bareinnahmen erfasst.")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                }

                Divider().padding(.vertical, 6)
                VStack(spacing: 6) {
                    HStack {
                        TextField("Wofür (z. B. Website Cash)", text: $newCashDesc)
                            .textFieldStyle(.roundedBorder)
                        TextField("€", text: $newCashAmount)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        DatePicker("", selection: $newCashDate, displayedComponents: .date)
                            .labelsHidden().frame(width: 130)
                        Button {
                            addCashIncome()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(newCashDesc.trimmingCharacters(in: .whitespaces).isEmpty
                            || Double(newCashAmount.replacingOccurrences(of: ",", with: ".")) == nil)
                    }
                    TextField("Notiz (optional)", text: $newCashNotes)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func addCashIncome() {
        let desc = newCashDesc.trimmingCharacters(in: .whitespaces)
        let amt = Double(newCashAmount.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard !desc.isEmpty, amt > 0 else { return }
        let cash = CashIncome(
            details: desc,
            amount: amt,
            date: newCashDate,
            notes: newCashNotes
        )
        cash.customer = customer
        modelContext.insert(cash)
        try? modelContext.save()
        newCashDesc = ""
        newCashAmount = ""
        newCashNotes = ""
        newCashDate = Date()
    }

    private func saveUploadedFile(data: Data, originalName: String, customer: Customer) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport
            .appendingPathComponent("FyluAgency", isDirectory: true)
            .appendingPathComponent("uploads", isDirectory: true)
            .appendingPathComponent(customer.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = originalName.replacingOccurrences(of: "/", with: "_")
        let url = dir.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(safe)")
        try data.write(to: url)
        return url
    }

    // MARK: Stammdaten

    private var stammdatenCard: some View {
        Card("Stammdaten") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledField(label: "Name", text: $customer.name)
                LabeledField(label: "Firma", text: $customer.company)
                LabeledField(label: "E-Mail", text: $customer.email)
                LabeledField(label: "Telefon", text: $customer.phone)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Adresse").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $customer.address).frame(minHeight: 70)
                        .border(Color.gray.opacity(0.2))
                }
                LabeledField(label: "USt-ID", text: $customer.taxId)
            }
        }
    }

    private var notesCard: some View {
        Card("Notizen") {
            TextEditor(text: $customer.notes)
                .frame(minHeight: 200)
                .border(Color.gray.opacity(0.2))
        }
    }
}

// MARK: - Row views

struct IssueRow: View {
    @Bindable var issue: Issue
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                issue.toggle()
                try? modelContext.save()
            } label: {
                Image(systemName: issue.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(issue.done ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title)
                    .strikethrough(issue.done)
                    .foregroundStyle(issue.done ? .secondary : .primary)
                if !issue.details.isEmpty {
                    Text(issue.details).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let p = issue.price {
                Text(Money.format(p)).font(.caption).foregroundStyle(.secondary)
            }

            Button {
                modelContext.delete(issue)
                try? modelContext.save()
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        Divider()
    }
}

struct CostRow: View {
    @Bindable var cost: Cost
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(cost.details).fontWeight(.medium)
                HStack(spacing: 6) {
                    StatusPill(text: cost.frequency.title, color: .gray)
                    if let due = cost.dueDate {
                        Text("fällig \(DateFmt.short(due))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(Money.format(cost.amount)).monospacedDigit().fontWeight(.medium)
            Button {
                modelContext.delete(cost)
                try? modelContext.save()
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        Divider()
    }
}

struct LabeledField: View {
    let label: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: $text).textFieldStyle(.roundedBorder)
        }
    }
}
