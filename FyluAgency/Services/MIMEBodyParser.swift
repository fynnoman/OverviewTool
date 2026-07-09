import Foundation

/// Extracts a clean plain-text body from a raw RFC822 message (as returned by
/// IMAP `BODY[]`). Handles the three things that ruined our v1 rendering:
///
///  1. `multipart/*` bodies — recurses into the parts and picks `text/plain`
///     (falling back to a stripped-down `text/html`).
///  2. `Content-Transfer-Encoding: base64` and `quoted-printable` — decoded
///     before we hand the string to the UI.
///  3. Non-UTF8 charsets declared in the part's `Content-Type` header
///     (Latin-1, Windows-1252, …).
///
/// Everything is best-effort — if the mail isn't proper MIME (older
/// mailer, garbled, single-part with no headers) we fall through to a
/// straight string.
enum MIMEBodyParser {

    /// Public entry point. `raw` is the full RFC822 message text as returned
    /// by `BODY[]`.
    static func extractPlainText(from raw: String) -> String {
        let (headers, body) = splitHeadersAndBody(raw)
        let extracted = decodePart(headers: headers, body: body)
        // Some senders declare text/plain but ship HTML anyway — sniff so
        // the doctype doesn't leak into the reading pane or preview.
        return sniffHTMLIfNeeded(extracted)
    }

    /// Produce a preview-friendly snippet from a body that may still contain
    /// MIME leftovers — boundary lines, orphan part headers, the "This is a
    /// multi-part message" preamble, or raw HTML. Idempotent: safe to run
    /// on an already-clean string.
    static func sanitizeForPreview(_ body: String) -> String {
        sanitize(body, singleLine: true, maxLength: 4000)
    }

    /// Sanitize the full body for the reading pane. Same filters as the
    /// preview path (drop MIME boundaries, orphan part headers, preamble
    /// text, strip raw HTML) but preserves paragraph structure so the
    /// mail actually reads like a mail. Hard-capped at 100k chars — beyond
    /// that SwiftUI's `Text` in an unbounded ScrollView can hang the layout
    /// engine and blank out the pane; the cap lets us fail visibly instead
    /// of freezing.
    static func sanitizeForDetail(_ body: String) -> String {
        sanitize(body, singleLine: false, maxLength: 100_000)
    }

    private static func sanitize(_ body: String, singleLine: Bool, maxLength: Int) -> String {
        // Some IMAP servers hand us the whole multipart body verbatim
        // (missing/mis-typed top-level Content-Type). If we can spot the
        // "Content-Type: text/plain" header inside the body, pull that
        // part out first — this is what turns a screen full of MIME
        // scaffolding into an actual readable mail.
        var t = extractInlinedPlainText(from: body) ?? body
        t = sniffHTMLIfNeeded(t)

        // Drop the RFC 2049 preamble text some clients ship literally.
        t = t.replacingOccurrences(
            of: #"This\s+is\s+a\s+multi-?part\s+message\s+in\s+MIME\s+format\.?"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        t = t.replacingOccurrences(
            of: #"This\s+is\s+a\s+MIME[- ]encapsulated\s+message\.?"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Drop lines that look like a MIME boundary marker or an orphan
        // part header that leaked past the parser.
        let kept = t.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { String($0) }
            .filter { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if looksLikeMIMEBoundary(line) { return false }
                if line.range(
                    of: #"^Content-(Type|Transfer-Encoding|Disposition|ID|Description|Location)\s*:"#,
                    options: [.regularExpression, .caseInsensitive]
                ) != nil { return false }
                if line.range(
                    of: #"^(MIME-Version|boundary\s*=)"#,
                    options: [.regularExpression, .caseInsensitive]
                ) != nil { return false }
                return true
            }

        let joined: String
        if singleLine {
            joined = kept
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        } else {
            joined = kept.joined(separator: "\n")
                // Collapse runs of ≥3 blank lines into a single blank line.
                .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        }

        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > maxLength {
            let cap = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
            return String(trimmed[..<cap]) + "\n\n[… gekürzt: Mail zu groß fürs Lesefenster.]"
        }
        return trimmed
    }

    /// If `s` looks like HTML anywhere in its content (not just the first
    /// 200 chars), run it through the tag stripper. Handles the case where
    /// the plain-text part is short and the HTML part sits below it.
    private static func sniffHTMLIfNeeded(_ s: String) -> String {
        let sample = s.prefix(4000).lowercased()
        if sample.contains("<!doctype html")
            || sample.contains("<html")
            || sample.contains("<body")
            || sample.contains("<div ")
            || sample.contains("<table ")
        {
            return stripHTML(s)
        }
        return s
    }

    /// Heuristic MIME boundary detection. Standard boundaries are `--<token>`
    /// but we've seen mails leak lines like `-=-yu9+AfHGLz==` (missing dash,
    /// stripped by an intermediate MTA). Any single-word line starting with
    /// `-` that contains typical boundary characters (`=`, `_`, `+`) and no
    /// whitespace is almost certainly a boundary — treating it as such is
    /// safer than showing it as content.
    private static func looksLikeMIMEBoundary(_ line: String) -> Bool {
        if line.hasPrefix("--"), line.count >= 4 { return true }
        guard line.count >= 6, line.hasPrefix("-") else { return false }
        if line.rangeOfCharacter(from: .whitespaces) != nil { return false }
        if line.contains("=") || line.contains("_") || line.contains("+") { return true }
        return false
    }

    /// When the top-level MIME parse didn't succeed and we end up with the
    /// raw multipart source in the "body", try to pluck out just the
    /// text/plain part so the reader isn't stuck with headers + boundaries.
    ///
    /// Strategy: find the first `Content-Type: text/plain` header, skip to
    /// its blank-line separator, and return everything up to the next
    /// boundary line or the next Content-Type header.
    private static func extractInlinedPlainText(from body: String) -> String? {
        guard let ctRange = body.range(
            of: #"Content-Type\s*:\s*text/plain[^\n\r]*"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }

        // The header may be followed by other part-headers (Content-Transfer-
        // Encoding, Content-Disposition, …). Skip until the first blank line,
        // which marks the start of the body.
        let afterHeader = body[ctRange.upperBound...]
        let blankLineRange = afterHeader.range(of: "\r\n\r\n")
            ?? afterHeader.range(of: "\n\n")
        guard let blankLine = blankLineRange else { return nil }
        let contentStart = blankLine.upperBound

        // Cut off at the next MIME-ish separator. Accept both real boundary
        // lines (`--foo`) and the mangled variants (`-=-foo`), or any new
        // `Content-Type:` header that marks the next part.
        let content = afterHeader[contentStart...]
        let terminator = content.range(
            of: #"\r?\n(-{1,}[^\s]+|Content-Type\s*:)"#,
            options: [.regularExpression, .caseInsensitive]
        )
        let end = terminator?.lowerBound ?? content.endIndex
        let extracted = String(content[..<end])
        let trimmed = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only trust the extraction if it produced meaningful content —
        // very short results probably mean the parser tripped on a weird
        // header layout and we'd lose more than we gain.
        return trimmed.count >= 40 ? trimmed : nil
    }

    // MARK: - Recursive part decoding

    private static func decodePart(headers: String, body: String) -> String {
        let contentType = headerValue(name: "Content-Type", in: headers) ?? "text/plain"
        let ctLower = contentType.lowercased()
        let encoding = (headerValue(name: "Content-Transfer-Encoding", in: headers) ?? "7bit")
            .lowercased()
            .trimmingCharacters(in: .whitespaces)

        // Multipart? Recurse and pick the best child.
        if ctLower.hasPrefix("multipart/"),
           let boundary = parameter(name: "boundary", in: contentType) {
            return extractFromMultipart(body: body, boundary: boundary)
        }

        // Single-part: transfer-decode → charset-decode → maybe strip HTML.
        let charset = parameter(name: "charset", in: contentType) ?? "utf-8"
        let bytes = decodeTransferEncoding(body, encoding: encoding)
        let text = String(data: bytes, encoding: stringEncoding(for: charset))
            ?? String(data: bytes, encoding: .isoLatin1)
            ?? body

        if ctLower.hasPrefix("text/html") {
            return stripHTML(text)
        }
        return text
    }

    private static func extractFromMultipart(body: String, boundary: String) -> String {
        // Split on the boundary marker `--<boundary>`. The parts alternate
        // preamble → part₁ → part₂ → … → epilogue.
        let delimiter = "--\(boundary)"
        let chunks = body.components(separatedBy: delimiter)
        // Drop leading preamble (before first boundary) and trailing epilogue
        // (after `--<boundary>--`).
        guard chunks.count >= 2 else { return body }

        var plain: String?
        var html: String?

        for chunk in chunks.dropFirst() {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "--" || trimmed.isEmpty { continue }  // end marker

            // Strip the leading CRLF that follows the boundary line.
            var partRaw = chunk
            if partRaw.hasPrefix("\r\n") {
                partRaw.removeFirst(2)
            } else if partRaw.hasPrefix("\n") {
                partRaw.removeFirst(1)
            }
            // If this chunk ends with `--` (the closing marker), snip it off.
            if partRaw.hasSuffix("--") {
                partRaw = String(partRaw.dropLast(2))
            }

            let (partHeaders, partBody) = splitHeadersAndBody(partRaw)
            let partContentType = (headerValue(name: "Content-Type", in: partHeaders) ?? "text/plain").lowercased()
            let decoded = decodePart(headers: partHeaders, body: partBody)

            if partContentType.hasPrefix("multipart/") {
                // Nested multipart — take whatever it returned as a plain candidate.
                if plain == nil { plain = decoded }
            } else if partContentType.hasPrefix("text/plain") {
                if plain == nil { plain = decoded }
            } else if partContentType.hasPrefix("text/html") {
                if html == nil { html = decoded }
            }
        }

        return plain ?? html ?? ""
    }

    // MARK: - Header parsing

    /// Split the message at the first blank line (`CRLF CRLF` or `LF LF`).
    /// Everything before is headers, everything after is the body.
    private static func splitHeadersAndBody(_ raw: String) -> (headers: String, body: String) {
        if let r = raw.range(of: "\r\n\r\n") {
            return (String(raw[..<r.lowerBound]), String(raw[r.upperBound...]))
        }
        if let r = raw.range(of: "\n\n") {
            return (String(raw[..<r.lowerBound]), String(raw[r.upperBound...]))
        }
        return ("", raw)
    }

    /// Case-insensitive header lookup that respects RFC 5322 header folding
    /// (a continuation line starts with whitespace and is logically part of
    /// the previous header).
    private static func headerValue(name: String, in headers: String) -> String? {
        // Unfold: a line starting with SP/TAB continues the previous line.
        let unfolded = headers
            .replacingOccurrences(of: "\r\n ", with: " ")
            .replacingOccurrences(of: "\r\n\t", with: " ")
            .replacingOccurrences(of: "\n ", with: " ")
            .replacingOccurrences(of: "\n\t", with: " ")

        let target = name.lowercased() + ":"
        for line in unfolded.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let l = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if l.lowercased().hasPrefix(target) {
                return String(l.dropFirst(target.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Pull a parameter (`key=value` or `key="value"`) out of a structured
    /// header value like `multipart/alternative; boundary="foo"; charset=utf-8`.
    private static func parameter(name: String, in headerValue: String) -> String? {
        let target = name.lowercased() + "="
        for part in headerValue.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix(target) {
                var v = String(trimmed.dropFirst(target.count))
                if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 {
                    v = String(v.dropFirst().dropLast())
                }
                return v
            }
        }
        return nil
    }

    // MARK: - Transfer encoding

    private static func decodeTransferEncoding(_ body: String, encoding: String) -> Data {
        switch encoding {
        case "base64":
            // Base64 as it appears in mail is line-wrapped every 76 chars —
            // strip all whitespace before feeding it to Data(base64Encoded:).
            let cleaned = body.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
            let cleanedString = String(String.UnicodeScalarView(cleaned))
            return Data(base64Encoded: cleanedString) ?? Data(body.utf8)
        case "quoted-printable":
            return decodeQuotedPrintable(body)
        case "7bit", "8bit", "binary", "":
            return Data(body.utf8)
        default:
            return Data(body.utf8)
        }
    }

    /// Minimal RFC 2045 quoted-printable decoder. Handles the two things we
    /// see in the wild: `=XX` hex bytes and `=` at EOL as a soft line break.
    private static func decodeQuotedPrintable(_ s: String) -> Data {
        var out: [UInt8] = []
        let scalars = Array(s.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if c == "=" {
                // Soft line break: "=" followed by CRLF or LF → drop all three
                // (or two) chars, no output emitted.
                if i + 1 < scalars.count, scalars[i + 1] == "\r" {
                    i += 2
                    if i < scalars.count, scalars[i] == "\n" { i += 1 }
                    continue
                }
                if i + 1 < scalars.count, scalars[i + 1] == "\n" {
                    i += 2
                    continue
                }
                // "=XX" → single byte from two hex digits
                if i + 2 < scalars.count {
                    let hex = String(scalars[i + 1]) + String(scalars[i + 2])
                    if let b = UInt8(hex, radix: 16) {
                        out.append(b)
                        i += 3
                        continue
                    }
                }
                // Malformed `=` — pass through so we don't lose data.
                out.append(UInt8(ascii: "="))
                i += 1
            } else if c.isASCII {
                out.append(UInt8(c.value))
                i += 1
            } else {
                // Non-ASCII inside a QP-encoded body is technically illegal
                // but some servers emit UTF-8 bytes anyway — pass them
                // through as UTF-8 so the outer charset decode still works.
                for b in String(c).utf8 { out.append(b) }
                i += 1
            }
        }
        return Data(out)
    }

    // MARK: - HTML fallback

    /// Strip HTML down to something legible for the reading pane. Not a full
    /// renderer — we drop scripts/styles, collapse tags, translate a handful
    /// of common entities.
    private static func stripHTML(_ s: String) -> String {
        var t = s
        // Kill script/style blocks entirely before touching anything else.
        t = t.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        t = t.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Preserve paragraph/line structure before we drop the tags.
        t = t.replacingOccurrences(
            of: "<br\\s*/?>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        t = t.replacingOccurrences(
            of: "</p\\s*>",
            with: "\n\n",
            options: [.regularExpression, .caseInsensitive]
        )
        t = t.replacingOccurrences(
            of: "</div\\s*>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        // Drop all remaining tags.
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode entities.
        t = decodeHTMLEntities(t)
        // Collapse runs of blank lines and trim.
        t = t.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ s: String) -> String {
        var t = s
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&hellip;", with: "…")
            .replacingOccurrences(of: "&auml;", with: "ä")
            .replacingOccurrences(of: "&ouml;", with: "ö")
            .replacingOccurrences(of: "&uuml;", with: "ü")
            .replacingOccurrences(of: "&Auml;", with: "Ä")
            .replacingOccurrences(of: "&Ouml;", with: "Ö")
            .replacingOccurrences(of: "&Uuml;", with: "Ü")
            .replacingOccurrences(of: "&szlig;", with: "ß")

        // Numeric entities: &#123; and &#x1F;
        t = replaceNumericEntities(in: t)
        return t
    }

    private static func replaceNumericEntities(in s: String) -> String {
        var result = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i...].firstIndex(of: ";") {
                let inner = s[s.index(after: i)..<semi]
                if inner.hasPrefix("#") {
                    let numPart = inner.dropFirst()
                    let value: Int?
                    if numPart.hasPrefix("x") || numPart.hasPrefix("X") {
                        value = Int(numPart.dropFirst(), radix: 16)
                    } else {
                        value = Int(numPart)
                    }
                    if let v = value, let scalar = Unicode.Scalar(v) {
                        result.append(Character(scalar))
                        i = s.index(after: semi)
                        continue
                    }
                }
            }
            result.append(s[i])
            i = s.index(after: i)
        }
        return result
    }

    // MARK: - Charset

    private static func stringEncoding(for charset: String) -> String.Encoding {
        switch charset.uppercased().trimmingCharacters(in: .whitespaces) {
        case "UTF-8", "UTF8":              return .utf8
        case "ISO-8859-1", "LATIN1":       return .isoLatin1
        case "ISO-8859-2", "LATIN2":       return .isoLatin2
        case "ISO-8859-15":                return .isoLatin1  // close enough for our fallback
        case "US-ASCII", "ASCII":          return .ascii
        case "WINDOWS-1252", "CP1252":     return .windowsCP1252
        case "WINDOWS-1250", "CP1250":     return .windowsCP1250
        case "WINDOWS-1251", "CP1251":     return .windowsCP1251
        case "UTF-16", "UTF16":            return .utf16
        default:                           return .utf8
        }
    }
}
