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

/// Beschreibt das Business hinter einem Workspace — wird in die
/// AI-Prompts gestopft, damit Upsell-Vorschläge zur Branche passen
/// (Webdesign, SaaS, Beratung, …) statt generisch geraten zu werden.
struct WorkspaceAIProfile {
    /// Kurzname der Branche, z. B. "Webdesign-Agentur", "B2B-SaaS".
    var businessKind: String
    /// Freitext-Beschreibung was verkauft wird, an wen, USP.
    var businessProfile: String
    /// Optional: typische Upsells als Hinweis ans Modell.
    var upsellPlaybook: String
    /// Anzeigename des Workspaces — als Hinweis ans Modell, wenn kein
    /// echtes Profil hinterlegt ist (z. B. "Taskey" → Modell soll nicht
    /// blind Webdesign empfehlen).
    var workspaceName: String

    /// `true`, wenn der User wirklich etwas konfiguriert hat.
    var hasContent: Bool {
        !businessKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !businessProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !upsellPlaybook.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        businessKind: String = "",
        businessProfile: String = "",
        upsellPlaybook: String = "",
        workspaceName: String = ""
    ) {
        self.businessKind = businessKind
        self.businessProfile = businessProfile
        self.upsellPlaybook = upsellPlaybook
        self.workspaceName = workspaceName
    }

    init(workspace: Workspace) {
        self.businessKind = workspace.businessKind ?? ""
        self.businessProfile = workspace.businessProfile ?? ""
        self.upsellPlaybook = workspace.aiUpsellPlaybook ?? ""
        self.workspaceName = workspace.name
    }
}

/// Result of asking the model whether an email confirms a concrete appointment.
struct ExtractedAppointment: Codable {
    var accepted: Bool
    var title: String?
    var startsAt: String?    // ISO 8601, may include timezone
    var endsAt: String?
    var location: String?
    var allDay: Bool?
}

/// Reply draft generated for a received email — subject + body, nothing persisted.
struct DraftedReply: Codable {
    var subject: String
    var body: String
}

/// One follow-up action the model suggests after reading a lead's notes and
/// emails. `leadId` is the UUID of the source lead so the sheet can jump
/// straight to the lead detail on tap.
struct LeadActionSuggestion: Codable, Identifiable {
    enum Kind: String, Codable {
        case call, email, meeting, other
    }
    enum Priority: String, Codable {
        case high, medium, low
    }

    var leadId: String
    var leadName: String
    var kind: Kind
    var title: String
    var reason: String
    /// ISO 8601 date if the model spotted a concrete upcoming date/time in
    /// the notes/emails; `nil` otherwise.
    var dueDate: String?
    var priority: Priority

    var id: String { leadId + "|" + title }
}

/// Prompt-ready snapshot of one lead. The `LeadsListView` builds these from
/// SwiftData just before the API call so we don't send full DB objects and
/// can trim large email bodies without touching the persistent store.
struct LeadAIInput {
    struct EmailSnapshot {
        var direction: String   // "sent" | "received"
        var subject: String
        var summary: String     // may be empty
        var body: String        // may be truncated
        var sentAt: Date?
    }

    var id: String
    var name: String
    var company: String
    var status: String
    var offerDescription: String
    var expectedValue: Double?
    var lastContactAt: Date?
    var notes: String
    var emails: [EmailSnapshot]

    /// Compact textual form for the model. Chronological emails, summary
    /// preferred over body to keep tokens low.
    var serializedForPrompt: String {
        var out = "leadId: \(id)\n"
        out += "name: \(name)\n"
        if !company.isEmpty { out += "company: \(company)\n" }
        out += "status: \(status)\n"
        if !offerDescription.isEmpty { out += "offer: \(offerDescription)\n" }
        if let v = expectedValue { out += "expectedValue: \(String(format: "%.0f", v)) EUR\n" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "yyyy-MM-dd"
        if let d = lastContactAt { out += "lastContactAt: \(df.string(from: d))\n" }
        if !notes.isEmpty { out += "notes:\n\(notes.prefix(1500))\n" }
        if !emails.isEmpty {
            out += "emails (chronologisch, älteste zuerst):\n"
            for e in emails {
                let when = e.sentAt.map { df.string(from: $0) } ?? "?"
                let content = e.summary.isEmpty ? e.body : e.summary
                out += "- [\(when)] \(e.direction) · \(e.subject)\n"
                if !content.isEmpty {
                    out += "  \(content.replacingOccurrences(of: "\n", with: " ").prefix(800))\n"
                }
            }
        }
        return out
    }
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
        Wenn nur Brutto und VAT erkennbar sind, berechne net = total - vat.

        Datum-Regeln (WICHTIG):
        - Gib das RECHNUNGSDATUM zurück, NICHT Leistungs-, Fällig- oder Zahldatum.
        - Format ZWINGEND: yyyy-MM-dd (z. B. 2026-03-15).
        - Wandle deutsche Formate wie "15.03.2026", "15. März 2026", "15/3/26" \
          IMMER in yyyy-MM-dd um.
        - Lieber null als ein erratenes Datum, aber wenn irgendwo eindeutig ein \
          Rechnungsdatum steht: zurückgeben.
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
    /// `profile` beschreibt das Business hinter dem aktiven Workspace —
    /// wenn leer, bleibt das alte "Webdesign-Agentur"-Prompt aktiv, damit
    /// bestehende Workspaces ohne KI-Profil identisch laufen.
    func suggestUpsell(
        for summary: String,
        profile: WorkspaceAIProfile = WorkspaceAIProfile()
    ) async throws -> (headline: String, reason: String, amount: Double)? {
        let system = upsellSystemPrompt(profile: profile)

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

    /// Baut den System-Prompt für `suggestUpsell` zusammen. Mit gepflegtem
    /// KI-Profil wird Branche/Beschreibung direkt durchgereicht. Ohne
    /// Profil schauen wir auf den Workspace-Namen: nur wenn er klar nach
    /// Webdesign/Marketing klingt, bleibt der alte Webdesign-Prompt aktiv
    /// — sonst fragt das Modell konservativ aus den Kundendaten allein.
    private func upsellSystemPrompt(profile: WorkspaceAIProfile) -> String {
        guard profile.hasContent else {
            let name = profile.workspaceName.lowercased()
            let looksLikeWebdesign = name.contains("webdesign")
                || name.contains("marketing")
                || name.contains("agency")
                || name.contains("agentur")
                || name.contains("design")
            if looksLikeWebdesign {
                return """
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
            }
            return """
            Du bist Vertriebs-Coach für das Unternehmen "\(profile.workspaceName)". \
            WICHTIG: Du hast KEINE genauere Beschreibung der Branche. Leite die \
            wahrscheinliche Branche aus den unten gelisteten Leistungen/Rechnungs-Posten \
            des Kunden ab. Erfinde NIEMALS Webdesign-Upsells (SEO, Google Ads, Wartung, \
            Website-Pflege), nur weil sie generisch klingen.

            Schlag den NÄCHSTEN sinnvollen Upsell auf Deutsch vor, der streng zu den \
            tatsächlich gebuchten Leistungen passt. Sinnvolle Hebel sind je nach \
            Geschäftsmodell z. B.:
            - höhere Lizenz-/Subscription-Tiers
            - Add-on-Module oder Zusatz-User
            - Service-/Support-/Wartungs-Verträge passend zum Produkt
            - Schulungen, Onboarding, Begleitung
            - Mengen-/Volumen-Erweiterungen, weitere Standorte
            - Folge-Mandate / wiederkehrende Beratung

            Antworte konkret und im realistischen Preisrahmen für die Branche.
            """
        }

        let kind = profile.businessKind.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = profile.businessProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        let playbook = profile.upsellPlaybook.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        lines.append("Du bist Vertriebs-Coach für ein konkret beschriebenes Business. " +
                     "Du bekommst die Daten eines bestehenden Kunden. Schlag den NÄCHSTEN sinnvollen " +
                     "Upsell vor: konkret, auf Deutsch, exakt passend zur Branche.")
        lines.append("")
        if !kind.isEmpty {
            lines.append("Branche / Geschäftsmodell: \(kind)")
        }
        if !desc.isEmpty {
            lines.append("Was das Business macht / verkauft:\n\(desc)")
        }
        lines.append("")
        if !playbook.isEmpty {
            lines.append("Typische Upsells in diesem Geschäftsmodell (Anhaltspunkte):\n\(playbook)")
        } else {
            lines.append("Leite typische Upsells aus der oben beschriebenen Branche ab — " +
                         "z. B. Service-Verträge, Support-/Pflege-Pakete, höhere Lizenztiers, " +
                         "Schulungen, Add-on-Module, Mengen-Erweiterungen, Begleitberatung.")
        }
        lines.append("")
        lines.append("Wichtig: Der Vorschlag muss zur Branche passen. Wenn es kein Webdesign-Business " +
                     "ist, erfinde KEINE SEO-/Google-Ads-Upsells nur weil sie generisch sind.")
        return lines.joined(separator: "\n")
    }

    /// Summarize a customer/lead email into 2-4 short German bullet points.
    func summarizeEmail(subject: String, body: String) async throws -> String {
        let system = """
        Du fasst E-Mails einer kleinen Webdesign-/Marketing-Agentur in 2-4 kurzen \
        Bullet-Points auf Deutsch zusammen. Konzentriere dich auf: Anliegen/Thema, \
        konkrete Vereinbarungen, offene Fragen, nächste Schritte.

        Regeln:
        - Antworte ausschließlich mit Bullet-Points (Format: "• …").
        - Keine Anrede, keine Einleitung, kein Fließtext drumherum.
        - Maximal 4 Punkte, möglichst knapp.
        - Wenn die E-Mail leer oder sinnlos kurz ist, gib einen einzigen Punkt zurück: \
          "• Keine relevanten Inhalte erkennbar."
        """

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "summary": ["type": "string"]
            ],
            "required": ["summary"]
        ]

        let trimmedBody = String(body.prefix(8000))
        let userText: String = {
            let subjectLine = subject.isEmpty ? "" : "Betreff: \(subject)\n\n"
            return "\(subjectLine)E-Mail-Inhalt:\n\(trimmedBody)"
        }()

        struct R: Codable { let summary: String }
        let r: R = try await callJSON(
            schemaName: "email_summary",
            schema: schema,
            messages: [
                ["role": "system", "content": system],
                ["role": "user", "content": userText]
            ]
        )
        return r.summary
    }

    /// Decide whether an email confirms a concrete appointment and, if so,
    /// pull out title/date/time/location. The model is instructed to be
    /// conservative: `accepted=true` only for clearly mutual confirmations.
    func extractAppointment(subject: String, body: String) async throws -> ExtractedAppointment {
        let system = """
        Du bist ein präziser Termin-Extraktor für E-Mails einer kleinen \
        Webdesign-/Marketing-Agentur. Lies die E-Mail und entscheide, ob darin \
        ein konkreter Termin VERBINDLICH bestätigt oder akzeptiert wurde.

        Regeln für accepted=true:
        - Es gibt ein konkretes Datum UND eine konkrete Uhrzeit (oder klar ganztägig).
        - Der Termin ist erkennbar bestätigt — z. B. "passt", "bestätigt", \
          "freue mich auf Donnerstag 14 Uhr", "wir sehen uns am 20.06. um 10:00", \
          "der vorgeschlagene Termin am … passt mir".
        - Auch wenn jemand einen Vorschlag eindeutig annimmt: true.

        Regeln für accepted=false:
        - Reine Terminvorschläge ohne Bestätigung ("Wie wäre Donnerstag?").
        - Vages ("vielleicht nächste Woche", "melde mich noch").
        - Absagen / Stornierungen / Verschiebungen ohne neuen festen Termin.
        - Kein konkretes Datum ODER keine konkrete Uhrzeit (außer bei expliziter \
          Ganztags-Vereinbarung).

        Feld-Format:
        - title: Kurzer aussagekräftiger Titel (z. B. "Kickoff Website", \
          "Beratung SEO"). Bei accepted=false: null.
        - startsAt: ISO 8601 mit Zeitzone wenn bekannt (Beispiel \
          "2026-06-20T14:00:00+02:00"). Wenn keine Zeitzone genannt: \
          "2026-06-20T14:00:00" (interpretiert als Europa/Berlin). Bei \
          accepted=false oder ohne klaren Zeitpunkt: null.
        - endsAt: gleiches Format, optional. Wenn keine Endzeit/Dauer \
          erkennbar: null.
        - location: physische Adresse, Raum, Video-Link (Zoom/Meet/Teams) \
          oder Telefon. Wenn unbekannt: null.
        - allDay: true nur bei klar ganztägigem Termin, sonst false.

        Wenn mehrere Termine im Text stehen, wähle den EINEN, der am \
        eindeutigsten verbindlich vereinbart ist.
        """

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "accepted": ["type": "boolean"],
                "title":    ["type": ["string", "null"]],
                "startsAt": ["type": ["string", "null"]],
                "endsAt":   ["type": ["string", "null"]],
                "location": ["type": ["string", "null"]],
                "allDay":   ["type": ["boolean", "null"]]
            ],
            "required": ["accepted", "title", "startsAt", "endsAt", "location", "allDay"]
        ]

        let trimmedBody = String(body.prefix(8000))
        let userText: String = {
            let subjectLine = subject.isEmpty ? "" : "Betreff: \(subject)\n\n"
            return "\(subjectLine)E-Mail-Inhalt:\n\(trimmedBody)"
        }()

        return try await callJSON(
            schemaName: "appointment_extract",
            schema: schema,
            messages: [
                ["role": "system", "content": system],
                ["role": "user", "content": userText]
            ]
        )
    }

    /// Draft a friendly German reply to a received customer/lead email.
    /// Returns subject + body; nothing is persisted — the caller decides what to do.
    func draftReply(
        receivedSubject: String,
        receivedBody: String,
        leadName: String,
        leadCompany: String,
        offerDescription: String?
    ) async throws -> DraftedReply {
        let system = """
        Du verfasst freundliche, professionelle Antwort-E-Mails für eine kleine \
        Webdesign-/Marketing-Agentur. Antworte ausschließlich auf Deutsch.

        Regeln:
        - Beginne mit einer passenden Anrede ("Hallo {Vorname}" wenn ein Vorname \
          erkennbar ist, sonst "Hallo {Name}", sonst "Hallo zusammen").
        - Knapper, warmer Ton — keine Floskeln, keine Marketing-Phrasen.
        - Beziehe dich klar auf die Inhalte der empfangenen E-Mail.
        - Beantworte gestellte Fragen konkret. Falls offen, kündige Klärung an.
        - Maximal 4–6 Sätze plus Schlussformel.
        - Schluss mit "Beste Grüße" auf eigener Zeile (kein Name dahinter, \
          das ergänzt der Nutzer beim Versenden).
        - subject: "Re: {empfangener Betreff}" wenn vorhanden, sonst ein \
          eigener, treffender Betreff.
        """

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "subject": ["type": "string"],
                "body":    ["type": "string"]
            ],
            "required": ["subject", "body"]
        ]

        let trimmedBody = String(receivedBody.prefix(8000))
        let leadLine = leadCompany.isEmpty
            ? "Lead: \(leadName)"
            : "Lead: \(leadName) (\(leadCompany))"
        let offerLine: String = {
            guard let o = offerDescription?.trimmingCharacters(in: .whitespaces),
                  !o.isEmpty else { return "" }
            return "Aktuelles Angebot: \(o)\n"
        }()
        let subjectLine = receivedSubject.isEmpty
            ? ""
            : "Empfangener Betreff: \(receivedSubject)\n\n"
        let userText = """
        \(leadLine)
        \(offerLine)\(subjectLine)Empfangener E-Mail-Inhalt:
        \(trimmedBody)
        """

        return try await callJSON(
            schemaName: "reply_draft",
            schema: schema,
            messages: [
                ["role": "system", "content": system],
                ["role": "user", "content": userText]
            ]
        )
    }

    /// Quick health check used by the Settings view to validate a key.
    /// Read every lead's notes + emails + metadata in one call and return a
    /// prioritized list of concrete follow-up actions (call X again, chase
    /// the proposal, prepare for the meeting on … ). The caller is
    /// responsible for shaping `leads` — trim large bodies, prefer email
    /// summaries where available.
    func analyzeLeadsForActions(_ leads: [LeadAIInput]) async throws -> [LeadActionSuggestion] {
        let system = """
        Du bist ein Sales-Follow-up-Assistent für eine kleine Webdesign-/Marketing-Agentur. \
        Du bekommst mehrere Leads mit Notizen, E-Mail-Verlauf und Metadaten. Deine Aufgabe: \
        pro Lead 0–3 konkrete, priorisierte Handlungsempfehlungen ableiten, die dem User \
        heute wirklich weiterhelfen.

        Achte besonders auf:
        - Offene Angebote ohne Reaktion (Status "Angebot raus" + kein Kontakt seit >7 Tagen \
          → hohe Priorität: nachhaken).
        - Explizite Zusagen wie "melde mich Freitag" ohne bisherige Rückmeldung.
        - Konkrete Datumsangaben in Notizen oder E-Mails (Termine, Deadlines, Rückrufe) — \
          diese kommen als eigene Aktion mit `dueDate` im Feld raus, damit der User sich \
          vorbereiten kann.
        - Leads im Status "Neu" ohne Erstkontakt (klare Erstansprache empfehlen).

        Regeln:
        - Antworte ausschließlich mit dem JSON-Schema.
        - `leadId` UND `leadName` MÜSSEN dem Input entsprechen. Erfinde keine Leads.
        - `kind`: "call" für Anrufe, "email" für Nachfassmails/Erstansprachen, \
          "meeting" für vereinbarte oder anstehende Termine, "other" nur wenn wirklich \
          nichts davon passt.
        - `title`: knappe, sprechende Aktion in der Du-Form ("Ruf Anna Weber nochmal an", \
          "Schreib GmbH XY wegen Angebot", "Termin mit Meier am 15.07. vorbereiten").
        - `reason`: 1 Satz, warum jetzt — bezieht sich konkret auf das, was in den Daten \
          steht (Datum, Tag, letzter Kontakt, offene Frage).
        - `dueDate`: ISO 8601 (YYYY-MM-DD oder YYYY-MM-DDTHH:mm) NUR wenn im Input ein \
          echtes Datum steht. Sonst null. Vage Angaben ("bald", "nächste Woche") → null.
        - `priority`: "high" für heute/überfällig/verbindlich zugesagt, \
          "medium" für offene Angebote / laufender Kontakt, \
          "low" für Nice-to-have.
        - Wenn ein Lead absolut keine Aktion braucht (frisch gewonnen, klar verloren, \
          alles am Laufen), gib nichts für diesen Lead zurück — die Liste kann kürzer sein \
          als die Anzahl der Leads.
        - Insgesamt maximal 40 Aktionen zurückgeben.
        """

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "actions": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "leadId":   ["type": "string"],
                            "leadName": ["type": "string"],
                            "kind":     ["type": "string", "enum": ["call", "email", "meeting", "other"]],
                            "title":    ["type": "string"],
                            "reason":   ["type": "string"],
                            "dueDate":  ["type": ["string", "null"]],
                            "priority": ["type": "string", "enum": ["high", "medium", "low"]]
                        ],
                        "required": ["leadId", "leadName", "kind", "title", "reason", "dueDate", "priority"]
                    ]
                ]
            ],
            "required": ["actions"]
        ]

        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let userText = """
        Heutiges Datum: \(today)

        Leads:
        \(leads.map(\.serializedForPrompt).joined(separator: "\n\n---\n\n"))
        """

        struct R: Codable { let actions: [LeadActionSuggestion] }
        let r: R = try await callJSON(
            schemaName: "lead_actions",
            schema: schema,
            messages: [
                ["role": "system", "content": system],
                ["role": "user", "content": userText]
            ]
        )
        return r.actions
    }

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
