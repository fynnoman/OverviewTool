import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct QuoteDetailView: View {
    @Bindable var quote: Quote
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
        .alert("Angebot wirklich löschen?", isPresented: $showDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                modelContext.delete(quote)
                try? modelContext.save()
                dismiss()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Angebot \(quote.number)")
                    .font(.title).fontWeight(.semibold)
                Text("\(quote.customer?.name ?? "—") · \(DateFmt.short(quote.date))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusBar: some View {
        Card("Status") {
            HStack(spacing: 8) {
                ForEach(selectableStatuses) { s in
                    QuoteStatusButton(status: s, active: quote.status == s) {
                        quote.status = s
                        try? modelContext.save()
                    }
                }
                Spacer()
                if quote.effectiveStatus == .expired {
                    StatusPill(text: "Abgelaufen", color: .orange)
                }
                Button(role: .destructive) {
                    showDelete = true
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
        }
    }

    /// Nur manuell setzbare Stati — .expired ist automatisch (Datum), .converted
    /// gibt es noch nicht als Flow.
    private var selectableStatuses: [QuoteStatus] {
        [.draft, .sent, .accepted, .declined]
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
                ForEach(quote.items.sorted(by: { $0.order < $1.order })) { item in
                    QuoteItemRow(item: item)
                    Divider()
                }
                totalsBlock
            }
            if !quote.notes.isEmpty {
                Divider().padding(.vertical, 8)
                Text(quote.notes).font(.callout).foregroundStyle(.secondary)
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
            HStack { Text("Netto"); Spacer(); Text(Money.format(quote.subtotal)) }
            HStack {
                Text("MwSt. (\(Int(quote.vatRate))%)")
                Spacer()
                Text(Money.format(quote.vatAmount))
            }
            .foregroundStyle(.secondary)
            Divider().padding(.vertical, 4)
            HStack {
                Text("Brutto").fontWeight(.semibold)
                Spacer()
                Text(Money.format(quote.total)).fontWeight(.semibold)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 16) {
            if let customer = quote.customer {
                QuoteCustomerSummaryCard(customer: customer)
            }
            overviewCard
        }
    }

    private var overviewCard: some View {
        Card("Übersicht") {
            VStack(alignment: .leading, spacing: 4) {
                metaRow("Angebotsdatum", DateFmt.short(quote.date))
                metaRow("Gültig bis", DateFmt.short(quote.validUntil))
                metaRow("MwSt.-Satz", "\(Int(quote.vatRate)) %")
                if let sentAt = quote.sentAt {
                    metaRow("Verschickt am", DateFmt.short(sentAt))
                }
                if let acceptedAt = quote.acceptedAt {
                    metaRow("Angenommen am", DateFmt.short(acceptedAt))
                }
                if let declinedAt = quote.declinedAt {
                    metaRow("Abgelehnt am", DateFmt.short(declinedAt))
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
        guard let workspace = quote.customer?.workspace,
              let pdf = PDFRenderer.renderQuote(quote, workspace: workspace)
        else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "Angebot-\(quote.number).pdf"
        savePanel.title = "Angebot als PDF speichern"

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

private struct QuoteStatusButton: View {
    let status: QuoteStatus
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

private struct QuoteItemRow: View {
    let item: QuoteItem
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

private struct QuoteCustomerSummaryCard: View {
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
