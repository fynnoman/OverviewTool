import Foundation
import SwiftData

/// Status einer Verkaufs-/Marketing-Idee oder -Masche.
/// Wird zur visuellen Einordnung in der Pipeline verwendet.
enum IdeaStatus: String, Codable, CaseIterable, Identifiable {
    case idea         // Notiert, noch nicht ausprobiert
    case testing      // Wird gerade getestet
    case working      // Validiert, funktioniert
    case scaled       // Im Standard-Playbook angekommen
    case abandoned    // Geht nicht, eingestellt

    var id: String { rawValue }
    var title: String {
        switch self {
        case .idea:      "Notiert"
        case .testing:   "Im Test"
        case .working:   "Funktioniert"
        case .scaled:    "Skaliert"
        case .abandoned: "Verworfen"
        }
    }
    var color: String {
        switch self {
        case .idea:      "gray"
        case .testing:   "orange"
        case .working:   "green"
        case .scaled:    "blue"
        case .abandoned: "red"
        }
    }

    static let pipelineOrder: [IdeaStatus] = [.idea, .testing, .working, .scaled, .abandoned]
}

/// Verkaufs-Masche, Outreach-Trick oder allgemeine Marketing-Idee.
/// Du kannst sie eintragen, dokumentieren wie oft sie probiert wurde,
/// wie oft sie funktioniert hat, und einen freien Notiz-Log pflegen.
@Model
final class Idea {
    @Attribute(.unique) var id: UUID
    var title: String
    var category: String              // z. B. "Cold-Email", "Demo-Skript", "Pricing"
    var details: String               // Beschreibung der Idee/Masche
    var statusRaw: String
    var rating: Int                   // 1–5, freie Selbst-Einschätzung
    var triedCount: Int               // wie oft angewendet
    var winCount: Int                 // wie oft erfolgreich (z. B. zu Lead/Kunde geführt)
    var notes: String                 // freier Beobachtungs-Log über die Zeit
    var lastTriedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var workspace: Workspace?

    var status: IdeaStatus {
        get { IdeaStatus(rawValue: statusRaw) ?? .idea }
        set { statusRaw = newValue.rawValue; updatedAt = Date() }
    }

    /// Erfolgsquote in Prozent (0–100). 0, wenn noch nichts versucht wurde.
    var successRate: Double {
        guard triedCount > 0 else { return 0 }
        return Double(winCount) / Double(triedCount) * 100.0
    }

    init(
        id: UUID = UUID(),
        title: String,
        category: String = "",
        details: String = "",
        status: IdeaStatus = .idea,
        rating: Int = 0,
        triedCount: Int = 0,
        winCount: Int = 0,
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.details = details
        self.statusRaw = status.rawValue
        self.rating = max(0, min(5, rating))
        self.triedCount = max(0, triedCount)
        self.winCount = max(0, winCount)
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Bumpt den Versuchs-Zähler und stempelt das Datum.
    func recordTry() {
        triedCount += 1
        lastTriedAt = Date()
        updatedAt = Date()
    }

    /// Bumpt sowohl Versuche als auch Erfolge.
    func recordWin() {
        triedCount += 1
        winCount += 1
        lastTriedAt = Date()
        updatedAt = Date()
    }
}
