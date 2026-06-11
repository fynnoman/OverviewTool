import Foundation
import SwiftData

enum CostFrequency: String, Codable, CaseIterable, Identifiable {
    case once, monthly, yearly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .once: "einmalig"
        case .monthly: "monatlich"
        case .yearly: "jährlich"
        }
    }
}

@Model
final class Cost {
    @Attribute(.unique) var id: UUID
    var details: String
    var amount: Double
    var frequencyRaw: String
    var dueDate: Date?
    var createdAt: Date

    var customer: Customer?

    var frequency: CostFrequency {
        get { CostFrequency(rawValue: frequencyRaw) ?? .once }
        set { frequencyRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        details: String,
        amount: Double,
        frequency: CostFrequency = .once,
        dueDate: Date? = nil
    ) {
        self.id = id
        self.details = details
        self.amount = amount
        self.frequencyRaw = frequency.rawValue
        self.dueDate = dueDate
        self.createdAt = Date()
    }
}
