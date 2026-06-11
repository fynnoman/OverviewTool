import SwiftUI
import SwiftData
import Charts

enum DashboardRange: String, CaseIterable, Identifiable {
    case today, week, month, year, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Heute"
        case .week:  "Diese Woche"
        case .month: "Diesen Monat"
        case .year:  "Dieses Jahr"
        case .all:   "Gesamt"
        }
    }

    func startDate() -> Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .today: return cal.startOfDay(for: now)
        case .week:  return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))
        case .month: return cal.date(from: cal.dateComponents([.year, .month], from: now))
        case .year:  return cal.date(from: cal.dateComponents([.year], from: now))
        case .all:   return nil
        }
    }
}

struct DashboardView: View {
    let workspace: Workspace
    @Environment(\.modelContext) private var modelContext
    @State private var range: DashboardRange = .month
    @State private var upsells: [(customer: Customer, headline: String, reason: String, amount: Double)] = []
    @State private var isLoadingUpsells = false

    private var invoices: [Invoice] {
        workspace.customers.flatMap(\.invoices)
    }

    private var filteredInvoices: [Invoice] {
        let start = range.startDate()
        return invoices.filter { inv in
            guard let start else { return true }
            return inv.date >= start
        }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Header(workspace: workspace, range: $range)

                kpiRow

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        chartCard
                        upsellCard
                        overdueCard
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 16) {
                        openIssuesCard
                        leadsCard
                    }
                    .frame(width: 320)
                }
            }
            .padding(20)
        }
        .task(id: workspace.id) {
            await refreshUpsells()
        }
    }

    private var kpiRow: some View {
        HStack(spacing: 12) {
            KpiCard(title: "Brutto", value: Money.format(grossTotal), accent: true)
            KpiCard(title: "Netto", value: Money.format(netTotal))
            KpiCard(title: "MwSt.", value: Money.format(vatTotal), muted: true)
            KpiCard(title: "Rechnungen", value: "\(filteredInvoices.count)", muted: true)
        }
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

    private var upsellCard: some View {
        Card("Wo holst du noch Geld raus?", subtitle: "KI-Vorschläge") {
            if isLoadingUpsells {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Lade Vorschläge…").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            } else if upsells.isEmpty {
                Text("Sobald Kunden mit Rechnungen vorhanden sind und ein API-Key in den Einstellungen liegt, kommen hier KI-Vorschläge.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(upsells.indices, id: \.self) { idx in
                        let s = upsells[idx]
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
                            }
                            Spacer()
                            Text("+\(Money.format(s.amount))")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.green)
                        }
                        .padding(.vertical, 6)
                        if idx < upsells.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            Button("Neue Vorschläge laden") {
                Task { await refreshUpsells(force: true) }
            }
            .controlSize(.small)
            .disabled(isLoadingUpsells)
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
        return Card("Offene Aufgaben", subtitle: "\(issues.count)") {
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
        guard !invoices.isEmpty else { return [] }
        var buckets: [String: (label: String, total: Double, sortKey: Int)] = [:]
        let cal = Calendar.current
        for inv in invoices {
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
        if upsells.count > 0 && !force { return }
        guard let service = OpenAIService(workspace: workspace) else {
            upsells = heuristicUpsells()
            return
        }
        isLoadingUpsells = true
        defer { isLoadingUpsells = false }

        var results: [(customer: Customer, headline: String, reason: String, amount: Double)] = []
        let payingCustomers = workspace.customers.filter { !$0.invoices.isEmpty }.prefix(5)
        for customer in payingCustomers {
            let summary = customerSummary(customer)
            if let r = try? await service.suggestUpsell(for: summary) {
                results.append((customer, r.headline, r.reason, r.amount))
            }
        }
        if results.isEmpty {
            results = heuristicUpsells()
        }
        upsells = results.sorted(by: { $0.amount > $1.amount })
    }

    private func customerSummary(_ c: Customer) -> String {
        let services = Set(c.invoices.flatMap(\.items).map(\.details)).joined(separator: ", ")
        let lastDate = c.invoices.sorted(by: { $0.date > $1.date }).first?.date
        let daysSince = lastDate.map { Int(Date().timeIntervalSince($0) / 86400) } ?? 999
        return """
        Kunde: \(c.name)
        Bisherige Leistungen: \(services.isEmpty ? "—" : services)
        Gesamtumsatz: \(Int(c.totalInvoiced)) €
        Tage seit letzter Rechnung: \(daysSince)
        Offene Aufgaben: \(c.openIssuesCount)
        """
    }

    private func heuristicUpsells() -> [(customer: Customer, headline: String, reason: String, amount: Double)] {
        var out: [(Customer, String, String, Double)] = []
        for c in workspace.customers where !c.invoices.isEmpty {
            let services = c.invoices.flatMap(\.items).map { $0.details.lowercased() }
            let has = { (label: String) in services.contains { $0.contains(label) } }
            if !has("seo") {
                out.append((c, "SEO-Paket anbieten — 200 €/Monat",
                            "Kunde hat noch kein SEO — klassischer Folge-Upsell.", 200))
            } else if !has("ads") {
                out.append((c, "Google Ads Setup + 200 € Betreuung/Monat",
                            "Kunde hat SEO aber keine bezahlte Reichweite.", 200))
            } else {
                out.append((c, "Wartungspaket für 99 €/Monat",
                            "Wiederkehrender Umsatz statt nur Projekt-Buchungen.", 99))
            }
        }
        return Array(out.prefix(5))
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
                Text("Übersicht für \(range.title.lowercased()).")
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

struct KpiCard: View {
    let title: String
    let value: String
    var accent: Bool = false
    var muted: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .tracking(0.5)
                .foregroundStyle(accent ? AnyShapeStyle(Color.white.opacity(0.75)) : AnyShapeStyle(Color.secondary))
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(accent ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.gray.opacity(0.06)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.15))
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
