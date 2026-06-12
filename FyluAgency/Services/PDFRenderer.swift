import SwiftUI
import PDFKit
import AppKit

/// Renders an `Invoice` to PDF using SwiftUI's `ImageRenderer`. The
/// template intentionally lives close to the renderer so changing the
/// look stays a one-file edit.
enum PDFRenderer {
    @MainActor
    static func renderInvoice(_ invoice: Invoice, workspace: Workspace) -> Data? {
        guard let customer = invoice.customer else { return nil }
        // A4 at 72 dpi = 595 x 842 pt
        let pageSize = CGSize(width: 595, height: 842)
        let view = InvoiceTemplate(invoice: invoice, customer: customer, workspace: workspace)
            .frame(width: pageSize.width, height: pageSize.height)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: pageSize.width, height: pageSize.height)

        let output = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return nil }

        renderer.render { _, render in
            context.beginPDFPage(nil)
            render(context)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }
}

struct InvoiceTemplate: View {
    let invoice: Invoice
    let customer: Customer
    let workspace: Workspace

    private var primary: Color { Color(hex: workspace.layoutPrimaryHex) }
    private var accent:  Color { Color(hex: workspace.layoutAccentHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().padding(.vertical, 24)

            customerBlock
                .padding(.bottom, 24)

            itemsTable

            HStack {
                Spacer()
                totalsBlock
                    .frame(width: 240)
            }
            .padding(.top, 16)

            if !invoice.notes.isEmpty {
                notes
                    .padding(.top, 24)
            }

            paymentBlock
                .padding(.top, 28)

            Spacer(minLength: 0)

            footer
        }
        .padding(48)
        .background(Color.white)
        .foregroundColor(.black)
        .font(.system(size: 10))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                if let data = workspace.logoData, let nsImg = NSImage(data: data) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 130, maxHeight: 50)
                }
                Text(workspace.businessName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(primary)
                Text(workspace.businessAddress)
                    .foregroundColor(.gray)
                if !workspace.businessEmail.isEmpty { Text(workspace.businessEmail).foregroundColor(.gray) }
                if !workspace.businessPhone.isEmpty { Text(workspace.businessPhone).foregroundColor(.gray) }
                if !workspace.taxId.isEmpty { Text("USt-ID: \(workspace.taxId)").foregroundColor(.gray) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("RECHNUNG")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(primary)
                metaRow("Nr.", invoice.number)
                metaRow("Datum", DateFmt.short(invoice.date))
                metaRow("Fällig", DateFmt.short(invoice.dueDate))
            }
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundColor(.gray)
            Text(value).fontWeight(.semibold)
        }
        .font(.system(size: 10))
    }

    private var customerBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RECHNUNG AN")
                .font(.system(size: 8, weight: .semibold))
                .tracking(1)
                .foregroundColor(.gray)
                .padding(.bottom, 4)
            Text(customer.name).font(.system(size: 11, weight: .semibold))
            if !customer.company.isEmpty { Text(customer.company).foregroundColor(.black.opacity(0.75)) }
            ForEach(Array(customer.address.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                Text(String(line)).foregroundColor(.black.opacity(0.75))
            }
            if !customer.taxId.isEmpty {
                Text("USt-ID: \(customer.taxId)").foregroundColor(.gray).padding(.top, 4)
            }
        }
    }

    private var itemsTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Leistung").frame(maxWidth: .infinity, alignment: .leading)
                Text("Anzahl").frame(width: 50, alignment: .trailing)
                Text("Preis").frame(width: 80, alignment: .trailing)
                Text("Summe").frame(width: 90, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(accent)

            ForEach(invoice.items.sorted(by: { $0.order < $1.order }), id: \.id) { item in
                HStack {
                    Text(item.details).frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.quantity.removingDecimalsIfWhole())
                        .frame(width: 50, alignment: .trailing)
                    Text(Money.format(item.unitPrice))
                        .frame(width: 80, alignment: .trailing)
                    Text(Money.format(item.lineTotal))
                        .frame(width: 90, alignment: .trailing)
                }
                .font(.system(size: 10))
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.gray.opacity(0.3)), alignment: .bottom)
            }
        }
        .overlay(Rectangle().stroke(accent, lineWidth: 1))
    }

    private var totalsBlock: some View {
        VStack(spacing: 4) {
            totalRow("Netto", Money.format(invoice.subtotal))
            totalRow("MwSt. \(String(format: "%.0f", invoice.vatRate))%", Money.format(invoice.vatAmount))
            Divider().padding(.vertical, 4)
            HStack {
                Text("Gesamt").font(.system(size: 12, weight: .bold))
                Spacer()
                Text(Money.format(invoice.total)).font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(primary)
        }
    }

    private func totalRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
        }
    }

    private var notes: some View {
        Text(invoice.notes)
            .font(.system(size: 9.5))
            .foregroundColor(.black.opacity(0.75))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.08))
            .overlay(Rectangle().frame(width: 2).foregroundColor(accent), alignment: .leading)
    }

    private var paymentBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Zahlungsinformationen").font(.system(size: 9, weight: .semibold))
            Text("Bitte überweise den Gesamtbetrag bis spätestens \(DateFmt.short(invoice.dueDate)) unter Angabe der Rechnungsnummer \(invoice.number).")
                .font(.system(size: 9))
                .foregroundColor(.black.opacity(0.7))
            if !workspace.iban.isEmpty {
                Text("\(workspace.bankName.isEmpty ? "" : workspace.bankName + " · ")IBAN \(workspace.iban)\(workspace.bic.isEmpty ? "" : " · BIC " + workspace.bic)")
                    .font(.system(size: 9))
                    .foregroundColor(.black.opacity(0.7))
            }
        }
        .padding(.top, 8)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.gray.opacity(0.3)), alignment: .top)
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack {
            Text(workspace.invoiceFooter)
            Spacer()
            Text(workspace.businessName)
        }
        .font(.system(size: 8))
        .foregroundColor(.gray)
        .padding(.top, 10)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.gray.opacity(0.3)), alignment: .top)
    }
}

private extension Double {
    func removingDecimalsIfWhole() -> String {
        self.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(self))
            : String(format: "%.2f", self)
    }
}
