import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct InvoiceDetailView: View {
    @Bindable var invoice: Invoice
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusBar
                contentRow
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportPDF()
                } label: {
                    Label("PDF exportieren", systemImage: "arrow.down.doc")
                }
            }
        }
        .alert("Rechnung wirklich löschen?", isPresented: $showDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                modelContext.delete(invoice)
                try? modelContext.save()
                dismiss()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rechnung \(invoice.number)")
                    .font(.title).fontWeight(.semibold)
                Text("\(invoice.customer?.name ?? "—") · \(DateFmt.short(invoice.date))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusBar: some View {
        Card("Status") {
            HStack(spacing: 8) {
                ForEach(InvoiceStatus.allCases) { s in
                    StatusButton(status: s, active: invoice.status == s) {
                        invoice.status = s
                        try? modelContext.save()
                    }
                }
                Spacer()
                Button(role: .destructive) {
                    showDelete = true
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
        }
    }

    private var contentRow: some View {
        HStack(alignment: .top, spacing: 16) {
            itemsCard
                .frame(maxWidth: .infinity)
            sidebar
                .frame(width: 320)
        }
    }

    private var itemsCard: some View {
        Card("Posten") {
            VStack(spacing: 0) {
                itemsHeader
                Divider()
                ForEach(invoice.items.sorted(by: { $0.order < $1.order })) { item in
                    ItemRow(item: item)
                    Divider()
                }
                totalsBlock
            }
            if !invoice.notes.isEmpty {
                Divider().padding(.vertical, 8)
                Text(invoice.notes).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var itemsHeader: some View {
        HStack {
            Text("Leistung").frame(maxWidth: .infinity, alignment: .leading)
            Text("Anzahl").frame(width: 60, alignment: .trailing)
            Text("Einzel").frame(width: 90, alignment: .trailing)
            Text("Summe").frame(width: 100, alignment: .trailing)
        }
        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
    }

    private var totalsBlock: some View {
        VStack(spacing: 4) {
            HStack { Text("Netto"); Spacer(); Text(Money.format(invoice.subtotal)) }
            HStack {
                Text("MwSt. (\(Int(invoice.vatRate))%)")
                Spacer()
                Text(Money.format(invoice.vatAmount))
            }
            .foregroundStyle(.secondary)
            Divider().padding(.vertical, 4)
            HStack {
                Text("Brutto").fontWeight(.semibold)
                Spacer()
                Text(Money.format(invoice.total)).fontWeight(.semibold)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 16) {
            if let customer = invoice.customer {
                CustomerSummaryCard(customer: customer)
            }
            overviewCard
        }
    }

    private var overviewCard: some View {
        Card("Übersicht") {
            VStack(alignment: .leading, spacing: 4) {
                metaRow("Rechnungsdatum", DateFmt.short(invoice.date))
                metaRow("Fällig", DateFmt.short(invoice.dueDate))
                metaRow("MwSt.-Satz", "\(Int(invoice.vatRate)) %")
                if let paidAt = invoice.paidAt {
                    metaRow("Bezahlt am", DateFmt.short(paidAt))
                }
            }
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout).monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    @MainActor
    private func exportPDF() {
        guard let workspace = invoice.customer?.workspace,
              let pdf = PDFRenderer.renderInvoice(invoice, workspace: workspace)
        else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "Rechnung-\(invoice.number).pdf"
        savePanel.title = "Rechnung als PDF speichern"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try pdf.write(to: url)
                NSWorkspace.shared.open(url)
            } catch {
                NSSound.beep()
            }
        }
    }
}

private struct StatusButton: View {
    let status: InvoiceStatus
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(status.title)
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

private struct ItemRow: View {
    let item: InvoiceItem
    var body: some View {
        HStack {
            Text(item.details).frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%g", item.quantity))
                .frame(width: 60, alignment: .trailing)
            Text(Money.format(item.unitPrice))
                .frame(width: 90, alignment: .trailing)
            Text(Money.format(item.lineTotal))
                .frame(width: 100, alignment: .trailing)
                .bold()
        }
        .padding(.vertical, 6)
    }
}

private struct CustomerSummaryCard: View {
    let customer: Customer
    var body: some View {
        Card("Kunde") {
            VStack(alignment: .leading, spacing: 4) {
                Text(customer.name).fontWeight(.semibold)
                if !customer.company.isEmpty {
                    Text(customer.company).foregroundStyle(.secondary)
                }
                if !customer.address.isEmpty {
                    Text(customer.address).font(.callout).foregroundStyle(.secondary)
                }
                NavigationLink {
                    CustomerDetailView(customer: customer)
                } label: {
                    Text("Kundenakte →").font(.caption).foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
