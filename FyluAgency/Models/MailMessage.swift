import Foundation
import SwiftData

/// A single synced email message. We store just enough to render a list and
/// a reading pane — full MIME/attachment handling is out of scope for v1.
///
/// `remoteUID` + `account.id` together are the natural key: IMAP guarantees a
/// message's UID is stable for the lifetime of a mailbox, so we use it to
/// de-duplicate on subsequent syncs.
@Model
final class MailMessage {
    @Attribute(.unique) var id: UUID
    /// IMAP UID in the mailbox on the server side (stable per mailbox).
    var remoteUID: UInt32
    /// IMAP folder this was fetched from. v1 only pulls INBOX.
    var folder: String
    var subject: String
    var fromName: String
    var fromAddress: String
    var toRaw: String        // comma-joined addresses; parsing done on read
    var date: Date
    /// First ~500 chars of the plain text body — used for the preview line.
    var preview: String
    /// Full plain-text body (best-effort decode). HTML-only mails currently
    /// arrive with tags stripped.
    var bodyText: String
    var isSeen: Bool
    var isFlagged: Bool
    var syncedAt: Date

    var account: MailAccount?

    init(
        id: UUID = UUID(),
        remoteUID: UInt32,
        folder: String = "INBOX",
        subject: String,
        fromName: String,
        fromAddress: String,
        toRaw: String,
        date: Date,
        preview: String,
        bodyText: String,
        isSeen: Bool = false,
        isFlagged: Bool = false
    ) {
        self.id = id
        self.remoteUID = remoteUID
        self.folder = folder
        self.subject = subject
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.toRaw = toRaw
        self.date = date
        self.preview = preview
        self.bodyText = bodyText
        self.isSeen = isSeen
        self.isFlagged = isFlagged
        self.syncedAt = Date()
    }

    /// Human-readable sender for list rows.
    var senderDisplay: String {
        fromName.isEmpty ? fromAddress : fromName
    }
}
