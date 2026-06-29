import Foundation
import SwiftData

@Model
final class Customer {
    @Attribute(.unique) var id: UUID
    var name: String
    var company: String
    var email: String
    var phone: String
    var address: String
    var taxId: String
    var notes: String
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    /// Manuell markierter Zeitpunkt des letzten Kontakts (Mail, Call, Treffen).
    /// Optional — existierende Kunden behalten nil, bis du das erste Mal
    /// "Kontakt notiert" drückst.
    var lastContactAt: Date?

    var workspace: Workspace?

    @Relationship(deleteRule: .cascade, inverse: \Issue.customer)
    var issues: [Issue] = []

    @Relationship(deleteRule: .cascade, inverse: \Cost.customer)
    var costs: [Cost] = []

    @Relationship(deleteRule: .cascade, inverse: \Invoice.customer)
    var invoices: [Invoice] = []

    @Relationship(deleteRule: .cascade, inverse: \Quote.customer)
    var quotes: [Quote] = []

    @Relationship(deleteRule: .cascade, inverse: \UploadedInvoice.customer)
    var uploadedInvoices: [UploadedInvoice] = []

    @Relationship(deleteRule: .cascade, inverse: \CashIncome.customer)
    var cashIncomes: [CashIncome] = []

    init(
        id: UUID = UUID(),
        name: String,
        company: String = "",
        email: String = "",
        phone: String = "",
        address: String = "",
        taxId: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.company = company
        self.email = email
        self.phone = phone
        self.address = address
        self.taxId = taxId
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Steuerpflichtiger Brutto-Umsatz aus echten Rechnungen — fließt in
    /// MwSt./Umsatzsteuer-Berechnungen ein.
    /// Cash-Einnahmen (siehe `totalCashIncome`) sind hier bewusst NICHT
    /// enthalten, weil sie ohne Rechnung & ohne Umsatzsteuer gebucht sind.
    var totalInvoiced: Double {
        invoices.reduce(0) { $0 + $1.total }
    }

    var totalNetInvoiced: Double {
        invoices.reduce(0) { $0 + $1.subtotal }
    }

    var totalVatInvoiced: Double {
        invoices.reduce(0) { $0 + $1.vatAmount }
    }

    /// Bareinnahmen — echtes Geld, aber steuerfrei für die App-internen
    /// Umsatzsteuer-KPIs.
    var totalCashIncome: Double {
        cashIncomes.reduce(0) { $0 + $1.amount }
    }

    /// Tatsächlich eingenommenes Geld (Rechnungen + Bareinnahmen) — nur
    /// für Reingewinn-Berechnungen, NICHT für USt.
    var totalIncomeAll: Double {
        totalInvoiced + totalCashIncome
    }

    /// Summe aller dem Kunden zugeordneten Kosten (egal welcher Frequenz —
    /// der eingetragene Betrag wird so gezählt, wie er erfasst wurde).
    var totalCosts: Double {
        costs.reduce(0) { $0 + $1.amount }
    }

    /// Reingewinn = alles was reinkam (Rechnungen + Bar) minus Kosten.
    var profit: Double {
        totalIncomeAll - totalCosts
    }

    var openIssuesCount: Int {
        issues.filter { !$0.done }.count
    }

    /// Summe der `price`-Werte aller offenen Aufgaben — was an Umsatz
    /// reinkäme, wenn man die heute alle abschließt.
    var openIssuesValue: Double {
        issues.filter { !$0.done }.compactMap(\.price).reduce(0, +)
    }

    var monthlyRecurringCost: Double {
        costs.filter { $0.frequency == .monthly }.reduce(0) { $0 + $1.amount }
    }
}
