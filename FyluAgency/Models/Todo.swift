import Foundation
import SwiftData

/// Persönliche To-Dos des Benutzers — *nicht* die Aufgaben/Wünsche des
/// Kunden (die liegen weiterhin im `Issue`-Modell).
///
/// Ein Todo kann optional einem Kunden zugeordnet werden, z. B.
/// „Claude Cowork nutzen für Gianluca" — das ist eine eigene Aufgabe,
/// nicht ein Wunsch des Kunden.
@Model
final class Todo {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var done: Bool
    var doneAt: Date?
    var dueDate: Date?
    var createdAt: Date

    var workspace: Workspace?
    var customer: Customer?

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        done: Bool = false,
        dueDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.done = done
        self.doneAt = done ? Date() : nil
        self.dueDate = dueDate
        self.createdAt = Date()
    }

    func toggle() {
        done.toggle()
        doneAt = done ? Date() : nil
    }
}
