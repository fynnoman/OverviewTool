import Foundation
import SwiftData

enum LeadEmailDirection: String, Codable, CaseIterable, Identifiable {
    case sent, received
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sent:     "Gesendet"
        case .received: "Empfangen"
        }
    }
}

@Model
final class LeadEmail: Identifiable {
    @Attribute(.unique) var id: UUID
    var directionRaw: String
    var subject: String
    var body: String
    var sentAt: Date?
    var summary: String
    var summaryUpdatedAt: Date?
    var createdAt: Date

    var lead: Lead?

    var direction: LeadEmailDirection {
        get { LeadEmailDirection(rawValue: directionRaw) ?? .sent }
        set { directionRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        direction: LeadEmailDirection = .sent,
        subject: String = "",
        body: String,
        sentAt: Date? = nil,
        summary: String = "",
        summaryUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.directionRaw = direction.rawValue
        self.subject = subject
        self.body = body
        self.sentAt = sentAt
        self.summary = summary
        self.summaryUpdatedAt = summaryUpdatedAt
        self.createdAt = Date()
    }
}
