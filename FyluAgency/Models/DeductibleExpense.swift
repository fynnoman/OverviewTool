import Foundation
import SwiftData

/// Absetzbare Ausgabe — nicht an einen Kunden gebunden.
/// Wird NICHT in den Reingewinn verrechnet (rein für Buchhaltung &
/// Umsatzsteuer-Voranmeldung — Vorsteuer-Tracking).
@Model
final class DeductibleExpense {
    @Attribute(.unique) var id: UUID
    var details: String
    var amount: Double         // brutto
    var vatAmount: Double      // enthaltene MwSt (Vorsteuer)
    var date: Date
    var category: String       // freitext, z. B. "Material", "Büro", "Fahrtkosten"
    var notes: String
    var createdAt: Date

    var workspace: Workspace?

    init(
        id: UUID = UUID(),
        details: String,
        amount: Double,
        vatAmount: Double = 0,
        date: Date = Date(),
        category: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.details = details
        self.amount = amount
        self.vatAmount = vatAmount
        self.date = date
        self.category = category
        self.notes = notes
        self.createdAt = Date()
    }

    var net: Double { amount - vatAmount }
}
