import Foundation
import Network

/// Errors surfaced from the IMAP flow. Keep these strings user-friendly —
/// they get shown directly in the account list when a sync fails.
enum IMAPError: Error, LocalizedError {
    case connectionFailed(String)
    case authenticationFailed(String)
    case protocolError(String)
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let m): "Verbindung fehlgeschlagen: \(m)"
        case .authenticationFailed(let m): "Anmeldung fehlgeschlagen: \(m)"
        case .protocolError(let m): "IMAP-Fehler: \(m)"
        case .timeout: "Zeitüberschreitung beim Server"
        case .cancelled: "Abgebrochen"
        }
    }
}

/// Thread-safe once-only continuation gate. `NWConnection.stateUpdateHandler`
/// can fire multiple times (e.g. `.ready` then `.cancelled`), and we can only
/// resume the continuation once — the class-boxed lock guards that.
private final class ContinuationGate<T>: @unchecked Sendable {
    private var cont: CheckedContinuation<T, Error>?
    private let lock = NSLock()

    func attach(_ c: CheckedContinuation<T, Error>) {
        lock.lock(); defer { lock.unlock() }
        cont = c
    }
    func succeed(_ value: T) {
        lock.lock(); defer { lock.unlock() }
        cont?.resume(returning: value)
        cont = nil
    }
    func fail(_ err: Error) {
        lock.lock(); defer { lock.unlock() }
        cont?.resume(throwing: err)
        cont = nil
    }
}

/// A single fetched envelope + text body. `IMAPClient` returns these; the
/// sync service maps them to persisted `MailMessage` entities.
struct IMAPFetchedMessage {
    var uid: UInt32
    var subject: String
    var fromName: String
    var fromAddress: String
    var toList: [String]
    var date: Date
    var bodyText: String
    var isSeen: Bool
    var isFlagged: Bool
}

/// Minimal read-only IMAP client (Network.framework, implicit TLS).
///
/// Scope for v1:
///  - Implicit TLS on port 993 (STARTTLS not implemented)
///  - LOGIN auth with plain username/password (App-passwords work fine)
///  - SELECT INBOX
///  - FETCH last N messages (UID ENVELOPE FLAGS BODY.PEEK[TEXT])
///
/// The parser handles the two things that trip up naive IMAP consumers:
/// tagged/untagged line demux and RFC 3501 `{N}` string literals (which can
/// contain arbitrary bytes including CR/LF).
actor IMAPClient {
    private let host: String
    private let port: UInt16
    private let username: String
    private let password: String

    private var connection: NWConnection?
    private var buffer = Data()
    private var tagCounter: Int = 0

    init(host: String, port: UInt16, username: String, password: String) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    /// End-to-end: connect + login + select INBOX + fetch the newest `limit`
    /// messages. Also logs out and tears the connection down before returning.
    func fetchRecent(limit: Int) async throws -> [IMAPFetchedMessage] {
        try await connectTLS()
        try await readGreeting()
        try await login()
        let exists = try await selectInbox()
        defer { Task { await self.logoutQuietly() } }

        guard exists > 0 else { return [] }

        // Fetch by message sequence number range (last N).
        let from = max(1, exists - limit + 1)
        let range = "\(from):\(exists)"

        let lines = try await sendAndCollect(
            "FETCH \(range) (UID FLAGS ENVELOPE BODY.PEEK[TEXT])"
        )
        return IMAPResponseParser.parseFetchResponses(lines)
    }

    // MARK: - Networking

    private func connectTLS() async throws {
        let tls = NWProtocolTLS.Options()
        let params = NWParameters(tls: tls)
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? 993,
            using: params
        )
        self.connection = conn

        let gate = ContinuationGate<Void>()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            gate.attach(cont)
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.succeed(())
                case .failed(let err):
                    gate.fail(IMAPError.connectionFailed(err.localizedDescription))
                case .cancelled:
                    gate.fail(IMAPError.cancelled)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    private func send(_ raw: String) async throws {
        guard let conn = connection else {
            throw IMAPError.connectionFailed("Keine Verbindung")
        }
        let data = Data(raw.utf8)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err {
                    cont.resume(throwing: IMAPError.connectionFailed(err.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
    }

    /// Reads until at least `minBytes` bytes are buffered. Used when we know
    /// a literal of a specific size is on the wire.
    private func receive(minBytes: Int) async throws {
        guard let conn = connection else {
            throw IMAPError.connectionFailed("Keine Verbindung")
        }
        while buffer.count < minBytes {
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, err in
                    if let err {
                        cont.resume(throwing: IMAPError.connectionFailed(err.localizedDescription))
                    } else if let data, !data.isEmpty {
                        cont.resume(returning: data)
                    } else if isComplete {
                        cont.resume(throwing: IMAPError.connectionFailed("Verbindung geschlossen"))
                    } else {
                        cont.resume(returning: Data())
                    }
                }
            }
            if chunk.isEmpty { throw IMAPError.connectionFailed("Leere Antwort") }
            buffer.append(chunk)
        }
    }

    /// Reads a single CRLF-terminated line from the buffer. Handles `{N}`
    /// literals by absorbing the exact byte count and continuing on the
    /// following line — the returned String is a single logical response
    /// line with the literal spliced in verbatim.
    private func readLine() async throws -> String {
        var line = Data()
        while true {
            // Guarantee we have at least one CRLF ahead, or find a literal marker.
            if let crlfRange = buffer.range(of: Data([0x0D, 0x0A])) {
                let head = buffer.subdata(in: 0..<crlfRange.lowerBound)
                buffer.removeSubrange(0..<crlfRange.upperBound)
                line.append(head)

                // Look at trailing "{N}" on this partial line — if present,
                // pull N more bytes then keep going (literal continuation).
                if let literalSize = trailingLiteralSize(in: head) {
                    line.append(Data([0x0D, 0x0A]))
                    try await receive(minBytes: literalSize)
                    let literal = buffer.prefix(literalSize)
                    buffer.removeFirst(literalSize)
                    line.append(literal)
                    // A literal is always followed by more of the same
                    // logical response line — loop and read the tail.
                    continue
                }
                return String(data: line, encoding: .utf8) ?? String(data: line, encoding: .isoLatin1) ?? ""
            }
            try await receive(minBytes: buffer.count + 1)
        }
    }

    private func trailingLiteralSize(in line: Data) -> Int? {
        guard let s = String(data: line, encoding: .utf8) else { return nil }
        guard let end = s.range(of: "}", options: .backwards),
              let start = s.range(of: "{", options: .backwards),
              start.lowerBound < end.lowerBound else { return nil }
        let inside = s[start.upperBound..<end.lowerBound]
        return Int(inside)
    }

    private func nextTag() -> String {
        tagCounter += 1
        return String(format: "A%04d", tagCounter)
    }

    /// Sends a tagged command and returns each logical response line as a
    /// separate array entry — literals are already spliced into their line
    /// so parsers don't have to reassemble them.
    private func sendAndCollect(_ command: String) async throws -> [String] {
        let tag = nextTag()
        try await send("\(tag) \(command)\r\n")
        var collected: [String] = []
        while true {
            let line = try await readLine()
            if line.hasPrefix("\(tag) ") {
                if line.contains(" OK ") { return collected }
                if line.contains(" NO ") || line.contains(" BAD ") {
                    let msg = line.replacingOccurrences(of: "\(tag) ", with: "")
                    throw IMAPError.protocolError(msg)
                }
                throw IMAPError.protocolError(line)
            } else {
                collected.append(line)
            }
        }
    }

    // MARK: - Flow

    private func readGreeting() async throws {
        let greeting = try await readLine()
        guard greeting.hasPrefix("* OK") else {
            throw IMAPError.protocolError("Unerwarteter Server-Gruß: \(greeting)")
        }
    }

    private func login() async throws {
        let escUser = escaped(username)
        let escPass = escaped(password)
        do {
            _ = try await sendAndCollect("LOGIN \(escUser) \(escPass)")
        } catch let e as IMAPError {
            if case .protocolError(let m) = e {
                throw IMAPError.authenticationFailed(m)
            }
            throw e
        }
    }

    private func selectInbox() async throws -> Int {
        let lines = try await sendAndCollect("SELECT INBOX")
        for line in lines {
            // Untagged EXISTS response: "* 123 EXISTS"
            let parts = line.split(separator: " ")
            if parts.count >= 3,
               parts[0] == "*",
               parts[2].uppercased() == "EXISTS",
               let n = Int(parts[1]) {
                return n
            }
        }
        return 0
    }

    private func logoutQuietly() async {
        _ = try? await sendAndCollect("LOGOUT")
        connection?.cancel()
        connection = nil
    }

    /// Quotes a string for use in an IMAP command per RFC 3501. Backslashes
    /// and quotes are escaped; the whole thing is wrapped in double quotes.
    private func escaped(_ s: String) -> String {
        var out = ""
        out.append("\"")
        for c in s {
            if c == "\\" || c == "\"" { out.append("\\") }
            out.append(c)
        }
        out.append("\"")
        return out
    }
}
