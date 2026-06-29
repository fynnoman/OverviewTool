import Foundation
import SwiftData

enum QuoteStatus: String, Codable, CaseIterable, Identifiable {
    case draft, sent, accepted, declined, expired, converted
    var id: String { rawValue }
    var title: String {
        switch self {
        case .draft:     "Entwurf"
        case .sent:      "Verschickt"
        case .accepted:  "Angenommen"
        case .declined:  "Abgelehnt"
        case .expired:   "Abgelaufen"
        case .converted: "In Rechnung"
        }
    }
}

@Model
final class Quote {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var number: String
    var date: Date
    var validUntil: Date?
    var statusRaw: String
    var subtotal: Double
    var vatRate: Double
    var vatAmount: Double
    var total: Double
    var notes: String
    var sentAt: Date?
    var acceptedAt: Date?
    var declinedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var customer: Customer?

    @Relationship(deleteRule: .cascade, inverse: \QuoteItem.quote)
    var items: [QuoteItem] = []

    /// Manuell gesetzter Status — wird über `status` gelesen/geschrieben.
    var status: QuoteStatus {
        get { QuoteStatus(rawValue: statusRaw) ?? .draft }
        set {
            statusRaw = newValue.rawValue
            switch newValue {
            case .sent:     sentAt = sentAt ?? Date()
            case .accepted: acceptedAt = Date()
            case .declined: declinedAt = Date()
            default: break
            }
            updatedAt = Date()
        }
    }

    /// Status inkl. Auto-Ablauf: ein verschicktes Angebot, dessen
    /// Gültigkeit überschritten ist, wird als „Abgelaufen" angezeigt.
    /// Finale Zustände (accepted/declined/converted) bleiben unberührt.
    var effectiveStatus: QuoteStatus {
        guard let validUntil else { return status }
        if status == .sent && validUntil < Date() {
            return .expired
        }
        return status
    }

    init(
        id: UUID = UUID(),
        number: String,
        date: Date = Date(),
        validUntil: Date? = nil,
        status: QuoteStatus = .draft,
        subtotal: Double = 0,
        vatRate: Double = 19,
        vatAmount: Double = 0,
        total: Double = 0,
        notes: String = ""
    ) {
        self.id = id
        self.number = number
        self.date = date
        self.validUntil = validUntil
        self.statusRaw = status.rawValue
        self.subtotal = subtotal
        self.vatRate = vatRate
        self.vatAmount = vatAmount
        self.total = total
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
    }

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
final class QuoteItem {
    @Attribute(.unique) var id: UUID
    var details: String
    var quantity: Double
    var unitPrice: Double
    var order: Int

    var quote: Quote?

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
