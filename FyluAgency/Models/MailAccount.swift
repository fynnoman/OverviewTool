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

    /// Concrete step-by-step for the provider. Rendered as a numbered list
    /// in the add-account sheet. Shipping this alongside `authHint` because
    /// the free-text hint alone doesn't cut it — Google especially: users
    /// see "Passkey" as their sign-in method and try to type that here,
    /// which never works for IMAP.
    var setupSteps: [String] {
        switch self {
        case .gmail:
            return [
                #"Google akzeptiert für IMAP keine Passkeys und keine normalen Passwörter — du brauchst ein separates App-Passwort."#,
                #"Voraussetzung: 2-Faktor-Authentifizierung ist an. Falls nicht: myaccount.google.com → Sicherheit → 2-Schritt-Verifizierung aktivieren."#,
                #"App-Passwort erstellen: myaccount.google.com/apppasswords → App-Name 'Fylu Agency' eintragen → 'Erstellen'."#,
                #"Google zeigt dir dann 16 Zeichen in 4er-Gruppen (z. B. 'abcd efgh ijkl mnop'). Genau das kommt hier unten ins Passwort-Feld. Leerzeichen darfst du drin lassen oder rausnehmen."#,
                #"Server und Port füllt Fylu automatisch aus (imap.gmail.com, 993, TLS)."#
            ]
        case .icloud:
            return [
                #"iCloud akzeptiert für IMAP nur App-spezifische Passwörter."#,
                #"appleid.apple.com → Anmelden → Anmeldung & Sicherheit → App-spezifische Passwörter → Generieren."#,
                #"Name z. B. 'Fylu Agency' vergeben, das erzeugte Passwort ins Feld unten kopieren."#,
                #"Server und Port sind vorausgefüllt (imap.mail.me.com, 993)."#
            ]
        case .outlook:
            return [
                #"Bei Konten ohne 2FA reicht das normale Passwort."#,
                #"Bei aktivem 2FA: account.microsoft.com/security → App-Kennwörter erstellen → hier eintragen."#,
                #"Server und Port sind vorausgefüllt (outlook.office365.com, 993)."#
            ]
        case .yahoo:
            return [
                #"Yahoo verlangt ein App-Passwort, nicht dein Login-Passwort."#,
                #"login.yahoo.com/account/security → App-Passwort erzeugen."#,
                #"Passwort hier eintragen. Server/Port sind vorausgefüllt."#
            ]
        case .gmx, .webde:
            return [
                #"IMAP im Web-Postfach freischalten: Einstellungen → POP3/IMAP-Abruf → IMAP aktivieren."#,
                #"Dann hier dein normales Postfach-Passwort eintragen. Server/Port sind vorausgefüllt."#
            ]
        case .custom:
            return []
        }
    }

    /// Optional deep link that opens exactly the page where the user creates
    /// the credential. Shown as a "Anleitung öffnen"-button in the sheet.
    var setupURL: URL? {
        switch self {
        case .gmail:   return URL(string: "https://myaccount.google.com/apppasswords")
        case .icloud:  return URL(string: "https://appleid.apple.com/account/manage")
        case .outlook: return URL(string: "https://account.microsoft.com/security")
        case .yahoo:   return URL(string: "https://login.yahoo.com/account/security")
        case .gmx:     return URL(string: "https://www.gmx.net/produkte/mail/imap-pop3/")
        case .webde:   return URL(string: "https://hilfe.web.de/pop-imap/imap.html")
        case .custom:  return nil
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
