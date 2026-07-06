import Foundation

/// Server presets for the well-known providers. Ports/hosts follow each
/// provider's public IMAP documentation (state as of 2026). If a provider
/// changes their endpoints the presets can be adjusted in one place.
struct MailProviderPreset {
    let imapHost: String
    let imapPort: Int
    let imapUseTLS: Bool
    /// Whether the local part of the email address is used as the login
    /// (some providers), vs. the full email address (most providers).
    let loginIsFullEmail: Bool
}

enum MailProviderPresets {
    static func preset(for provider: MailProvider) -> MailProviderPreset? {
        switch provider {
        case .gmail:
            return MailProviderPreset(imapHost: "imap.gmail.com",       imapPort: 993, imapUseTLS: true, loginIsFullEmail: true)
        case .outlook:
            return MailProviderPreset(imapHost: "outlook.office365.com", imapPort: 993, imapUseTLS: true, loginIsFullEmail: true)
        case .icloud:
            return MailProviderPreset(imapHost: "imap.mail.me.com",      imapPort: 993, imapUseTLS: true, loginIsFullEmail: true)
        case .gmx:
            return MailProviderPreset(imapHost: "imap.gmx.net",          imapPort: 993, imapUseTLS: true, loginIsFullEmail: true)
        case .webde:
            return MailProviderPreset(imapHost: "imap.web.de",           imapPort: 993, imapUseTLS: true, loginIsFullEmail: true)
        case .yahoo:
            return MailProviderPreset(imapHost: "imap.mail.yahoo.com",   imapPort: 993, imapUseTLS: true, loginIsFullEmail: true)
        case .custom:
            return nil
        }
    }
}
