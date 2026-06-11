# Fylu Agency — macOS App

Native SwiftUI app for managing customers, leads, invoices and uploaded receipts —
with built-in multi-tenancy (workspaces), OpenAI-powered text parsing, and Apple
Vision OCR for scanned PDFs.

## What's in the box

- **Multi-workspace**: each workspace is a fully isolated agency identity
  (own customers, leads, invoices, business info, IBAN, layout colors,
  even its own OpenAI API key).
- **Dashboard**: KPIs (gross/net/VAT/count), filter today/week/month/year/all,
  Swift Charts revenue line, AI upsell suggestions, overdue invoices,
  open tasks across customers.
- **Customers**: stammdaten, issues with checkboxes, costs with frequency,
  invoices, uploaded PDFs.
- **Leads**: Kanban-style pipeline (new → contacted → meeting → proposal →
  won/lost), "convert to customer" action.
- **Invoices**: organic-text generator parses German prose into items via
  GPT-5.4-mini, computes VAT, exports A4 PDF with logo and configurable
  layout colors.
- **Upload + OCR**: drop a PDF on a customer, Vision OCR extracts text,
  GPT-5.4-mini pulls gross/net/VAT/date — even from scanned invoices.
- **Settings**: API key (Keychain), business info, banking, VAT, payment
  terms, invoice prefix, layout colors, logo upload, workspace management.

## Stack

- SwiftUI + SwiftData (macOS 14+)
- Swift Charts (dashboard)
- Vision Framework (OCR fallback for image-only PDFs)
- PDFKit (read PDFs)
- ImageRenderer (SwiftUI → PDF for invoice export)
- OpenAI Responses API (gpt-5.4-mini by default)
- Keychain for API keys (kSecClassGenericPassword, per workspace)

## Setup

```bash
# 1. Install xcodegen (one-time)
brew install xcodegen

# 2. Generate the Xcode project
cd ~/fylu-mac
xcodegen generate

# 3. Open in Xcode
open FyluAgency.xcodeproj
```

In Xcode: hit Run (⌘R). On first launch a "Fylu Marketing & Design" workspace
is created automatically — you can rename it, add more workspaces, or wipe it.

## OpenAI key

Open Settings (the gear icon in the sidebar or `⌘,` once running). Paste your
OpenAI API key into the **OpenAI API-Key** card and hit "Key speichern". The
key lands in the macOS Keychain under
`com.fylu.agency.openai` / `workspace.<UUID>.openai` — never in any file.

Hit "Verbindung testen" to verify the model name + key work.

## Project structure

```
fylu-mac/
├── project.yml                       # xcodegen config
├── FyluAgency/
│   ├── Info.plist
│   ├── FyluAgency.entitlements       # non-sandboxed for simplicity
│   ├── FyluAgencyApp.swift           # @main + ModelContainer
│   ├── AppState.swift                # global state, workspace tracking
│   ├── Models/
│   │   ├── Workspace.swift           # tenant root
│   │   ├── Customer.swift
│   │   ├── Lead.swift
│   │   ├── Issue.swift
│   │   ├── Cost.swift
│   │   ├── Invoice.swift             # +InvoiceItem
│   │   └── UploadedInvoice.swift
│   ├── Services/
│   │   ├── KeychainService.swift     # per-workspace API key storage
│   │   ├── OpenAIService.swift       # Responses API, JSON schema
│   │   ├── OCRService.swift          # Vision + PDFKit
│   │   ├── PDFRenderer.swift         # SwiftUI invoice template → PDF
│   │   └── Formatting.swift          # Money, dates, hex colors
│   ├── Components/
│   │   └── WorkspaceSwitcher.swift   # sidebar dropdown + new-workspace sheet
│   └── Views/
│       ├── ContentView.swift         # NavigationSplitView + sidebar
│       ├── DashboardView.swift
│       ├── CustomersListView.swift
│       ├── CustomerDetailView.swift
│       ├── LeadsListView.swift       # +LeadDetailView + Kanban
│       ├── InvoicesListView.swift    # +InvoiceComposerView (Generator)
│       ├── InvoiceDetailView.swift
│       └── SettingsView.swift
```

## Notes

- Storage is local — SwiftData SQLite file lives under
  `~/Library/Application Support/FyluAgency/`.
- Uploaded invoice PDFs land under
  `~/Library/Application Support/FyluAgency/uploads/<customerId>/`.
- No network calls except the OpenAI requests you trigger explicitly.
- Heuristic fallbacks for both invoice-text parsing and total extraction
  exist so the app stays usable if the API key is missing or the network
  is offline.
