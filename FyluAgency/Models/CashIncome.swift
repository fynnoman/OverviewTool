import Foundation
import SwiftData

/// Off-the-books income recorded per customer — no invoice, no VAT split.
/// Counted into the customer's gross revenue KPI so the dashboard reflects
/// reality even when something was settled in cash.
@Model
final class CashIncome {
    @Attribute(.unique) var id: UUID
    var details: String
    var amount: Double
    var date: Date
    var notes: String
    var createdAt: Date

    var customer: Customer?

    init(
        id: UUID = UUID(),
        details: String,
        amount: Double,
        date: Date = Date(),
        notes: String = ""
    ) {
        self.id = id
        self.details = details
        self.amount = amount
        self.date = date
        self.notes = notes
        self.createdAt = Date()
    }
}
