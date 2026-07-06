import Foundation
import SwiftData

/// Well-known providers we ship with pre-filled IMAP/SMTP endpoints. `custom`
/// lets the user enter host/port manually for anything else (own domain,
/// smaller providers, corporate mail).
enum MailProvider: String, Codable, CaseIterable, Identifiable {
    case gmail, outlook, icloud, gmx, webde, yahoo, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gmail:   "Gmail"
        case .outlook: "Outlook / Microsoft 365"
        case .icloud:  "iCloud Mail"
        case .gmx:     "GMX"
        case .webde:   "Web.de"
        case .yahoo:   "Yahoo Mail"
        case .custom:  "Anderer Anbieter (IMAP)"
        }
    }
    var symbolName: String {
        switch self {
        case .gmail:   "envelope.fill"
        case .outlook: "envelope.fill"
        case .icloud:  "icloud.fill"
        case .gmx, .webde, .yahoo, .custom: "at"
        }
    }
    /// User-facing hint about how to authenticate. Gmail/iCloud enforce
    /// app-passwords when 2FA is on — this is the single most common source
    /// of "wrong password" reports so we surface it prominently in the UI.
    var authHint: String? {
        switch self {
        case .gmail:
            "Bei aktiver 2FA benötigst du ein App-Passwort. Erstelle es unter myaccount.google.com → Sicherheit → App-Passwörter."
        case .icloud:
            "iCloud verlangt ein App-spezifisches Passwort. Erstelle es unter appleid.apple.com → Anmeldung & Sicherheit → App-spezifische Passwörter."
        case .outlook:
            "Outlook/Microsoft 365 unterstützt IMAP mit Kontopasswort. Bei aktivierter 2FA App-Passwort erforderlich."
        case .yahoo:
            "Yahoo verlangt ein App-Passwort (nicht das reguläre Login-Passwort)."
        case .gmx, .webde:
            "IMAP muss im Web-Postfach unter Einstellungen → POP3/IMAP-Abruf aktiviert werden."
        case .custom:
            nil
        }
    }
}

/// A connected mailbox. One row per (provider, address) pair. Password lives
/// in the Keychain — never in SwiftData — and is looked up via
/// `keychainAccount`.
@Model
final class MailAccount {
    @Attribute(.unique) var id: UUID
    var providerRaw: String
    var displayName: String
    var emailAddress: String
    var imapHost: String
    var imapPort: Int
    var imapUseTLS: Bool
    var username: String
    /// Keychain handle for the IMAP password. Never store the password itself.
    var keychainAccount: String
    var lastSyncAt: Date?
    var lastSyncError: String?
    var isEnabled: Bool
    var createdAt: Date

    var workspace: Workspace?

    @Relationship(deleteRule: .cascade, inverse: \MailMessage.account)
    var messages: [MailMessage] = []

    var provider: MailProvider {
        get { MailProvider(rawValue: providerRaw) ?? .custom }
        set { providerRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        provider: MailProvider,
        displayName: String,
        emailAddress: String,
        imapHost: String,
        imapPort: Int = 993,
        imapUseTLS: Bool = true,
        username: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.providerRaw = provider.rawValue
        self.displayName = displayName
        self.emailAddress = emailAddress
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.imapUseTLS = imapUseTLS
        self.username = username
        self.keychainAccount = "mailaccount.\(id.uuidString).imap"
        self.isEnabled = isEnabled
        self.createdAt = Date()
    }
}
