import Foundation
import Vision
import PDFKit
import AppKit
import CoreGraphics

enum OCRError: LocalizedError {
    case invalidPDF
    case renderFailed
    case visionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPDF: "Datei ist kein gültiges PDF."
        case .renderFailed: "PDF-Seite konnte nicht gerendert werden."
        case .visionFailed(let s): "OCR fehlgeschlagen: \(s)"
        }
    }
}

/// Reads text from invoice PDFs. We try the embedded text layer first
/// (fast + perfect when the PDF was generated digitally) and fall back
/// to Apple's Vision framework when the PDF is a scan / image-only.
enum OCRService {
    /// Returns the recognised text and a flag indicating whether OCR
    /// (vs. direct extraction) was used.
    static func extractText(from data: Data) async throws -> (text: String, usedOCR: Bool) {
        guard let document = PDFDocument(data: data) else {
            throw OCRError.invalidPDF
        }

        // 1. Try direct text layer
        var directText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let s = page.string {
                directText += s + "\n"
            }
        }
        if directText.trimmingCharacters(in: .whitespacesAndNewlines).count > 50 {
            return (directText, false)
        }

        // 2. Fall back to Vision OCR (German + English, accurate mode)
        var collected = ""
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let pageText = try await ocrPage(page)
            if !pageText.isEmpty {
                collected += pageText + "\n"
            }
        }
        return (collected, true)
    }

    private static func ocrPage(_ page: PDFPage) async throws -> String {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0   // 2x for better OCR
        let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        // Render the PDF page into a CGImage
        guard let cgImage = renderPDFPage(page, pixelSize: pixelSize) else {
            throw OCRError.renderFailed
        }

        return try await recognize(cgImage: cgImage)
    }

    private static func renderPDFPage(_ page: PDFPage, pixelSize: CGSize) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scaleX = pixelSize.width / bounds.width
        let scaleY = pixelSize.height / bounds.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.setFillColor(CGColor.white)
        context.fill(CGRect(origin: .zero, size: pixelSize))
        context.saveGState()
        context.scaleBy(x: scaleX, y: scaleY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        return context.makeImage()
    }

    private static func recognize(cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.visionFailed(error.localizedDescription))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines: [String] = observations.compactMap { obs in
                    obs.topCandidates(1).first?.string
                }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["de-DE", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRError.visionFailed(error.localizedDescription))
                }
            }
        }
    }
}
