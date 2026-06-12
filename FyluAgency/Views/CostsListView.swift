import SwiftUI
import SwiftData

/// Globale Kosten-Übersicht: Kunden-Kosten + absetzbare Ausgaben,
/// suchbar (Text, Kunde, Kategorie), filterbar (Typ, Zeitraum).
struct CostsListView: View {
    let workspace: Workspace
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var typeFilter: TypeFilter = .all
    @State private var rangeFilter: DashboardRange = .all
    @State private var customerFilterID: UUID?

    @State private var showAddSheet = false

    enum TypeFilter: String, CaseIterable, Identifiable {
        case all, customer, deductible
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all:        "Alle"
            case .customer:   "Kunden-Kosten"
            case .deductible: "Absetzbar"
            }
        }
    }

    // MARK: - Datenquellen

    private var customers: [Customer] { workspace.customers.sorted(by: { $0.name < $1.name }) }

    private var allCustomerCostCostListRows: [CostListRow] {
        workspace.customers.flatMap { customer in
            customer.costs.map { CostListRow.customerCost($0, customer) }
        }
    }

    private var allDeductibleCostListRows: [CostListRow] {
        workspace.deductibleExpenses.map { CostListRow.deductible($0) }
    }

    private var filteredCostListRows: [CostListRow] {
        let typed: [CostListRow]
        switch typeFilter {
        case .all:        typed = allCustomerCostCostListRows + allDeductibleCostListRows
        case .customer:   typed = allCustomerCostCostListRows
        case .deductible: typed = allDeductibleCostListRows
        }

        let start = rangeFilter.startDate()
        let inRange = typed.filter { row in
            guard let start else { return true }
            return row.date >= start
        }

        let byCustomer = inRange.filter { row in
            guard let id = customerFilterID else { return true }
            return row.customerID == id
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return byCustomer.sorted(by: { $0.date > $1.date }) }
        return byCustomer
            .filter { row in row.matches(q) }
            .sorted(by: { $0.date > $1.date })
    }

    // MARK: - Summen

    private var customerCostTotal: Double {
        filteredCostListRows.compactMap { row -> Double? in
            if case .customerCost(let c, _) = row { return c.amount } else { return nil }
        }.reduce(0, +)
    }
    private var deductibleTotal: Double {
        filteredCostListRows.compactMap { row -> Double? in
            if case .deductible(let e) = row { return e.amount } else { return nil }
        }.reduce(0, +)
    }
    private var vorsteuerTotal: Double {
        filteredCostListRows.compactMap { row -> Double? in
            if case .deductible(let e) = row { return e.vatAmount } else { return nil }
        }.reduce(0, +)
    }
    private var grandTotal: Double { customerCostTotal + deductibleTotal }

    // MARK: - View

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                kpiCostListRow
                filterBar
                table
            }
            .padding(20)
        }
        .sheet(isPresented: $showAddSheet) {
            AddDeductibleSheet(workspace: workspace)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Kosten").font(.title2).fontWeight(.semibold)
                Text("Alle Ausgaben — pro Kunde verrechnet oder absetzbar (Vorsteuer).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showAddSheet = true
            } label: {
                Label("Absetzbare Ausgabe", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var kpiCostListRow: some View {
        HStack(spacing: 12) {
            KpiCard(title: "Gesamt", value: Money.format(grandTotal), accent: true)
            KpiCard(title: "Kunden-Kosten", value: Money.format(customerCostTotal), muted: true)
            KpiCard(title: "Absetzbar", value: Money.format(deductibleTotal), muted: true)
            KpiCard(title: "Vorsteuer", value: Money.format(vorsteuerTotal), tone: vorsteuerTotal > 0 ? .positive : .neutral)
            KpiCard(title: "Einträge", value: "\(filteredCostListRows.count)", muted: true)
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Suche nach Beschreibung, Kunde, Kategorie, Notiz…", text: $searchText)
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

            HStack(spacing: 12) {
                Picker("Typ", selection: $typeFilter) {
                    ForEach(TypeFilter.allCases) { t in
                        Text(t.title).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Picker("Zeitraum", selection: $rangeFilter) {
                    ForEach(DashboardRange.allCases) { r in
                        Text(r.title).tag(r)
                    }
                }
                .frame(width: 140)

                Picker("Kunde", selection: $customerFilterID) {
                    Text("Alle Kunden").tag(Optional<UUID>.none)
                    ForEach(customers) { c in
                        Text(c.name).tag(Optional(c.id))
                    }
                }
                .frame(width: 200)

                Spacer()

                if customerFilterID != nil || rangeFilter != .all || typeFilter != .all || !searchText.isEmpty {
                    Button("Filter zurücksetzen") {
                        searchText = ""
                        customerFilterID = nil
                        rangeFilter = .all
                        typeFilter = .all
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Datum").frame(width: 100, alignment: .leading)
                Text("Typ").frame(width: 110, alignment: .leading)
                Text("Beschreibung").frame(maxWidth: .infinity, alignment: .leading)
                Text("Kategorie").frame(width: 140, alignment: .leading)
                Text("Brutto").frame(width: 90, alignment: .trailing)
                Text("MwSt.").frame(width: 80, alignment: .trailing)
                Spacer().frame(width: 32)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.vertical, 6)
            Divider()

            if filteredCostListRows.isEmpty {
                ContentUnavailableView(
                    "Keine Einträge",
                    systemImage: "tray",
                    description: Text("Keine Kosten gefunden — passe Suche oder Filter an, oder lege eine absetzbare Ausgabe an.")
                )
                .frame(minHeight: 200)
            } else {
                ForEach(filteredCostListRows) { row in
                    CostCostListRowView(row: row, modelContext: modelContext)
                    Divider()
                }
            }
        }
        .background(Color.gray.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.15))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - CostListRow model + view

enum CostListRow: Identifiable {
    case customerCost(Cost, Customer)
    case deductible(DeductibleExpense)

    var id: String {
        switch self {
        case .customerCost(let c, _): "c-\(c.id.uuidString)"
        case .deductible(let e):      "d-\(e.id.uuidString)"
        }
    }
    var date: Date {
        switch self {
        case .customerCost(let c, _): c.dueDate ?? c.createdAt
        case .deductible(let e):      e.date
        }
    }
    var customerID: UUID? {
        switch self {
        case .customerCost(_, let c): c.id
        case .deductible:             nil
        }
    }

    func matches(_ q: String) -> Bool {
        switch self {
        case .customerCost(let c, let cust):
            return c.details.lowercased().contains(q)
                || cust.name.lowercased().contains(q)
                || cust.company.lowercased().contains(q)
        case .deductible(let e):
            return e.details.lowercased().contains(q)
                || e.category.lowercased().contains(q)
                || e.notes.lowercased().contains(q)
        }
    }
}

private struct CostCostListRowView: View {
    let row: CostListRow
    let modelContext: ModelContext

    var body: some View {
        HStack {
            Text(DateFmt.short(row.date))
                .frame(width: 100, alignment: .leading)
                .font(.callout).monospacedDigit()

            switch row {
            case .customerCost(let cost, let customer):
                StatusPill(text: customer.name, color: .blue)
                    .frame(width: 110, alignment: .leading)
                Text(cost.details)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(cost.frequency.title)
                    .frame(width: 140, alignment: .leading)
                    .font(.caption).foregroundStyle(.secondary)
                Text(Money.format(cost.amount))
                    .frame(width: 90, alignment: .trailing).monospacedDigit()
                Text("—")
                    .frame(width: 80, alignment: .trailing).foregroundStyle(.tertiary)

            case .deductible(let exp):
                StatusPill(text: "Absetzbar", color: .green)
                    .frame(width: 110, alignment: .leading)
                Text(exp.details)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(exp.category.isEmpty ? "—" : exp.category)
                    .frame(width: 140, alignment: .leading)
                    .font(.caption).foregroundStyle(.secondary)
                Text(Money.format(exp.amount))
                    .frame(width: 90, alignment: .trailing).monospacedDigit()
                Text(Money.format(exp.vatAmount))
                    .frame(width: 80, alignment: .trailing).monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Button {
                deleteCostListRow()
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 32)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
    }

    private func deleteCostListRow() {
        switch row {
        case .customerCost(let c, _): modelContext.delete(c)
        case .deductible(let e):      modelContext.delete(e)
        }
        try? modelContext.save()
    }
}

// MARK: - Sheet zum Anlegen

private struct AddDeductibleSheet: View {
    let workspace: Workspace
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var details = ""
    @State private var category = ""
    @State private var amountStr = ""
    @State private var vatRateStr = "19"
    @State private var date = Date()
    @State private var notes = ""

    private static let categories = [
        "Material", "Werkzeug", "Büro", "Fahrtkosten",
        "Telefon / Internet", "Software / Lizenzen",
        "Werbung / Marketing", "Versicherung", "Fortbildung",
        "Steuerberater", "Bewirtung", "Sonstiges"
    ]

    private var amount: Double {
        Double(amountStr.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var vatRate: Double {
        Double(vatRateStr.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var vatAmount: Double {
        guard vatRate > 0 else { return 0 }
        let net = amount / (1 + vatRate / 100)
        return (amount - net).rounded2()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Absetzbare Ausgabe").font(.title3).fontWeight(.semibold)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Beschreibung *").font(.caption).foregroundStyle(.secondary)
                TextField("z. B. Akku-Bohrmaschine", text: $details)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Kategorie").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $category) {
                        Text("— wählen —").tag("")
                        ForEach(Self.categories, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                    .labelsHidden()
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Datum").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: $date, displayedComponents: .date).labelsHidden()
                }
                .frame(width: 180)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Brutto € *").font(.caption).foregroundStyle(.secondary)
                    TextField("0,00", text: $amountStr).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("MwSt-Satz %").font(.caption).foregroundStyle(.secondary)
                    TextField("19", text: $vatRateStr).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Vorsteuer (berechnet)").font(.caption).foregroundStyle(.secondary)
                    Text(Money.format(vatAmount))
                        .font(.callout).monospacedDigit()
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notiz (optional)").font(.caption).foregroundStyle(.secondary)
                TextField("z. B. Rechnungsnr., Quelle…", text: $notes)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Speichern") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(details.trimmingCharacters(in: .whitespaces).isEmpty || amount <= 0)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func save() {
        let expense = DeductibleExpense(
            details: details.trimmingCharacters(in: .whitespaces),
            amount: amount.rounded2(),
            vatAmount: vatAmount,
            date: date,
            category: category,
            notes: notes
        )
        expense.workspace = workspace
        modelContext.insert(expense)
        try? modelContext.save()
        dismiss()
    }
}
