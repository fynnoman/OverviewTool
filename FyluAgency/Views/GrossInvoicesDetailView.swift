import SwiftUI

struct GrossInvoicesDetailView: View {
    let invoices: [Invoice]
    let rangeTitle: String
    let total: Double

    @Environment(\.dismiss) private var dismiss

    enum SortMode: String, CaseIterable, Identifiable {
        case dateNewest, dateOldest, amountDesc, amountAsc, customer
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dateNewest: "Datum (neueste zuerst)"
            case .dateOldest: "Datum (älteste zuerst)"
            case .amountDesc: "Betrag (höchste zuerst)"
            case .amountAsc:  "Betrag (niedrigste zuerst)"
            case .customer:   "Kunde (A–Z)"
            }
        }
    }

    @State private var sortMode: SortMode = .dateNewest

    private var sortedInvoices: [Invoice] {
        switch sortMode {
        case .dateNewest: invoices.sorted { $0.date > $1.date }
        case .dateOldest: invoices.sorted { $0.date < $1.date }
        case .amountDesc: invoices.sorted { $0.total > $1.total }
        case .amountAsc:  invoices.sorted { $0.total < $1.total }
        case .customer:
            invoices.sorted {
                ($0.customer?.name ?? "").localizedCaseInsensitiveCompare($1.customer?.name ?? "")
                    == .orderedAscending
            }
        }
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            controls
            Divider()
            content
        }
        .frame(minWidth: 560, minHeight: 460)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Brutto (steuerpflichtig)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(Money.format(total))
                    .font(.title)
                    .fontWeight(.semibold)
                Text("\(rangeTitle) · \(invoices.count) \(invoices.count == 1 ? "Rechnung" : "Rechnungen")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Schließen") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Text("Sortieren nach")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("", selection: $sortMode) {
                ForEach(SortMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 260)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if sortedInvoices.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Keine Rechnungen in diesem Zeitraum.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(sortedInvoices, id: \.id) { inv in
                        InvoiceRow(invoice: inv, dateString: dateFormatter.string(from: inv.date))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }
}

private struct InvoiceRow: View {
    let invoice: Invoice
    let dateString: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(invoice.customer?.name ?? "Ohne Kunde")
                        .font(.callout)
                        .fontWeight(.semibold)
                    StatusPill(text: invoice.status.title, color: statusColor)
                }
                Text("Nr. \(invoice.number) · \(dateString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(invoice.total))
                    .font(.callout)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text("Netto \(Money.format(invoice.subtotal))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15))
        )
    }

    private var statusColor: Color {
        switch invoice.status {
        case .draft:   .secondary
        case .sent:    .blue
        case .paid:    .green
        case .overdue: .red
        }
    }
}
