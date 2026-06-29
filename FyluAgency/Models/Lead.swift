import Foundation
import SwiftData

enum LeadStatus: String, Codable, CaseIterable, Identifiable {
    case new, contacted, meeting, proposal, won, lost
    var id: String { rawValue }
    var title: String {
        switch self {
        case .new:        "Neu"
        case .contacted:  "Kontaktiert"
        case .meeting:    "Termin"
        case .proposal:   "Angebot raus"
        case .won:        "Gewonnen"
        case .lost:       "Verloren"
        }
    }
    var color: String {
        switch self {
        case .new, .contacted: "blue"
        case .meeting, .proposal: "orange"
        case .won: "green"
        case .lost: "red"
        }
    }
    static let pipelineOrder: [LeadStatus] = [.new, .contacted, .meeting, .proposal, .won, .lost]
}

@Model
final class Lead {
    @Attribute(.unique) var id: UUID
    var name: String
    var company: String
    var email: String
    var phone: String
    var source: String
    var statusRaw: String
    var expectedValue: Double?
    var offerDescription: String?   // wofür das Angebot ist, z. B. „Website-Setup + SEO"
    var notes: String
    var lastContactAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var workspace: Workspace?

    @Relationship(deleteRule: .cascade, inverse: \Issue.lead)
    var issues: [Issue] = []

    @Relationship(deleteRule: .cascade, inverse: \LeadEmail.lead)
    var emails: [LeadEmail] = []

    var status: LeadStatus {
        get { LeadStatus(rawValue: statusRaw) ?? .new }
        set { statusRaw = newValue.rawValue; updatedAt = Date(); lastContactAt = Date() }
    }

    init(
        id: UUID = UUID(),
        name: String,
        company: String = "",
        email: String = "",
        phone: String = "",
        source: String = "",
        status: LeadStatus = .new,
        expectedValue: Double? = nil,
        offerDescription: String? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.company = company
        self.email = email
        self.phone = phone
        self.source = source
        self.statusRaw = status.rawValue
        self.expectedValue = expectedValue
        self.offerDescription = (offerDescription?.isEmpty ?? true) ? nil : offerDescription
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
