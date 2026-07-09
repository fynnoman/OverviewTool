import SwiftUI
import SwiftData

@main
struct FyluAgencyApp: App {
    @State private var appState = AppState()
    @State private var updateChecker = UpdateChecker()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Workspace.self,
            Customer.self,
            Lead.self,
            LeadEmail.self,
            Issue.self,
            Cost.self,
            Invoice.self,
            InvoiceItem.self,
            UploadedInvoice.self,
            CashIncome.self,
            DeductibleExpense.self,
            Todo.self,
            Quote.self,
            QuoteItem.self,
            Appointment.self,
            Idea.self,
            MailAccount.self,
            MailMessage.self
        ])
        let config = ModelConfiguration(
            "FyluAgency",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Konnte ModelContainer nicht erstellen: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                if let release = updateChecker.availableRelease {
                    UpdateBanner(
                        release: release,
                        onOpen: { NSWorkspace.shared.open(release.htmlURL) },
                        onDismiss: { updateChecker.dismiss() }
                    )
                }
                ContentView()
                    .environment(appState)
                    .frame(minWidth: 1100, minHeight: 700)
                    .task {
                        await appState.bootstrap(context: sharedModelContainer.mainContext)
                    }
            }
            .task { await updateChecker.checkSilently() }
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Neue Rechnung") {
                    appState.selection = .invoices
                    appState.requestNewInvoice = true
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen …") {
                    Task { await updateChecker.checkManually() }
                }
                .disabled(updateChecker.isChecking)
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
                .modelContainer(sharedModelContainer)
        }
    }
}
