import SwiftUI
import SwiftData

/// Modal sheet triggered from the Leads toolbar. Reads every lead's notes,
/// email history and metadata, sends the batch to OpenAI, and renders a
/// prioritized list of concrete follow-up actions. Tapping an action calls
/// `onOpenLead` — the parent view is responsible for dismissing the sheet
/// and pushing the lead detail.
struct LeadsInsightsSheet: View {
    let workspace: Workspace
    let onOpenLead: (Lead) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var actions: [LeadActionSuggestion] = []
    @State private var errorMessage: String?
    @State private var lastRunAt: Date?

    private var groupedActions: [(kind: LeadActionSuggestion.Kind, items: [LeadActionSuggestion])] {
        let order: [LeadActionSuggestion.Kind] = [.call, .email, .meeting, .other]
        return order.compactMap { kind in
            let items = actions.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind, items.sorted { priorityRank($0.priority) < priorityRank($1.priority) })
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("KI-Analyse")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await runAnalysis() }
                        } label: {
                            if isLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(actions.isEmpty ? "Analysieren" : "Neu analysieren", systemImage: "sparkles")
                            }
                        }
                        .disabled(isLoading || workspace.leads.isEmpty)
                    }
                }
        }
        .frame(minWidth: 560, minHeight: 520)
        .task {
            if actions.isEmpty && errorMessage == nil {
                await runAnalysis()
            }
        }
    }

    @ViewBuilder private var content: some View {
        if isLoading && actions.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Analysiere \(workspace.leads.count) Leads …")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.orange)
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Nochmal versuchen") {
                    Task { await runAnalysis() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if actions.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("Keine offenen Aktionen.")
                    .font(.headline)
                Text("Die KI hat aktuell nichts gefunden, wo du dranbleiben müsstest.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if let lastRunAt {
                        Text("Zuletzt analysiert: \(lastRunAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 20)
                    }
                    ForEach(groupedActions, id: \.kind) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: iconName(for: group.kind))
                                Text(sectionTitle(for: group.kind))
                                    .font(.headline)
                                Text("(\(group.items.count))")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 20)

                            VStack(spacing: 8) {
                                ForEach(group.items) { action in
                                    ActionCard(action: action) {
                                        openLead(for: action)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Actions

    private func openLead(for action: LeadActionSuggestion) {
        if let lead = workspace.leads.first(where: { $0.id.uuidString == action.leadId }) {
            onOpenLead(lead)
            dismiss()
        }
    }

    private func runAnalysis() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let service = OpenAIService(workspace: workspace) else {
            errorMessage = OpenAIError.missingAPIKey.errorDescription
            return
        }

        var inputs: [LeadAIInput] = []
        inputs.reserveCapacity(workspace.leads.count)
        for lead in workspace.leads {
            let sortedEmails = lead.emails.sorted { lhs, rhs in
                (lhs.sentAt ?? lhs.createdAt) < (rhs.sentAt ?? rhs.createdAt)
            }
            var snapshots: [LeadAIInput.EmailSnapshot] = []
            snapshots.reserveCapacity(sortedEmails.count)
            for email in sortedEmails {
                snapshots.append(LeadAIInput.EmailSnapshot(
                    direction: email.direction.rawValue,
                    subject: email.subject,
                    summary: email.summary,
                    body: email.body,
                    sentAt: email.sentAt
                ))
            }
            inputs.append(LeadAIInput(
                id: lead.id.uuidString,
                name: lead.name,
                company: lead.company,
                status: lead.status.title,
                offerDescription: lead.offerDescription ?? "",
                expectedValue: lead.expectedValue,
                lastContactAt: lead.lastContactAt,
                notes: lead.notes,
                emails: snapshots
            ))
        }

        guard !inputs.isEmpty else {
            actions = []
            return
        }

        do {
            let result = try await service.analyzeLeadsForActions(inputs)
            actions = result
            lastRunAt = Date()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Presentation helpers

    private func priorityRank(_ p: LeadActionSuggestion.Priority) -> Int {
        switch p {
        case .high:   return 0
        case .medium: return 1
        case .low:    return 2
        }
    }

    private func iconName(for kind: LeadActionSuggestion.Kind) -> String {
        switch kind {
        case .call:    return "phone.fill"
        case .email:   return "envelope.fill"
        case .meeting: return "calendar"
        case .other:   return "sparkles"
        }
    }

    private func sectionTitle(for kind: LeadActionSuggestion.Kind) -> String {
        switch kind {
        case .call:    return "Anrufen"
        case .email:   return "Schreiben"
        case .meeting: return "Termine"
        case .other:   return "Sonstiges"
        }
    }
}

// MARK: - Action card

private struct ActionCard: View {
    let action: LeadActionSuggestion
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                PriorityChip(priority: action.priority)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(action.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 4)
                        if let due = formattedDueDate(action.dueDate) {
                            Label(due, systemImage: "calendar")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    Text(action.leadName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(action.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.gray.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }

    private func formattedDueDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let parsers: [DateFormatter] = {
            let a = DateFormatter(); a.dateFormat = "yyyy-MM-dd'T'HH:mm"
            let b = DateFormatter(); b.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            let c = DateFormatter(); c.dateFormat = "yyyy-MM-dd"
            return [a, b, c]
        }()
        for p in parsers {
            if let d = p.date(from: raw) {
                let out = DateFormatter()
                out.locale = Locale(identifier: "de_DE")
                out.dateFormat = raw.contains("T") ? "dd.MM. HH:mm" : "dd.MM.yyyy"
                return out.string(from: d)
            }
        }
        return raw
    }
}

private struct PriorityChip: View {
    let priority: LeadActionSuggestion.Priority

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(color)
            .clipShape(Capsule())
            .frame(minWidth: 46)
    }

    private var label: String {
        switch priority {
        case .high:   return "HOCH"
        case .medium: return "MITTEL"
        case .low:    return "NIEDRIG"
        }
    }

    private var color: Color {
        switch priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .gray
        }
    }
}
