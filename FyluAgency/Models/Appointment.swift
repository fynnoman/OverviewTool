import Foundation
import SwiftData

enum AppointmentSource: String, Codable, CaseIterable, Identifiable {
    case manual, email
    var id: String { rawValue }
    var title: String {
        switch self {
        case .manual: "Manuell"
        case .email:  "Aus E-Mail"
        }
    }
}

/// Vorgefertigte Termin-Farben. Werden als Hex-String auf dem Appointment
/// abgelegt — eigene Hexwerte aus alten Daten bleiben dadurch gültig.
enum AppointmentColor: String, CaseIterable, Identifiable {
    case blue, green, orange, red, purple, pink, yellow, teal, gray
    var id: String { rawValue }
    var hex: String {
        switch self {
        case .blue:   "#3B82F6"
        case .green:  "#10B981"
        case .orange: "#F59E0B"
        case .red:    "#EF4444"
        case .purple: "#8B5CF6"
        case .pink:   "#EC4899"
        case .yellow: "#FBBF24"
        case .teal:   "#14B8A6"
        case .gray:   "#6B7280"
        }
    }
    var title: String {
        switch self {
        case .blue:   "Blau"
        case .green:  "Grün"
        case .orange: "Orange"
        case .red:    "Rot"
        case .purple: "Lila"
        case .pink:   "Pink"
        case .yellow: "Gelb"
        case .teal:   "Türkis"
        case .gray:   "Grau"
        }
    }
}

@Model
final class Appointment {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var startsAt: Date
    var endsAt: Date?
    var location: String
    var isAllDay: Bool
    var sourceRaw: String
    /// Set when this appointment was auto-created from a `LeadEmail`. Used to
    /// avoid creating duplicates if the email is re-summarized.
    var sourceEmailID: UUID?
    var createdAt: Date
    var updatedAt: Date

    var workspace: Workspace?
    var lead: Lead?
    /// Optional: Termin direkt einem Kunden zuordnen (zusätzlich oder
    /// alternativ zu einem Lead). Bestehende Termine bleiben unverändert
    /// (`nil`).
    var customer: Customer?
    /// Optionaler Farb-Hex für die visuelle Markierung des Termins. `nil`
    /// = keine Farbe gesetzt (Standardstyling wie bisher).
    var colorHex: String?

    var source: AppointmentSource {
        get { AppointmentSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue; updatedAt = Date() }
    }

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        startsAt: Date,
        endsAt: Date? = nil,
        location: String = "",
        isAllDay: Bool = false,
        source: AppointmentSource = .manual,
        sourceEmailID: UUID? = nil,
        colorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.location = location
        self.isAllDay = isAllDay
        self.sourceRaw = source.rawValue
        self.sourceEmailID = sourceEmailID
        self.colorHex = colorHex
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// Parses the ISO-ish date strings the LLM returns. Falls back to a series of
/// formats and interprets timezone-less strings as Europe/Berlin local time.
enum AppointmentDateParser {
    static func parse(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }

        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        for fmt in [
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd"
        ] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

enum AppointmentFmt {
    static let timeShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()
    static let dateLong: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, d. MMMM yyyy"
        return f
    }()
    static let dateMedium: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EE, dd.MM."
        return f
    }()
    static let weekdayShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EE"
        return f
    }()
}
