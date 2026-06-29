import Foundation
import SwiftData

/// Top-level tenant — a complete agency identity (own customers, leads,
/// invoices, business info, even its own OpenAI API key). All other
/// entities reference exactly one Workspace.
@Model
final class Workspace {
    @Attribute(.unique) var id: UUID
    var name: String

    // Business / invoice issuer info
    var businessName: String
    var businessAddress: String
    var businessEmail: String
    var businessPhone: String
    var taxId: String
    var iban: String
    var bic: String
    var bankName: String

    /// Logo PNG/JPG/SVG data (≤ 2 MB enforced in UI).
    var logoData: Data?
    var logoFilename: String?

    var vatRate: Double               // percent
    var paymentTermsDays: Int
    var invoiceNumberPrefix: String
    var invoiceNumberCounter: Int
    var invoiceFooter: String

    // Optional, weil sie über die SwiftData-Migration zu existierenden
    // Workspaces hinzukamen — Core Data kann mandatory new attributes
    // ohne in-store default nicht migrieren. Defaults werden in den
    // Accessoren bzw. an den Aufrufstellen via `??` ergänzt.
    var quoteNumberPrefix: String?
    var quoteNumberCounter: Int?
    var quoteValidityDays: Int?
    var quoteFooter: String?

    // KI-Profil — beschreibt das Business hinter dem Workspace, damit die
    // KI-Vorschläge (Upsells, Reminder-Texte) sich an die tatsächliche
    // Branche anpassen statt generisch "Webdesign-Agentur" zu raten.
    // Alle optional, damit existierende Workspaces ohne Migration laufen.
    var businessKind: String?         // z. B. "Webdesign-Agentur", "B2B-SaaS"
    var businessProfile: String?      // Freitext: was du verkaufst, an wen, USP
    var aiUpsellPlaybook: String?     // Optional: typische Upsells als Hinweis

    // Reminder-Schwellen (Tage). Nil = nutze App-Default.
    var leadReminderDays: Int?
    var customerReminderDays: Int?

    var layoutPrimaryHex: String
    var layoutAccentHex: String

    var openAIModel: String

    /// Per-workspace handle for the Keychain entry holding the API key.
    /// Each workspace can connect to a different OpenAI account.
    var keychainAccount: String

    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Customer.workspace)
    var customers: [Customer] = []

    @Relationship(deleteRule: .cascade, inverse: \Lead.workspace)
    var leads: [Lead] = []

    @Relationship(deleteRule: .cascade, inverse: \DeductibleExpense.workspace)
    var deductibleExpenses: [DeductibleExpense] = []

    @Relationship(deleteRule: .cascade, inverse: \Todo.workspace)
    var todos: [Todo] = []

    @Relationship(deleteRule: .cascade, inverse: \Idea.workspace)
    var ideas: [Idea] = []

    init(
        id: UUID = UUID(),
        name: String,
        businessName: String = "",
        businessAddress: String = "",
        businessEmail: String = "",
        businessPhone: String = "",
        taxId: String = "",
        iban: String = "",
        bic: String = "",
        bankName: String = "",
        logoData: Data? = nil,
        logoFilename: String? = nil,
        vatRate: Double = 19.0,
        paymentTermsDays: Int = 14,
        invoiceNumberPrefix: String = "RE",
        invoiceNumberCounter: Int = 1,
        invoiceFooter: String = "Vielen Dank für die gute Zusammenarbeit.",
        quoteNumberPrefix: String = "AN",
        quoteNumberCounter: Int = 1,
        quoteValidityDays: Int = 14,
        quoteFooter: String = "Wir freuen uns auf Ihre Rückmeldung.",
        layoutPrimaryHex: String = "#0B0B0E",
        layoutAccentHex: String = "#1F2937",
        openAIModel: String = "gpt-5.4-mini"
    ) {
        self.id = id
        self.name = name
        self.businessName = businessName.isEmpty ? name : businessName
        self.businessAddress = businessAddress
        self.businessEmail = businessEmail
        self.businessPhone = businessPhone
        self.taxId = taxId
        self.iban = iban
        self.bic = bic
        self.bankName = bankName
        self.logoData = logoData
        self.logoFilename = logoFilename
        self.vatRate = vatRate
        self.paymentTermsDays = paymentTermsDays
        self.invoiceNumberPrefix = invoiceNumberPrefix
        self.invoiceNumberCounter = invoiceNumberCounter
        self.invoiceFooter = invoiceFooter
        self.quoteNumberPrefix = quoteNumberPrefix
        self.quoteNumberCounter = quoteNumberCounter
        self.quoteValidityDays = quoteValidityDays
        self.quoteFooter = quoteFooter
        self.layoutPrimaryHex = layoutPrimaryHex
        self.layoutAccentHex = layoutAccentHex
        self.openAIModel = openAIModel
        self.keychainAccount = "workspace.\(id.uuidString).openai"
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    static func makeDefault(name: String) -> Workspace {
        Workspace(name: name, businessName: name)
    }

    /// App-weite Defaults für die Reminder-Schwellen. Werden genutzt, solange
    /// der Workspace selbst noch keinen eigenen Wert hat.
    static let defaultLeadReminderDays: Int = 7
    static let defaultCustomerReminderDays: Int = 30

    /// Effektive Schwellen (Workspace-Wert oder App-Default).
    var effectiveLeadReminderDays: Int {
        leadReminderDays ?? Workspace.defaultLeadReminderDays
    }
    var effectiveCustomerReminderDays: Int {
        customerReminderDays ?? Workspace.defaultCustomerReminderDays
    }

    /// Atomically pull the next invoice number and bump the counter.
    func consumeNextInvoiceNumber() -> String {
        let year = Calendar.current.component(.year, from: Date())
        let padded = String(format: "%04d", invoiceNumberCounter)
        let number = "\(invoiceNumberPrefix)-\(year)-\(padded)"
        invoiceNumberCounter += 1
        updatedAt = Date()
        return number
    }

    /// Same idea as invoices — pull next quote number and bump the counter.
    func consumeNextQuoteNumber() -> String {
        let prefix = quoteNumberPrefix ?? "AN"
        let counter = quoteNumberCounter ?? 1
        let year = Calendar.current.component(.year, from: Date())
        let padded = String(format: "%04d", counter)
        let number = "\(prefix)-\(year)-\(padded)"
        quoteNumberCounter = counter + 1
        updatedAt = Date()
        return number
    }
}
