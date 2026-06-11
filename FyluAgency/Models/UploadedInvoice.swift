import Foundation
import SwiftData

@Model
final class UploadedInvoice {
    @Attribute(.unique) var id: UUID
    var filename: String
    var fileURL: URL?
    var extractedTotal: Double?
    var extractedNet: Double?
    var extractedVat: Double?
    var extractedDate: Date?
    var extractedRaw: String
    var statusRaw: String
    var uploadedAt: Date

    var customer: Customer?

    /// Raw status: pending | parsed | manual (couldn't parse)
    enum ParseStatus: String {
        case pending, parsed, manual
    }

    var status: ParseStatus {
        ParseStatus(rawValue: statusRaw) ?? .pending
    }

    init(
        id: UUID = UUID(),
        filename: String,
        fileURL: URL? = nil,
        extractedTotal: Double? = nil,
        extractedNet: Double? = nil,
        extractedVat: Double? = nil,
        extractedDate: Date? = nil,
        extractedRaw: String = "",
        status: ParseStatus = .pending
    ) {
        self.id = id
        self.filename = filename
        self.fileURL = fileURL
        self.extractedTotal = extractedTotal
        self.extractedNet = extractedNet
        self.extractedVat = extractedVat
        self.extractedDate = extractedDate
        self.extractedRaw = extractedRaw
        self.statusRaw = status.rawValue
        self.uploadedAt = Date()
    }
}
