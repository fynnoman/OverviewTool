import Foundation

/// Parses IMAP FETCH untagged responses into `IMAPFetchedMessage` values.
///
/// The wire format of a FETCH response is a mini-Lisp: parenthesized lists of
/// atoms, quoted strings, and (via the inlining done in `IMAPClient`) literal
/// payloads. This parser tokenises a single logical response line then walks
/// the key/value pairs — it deliberately handles only the subset we ask for
/// (UID, FLAGS, ENVELOPE, BODY[TEXT]).
enum IMAPResponseParser {

    /// Any IMAP data token. `list` is used for both address lists and the
    /// ENVELOPE structure itself.
    indirect enum Token {
        case atom(String)
        case string(String)
        case list([Token])
        case nilValue
    }

    static func parseFetchResponses(_ lines: [String]) -> [IMAPFetchedMessage] {
        var result: [IMAPFetchedMessage] = []
        for line in lines {
            guard line.hasPrefix("*") else { continue }
            // "* 123 FETCH (...)"
            guard let openIdx = line.firstIndex(of: "(") else { continue }
            // Verify the second word is FETCH so we don't try to parse
            // untagged EXISTS/EXPUNGE lines that share the "*" prefix.
            let head = line[..<openIdx]
            let parts = head.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 3, parts[2].uppercased() == "FETCH" else { continue }

            let body = String(line[openIdx...])
            var tokenizer = Tokenizer(body)
            guard case .list(let items) = tokenizer.readToken() ?? .nilValue else { continue }
            if let msg = messageFromKeyValueList(items) { result.append(msg) }
        }
        return result
    }

    // MARK: - Structured extraction

    private static func messageFromKeyValueList(_ items: [Token]) -> IMAPFetchedMessage? {
        // Items alternate: key(atom), value, key(atom), value, ...
        var uid: UInt32?
        var flags: [String] = []
        var envelope: [Token]?
        var bodyText = ""

        var i = 0
        while i < items.count - 1 {
            guard case .atom(let key) = items[i] else { i += 1; continue }
            let value = items[i + 1]
            switch key.uppercased() {
            case "UID":
                if case .atom(let n) = value, let u = UInt32(n) { uid = u }
            case "FLAGS":
                if case .list(let f) = value {
                    flags = f.compactMap { t in
                        if case .atom(let a) = t { return a }
                        return nil
                    }
                }
            case "ENVELOPE":
                if case .list(let e) = value { envelope = e }
            default:
                // BODY[TEXT] arrives as an atom key with either a quoted
                // string or a literal-derived string as the value.
                if key.uppercased().hasPrefix("BODY[") {
                    switch value {
                    case .string(let s): bodyText = s
                    case .atom(let a):   bodyText = a
                    default: break
                    }
                }
            }
            i += 2
        }

        guard let uid, let envelope else { return nil }

        // ENVELOPE = (date, subject, from, sender, reply-to, to, cc, bcc,
        //            in-reply-to, message-id)
        let dateStr    = tokenAsString(envelope, safeIndex: 0)
        let subjectStr = tokenAsString(envelope, safeIndex: 1)
        let fromList   = firstAddress(envelope, safeIndex: 2)
        let toAddrs    = addresses(envelope, safeIndex: 5)

        let date = IMAPDateParser.parse(dateStr) ?? Date()
        let subject = MIMEHeaderDecoder.decode(subjectStr)
        let fromName = MIMEHeaderDecoder.decode(fromList.name)
        let fromAddress = fromList.address
        let bodyDecoded = plainTextFallback(from: bodyText)

        return IMAPFetchedMessage(
            uid: uid,
            subject: subject,
            fromName: fromName,
            fromAddress: fromAddress,
            toList: toAddrs.map(\.address),
            date: date,
            bodyText: bodyDecoded,
            isSeen: flags.contains("\\Seen"),
            isFlagged: flags.contains("\\Flagged")
        )
    }

    private static func tokenAsString(_ items: [Token], safeIndex idx: Int) -> String {
        guard idx < items.count else { return "" }
        switch items[idx] {
        case .string(let s): return s
        case .atom(let a):   return a == "NIL" ? "" : a
        case .nilValue:      return ""
        case .list:          return ""
        }
    }

    private struct Addr { let name: String; let address: String }

    private static func firstAddress(_ items: [Token], safeIndex idx: Int) -> Addr {
        let all = addresses(items, safeIndex: idx)
        return all.first ?? Addr(name: "", address: "")
    }

    private static func addresses(_ items: [Token], safeIndex idx: Int) -> [Addr] {
        guard idx < items.count else { return [] }
        guard case .list(let list) = items[idx] else { return [] }
        var out: [Addr] = []
        for entry in list {
            guard case .list(let addrParts) = entry else { continue }
            // (name adl mailbox host)
            let name = tokenAsString(addrParts, safeIndex: 0)
            let mailbox = tokenAsString(addrParts, safeIndex: 2)
            let host = tokenAsString(addrParts, safeIndex: 3)
            let addr = "\(mailbox)@\(host)"
            out.append(Addr(name: name, address: addr))
        }
        return out
    }

    /// If the fetched body looks like MIME (headers + blank line + payload),
    /// strip the headers. Best-effort — a proper MIME walker comes later.
    private static func plainTextFallback(from raw: String) -> String {
        var text = raw
        // Some servers include a leading empty line before the body.
        if text.hasPrefix("\r\n") { text.removeFirst(2) }
        else if text.hasPrefix("\n") { text.removeFirst(1) }
        // Very light HTML strip so preview lines aren't full of tags.
        if text.contains("<") && text.contains(">") {
            text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        }
        return text
    }

    // MARK: - Tokenizer

    private struct Tokenizer {
        let chars: [Character]
        var i: Int = 0

        init(_ s: String) { self.chars = Array(s) }

        mutating func skipSpaces() {
            while i < chars.count, chars[i] == " " || chars[i] == "\t" || chars[i] == "\r" || chars[i] == "\n" {
                i += 1
            }
        }

        mutating func readToken() -> Token? {
            skipSpaces()
            guard i < chars.count else { return nil }
            let c = chars[i]
            if c == "(" {
                i += 1
                var items: [Token] = []
                while true {
                    skipSpaces()
                    if i >= chars.count { break }
                    if chars[i] == ")" { i += 1; break }
                    if let t = readToken() { items.append(t) } else { break }
                }
                return .list(items)
            } else if c == ")" {
                return nil
            } else if c == "\"" {
                return .string(readQuotedString())
            } else if c == "{" {
                // Literal marker: {N}<CRLF><N bytes>. The CRLF and payload
                // are already inlined by IMAPClient.readLine — we just need
                // to consume N bytes from the character stream.
                return readLiteral()
            } else {
                return readAtom()
            }
        }

        private mutating func readQuotedString() -> String {
            // consume opening "
            i += 1
            var out = ""
            while i < chars.count {
                let c = chars[i]
                if c == "\\" && i + 1 < chars.count {
                    out.append(chars[i + 1])
                    i += 2
                    continue
                }
                if c == "\"" { i += 1; return out }
                out.append(c)
                i += 1
            }
            return out
        }

        private mutating func readAtom() -> Token {
            var out = ""
            while i < chars.count {
                let c = chars[i]
                if c == " " || c == "(" || c == ")" || c == "\r" || c == "\n" { break }
                out.append(c)
                i += 1
            }
            if out.uppercased() == "NIL" { return .nilValue }
            return .atom(out)
        }

        private mutating func readLiteral() -> Token {
            // Skip "{"
            i += 1
            var sizeStr = ""
            while i < chars.count, chars[i] != "}" {
                sizeStr.append(chars[i]); i += 1
            }
            if i < chars.count { i += 1 } // consume "}"
            // Skip the CRLF that follows the "}"
            if i < chars.count, chars[i] == "\r" { i += 1 }
            if i < chars.count, chars[i] == "\n" { i += 1 }
            let n = Int(sizeStr) ?? 0
            let end = min(chars.count, i + n)
            let payload = String(chars[i..<end])
            i = end
            return .string(payload)
        }
    }
}

/// Small helper for parsing IMAP ENVELOPE date strings (RFC 2822 date-time).
enum IMAPDateParser {
    private static let formatters: [DateFormatter] = {
        let variants = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss zzz",
        ]
        return variants.map { fmt in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            return f
        }
    }()

    static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for f in formatters {
            if let d = f.date(from: trimmed) { return d }
        }
        return nil
    }
}

/// Decodes RFC 2047 encoded-word headers (`=?UTF-8?B?...?=` / `=?UTF-8?Q?...?=`)
/// so subjects with umlauts and non-ASCII names render correctly.
enum MIMEHeaderDecoder {
    static func decode(_ raw: String) -> String {
        guard raw.contains("=?") else { return raw }
        let regex = try? NSRegularExpression(
            pattern: #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#,
            options: []
        )
        guard let regex else { return raw }
        let ns = raw as NSString
        var result = ""
        var cursor = 0
        let matches = regex.matches(in: raw, options: [], range: NSRange(location: 0, length: ns.length))
        for m in matches {
            if m.range.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            }
            let charset = ns.substring(with: m.range(at: 1))
            let encoding = ns.substring(with: m.range(at: 2)).uppercased()
            let payload = ns.substring(with: m.range(at: 3))
            result += decodePart(payload: payload, encoding: encoding, charset: charset) ?? payload
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return result
    }

    private static func decodePart(payload: String, encoding: String, charset: String) -> String? {
        let cs = stringEncoding(for: charset)
        switch encoding {
        case "B":
            guard let data = Data(base64Encoded: payload) else { return nil }
            return String(data: data, encoding: cs)
        case "Q":
            var bytes: [UInt8] = []
            var i = payload.startIndex
            while i < payload.endIndex {
                let c = payload[i]
                if c == "_" {
                    bytes.append(0x20)
                    i = payload.index(after: i)
                } else if c == "=" {
                    let hexEnd = payload.index(i, offsetBy: 3, limitedBy: payload.endIndex) ?? payload.endIndex
                    let hex = payload[payload.index(after: i)..<hexEnd]
                    if let b = UInt8(hex, radix: 16) { bytes.append(b) }
                    i = hexEnd
                } else {
                    if let ascii = c.asciiValue { bytes.append(ascii) }
                    i = payload.index(after: i)
                }
            }
            return String(data: Data(bytes), encoding: cs)
        default:
            return nil
        }
    }

    private static func stringEncoding(for charset: String) -> String.Encoding {
        switch charset.uppercased() {
        case "UTF-8", "UTF8": return .utf8
        case "ISO-8859-1", "LATIN1": return .isoLatin1
        case "ISO-8859-15": return .isoLatin2
        case "US-ASCII", "ASCII": return .ascii
        default: return .utf8
        }
    }
}
