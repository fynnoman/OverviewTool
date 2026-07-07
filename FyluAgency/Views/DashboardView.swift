import SwiftUI
import SwiftData
import Charts

enum DashboardRange: String, CaseIterable, Identifiable {
    case today, week, month, quarter, year, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today:   "Heute"
        case .week:    "Woche"
        case .month:   "Monat"
        case .quarter: "Quartal"
        case .year:    "Jahr"
        case .all:     "Gesamt"
        }
    }

    var longTitle: String {
        switch self {
        case .today:   "Heute"
        case .week:    "Diese Woche"
        case .month:   "Diesen Monat"
        case .quarter: "Dieses Quartal"
        case .year:    "Dieses Jahr"
        case .all:     "Gesamt"
        }
    }

    func startDate() -> Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .today:   return cal.startOfDay(for: now)
        case .week:    return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))
        case .month:   return cal.date(from: cal.dateComponents([.year, .month], from: now))
        case .quarter:
            let month = cal.component(.month, from: now)
            let qStartMonth = ((month - 1) / 3) * 3 + 1
            var comps = cal.dateComponents([.year], from: now)
            comps.month = qStartMonth
            comps.day = 1
            return cal.date(from: comps)
        case .year:    return cal.date(from: cal.dateComponents([.year], from: now))
        case .all:     return nil
        }
    }

    /// Q1 / Q2 / Q3 / Q4 — nur sinnvoll für .quarter.
    static var currentQuarterLabel: String {
        let month = Calendar.current.component(.month, from: Date())
        return "Q\((month - 1) / 3 + 1)"
    }
}

struct DashboardView: View {
    let workspace: Workspace
    @Environment(\.modelContext) private var modelContext
    @State private var range: DashboardRange = .month
    /// Months offset from "now" for the .month range. 0 = current month,
    /// -1 = last month, etc. Reset whenever `range` leaves `.month`.
    @State private var monthOffset: Int = 0
    @State private var upsells: [(customer: Customer, headline: String, reason: String, amount: Double)] = []
    @State private var isLoadingUpsells = false
    @State private var upsellError: String?
    @State private var upsellSource: String?
    @State private var showGrossDetail = false
    /// Inline-Eingabe für den AI-Profil-Banner ganz oben. Wird beim Laden
    /// und beim Workspace-Wechsel aus `workspace.businessProfile` befüllt.
    @State private var profileDraft: String = ""
    @State private var isSavingProfile: Bool = false
    /// Wenn ein Profil schon existiert, zeigen wir eine kompakte Karte —
    /// dieser Flag klappt den Editor auf, damit der Kontext nachträglich
    /// erweitert / korrigiert werden kann (früher war das nach dem ersten
    /// Speichern nicht mehr möglich).
    @State private var isEditingProfile: Bool = false

    private var invoices: [Invoice] {
        workspace.customers.flatMap(\.invoices)
    }

    /// Reference date inside the month the user is currently looking at.
    /// Only meaningful when `range == .month`.
    private var monthAnchor: Date {
        Calendar.current.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: monthAnchor).capitalized
    }

    /// Lower bound for the active range. For `.month` we override the
    /// default (start of current month) with the start of `monthAnchor`'s
    /// month so the user can scroll back to e.g. January.
    private var rangeStart: Date? {
        if range == .month {
            let cal = Calendar.current
            return cal.date(from: cal.dateComponents([.year, .month], from: monthAnchor))
        }
        return range.startDate()
    }

    /// Upper bound — only set when looking at a bounded historical period.
    /// `nil` means "no upper bound" (everything up to now is included).
    private var rangeEnd: Date? {
        if range == .month, let start = rangeStart {
            return Calendar.current.date(byAdding: .month, value: 1, to: start)
        }
        return nil
    }

    private func inRange(_ d: Date) -> Bool {
        if let start = rangeStart, d < start { return false }
        if let end = rangeEnd, d >= end { return false }
        return true
    }

    private var filteredInvoices: [Invoice] {
        invoices.filter { inRange($0.date) }
    }

    private var grossTotal: Double { filteredInvoices.reduce(0) { $0 + $1.total } }
    private var netTotal: Double { filteredInvoices.reduce(0) { $0 + $1.subtotal } }
    private var vatTotal: Double { filteredInvoices.reduce(0) { $0 + $1.vatAmount } }
    private var paidTotal: Double {
        filteredInvoices.filter { $0.status == .paid }.reduce(0) { $0 + $1.total }
    }
    private var openTotal: Double {
        filteredInvoices.filter { $0.status != .paid }.reduce(0) { $0 + $1.total }
    }

    private var filteredCustomerCosts: [Cost] {
        workspace.customers.flatMap(\.costs).filter { inRange($0.dueDate ?? $0.createdAt) }
    }

    private var costsTotal: Double {
        filteredCustomerCosts.reduce(0) { $0 + $1.amount }
    }

    private var cashIncomeTotal: Double {
        workspace.customers.flatMap(\.cashIncomes)
            .filter { inRange($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    private var profitTotal: Double { grossTotal + cashIncomeTotal - costsTotal }

    // —— Steuer-Schätzung auf den Range-Profit ——
    // Tax wird auf JAHRES-zvE berechnet, dann anteilig auf den Range-Profit angewandt.
    private var workspaceYearProfit: Double {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        let yearInvoiceNet = workspace.customers.flatMap(\.invoices)
            .filter { cal.component(.year, from: $0.date) == year }
            .reduce(0) { $0 + $1.subtotal }
        let yearCosts = workspace.customers.flatMap(\.costs)
            .filter { c in cal.component(.year, from: c.dueDate ?? c.createdAt) == year }
            .reduce(0) { $0 + $1.amount }
        let yearDeductibleNet = workspace.deductibleExpenses
            .filter { cal.component(.year, from: $0.date) == year }
            .reduce(0) { $0 + $1.net }
        return yearInvoiceNet - yearCosts - yearDeductibleNet
    }

    private var effectiveTaxRate: Double {
        let yp = workspaceYearProfit
        guard yp > 0 else { return 0 }
        return TaxView.germanIncomeTax(zvE: yp) / yp
    }

    /// USt-Zahllast im aktuellen Range: MwSt aus Rechnungen − Vorsteuer aus absetzbaren Ausgaben.
    /// Cash-Einnahmen bleiben außen vor (steuerfrei). Mindestens 0 — Vorsteuer-Überhänge
    /// werden im Folgemonat verrechnet, drücken aber nicht den aktuellen Gewinn nach oben.
    private var ustZahllastInRange: Double {
        max(0, vatTotal - vorsteuerTotal)
    }

    /// Anteilige Einkommensteuer auf den Gewinn im aktuellen Range.
    private var incomeTaxOnRangeProfit: Double {
        profitTotal * effectiveTaxRate
    }

    /// Tatsächlich übrig bleibendes Geld: Gewinn brutto − USt-Zahllast − geschätzte ESt.
    private var profitAfterTaxesTotal: Double {
        profitTotal - ustZahllastInRange - incomeTaxOnRangeProfit
    }

    private var filteredDeductibleExpenses: [DeductibleExpense] {
        workspace.deductibleExpenses.filter { inRange($0.date) }
    }

    private var deductibleTotal: Double {
        filteredDeductibleExpenses.reduce(0) { $0 + $1.amount }
    }

    private var vorsteuerTotal: Double {
        filteredDeductibleExpenses.reduce(0) { $0 + $1.vatAmount }
    }

    private var openIssuesValue: Double {
        workspace.customers.flatMap(\.issues).filter { !$0.done }.compactMap(\.price).reduce(0, +)
    }
    private var openIssuesCount: Int {
        workspace.customers.flatMap(\.issues).filter { !$0.done }.count
    }
    private var openLeadValue: Double {
        workspace.leads
            .filter { $0.status != .lost && $0.status != .won }
            .compactMap(\.expectedValue)
            .reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Header(workspace: workspace, range: $range)

                aiProfileBanner

                if range == .month {
                    monthNavigator
                }

                kpiRow

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        chartCard
                        upsellCard
                        overdueCard
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 16) {
                        followUpCard
                        openIssuesCard
                        leadsCard
                    }
                    .frame(width: 320)
                }
            }
            .padding(20)
        }
        .task(id: workspace.id) {
            profileDraft = workspace.businessProfile ?? ""
            await refreshUpsells()
        }
        .onChange(of: range) { _, newValue in
            if newValue != .month { monthOffset = 0 }
        }
        .sheet(isPresented: $showGrossDetail) {
            GrossInvoicesDetailView(
                invoices: filteredInvoices,
                rangeTitle: rangeDisplayTitle,
                total: grossTotal
            )
        }
    }

    /// Label used in the detail sheet and elsewhere. Mirrors `range.longTitle`
    /// but for `.month` falls back to the actual month name when the user has
    /// scrolled away from the current month.
    private var rangeDisplayTitle: String {
        if range == .month && monthOffset != 0 { return monthLabel }
        return range.longTitle
    }

    /// KI-Kontext-Karte ganz oben. Zwei Zustände:
    ///  - **leer**: prominenter Setup-Block mit Editor, damit klar ist, dass
    ///    die KI ohne Kontext generisch rät (früher: „Webdesign-Agentur").
    ///  - **gesetzt**: kompakte Zeile mit dem aktuellen Profiltext + einem
    ///    „Bearbeiten"-Button, der den Editor wieder ausklappt. Ohne die
    ///    Bearbeiten-Option verschwand die Eingabe nach dem ersten
    ///    Speichern komplett — Kontext nachträglich zu erweitern war so
    ///    nicht mehr möglich.
    @ViewBuilder
    private var aiProfileBanner: some View {
        let profile = (workspace.businessProfile ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmpty = profile.isEmpty

        if isEmpty || isEditingProfile {
            profileEditor(isFirstTimeSetup: isEmpty)
        } else {
            profileSummary(profile: profile)
        }
    }

    private func profileEditor(isFirstTimeSetup: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text(isFirstTimeSetup
                     ? "KI braucht noch Kontext für \"\(workspace.name)\""
                     : "KI-Kontext für \"\(workspace.name)\" bearbeiten")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if !isFirstTimeSetup {
                    Button("Abbrechen") {
                        profileDraft = workspace.businessProfile ?? ""
                        isEditingProfile = false
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            Text("Beschreib kurz, was dieser Workspace verkauft — z. B. \"Software für Gebäudereiniger, B2B, 49–249 €/Monat\". Sonst rät die KI generisch (oft Webdesign), weil sie's nicht besser weiß.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $profileDraft)
                .frame(minHeight: 90)
                .border(Color.gray.opacity(0.25))
            HStack {
                Button {
                    saveProfileFromBanner()
                } label: {
                    Label(isSavingProfile ? "Speichere…" : "Speichern & KI neu laden",
                          systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSavingProfile || profileDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("Detailliertere Felder findest du in den Einstellungen → KI-Profil.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.35))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func profileSummary(profile: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("KI-Kontext")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(profile)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 8)
            Button {
                profileDraft = workspace.businessProfile ?? ""
                isEditingProfile = true
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.2))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func saveProfileFromBanner() {
        let trimmed = profileDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSavingProfile = true
        workspace.businessProfile = trimmed
        workspace.updatedAt = Date()
        try? modelContext.save()
        isEditingProfile = false
        Task {
            await refreshUpsells(force: true)
            isSavingProfile = false
        }
    }

    private var monthNavigator: some View {
        HStack(spacing: 10) {
            Button {
                monthOffset -= 1
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .help("Vorheriger Monat")

            Text(monthLabel)
                .font(.callout).fontWeight(.semibold)
                .frame(minWidth: 150, alignment: .center)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(Color.gray.opacity(0.06))
                .clipShape(Capsule())

            Button {
                monthOffset += 1
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(monthOffset >= 0)
            .help("Nächster Monat")

            if monthOffset != 0 {
                Button("Aktueller Monat") {
                    monthOffset = 0
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
            }

            Spacer()
        }
    }

    private var kpiRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                KpiCard(title: "Brutto (steuerpflichtig)", value: Money.format(grossTotal), accent: true)
                    .contentShape(Rectangle())
                    .onTapGesture { showGrossDetail = true }
                    .help("Tippen, um die Rechnungen dieser Periode zu sehen")
                KpiCard(
                    title: "Bar (ohne Rechnung)",
                    value: Money.format(cashIncomeTotal),
                    tone: cashIncomeTotal > 0 ? .positive : .neutral
                )
                KpiCard(title: "Kosten", value: Money.format(costsTotal), muted: true)
                KpiCard(
                    title: "Gewinn (nach Steuern)",
                    value: Money.format(profitAfterTaxesTotal),
                    tone: profitAfterTaxesTotal < 0 ? .danger : (profitAfterTaxesTotal > 0 ? .positive : .neutral)
                )
            }
            HStack(spacing: 12) {
                KpiCard(title: "Netto", value: Money.format(netTotal), muted: true)
                KpiCard(title: "MwSt.", value: Money.format(vatTotal), muted: true)
                KpiCard(title: "Absetzbare Ausgaben", value: Money.format(deductibleTotal), muted: true)
                KpiCard(title: "Vorsteuer", value: Money.format(vorsteuerTotal), muted: true)
            }
            HStack(spacing: 12) {
                KpiCard(
                    title: "Ausstehend (offene Aufträge)",
                    value: "\(openIssuesCount) · \(Money.format(openIssuesValue))",
                    tone: openIssuesValue > 0 ? .positive : .neutral
                )
                KpiCard(
                    title: "Lead-Pipeline",
                    value: Money.format(openLeadValue),
                    tone: openLeadValue > 0 ? .positive : .neutral
                )
                KpiCard(
                    title: "Potenzial gesamt",
                    value: Money.format(openIssuesValue + openLeadValue),
                    accent: openIssuesValue + openLeadValue > 0
                )
                KpiCard(title: "Kunden", value: "\(workspace.customers.count)", muted: true)
            }
            if openIssuesValue > 0 || openLeadValue > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .foregroundStyle(Color.green)
                    Text(potenzialHinweisText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        }
    }

    private var potenzialHinweisText: String {
        var parts: [String] = []
        if openIssuesValue > 0 {
            parts.append("Wenn du alle offenen Aufträge abschließt, kommen \(Money.format(openIssuesValue)) rein.")
        }
        if openLeadValue > 0 {
            parts.append("Aus aktiven Leads sind weitere \(Money.format(openLeadValue)) möglich.")
        }
        return parts.joined(separator: " ")
    }

    private var chartCard: some View {
        Card("Umsatzverlauf", subtitle: "Brutto pro Periode") {
            let data = buildChartData()
            if data.count < 2 {
                Text("Sobald du mehrere Rechnungen hast, zeigen wir hier den Verlauf.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                Chart(data, id: \.label) { point in
                    AreaMark(
                        x: .value("Periode", point.label),
                        y: .value("Brutto", point.total)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    LineMark(
                        x: .value("Periode", point.label),
                        y: .value("Brutto", point.total)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .frame(height: 220)
            }
            HStack(spacing: 12) {
                MiniStat(label: "bezahlt", value: Money.format(paidTotal), color: .green)
                MiniStat(label: "offen", value: Money.format(openTotal), color: openTotal > 0 ? .orange : .secondary)
            }
        }
    }

    private func upsellAlreadyTodo(_ u: (customer: Customer, headline: String, reason: String, amount: Double)) -> Bool {
        workspace.todos.contains { todo in
            !todo.done
                && todo.customer?.id == u.customer.id
                && todo.title.localizedCaseInsensitiveCompare(u.headline) == .orderedSame
        }
    }

    private var visibleUpsells: [(customer: Customer, headline: String, reason: String, amount: Double)] {
        upsells.filter { !upsellAlreadyTodo($0) }
    }

    private func addUpsellAsTodo(_ u: (customer: Customer, headline: String, reason: String, amount: Double)) {
        let detailLine = u.amount > 0
            ? "\(u.reason)\n\nGeschätztes Umsatzpotenzial: \(Money.format(u.amount))"
            : u.reason
        let todo = Todo(
            title: u.headline,
            details: detailLine
        )
        todo.workspace = workspace
        todo.customer = u.customer
        modelContext.insert(todo)
        try? modelContext.save()
    }

    private var upsellCard: some View {
        Card("Wo holst du noch Geld raus?", subtitle: upsellSource ?? "KI-Vorschläge") {
            if isLoadingUpsells {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Lade Vorschläge…").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            } else if workspace.customers.isEmpty {
                Text("Leg erst Kunden an — dann gibt's hier passende Upsell-Vorschläge.")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
            } else if upsells.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Noch keine Vorschläge geladen.")
                        .font(.callout).foregroundStyle(.secondary)
                    if let err = upsellError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.vertical, 8)
            } else if visibleUpsells.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Alle Empfehlungen sind schon in der Aufgabenliste.", systemImage: "checkmark.seal.fill")
                        .font(.callout)
                        .foregroundStyle(Color.green)
                    Text("Im Reiter Aufgaben kannst du sie abarbeiten — danach erscheinen hier neue Vorschläge.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    let vis = visibleUpsells
                    ForEach(vis.indices, id: \.self) { idx in
                        let s = vis[idx]
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.customer.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                Text(s.headline)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(s.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                Button {
                                    addUpsellAsTodo(s)
                                } label: {
                                    Label("Auf meine Aufgabenliste", systemImage: "plus.circle")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .padding(.top, 4)
                            }
                            Spacer()
                            Text("+\(Money.format(s.amount))")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.green)
                        }
                        .padding(.vertical, 6)
                        if idx < vis.count - 1 {
                            Divider()
                        }
                    }
                    if let err = upsellError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            Button("Neue Vorschläge laden") {
                Task { await refreshUpsells(force: true) }
            }
            .controlSize(.small)
            .disabled(isLoadingUpsells || workspace.customers.isEmpty)
        }
    }

    private var overdueCard: some View {
        let overdue = filteredInvoices.filter {
            $0.status != .paid && ($0.dueDate.map { $0 < Date() } ?? false)
        }
        return Group {
            if !overdue.isEmpty {
                Card("Überfällige Rechnungen", subtitle: "\(overdue.count) Stück", danger: true) {
                    VStack(spacing: 6) {
                        ForEach(overdue) { inv in
                            HStack {
                                Text(inv.number).font(.system(.callout, design: .monospaced))
                                Text(inv.customer?.name ?? "—")
                                Spacer()
                                Text(DateFmt.short(inv.dueDate)).foregroundStyle(.red)
                                Text(Money.format(inv.total)).bold()
                            }
                            .font(.callout)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    private var openIssuesCard: some View {
        let issues = workspace.customers
            .flatMap(\.issues)
            .filter { !$0.done }
            .sorted(by: { $0.createdAt > $1.createdAt })
            .prefix(8)
        return Card("Offene Kundenwünsche", subtitle: "\(issues.count) — getrennt von deiner Todo-Liste") {
            if issues.isEmpty {
                Text("Alles erledigt.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                ForEach(Array(issues), id: \.id) { issue in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title).font(.system(size: 13, weight: .medium))
                            if let cust = issue.customer {
                                Text(cust.name).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let p = issue.price {
                            Text(Money.format(p)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    private var leadsCard: some View {
        let leads = workspace.leads
            .filter { $0.status == .contacted || $0.status == .meeting || $0.status == .proposal }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .prefix(5)
        return Card("Leads warten auf dich", subtitle: "\(leads.count)") {
            if leads.isEmpty {
                Text("Keine offenen Leads.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                ForEach(Array(leads), id: \.id) { lead in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lead.name).font(.system(size: 13, weight: .medium))
                            HStack(spacing: 6) {
                                if !lead.company.isEmpty {
                                    Text(lead.company)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let v = lead.expectedValue {
                                    Text(Money.format(v))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        StatusPill(text: lead.status.title, color: pillColor(for: lead.status))
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    // MARK: Follow-up reminders

    /// Eintrag für die "Wieder melden"-Card. Wir mischen Leads und Kunden
    /// in einer gemeinsamen Liste, sortiert nach "Tage seit letztem Kontakt
    /// absteigend" — wer am längsten Funkstille hat, steht oben.
    private struct FollowUp: Identifiable {
        enum Kind { case lead, customer }
        let id: UUID
        let kind: Kind
        let title: String
        let subtitle: String
        let lastContact: Date?
        let daysSince: Int   // -1 = nie kontaktiert
        let threshold: Int
        var overdueBy: Int { daysSince - threshold }
    }

    /// Letzter Kontakt-Zeitpunkt für einen Lead. Wir bevorzugen das
    /// explizite `lastContactAt`-Feld; fallen sonst auf die jüngste Mail
    /// bzw. `updatedAt` zurück.
    private func leadLastContact(_ lead: Lead) -> Date? {
        if let last = lead.lastContactAt { return last }
        let mailDates = lead.emails.compactMap { $0.sentAt ?? $0.createdAt }
        if let newest = mailDates.max() { return newest }
        return lead.updatedAt
    }

    private var followUps: [FollowUp] {
        let leadThreshold = workspace.effectiveLeadReminderDays
        let customerThreshold = workspace.effectiveCustomerReminderDays
        var out: [FollowUp] = []

        // Leads in aktiven Pipeline-Phasen — gewonnene/verlorene ignorieren
        for lead in workspace.leads where lead.status != .won && lead.status != .lost {
            let last = leadLastContact(lead)
            let days: Int = last.map { Int(Date().timeIntervalSince($0) / 86_400) } ?? -1
            // -1 (nie) zählt wie ∞ Tage Funkstille, aber nur wenn der Lead
            // schon eine Weile existiert (mind. so lang wie die Schwelle).
            let ageDays = Int(Date().timeIntervalSince(lead.createdAt) / 86_400)
            if days >= leadThreshold || (days < 0 && ageDays >= leadThreshold) {
                let normalisedDays = days < 0 ? ageDays : days
                out.append(FollowUp(
                    id: lead.id,
                    kind: .lead,
                    title: lead.name,
                    subtitle: lead.company.isEmpty ? lead.status.title : "\(lead.company) · \(lead.status.title)",
                    lastContact: last,
                    daysSince: normalisedDays,
                    threshold: leadThreshold
                ))
            }
        }

        // Kunden — nur Bestandskunden (mind. 1 Rechnung), Archivierte raus
        for customer in workspace.customers where customer.archivedAt == nil {
            guard !customer.invoices.isEmpty else { continue }
            let last = customer.lastContactAt
            // Wenn nie ein Kontakt notiert wurde, nutzen wir das Datum der
            // letzten Rechnung als Proxy — sonst landen alle bestehenden
            // Kunden sofort hier drin.
            let lastRef = last ?? customer.invoices.sorted(by: { $0.date > $1.date }).first?.date
            guard let lastRef else { continue }
            let days = Int(Date().timeIntervalSince(lastRef) / 86_400)
            if days >= customerThreshold {
                out.append(FollowUp(
                    id: customer.id,
                    kind: .customer,
                    title: customer.name,
                    subtitle: customer.company.isEmpty ? "Kunde" : customer.company,
                    lastContact: last,
                    daysSince: days,
                    threshold: customerThreshold
                ))
            }
        }

        return out
            .sorted(by: { $0.overdueBy > $1.overdueBy })
    }

    private var followUpCard: some View {
        let items = followUps
        let visible = Array(items.prefix(6))
        let leadDays = workspace.effectiveLeadReminderDays
        let custDays = workspace.effectiveCustomerReminderDays
        let subtitle = "Leads ab \(leadDays) T · Kunden ab \(custDays) T"

        return Card("Wieder melden", subtitle: subtitle) {
            if items.isEmpty {
                Text("Alles im Takt — keine offenen Kontakte überfällig.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(visible) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.kind == .lead ? "sparkles" : "person.fill")
                                .foregroundStyle(item.kind == .lead ? Color.blue : Color.accentColor)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(item.daysSince) T")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(item.overdueBy > item.threshold ? Color.red : Color.orange)
                                if let last = item.lastContact {
                                    Text(DateFmt.short(last))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                } else {
                                    Text("nie")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                    if items.count > visible.count {
                        Text("+\(items.count - visible.count) weitere")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                }
            }
        }
    }

    private func pillColor(for status: LeadStatus) -> Color {
        switch status {
        case .new, .contacted: .blue
        case .meeting, .proposal: .orange
        case .won: .green
        case .lost: .red
        }
    }

    // MARK: Chart data

    private struct ChartPoint { let label: String; let total: Double; let sortKey: Int }

    private func buildChartData() -> [ChartPoint] {
        let source = filteredInvoices
        guard !source.isEmpty else { return [] }
        var buckets: [String: (label: String, total: Double, sortKey: Int)] = [:]
        let cal = Calendar.current
        for inv in source {
            let d = inv.date
            let key: String
            let label: String
            let sortKey: Int
            switch range {
            case .today:
                let h = cal.component(.hour, from: d)
                key = "h-\(h)"; label = "\(h):00"; sortKey = h
            case .week:
                let day = cal.component(.weekday, from: d)
                let labels = ["So","Mo","Di","Mi","Do","Fr","Sa"]
                key = "d-\(day)"; label = labels[day - 1]; sortKey = day == 1 ? 7 : day
            case .month:
                let day = cal.component(.day, from: d)
                key = "md-\(day)"; label = "\(day)."; sortKey = day
            case .quarter:
                let m = cal.component(.month, from: d)
                let labels = ["Jan","Feb","Mär","Apr","Mai","Jun","Jul","Aug","Sep","Okt","Nov","Dez"]
                key = "qmo-\(m)"; label = labels[m - 1]; sortKey = m
            case .year:
                let m = cal.component(.month, from: d)
                let labels = ["Jan","Feb","Mär","Apr","Mai","Jun","Jul","Aug","Sep","Okt","Nov","Dez"]
                key = "mo-\(m)"; label = labels[m - 1]; sortKey = m
            case .all:
                let m = cal.component(.month, from: d)
                let y = cal.component(.year, from: d)
                key = "\(y)-\(m)"; label = String(format: "%02d/%02d", m, y % 100); sortKey = y * 12 + m
            }
            var cur = buckets[key] ?? (label, 0, sortKey)
            cur.total += inv.total
            buckets[key] = cur
        }
        return buckets.values
            .sorted(by: { $0.sortKey < $1.sortKey })
            .map { ChartPoint(label: $0.label, total: $0.total, sortKey: $0.sortKey) }
    }

    // MARK: AI upsells

    @MainActor
    private func refreshUpsells(force: Bool = false) async {
        // Don't auto-rerun if we already loaded — only manual refresh forces.
        if !upsells.isEmpty && !force { return }
        guard !workspace.customers.isEmpty else {
            upsells = []
            upsellError = nil
            return
        }

        isLoadingUpsells = true
        defer { isLoadingUpsells = false }
        upsellError = nil
        upsellSource = nil

        // Heuristic baseline first — covers the "no API key / API down" case.
        let heur = heuristicUpsells()

        guard let service = OpenAIService(workspace: workspace) else {
            upsells = heur
            upsellSource = "Heuristik (kein API-Key)"
            if heur.isEmpty {
                upsellError = "Hinterleg in den Einstellungen einen OpenAI-Key, dann kommen pro Kunde individuelle Vorschläge."
            }
            return
        }

        // Up to 5 most-relevant customers (most invoiced first; then newest).
        let prioritized = workspace.customers.sorted { lhs, rhs in
            if lhs.totalInvoiced != rhs.totalInvoiced {
                return lhs.totalInvoiced > rhs.totalInvoiced
            }
            return lhs.createdAt > rhs.createdAt
        }.prefix(5)

        var results: [(customer: Customer, headline: String, reason: String, amount: Double)] = []
        var firstError: String?

        let profile = WorkspaceAIProfile(workspace: workspace)
        for customer in prioritized {
            let summary = customerSummary(customer)
            do {
                if let r = try await service.suggestUpsell(for: summary, profile: profile) {
                    results.append((customer, r.headline, r.reason, r.amount))
                }
            } catch {
                if firstError == nil {
                    firstError = "OpenAI: \(error.localizedDescription)"
                }
            }
        }

        if results.isEmpty {
            upsells = heur
            upsellSource = heur.isEmpty ? nil : "Heuristik-Fallback"
            upsellError = firstError ?? (heur.isEmpty
                ? "Konnte keine Vorschläge generieren. Prüf das Modell in den Einstellungen oder ergänze Leistungen pro Kunde."
                : nil)
        } else {
            upsells = results.sorted(by: { $0.amount > $1.amount })
            upsellSource = "OpenAI (\(workspace.openAIModel))"
            upsellError = firstError
        }
    }

    private func customerSummary(_ c: Customer) -> String {
        let services = Set(c.invoices.flatMap(\.items).map(\.details))
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let openWishes = c.issues.filter { !$0.done }.prefix(5).map(\.title).joined(separator: ", ")
        let lastDate = c.invoices.sorted(by: { $0.date > $1.date }).first?.date
        let daysSince = lastDate.map { Int(Date().timeIntervalSince($0) / 86400) } ?? -1

        return """
        Kunde: \(c.name)\(c.company.isEmpty ? "" : " (\(c.company))")
        Bisherige Leistungen: \(services.isEmpty ? "noch keine Rechnung gestellt" : services)
        Gesamtumsatz bisher: \(Int(c.totalInvoiced)) €
        Tage seit letzter Rechnung: \(daysSince < 0 ? "noch nie" : "\(daysSince)")
        Offene Aufgaben: \(c.openIssuesCount)\(openWishes.isEmpty ? "" : " (\(openWishes))")
        Wiederkehrend pro Monat: \(Int(c.monthlyRecurringCost)) €
        """
    }

    private func heuristicUpsells() -> [(customer: Customer, headline: String, reason: String, amount: Double)] {
        // Branchen-Erkennung: wir gucken zuerst auf das KI-Profil. Wenn
        // das leer ist, fallen wir auf den Workspace-Namen zurück — nur
        // wenn DER klar nach Webdesign aussieht, bleibt die alte
        // SEO/Ads/Wartung-Heuristik aktiv. Sonst liefern wir generische
        // Vorschläge, damit Taskey & Co. keine Webdesign-Empfehlungen
        // serviert bekommen.
        let kindRaw = (workspace.businessKind ?? "").lowercased()
        let nameRaw = workspace.name.lowercased()
        let isWebdesign: Bool = {
            if !kindRaw.isEmpty {
                return kindRaw.contains("webdesign")
                    || kindRaw.contains("marketing")
                    || kindRaw.contains("agentur")
                    || kindRaw.contains("seo")
            }
            // Kein KI-Profil → letzter Anker: heißt der Workspace selbst so?
            return nameRaw.contains("webdesign")
                || nameRaw.contains("marketing")
                || nameRaw.contains("agency")
                || nameRaw.contains("agentur")
                || nameRaw.contains("design")
        }()

        var out: [(Customer, String, String, Double)] = []
        for c in workspace.customers {
            if isWebdesign {
                if c.invoices.isEmpty {
                    out.append((c, "Erstes Angebot platzieren — Website-Setup ab 800 €",
                                "Noch keine Rechnung. Klassischer Einstieg ist ein Website-Projekt.", 800))
                    continue
                }

                let services = c.invoices.flatMap(\.items).map { $0.details.lowercased() }
                let has = { (label: String) in services.contains { $0.contains(label) } }
                if !has("seo") {
                    out.append((c, "SEO-Paket anbieten — 200 €/Monat",
                                "Kunde hat noch kein SEO — klassischer Folge-Upsell.", 200))
                } else if !has("ads") && !has("google") {
                    out.append((c, "Google Ads Setup + 200 € Betreuung/Monat",
                                "Kunde hat SEO aber keine bezahlte Reichweite.", 200))
                } else if !has("wartung") && !has("pflege") {
                    out.append((c, "Wartungspaket für 99 €/Monat",
                                "Wiederkehrender Umsatz statt nur Projekt-Buchungen.", 99))
                } else {
                    out.append((c, "Performance-Audit für 350 €",
                                "Bestandskunde — guter Aufhänger für Check-in.", 350))
                }
            } else {
                // Branchen-neutraler Fallback — solange kein OpenAI-Key da
                // ist, zeigen wir generische "Anlass zum Reden"-Hinweise.
                // Die richtigen Vorschläge kommen via KI sobald ein Key
                // hinterlegt ist.
                let daysSince: Int = {
                    guard let last = c.invoices.sorted(by: { $0.date > $1.date }).first?.date else { return -1 }
                    return Int(Date().timeIntervalSince(last) / 86_400)
                }()
                if c.invoices.isEmpty {
                    out.append((c, "Erstgespräch / Pilot anbieten",
                                "Noch keine Rechnung — Anlass für einen konkreten Pilot- oder Erstauftrag.",
                                0))
                } else if daysSince > 60 {
                    out.append((c, "Check-in nach \(daysSince) Tagen Funkstille",
                                "Letzte Rechnung liegt \(daysSince) Tage zurück — guter Anlass für ein Status-Gespräch.",
                                0))
                } else if c.monthlyRecurringCost <= 0 {
                    out.append((c, "Wiederkehrendes Paket vorschlagen",
                                "Bisher nur Einmal-Aufträge. Ein Service-/Support-Paket würde wiederkehrenden Umsatz bringen.",
                                0))
                } else {
                    out.append((c, "Upgrade auf höheres Paket anstoßen",
                                "Bestandskunde mit laufender Buchung — guter Hebel für ein höheres Tier oder Zusatzmodul.",
                                0))
                }
            }
        }
        return Array(out.sorted(by: { $0.3 > $1.3 }).prefix(5))
    }
}

// MARK: - Sub-components

private struct Header: View {
    let workspace: Workspace
    @Binding var range: DashboardRange
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dashboard").font(.title2).fontWeight(.semibold)
                HStack(spacing: 6) {
                    Text("Übersicht für \(range.longTitle.lowercased()).")
                    if range == .quarter {
                        Text(DashboardRange.currentQuarterLabel)
                            .font(.callout.monospaced())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Zeitraum", selection: $range) {
                ForEach(DashboardRange.allCases) { r in
                    Text(r.title).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 480)
        }
    }
}

enum KpiTone {
    case neutral, positive, danger
}

struct KpiCard: View {
    let title: String
    let value: String
    var accent: Bool = false
    var muted: Bool = false
    var tone: KpiTone = .neutral

    private var valueColor: AnyShapeStyle {
        switch tone {
        case .positive: AnyShapeStyle(Color.green)
        case .danger:   AnyShapeStyle(Color.red)
        case .neutral:  muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
        }
    }

    private var bgFill: AnyShapeStyle {
        if accent { return AnyShapeStyle(Color.accentColor.gradient) }
        switch tone {
        case .positive: return AnyShapeStyle(Color.green.opacity(0.08))
        case .danger:   return AnyShapeStyle(Color.red.opacity(0.08))
        case .neutral:  return AnyShapeStyle(Color.gray.opacity(0.06))
        }
    }

    private var strokeColor: Color {
        switch tone {
        case .positive: Color.green.opacity(0.3)
        case .danger:   Color.red.opacity(0.3)
        case .neutral:  Color.gray.opacity(0.15)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .tracking(0.5)
                .foregroundStyle(accent ? AnyShapeStyle(Color.white.opacity(0.75)) : AnyShapeStyle(Color.secondary))
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(bgFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(strokeColor)
        )
    }
}

struct MiniStat: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption).fontWeight(.semibold).foregroundStyle(color)
        }
        .padding(8)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct Card<Content: View>: View {
    let title: String
    let subtitle: String?
    let danger: Bool
    let content: () -> Content

    init(_ title: String, subtitle: String? = nil, danger: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.danger = danger
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.subheadline).fontWeight(.semibold)
                if let sub = subtitle {
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            content()
        }
        .padding(16)
        .background(Color.gray.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(danger ? Color.red.opacity(0.4) : Color.gray.opacity(0.15))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
