import SwiftUI
import SwiftData

@main
struct FyluAgencyApp: App {
    @State private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Workspace.self,
            Customer.self,
            Lead.self,
            Issue.self,
            Cost.self,
            Invoice.self,
            InvoiceItem.self,
            UploadedInvoice.self
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
            ContentView()
                .environment(appState)
                .frame(minWidth: 1100, minHeight: 700)
                .task {
                    await appState.bootstrap(context: sharedModelContainer.mainContext)
                }
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
        }

        Settings {
            SettingsView()
                .environment(appState)
                .modelContainer(sharedModelContainer)
        }
    }
}
