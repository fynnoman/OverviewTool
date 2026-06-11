import Foundation
import SwiftData

enum InvoiceStatus: String, Codable, CaseIterable, Identifiable {
    case draft, sent, paid, overdue
    var id: String { rawValue }
    var title: String {
        switch self {
        case .draft: "Entwurf"
        case .sent: "Verschickt"
        case .paid: "Bezahlt"
        case .overdue: "Überfällig"
        }
    }
}

@Model
final class Invoice {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var number: String
    var date: Date
    var dueDate: Date?
    var statusRaw: String
    var subtotal: Double
    var vatRate: Double
    var vatAmount: Double
    var total: Double
    var notes: String
    var paidAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var customer: Customer?

    @Relationship(deleteRule: .cascade, inverse: \InvoiceItem.invoice)
    var items: [InvoiceItem] = []

    var status: InvoiceStatus {
        get { InvoiceStatus(rawValue: statusRaw) ?? .draft }
        set {
            statusRaw = newValue.rawValue
            paidAt = newValue == .paid ? Date() : nil
            updatedAt = Date()
        }
    }

    init(
        id: UUID = UUID(),
        number: String,
        date: Date = Date(),
        dueDate: Date? = nil,
        status: InvoiceStatus = .draft,
        subtotal: Double = 0,
        vatRate: Double = 19,
        vatAmount: Double = 0,
        total: Double = 0,
        notes: String = ""
    ) {
        self.id = id
        self.number = number
        self.date = date
        self.dueDate = dueDate
        self.statusRaw = status.rawValue
        self.subtotal = subtotal
        self.vatRate = vatRate
        self.vatAmount = vatAmount
        self.total = total
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Recalculates totals from current line items.
    func recompute() {
        let sub = items.reduce(0) { $0 + $1.lineTotal }
        let vat = (sub * vatRate / 100).rounded2()
        subtotal = sub.rounded2()
        vatAmount = vat
        total = (sub + vat).rounded2()
        updatedAt = Date()
    }
}

@Model
final class InvoiceItem {
    @Attribute(.unique) var id: UUID
    var details: String
    var quantity: Double
    var unitPrice: Double
    var order: Int

    var invoice: Invoice?

    var lineTotal: Double {
        (quantity * unitPrice).rounded2()
    }

    init(
        id: UUID = UUID(),
        details: String,
        quantity: Double = 1,
        unitPrice: Double = 0,
        order: Int = 0
    ) {
        self.id = id
        self.details = details
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.order = order
    }
}

extension Double {
    func rounded2() -> Double {
        (self * 100).rounded() / 100
    }
}
