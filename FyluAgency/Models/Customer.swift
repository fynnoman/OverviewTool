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

    var workspace: Workspace?

    @Relationship(deleteRule: .cascade, inverse: \Issue.customer)
    var issues: [Issue] = []

    @Relationship(deleteRule: .cascade, inverse: \Cost.customer)
    var costs: [Cost] = []

    @Relationship(deleteRule: .cascade, inverse: \Invoice.customer)
    var invoices: [Invoice] = []

    @Relationship(deleteRule: .cascade, inverse: \UploadedInvoice.customer)
    var uploadedInvoices: [UploadedInvoice] = []

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

    /// Total amount invoiced (gross). Computed on the fly because invoice
    /// status (paid / open) shouldn't affect what we count as billed.
    var totalInvoiced: Double {
        invoices.reduce(0) { $0 + $1.total }
    }

    var totalNetInvoiced: Double {
        invoices.reduce(0) { $0 + $1.subtotal }
    }

    var totalVatInvoiced: Double {
        invoices.reduce(0) { $0 + $1.vatAmount }
    }

    var openIssuesCount: Int {
        issues.filter { !$0.done }.count
    }

    var monthlyRecurringCost: Double {
        costs.filter { $0.frequency == .monthly }.reduce(0) { $0 + $1.amount }
    }
}
