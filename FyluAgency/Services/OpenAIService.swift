import Foundation

enum OpenAIError: LocalizedError {
    case missingAPIKey
    case http(Int, String)
    case decoding(String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Kein OpenAI API-Key in den Einstellungen hinterlegt."
        case .http(let code, let msg): "OpenAI-Fehler \(code): \(msg)"
        case .decoding(let s): "Antwort konnte nicht gelesen werden: \(s)"
        case .noContent: "OpenAI hat keine Antwort geliefert."
        }
    }
}

struct ParsedInvoiceItem: Codable, Identifiable {
    let id: UUID
    var details: String
    var quantity: Double
    var unitPrice: Double

    init(details: String, quantity: Double, unitPrice: Double) {
        self.id = UUID()
        self.details = details
        self.quantity = quantity
        self.unitPrice = unitPrice
    }

    enum CodingKeys: String, CodingKey { case details, quantity, unitPrice }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.details = try c.decode(String.self, forKey: .details)
        self.quantity = try c.decode(Double.self, forKey: .quantity)
        self.unitPrice = try c.decode(Double.self, forKey: .unitPrice)
    }
}

struct ExtractedInvoice: Codable {
    var total: Double?
    var net: Double?
    var vat: Double?
    var date: String?    // ISO yyyy-MM-dd
}

struct UpsellSuggestion: Codable {
    var customerId: String
    var customerName: String
    var headline: String
    var reason: String
    var amount: Double
}

/// Thin client against OpenAI's Responses API. We deliberately keep
/// requests synchronous + structured (JSON schema) so callers don't
/// have to parse free-form text. The active workspace decides which
/// API key + model is used.
struct OpenAIService {
    let apiKey: String
    var model: String = "gpt-5.4-mini"
    var endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!

    init?(workspace: Workspace) {
        guard let key = KeychainService.loadAPIKey(account: workspace.keychainAccount),
              !key.isEmpty else { return nil }
        self.apiKey = key
        self.model = workspace.openAIModel
    }

    init(apiKey: String, model: String = "gpt-5.4-mini") {
        self.apiKey = apiKey
        self.model = model
    }

    // MARK: - Public API

    /// Turn free-form German prose into structured invoice items.
    func parseInvoiceText(_ text: String) async throws -> [ParsedInvoiceItem] {
        let system = """
        Du bist ein präziser Parser für deutsche Rechnungs-Beschreibungen einer \
        Webdesign-/Marketing-Agentur. Extrahiere die einzelnen Leistungspositionen.

        Regeln:
        - description: Klarer Leistungstext (z. B. "SEO Optimierung")
        - unitPrice ist immer NETTO in Euro
        - quantity ist standardmäßig 1
        - keine Mehrwertsteuer-Zeile
        - sortiere logisch (größere Posten zuerst)
        """

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "details": ["type": "string"],
                            "quantity": ["type": "number"],
                            "unitPrice": ["type": "number"]
                        ],
                        "required": ["details", "quantity", "unitPrice"]
                    ]
                ]
            ],
            "required": ["items"]
        ]

        struct Wrapper: Codable { let items: [ParsedInvoiceItem] }
        let response: Wrapper = try await callJSON(
            schemaName: "invoice_items",
            schema: schema,
            messages: [
                ["role": "system", "content": system],
                ["role": "user", "content": text]
            ]
        )
        return response.items
    }

    /// Read OCR'd invoice text and pull out gross/net/VAT/date.
    func extractTotals(fromOCRText text: String) async throws -> ExtractedInvoice {
        let system = """
        Du bekommst rohen OCR-Text einer Rechnung (deutsch, häufig unsauber). \
        Extrahiere Brutto-Endbetrag, Netto-Summe, Mehrwertsteuer-Betrag und \
        Rechnungsdatum. Wenn ein Wert nicht eindeutig erkennbar ist: null. \
        Bevorzuge "Gesamtbetrag", "Endbetrag", "Brutto", "Total" für total. \
        Wenn nur Brutto und VAT erkennbar sind, berechne net = total - vat. \
        Datum als ISO yyyy-MM-dd.
        """

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "total": ["type": ["number", "null"]],
                "net":   ["type": ["number", "null"]],
                "vat":   ["type": ["number", "null"]],
                "date":  ["type": ["string", "null"]]
            ],
            "required": ["total", "net", "vat", "date"]
        ]

        return try await callJSON(
            schemaName: "invoice_totals",
            schema: schema,
            messages: [
                ["role": "system", "content": system],
                ["role": "user", "content": String(text.prefix(6000))]
            ]
        )
    }

    /// Ask the model for the next-best upsell given a customer summary.
    func suggestUpsell(for summary: String) async throws -> (headline: String, reason: String, amount: Double)? {
        let system = """
        Du bist Vertriebs-Coach für eine kleine Webdesign- und Marketing-Agentur. \
        Du bekommst die Daten eines bestehenden Kunden. Schlag den NÄCHSTEN sinnvollen \
        Upsell vor: konkret, auf Deutsch.

        Typische Upsells (Anhaltspunkte):
        - Website-Pflege/Wartungspaket (50–150 €/Monat)
        - Conversion-Optimierung (300–900 € einmalig)
        - SEO-Erweiterung (200–500 €/Monat)
        - Google Ads (150–400 € Leistung + Budget vorab)
        - Hosting/Domain-Bundle (15–40 €/Monat)
        - Performance-Audit (250–600 €)
        """

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "headline": ["type": "string"],
                "reason":   ["type": "string"],
                "amount":   ["type": "number"]
            ],
            "required": ["headline", "reason", "amount"]
        ]

        struct R: Codable { let headline: String; let reason: String; let amount: Double }
        let r: R = try await callJSON(
            schemaName: "upsell",
            schema: schema,
            messages: [
                ["role": "system", "content": system],
                ["role": "user", "content": summary]
            ]
        )
        return (r.headline, r.reason, r.amount)
    }

    /// Quick health check used by the Settings view to validate a key.
    func ping() async -> Bool {
        struct R: Codable { let ok: Bool }
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": ["ok": ["type": "boolean"]],
            "required": ["ok"]
        ]
        do {
            let r: R = try await callJSON(
                schemaName: "ping",
                schema: schema,
                messages: [["role": "user", "content": "Antworte mit {\"ok\": true}"]]
            )
            return r.ok
        } catch {
            return false
        }
    }

    // MARK: - Internals

    private func callJSON<T: Decodable>(
        schemaName: String,
        schema: [String: Any],
        messages: [[String: String]]
    ) async throws -> T {
        let payload: [String: Any] = [
            "model": model,
            "input": messages,
            "store": false,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": schemaName,
                    "schema": schema,
                    "strict": true
                ]
            ]
        ]

        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.http(0, "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.http(http.statusCode, msg)
        }

        guard let text = extractOutputText(from: data) else {
            throw OpenAIError.noContent
        }

        guard let textData = text.data(using: .utf8) else {
            throw OpenAIError.decoding("non-utf8")
        }
        return try JSONDecoder().decode(T.self, from: textData)
    }

    /// Walks the Responses-API payload to find the assistant's output_text.
    private func extractOutputText(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // Newer Responses API: { output: [{ content: [{ text: "..." }] }] } or
        // top-level convenience: output_text: "..."
        if let s = obj["output_text"] as? String, !s.isEmpty { return s }

        if let output = obj["output"] as? [[String: Any]] {
            for entry in output {
                if let content = entry["content"] as? [[String: Any]] {
                    for c in content {
                        if let txt = c["text"] as? String, !txt.isEmpty { return txt }
                        if let txt = c["output_text"] as? String, !txt.isEmpty { return txt }
                    }
                }
            }
        }
        return nil
    }
}
