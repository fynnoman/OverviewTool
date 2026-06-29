import SwiftUI
import SwiftData

struct QuotesListView: View {
    let workspace: Workspace
    @Environment(\.modelContext) private var modelContext
    @State private var showNewQuote = false
    @State private var selectedQuote: Quote?

    private var quotes: [Quote] {
        workspace.customers.flatMap(\.quotes).sorted(by: { $0.date > $1.date })
    }

    private var totalAll: Double { quotes.reduce(0) { $0 + $1.total } }
    private var totalOpen: Double {
        quotes
            .filter { $0.effectiveStatus == .draft || $0.effectiveStatus == .sent }
            .reduce(0) { $0 + $1.total }
    }
    private var totalAccepted: Double {
        quotes
            .filter { $0.effectiveStatus == .accepted || $0.effectiveStatus == .converted }
            .reduce(0) { $0 + $1.total }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Angebote").font(.title2).fontWeight(.semibold)
                        Text("\(quotes.count) Angebote · \(Money.format(totalAll)) gesamt")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        showNewQuote = true
                    } label: {
                        Label("Neues Angebot", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)

                HStack(spacing: 12) {
                    KpiCard(title: "Offen", value: Money.format(totalOpen))
                    KpiCard(title: "Angenommen", value: Money.format(totalAccepted))
                    KpiCard(title: "Gesamt brutto", value: Money.format(totalAll), accent: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                Divider()

                if quotes.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Angebote",
                        systemImage: "doc.badge.plus",
                        description: Text("Leg dein erstes an.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(quotes, selection: Binding(
                        get: { selectedQuote?.id },
                        set: { id in selectedQuote = quotes.first { $0.id == id } }
                    )) {
                        TableColumn("Nr.") { q in
                            Text(q.number).font(.system(.callout, design: .monospaced))
                        }
                        TableColumn("Kunde") { q in Text(q.customer?.name ?? "—") }
                        TableColumn("Datum") { q in Text(DateFmt.short(q.date)) }
                        TableColumn("Gültig bis") { q in Text(DateFmt.short(q.validUntil)) }
                        TableColumn("Status") { q in
                            StatusPill(text: q.effectiveStatus.title, color: statusColor(q.effectiveStatus))
                        }
                        TableColumn("Netto") { q in
                            Text(Money.format(q.subtotal)).monospacedDigit()
                        }
                        TableColumn("Brutto") { q in
                            Text(Money.format(q.total)).monospacedDigit().bold()
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedQuote) { q in
                QuoteDetailView(quote: q)
            }
        }
        .sheet(isPresented: $showNewQuote) {
            QuoteComposerView(workspace: workspace) { created in
                selectedQuote = created
            }
        }
    }

    private func statusColor(_ s: QuoteStatus) -> Color {
        switch s {
        case .draft:     .gray
        case .sent:      .blue
        case .accepted:  .green
        case .declined:  .red
        case .expired:   .orange
        case .converted: .purple
        }
    }
}

struct QuoteComposerView: View {
    let workspace: Workspace
    let onCreated: (Quote) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCustomerID: UUID?
    @State private var freeText: String = ""
    @State private var isParsing = false
    @State private var parseSource: String?
    @State private var items: [ParsedInvoiceItem] = []
    @State private var date: Date = Date()
    @State private var validUntil: Date
    @State private var vatRate: Double
    @State private var notes: String = ""
    @State private var errorMessage: String?

    private var customers: [Customer] {
        workspace.customers.sorted(by: { $0.name < $1.name })
    }

    private var subtotal: Double { items.reduce(0) { $0 + $1.quantity * $1.unitPrice } }
    private var vatAmount: Double { (subtotal * vatRate / 100).rounded2() }
    private var totalBrutto: Double { (subtotal + vatAmount).rounded2() }

    init(workspace: Workspace, onCreated: @escaping (Quote) -> Void) {
        self.workspace = workspace
        self.onCreated = onCreated
        _vatRate = State(initialValue: workspace.vatRate)
        let defaultValid = Calendar.current.date(
            byAdding: .day,
            value: max(workspace.quoteValidityDays ?? 14, 1),
            to: Date()
        ) ?? Date().addingTimeInterval(60 * 60 * 24 * 14)
        _validUntil = State(initialValue: defaultValid)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Neues Angebot").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    promptCard
                    itemsCard
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 14) {
                    metaCard
                    Spacer()
                    Button {
                        save()
                    } label: {
                        if isParsing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Angebot speichern")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(selectedCustomerID == nil || items.isEmpty || isParsing)
                }
                .frame(width: 280)
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 980, height: 720)
    }

    private var promptCard: some View {
        Card("Beschreib die Leistungen — KI macht Posten daraus", subtitle: "lokales OpenAI über Responses-API") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Beispiel: „Kunde will SEO, Website und Google Ads. SEO 200, Website 800, Google Ads Leistung 200, Google Ads Budget 250\"")
                    .font(.caption).foregroundStyle(.secondary)

                TextEditor(text: $freeText)
                    .frame(minHeight: 100)
                    .border(Color.gray.opacity(0.2))

                HStack {
                    Button {
                        Task { await parse() }
                    } label: {
                        Label(isParsing ? "Lese…" : "In Posten umwandeln", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isParsing || freeText.trimmingCharacters(in: .whitespaces).isEmpty)

                    if let source = parseSource {
                        Text(source).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var itemsCard: some View {
        Card("Posten", subtitle: items.isEmpty ? "noch leer" : "\(items.count) Stück") {
            VStack(spacing: 0) {
                if items.isEmpty {
                    Text("Schreib oben rein und lass die KI parsen — oder Posten manuell hinzufügen.")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 16)
                } else {
                    ForEach($items) { $item in
                        HStack(spacing: 8) {
                            TextField("Beschreibung", text: $item.details)
                                .textFieldStyle(.roundedBorder)
                            TextField("Anzahl", value: $item.quantity, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            TextField("€ netto", value: $item.unitPrice, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Text(Money.format(item.quantity * item.unitPrice))
                                .frame(width: 90, alignment: .trailing)
                                .monospacedDigit()
                            Button {
                                items.removeAll(where: { $0.id == item.id })
                            } label: {
                                Image(systemName: "trash").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Divider().padding(.vertical, 8)

                HStack {
                    Button {
                        items.append(ParsedInvoiceItem(details: "", quantity: 1, unitPrice: 0))
                    } label: {
                        Label("Posten hinzufügen", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Netto: \(Money.format(subtotal))").font(.caption).foregroundStyle(.secondary)
                        Text("MwSt. \(Int(vatRate))%: \(Money.format(vatAmount))").font(.caption).foregroundStyle(.secondary)
                        Text("Brutto: \(Money.format(totalBrutto))").font(.callout).fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private var metaCard: some View {
        Card("Angebot") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kunde").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $selectedCustomerID) {
                        Text("— wählen —").tag(Optional<UUID>.none)
                        ForEach(customers) { c in
                            Text(c.name + (c.company.isEmpty ? "" : " · " + c.company))
                                .tag(Optional(c.id))
                        }
                    }
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Datum").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: $date, displayedComponents: .date).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gültig bis").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: $validUntil, displayedComponents: .date).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("MwSt. %").font(.caption).foregroundStyle(.secondary)
                    TextField("19", value: $vatRate, format: .number).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notiz (auf Angebot)").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $notes).frame(minHeight: 80).border(Color.gray.opacity(0.2))
                }
            }
        }
    }

    private func parse() async {
        isParsing = true
        defer { isParsing = false }
        errorMessage = nil

        if let service = OpenAIService(workspace: workspace) {
            do {
                let parsed = try await service.parseInvoiceText(freeText)
                if !parsed.isEmpty {
                    items = parsed
                    parseSource = "Quelle: OpenAI (\(workspace.openAIModel))"
                    return
                }
            } catch {
                errorMessage = "OpenAI: \(error.localizedDescription) — nutze Fallback."
            }
        } else {
            errorMessage = "Kein API-Key — Heuristik wird genutzt."
        }
        items = heuristicParse(freeText)
        parseSource = items.isEmpty ? nil : "Quelle: Heuristik (Fallback)"
    }

    private func heuristicParse(_ text: String) -> [ParsedInvoiceItem] {
        let separators = CharacterSet(charactersIn: ",\n;")
        let segments = text
            .replacingOccurrences(of: " und ", with: ", ", options: .caseInsensitive)
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var out: [ParsedInvoiceItem] = []
        for seg in segments {
            guard let match = seg.range(of: #"([0-9]+([.,][0-9]{1,2})?)"#, options: .regularExpression) else { continue }
            let priceString = String(seg[match]).replacingOccurrences(of: ",", with: ".")
            guard let price = Double(priceString) else { continue }
            var desc = seg.replacingCharacters(in: match, with: "")
                .replacingOccurrences(of: "€", with: "")
                .replacingOccurrences(of: "EUR", with: "")
                .replacingOccurrences(of: "Euro", with: "")
                .replacingOccurrences(of: "für ", with: "")
                .replacingOccurrences(of: "nehme ich ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ":-–—"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if desc.isEmpty { continue }
            desc = desc.prefix(1).uppercased() + desc.dropFirst()
            out.append(ParsedInvoiceItem(details: desc, quantity: 1, unitPrice: price))
        }
        return out
    }

    private func save() {
        guard let customerID = selectedCustomerID,
              let customer = customers.first(where: { $0.id == customerID })
        else { return }

        let number = workspace.consumeNextQuoteNumber()

        let quote = Quote(
            number: number,
            date: date,
            validUntil: validUntil,
            vatRate: vatRate,
            notes: notes
        )
        quote.customer = customer

        var order = 0
        for it in items where !it.details.isEmpty {
            let item = QuoteItem(
                details: it.details,
                quantity: it.quantity,
                unitPrice: it.unitPrice,
                order: order
            )
            item.quote = quote
            quote.items.append(item)
            modelContext.insert(item)
            order += 1
        }

        modelContext.insert(quote)
        quote.recompute()
        try? modelContext.save()
        onCreated(quote)
        dismiss()
    }
}
