import Foundation
import SwiftData

@Model
final class Issue {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var price: Double?
    var done: Bool
    var doneAt: Date?
    var order: Int
    var createdAt: Date

    var customer: Customer?

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        price: Double? = nil,
        done: Bool = false,
        order: Int = 0
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.price = price
        self.done = done
        self.order = order
        self.createdAt = Date()
    }

    func toggle() {
        done.toggle()
        doneAt = done ? Date() : nil
    }
}
