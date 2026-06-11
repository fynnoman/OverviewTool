import SwiftUI
import SwiftData

struct CustomersListView: View {
    let workspace: Workspace
    @Environment(\.modelContext) private var modelContext
    @State private var selectedCustomer: Customer?
    @State private var showNewCustomer = false
    @State private var searchText = ""

    private var customers: [Customer] {
        let scope = workspace.customers.sorted(by: { $0.createdAt > $1.createdAt })
        guard !searchText.isEmpty else { return scope }
        let q = searchText.lowercased()
        return scope.filter { c in
            c.name.lowercased().contains(q)
            || c.company.lowercased().contains(q)
            || c.email.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Kunden").font(.title2).fontWeight(.semibold)
                    Text("· \(customers.count)").foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showNewCustomer = true
                    } label: {
                        Label("Neuer Kunde", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)

                Divider()

                if customers.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Kunden",
                        systemImage: "person.2",
                        description: Text("Leg deinen ersten Kunden an.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(customers, selection: Binding(
                        get: { selectedCustomer?.id },
                        set: { id in selectedCustomer = customers.first { $0.id == id } }
                    )) {
                        TableColumn("Name") { c in
                            Button {
                                selectedCustomer = c
                            } label: {
                                Text(c.name).foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                        TableColumn("Firma") { c in Text(c.company.isEmpty ? "—" : c.company) }
                        TableColumn("Offene Aufgaben") { c in
                            let n = c.openIssuesCount
                            if n == 0 {
                                StatusPill(text: "Fertig", color: .green)
                            } else {
                                StatusPill(text: "\(n) offen", color: .orange)
                            }
                        }
                        TableColumn("Umsatz brutto") { c in
                            Text(Money.format(c.totalInvoiced))
                                .monospacedDigit()
                        }
                        TableColumn("Angelegt") { c in
                            Text(DateFmt.short(c.createdAt)).foregroundStyle(.secondary)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Kunden suchen")
                }
            }
            .navigationDestination(item: $selectedCustomer) { c in
                CustomerDetailView(customer: c)
            }
        }
        .sheet(isPresented: $showNewCustomer) {
            NewCustomerSheet(workspace: workspace) { newCustomer in
                selectedCustomer = newCustomer
            }
        }
    }
}

struct NewCustomerSheet: View {
    let workspace: Workspace
    let onCreated: (Customer) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var company = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var taxId = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Neuer Kunde").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }

            Form {
                Section {
                    TextField("Name *", text: $name)
                    TextField("Firma", text: $company)
                    TextField("E-Mail", text: $email)
                    TextField("Telefon", text: $phone)
                }
                Section("Adresse") {
                    TextEditor(text: $address).frame(minHeight: 80)
                }
                Section("Steuer & Notizen") {
                    TextField("USt-ID", text: $taxId)
                    TextEditor(text: $notes).frame(minHeight: 80)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Anlegen") {
                    let customer = Customer(
                        name: name.trimmingCharacters(in: .whitespaces),
                        company: company,
                        email: email,
                        phone: phone,
                        address: address,
                        taxId: taxId,
                        notes: notes
                    )
                    customer.workspace = workspace
                    modelContext.insert(customer)
                    try? modelContext.save()
                    onCreated(customer)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 620)
    }
}
