import SwiftUI
import SwiftData

/// Steuer-Übersicht: Jahresumsatz, Kleinunternehmer-Status, Einkommensteuer-
/// Schätzung und Fristen-Erinnerungen (USt-Voranmeldungen, Jahreserklärungen,
/// ESt-Vorauszahlungen).
enum TaxRegime: String, CaseIterable, Identifiable {
    case regelbesteuert, kleinunternehmer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .regelbesteuert:   "Regelbesteuert"
        case .kleinunternehmer: "Kleinunternehmer (§ 19 UStG)"
        }
    }
}

struct TaxView: View {
    let workspace: Workspace
    @Environment(\.modelContext) private var modelContext
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @AppStorage("taxDeadlineCompletions") private var completionsJSON: String = "{}"
    @AppStorage("taxRegime") private var regimeRaw: String = TaxRegime.regelbesteuert.rawValue

    private var regime: TaxRegime {
        TaxRegime(rawValue: regimeRaw) ?? .regelbesteuert
    }

    private var calendar: Calendar { Calendar.current }
    private var now: Date { Date() }

    // MARK: - Datenquellen
    private var allInvoices: [Invoice] { workspace.customers.flatMap(\.invoices) }
    private var allCosts: [Cost] { workspace.customers.flatMap(\.costs) }
    private var allDeductible: [DeductibleExpense] { workspace.deductibleExpenses }

    private func invoicesInYear(_ year: Int) -> [Invoice] {
        allInvoices.filter { calendar.component(.year, from: $0.date) == year }
    }
    private func costsInYear(_ year: Int) -> [Cost] {
        allCosts.filter { cost in
            let d = cost.dueDate ?? cost.createdAt
            return calendar.component(.year, from: d) == year
        }
    }
    private func deductibleInYear(_ year: Int) -> [DeductibleExpense] {
        allDeductible.filter { calendar.component(.year, from: $0.date) == year }
    }

    private func revenue(year: Int) -> Double {
        invoicesInYear(year).reduce(0) { $0 + $1.total }
    }
    private func vatCollected(year: Int) -> Double {
        invoicesInYear(year).reduce(0) { $0 + $1.vatAmount }
    }
    private func vorsteuer(year: Int) -> Double {
        deductibleInYear(year).reduce(0) { $0 + $1.vatAmount }
    }
    private func costsTotal(year: Int) -> Double {
        costsInYear(year).reduce(0) { $0 + $1.amount }
    }
    private func deductibleNet(year: Int) -> Double {
        deductibleInYear(year).reduce(0) { $0 + $1.net }
    }
    private func deductibleBrutto(year: Int) -> Double {
        deductibleInYear(year).reduce(0) { $0 + $1.amount }
    }

    /// Gewinn vor Steuern auf BRUTTO-Basis — was tatsächlich in deiner Tasche ist,
    /// bevor du USt und ESt ans Finanzamt abführst. Das ist die intuitive Zahl:
    /// Umsatz brutto + Bar − Kosten − absetzbare Ausgaben.
    private func grossProfit(year: Int) -> Double {
        let cashYear = workspace.customers.flatMap(\.cashIncomes)
            .filter { calendar.component(.year, from: $0.date) == year }
            .reduce(0) { $0 + $1.amount }
        return revenue(year: year) + cashYear
            - costsTotal(year: year) - deductibleBrutto(year: year)
    }

    /// Bemessungsgrundlage für die Einkommensteuer (Netto-Rechnungen − Netto-Ausgaben).
    /// Bareinnahmen bleiben außen vor (steuerfrei). Diese Zahl ist nur intern für die
    /// ESt-Schätzung — sie wird im UI nicht direkt gezeigt.
    private func taxableProfit(year: Int) -> Double {
        let netRevenue = invoicesInYear(year).reduce(0) { $0 + $1.subtotal }
        return netRevenue - costsTotal(year: year) - deductibleNet(year: year)
    }

    // MARK: - Steuerberechnung

    /// Einkommensteuer nach deutschem Tarif (Jahres-zvE, Tarif 2025 als Näherung).
    static func germanIncomeTax(zvE: Double) -> Double {
        let z = max(0, zvE)
        if z <= 12_096 { return 0 }
        if z <= 17_443 {
            let y = (z - 12_096) / 10_000
            return (932.30 * y + 1_400) * y
        }
        if z <= 68_480 {
            let z2 = (z - 17_443) / 10_000
            return (176.64 * z2 + 2_397) * z2 + 1_015.13
        }
        if z <= 277_825 {
            return 0.42 * z - 10_911.92
        }
        return 0.45 * z - 19_246.67
    }

    private var currentYearRevenue: Double { revenue(year: selectedYear) }
    private var previousYearRevenue: Double { revenue(year: selectedYear - 1) }
    /// Gewinn vor allen Steuern auf Brutto-Basis (das was im UI als „Gewinn vor Steuern" steht).
    private var currentYearProfit: Double { grossProfit(year: selectedYear) }
    /// Bemessungsgrundlage der ESt (Netto-Basis, nicht direkt im UI).
    private var taxableNetProfit: Double { taxableProfit(year: selectedYear) }
    private var estimatedIncomeTax: Double { Self.germanIncomeTax(zvE: taxableNetProfit) }
    /// Gewinn nach allen Steuern: Brutto-Profit − USt-Zahllast − geschätzte ESt.
    private var profitAfterTax: Double {
        currentYearProfit - ustZahllast - estimatedIncomeTax
    }

    // MARK: - Kleinunternehmer

    private enum KUStatus {
        case isKU            // alle Schwellen unterschritten
        case approachingPrev // Vorjahr nähert sich 25.000
        case approachingCur  // laufendes Jahr nähert sich 100.000
        case lostNextYear    // Vorjahr > 25.000 → ab nächstem Jahr Regelbesteuerung
        case lostNow         // laufendes Jahr > 100.000 → sofort raus
    }

    private var kuStatus: KUStatus {
        let prev = previousYearRevenue
        let cur = currentYearRevenue
        if cur > 100_000 { return .lostNow }
        if prev > 25_000 { return .lostNextYear }
        if cur > 80_000 { return .approachingCur }
        if prev > 22_000 { return .approachingPrev }
        return .isKU
    }

    // MARK: - View

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                regimeCard
                kpiRow
                if regime == .kleinunternehmer {
                    kleinunternehmerCard
                } else {
                    umsatzsteuerCard
                }
                einkommensteuerCard
                deadlinesCard
            }
            .padding(20)
        }
    }

    private var regimeCard: some View {
        Card("Steuerstatus",
             subtitle: regime == .kleinunternehmer
                ? "Du weist auf Rechnungen keine USt aus."
                : "Du führst Umsatzsteuer ab und ziehst Vorsteuer.") {
            Picker("Status", selection: $regimeRaw) {
                ForEach(TaxRegime.allCases) { r in
                    Text(r.title).tag(r.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var ustZahllast: Double {
        max(0, vatCollected(year: selectedYear) - vorsteuer(year: selectedYear))
    }

    private var umsatzsteuerCard: some View {
        let collected = vatCollected(year: selectedYear)
        let vst = vorsteuer(year: selectedYear)
        let zahllast = ustZahllast
        return Card("Umsatzsteuer \(selectedYear)",
                    subtitle: "USt eingenommen − Vorsteuer = Zahllast ans Finanzamt",
                    danger: zahllast > 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 24) {
                    statRow("USt eingenommen", Money.format(collected))
                    Text("−").font(.title3).foregroundStyle(.secondary)
                    statRow("Vorsteuer", Money.format(vst))
                    Text("=").font(.title3).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("USt-Zahllast").font(.caption).foregroundStyle(.secondary)
                        Text(Money.format(zahllast))
                            .font(.title3).fontWeight(.bold).monospacedDigit()
                            .foregroundStyle(zahllast > 0 ? Color.red : Color.green)
                    }
                }
                if zahllast > 0 {
                    Label(
                        "Diese \(Money.format(zahllast)) musst du quartalsweise ans Finanzamt überweisen. Sie sind nicht dein Geld — leg sie am besten direkt zur Seite.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.callout)
                    .foregroundStyle(Color.orange)
                } else {
                    Label("Aktuell keine USt-Zahllast.", systemImage: "checkmark.seal.fill")
                        .font(.callout).foregroundStyle(Color.green)
                }
                Text("Aufteilung pro Quartal siehst du in der Fristen-Karte unten — dort kannst du jede Voranmeldung abhaken.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Steuern").font(.title2).fontWeight(.semibold)
                Text("Freigrenzen, geschätzte Einkommensteuer und Abgabe-Fristen — alles auf einer Seite.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Jahr", selection: $selectedYear) {
                ForEach(yearOptions, id: \.self) { y in
                    Text(String(y)).tag(y)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)
        }
    }

    private var yearOptions: [Int] {
        let current = calendar.component(.year, from: now)
        return Array((current - 3)...(current + 1))
    }

    private var totalTaxes: Double { ustZahllast + estimatedIncomeTax }

    private var kpiRow: some View {
        HStack(spacing: 12) {
            KpiCard(title: "Umsatz brutto \(selectedYear)",
                    value: Money.format(currentYearRevenue), accent: true)
            KpiCard(title: "Gewinn vor Steuern",
                    value: Money.format(currentYearProfit),
                    tone: currentYearProfit < 0 ? .danger : (currentYearProfit > 0 ? .positive : .neutral))
            KpiCard(title: "Steuern gesamt (USt + ESt)",
                    value: Money.format(totalTaxes),
                    tone: totalTaxes > 0 ? .danger : .neutral)
            KpiCard(title: "Gewinn nach Steuern",
                    value: Money.format(profitAfterTax),
                    tone: profitAfterTax > 0 ? .positive : (profitAfterTax < 0 ? .danger : .neutral))
        }
    }

    // MARK: - Kleinunternehmer-Karte

    private var kleinunternehmerCard: some View {
        Card("Kleinunternehmer-Status (§ 19 UStG)",
             subtitle: "Vorjahr: \(Money.format(previousYearRevenue)) · Laufend: \(Money.format(currentYearRevenue))",
             danger: kuStatus == .lostNow || kuStatus == .lostNextYear) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: kuIcon).font(.title2).foregroundStyle(kuColor)
                    Text(kuHeadline).font(.headline).foregroundStyle(kuColor)
                }
                Text(kuExplanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    progressBar(
                        label: "Vorjahr (≤ 25.000 €)",
                        value: previousYearRevenue, max: 25_000
                    )
                    progressBar(
                        label: "Lfd. Jahr (≤ 100.000 €)",
                        value: currentYearRevenue, max: 100_000
                    )
                }
            }
        }
    }

    private var kuIcon: String {
        switch kuStatus {
        case .isKU: "checkmark.circle.fill"
        case .approachingPrev, .approachingCur: "exclamationmark.triangle.fill"
        case .lostNextYear, .lostNow: "xmark.octagon.fill"
        }
    }
    private var kuColor: Color {
        switch kuStatus {
        case .isKU: .green
        case .approachingPrev, .approachingCur: .orange
        case .lostNextYear, .lostNow: .red
        }
    }
    private var kuHeadline: String {
        switch kuStatus {
        case .isKU: "Du bist Kleinunternehmer — keine Umsatzsteuer fällig."
        case .approachingPrev: "Vorjahr nähert sich 25.000 € — knapp am Limit."
        case .approachingCur: "Laufendes Jahr nähert sich 100.000 € — Achtung."
        case .lostNextYear: "Vorjahr > 25.000 € — ab nächstem Jahr Regelbesteuerung."
        case .lostNow: "Laufendes Jahr > 100.000 € — sofort regelbesteuert!"
        }
    }
    private var kuExplanation: String {
        switch kuStatus {
        case .isKU:
            return "Solange Vorjahr unter 25.000 € und laufendes Jahr unter 100.000 € bleibt, weist du keine Umsatzsteuer aus. Vorsteuer kannst du dafür auch nicht ziehen."
        case .approachingPrev:
            return "Pass auf: Wenn du das Vorjahr noch über 25.000 € drückst, fällst du im nächsten Jahr aus der Kleinunternehmerregelung."
        case .approachingCur:
            return "Wenn du im laufenden Jahr über 100.000 € kommst, fällst du sofort raus und musst rückwirkend USt abführen. Plane deine letzten Rechnungen entsprechend."
        case .lostNextYear:
            return "Du musst dich beim Finanzamt für die Regelbesteuerung anmelden. Ab nächstem Jahr stellst du USt aus und führst sie ab. Vorsteuer kannst du dann ziehen."
        case .lostNow:
            return "Du bist über der 100.000-€-Grenze und musst auf ALLE Rechnungen ab Überschreitung Umsatzsteuer aufschlagen — auch rückwirkend ggf. nachfordern. Sprich umgehend mit deinem Steuerberater."
        }
    }

    private func progressBar(label: String, value: Double, max: Double) -> some View {
        let pct = Swift.min(value / max, 1.0)
        let color: Color = pct >= 1 ? .red : (pct >= 0.8 ? .orange : .green)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(pct * 100)) %").font(.caption).foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * pct)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Einkommensteuer-Karte

    private var einkommensteuerCard: some View {
        Card("Einkommensteuer",
             subtitle: "Tarif 2025 (Grundfreibetrag 12.096 €) — Näherung, ersetzt keinen Steuerberater.") {
            VStack(alignment: .leading, spacing: 10) {
                if taxableNetProfit <= 12_096 {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Dein zu versteuerndes Einkommen (\(Money.format(taxableNetProfit))) liegt unter dem Grundfreibetrag — keine Einkommensteuer.")
                            .font(.callout)
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Du liegst über dem Grundfreibetrag. Geschätzte Einkommensteuer: \(Money.format(estimatedIncomeTax))")
                            .font(.callout)
                    }
                    HStack(spacing: 24) {
                        statRow("zvE (netto)", Money.format(taxableNetProfit))
                        statRow("ESt", Money.format(estimatedIncomeTax))
                        statRow("Effektiver Steuersatz",
                                String(format: "%.1f %%", taxableNetProfit > 0 ? estimatedIncomeTax / taxableNetProfit * 100 : 0))
                        statRow("Gewinn nach allen Steuern", Money.format(profitAfterTax))
                    }
                }
                Text("Berechnungsbasis: Netto-Umsatz aus Rechnungen − Kosten − absetzbare Ausgaben (netto). Bareinnahmen bleiben außen vor.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Divider()
                Text("Tipp: Lege etwa \(Money.format(estimatedIncomeTax)) auf ein separates Steuer-Sparkonto, damit dich die Nachzahlung nicht überrumpelt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).fontWeight(.semibold).monospacedDigit()
        }
    }

    // MARK: - Fristen-Karte

    private var deadlinesCard: some View {
        Card("Fristen & Erinnerungen",
             subtitle: "USt-Voranmeldungen, Jahreserklärungen, ESt-Vorauszahlungen.") {
            VStack(spacing: 0) {
                ForEach(upcomingDeadlines) { d in
                    DeadlineRow(
                        deadline: d,
                        isDone: isCompleted(d.id),
                        toggle: { setCompleted(d.id, !isCompleted(d.id)) }
                    )
                    Divider()
                }
                if upcomingDeadlines.isEmpty {
                    Text("Keine offenen Fristen in Sicht.")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                }
            }
        }
    }

    private var upcomingDeadlines: [Deadline] {
        let all = generateDeadlines()
        let now = Date()
        // 30 Tage rückwärts (für „überfällig"-Anzeige) bis Ende des nächsten Jahres
        let earliest = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let latest = calendar.date(byAdding: .month, value: 18, to: now) ?? now
        return all.filter { $0.date >= earliest && $0.date <= latest }
            .sorted(by: { $0.date < $1.date })
    }

    // MARK: - Deadline-Generation

    private func generateDeadlines() -> [Deadline] {
        var out: [Deadline] = []
        let year = selectedYear

        func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: day)) ?? now
        }

        // USt-Voranmeldungen (quartalsweise, fällig jeweils 10. des Folgemonats)
        out.append(Deadline(id: "USt-VA-\(year)-Q1", title: "USt-Voranmeldung Q1 \(year)",
                            kind: .ustVA, date: d(year, 4, 10)))
        out.append(Deadline(id: "USt-VA-\(year)-Q2", title: "USt-Voranmeldung Q2 \(year)",
                            kind: .ustVA, date: d(year, 7, 10)))
        out.append(Deadline(id: "USt-VA-\(year)-Q3", title: "USt-Voranmeldung Q3 \(year)",
                            kind: .ustVA, date: d(year, 10, 10)))
        out.append(Deadline(id: "USt-VA-\(year)-Q4", title: "USt-Voranmeldung Q4 \(year)",
                            kind: .ustVA, date: d(year + 1, 1, 10)))

        // ESt-Vorauszahlungen (10. März, Juni, September, Dezember)
        out.append(Deadline(id: "ESt-VZ-\(year)-Q1", title: "ESt-Vorauszahlung Q1 \(year)",
                            kind: .estVZ, date: d(year, 3, 10)))
        out.append(Deadline(id: "ESt-VZ-\(year)-Q2", title: "ESt-Vorauszahlung Q2 \(year)",
                            kind: .estVZ, date: d(year, 6, 10)))
        out.append(Deadline(id: "ESt-VZ-\(year)-Q3", title: "ESt-Vorauszahlung Q3 \(year)",
                            kind: .estVZ, date: d(year, 9, 10)))
        out.append(Deadline(id: "ESt-VZ-\(year)-Q4", title: "ESt-Vorauszahlung Q4 \(year)",
                            kind: .estVZ, date: d(year, 12, 10)))

        // Jahreserklärungen (Fälligkeit 31.07. des Folgejahres ohne Berater)
        out.append(Deadline(id: "Jahr-USt-\(year)", title: "USt-Jahreserklärung \(year)",
                            kind: .jahr, date: d(year + 1, 7, 31)))
        out.append(Deadline(id: "Jahr-ESt-\(year)", title: "Einkommensteuererklärung \(year)",
                            kind: .jahr, date: d(year + 1, 7, 31)))

        return out
    }

    // MARK: - Completion-Persistenz

    private func isCompleted(_ id: String) -> Bool {
        guard let data = completionsJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Bool].self, from: data)
        else { return false }
        return dict[id] ?? false
    }
    private func setCompleted(_ id: String, _ value: Bool) {
        var dict: [String: Bool] = (try? JSONDecoder().decode(
            [String: Bool].self,
            from: completionsJSON.data(using: .utf8) ?? Data()
        )) ?? [:]
        dict[id] = value
        if let data = try? JSONEncoder().encode(dict),
           let s = String(data: data, encoding: .utf8) {
            completionsJSON = s
        }
    }
}

// MARK: - Deadline Model

enum DeadlineKind {
    case ustVA, estVZ, jahr

    var color: Color {
        switch self {
        case .ustVA: return .blue
        case .estVZ: return .purple
        case .jahr:  return .indigo
        }
    }
    var pillTitle: String {
        switch self {
        case .ustVA: return "USt-VA"
        case .estVZ: return "ESt-VZ"
        case .jahr:  return "Jahreserklärung"
        }
    }
}

struct Deadline: Identifiable {
    let id: String
    let title: String
    let kind: DeadlineKind
    let date: Date
}

private struct DeadlineRow: View {
    let deadline: Deadline
    let isDone: Bool
    let toggle: () -> Void

    private var daysUntil: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: deadline.date)
        return cal.dateComponents([.day], from: today, to: target).day ?? 0
    }

    private var statusText: String {
        if isDone { return "erledigt" }
        if daysUntil < 0 { return "überfällig seit \(-daysUntil) Tagen" }
        if daysUntil == 0 { return "heute fällig" }
        if daysUntil <= 7 { return "in \(daysUntil) Tag\(daysUntil == 1 ? "" : "en")" }
        return "in \(daysUntil) Tagen"
    }

    private var statusColor: Color {
        if isDone { return .secondary }
        if daysUntil < 0 { return .red }
        if daysUntil <= 7 { return .orange }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            StatusPill(text: deadline.kind.pillTitle, color: deadline.kind.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(deadline.title)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? .secondary : .primary)
                Text(DateFmt.long.string(from: deadline.date))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Text(statusText)
                .font(.caption).fontWeight(.medium)
                .foregroundStyle(statusColor)
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
    }
}
