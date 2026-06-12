import SwiftUI

/// Save button that gives visible feedback after a click. Shows
/// "Gespeichert ✓" for ~2 seconds next to the button, then fades out.
/// Drop-in replacement for any `Button("Speichern") { ... }`.
struct SaveButton: View {
    let title: String
    let action: () -> Void

    @State private var justSaved = false

    init(_ title: String = "Speichern", action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(title) {
                action()
                withAnimation(.easeOut(duration: 0.15)) {
                    justSaved = true
                }
                Task {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    await MainActor.run {
                        withAnimation(.easeIn(duration: 0.25)) {
                            justSaved = false
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)

            if justSaved {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Gespeichert")
                }
                .font(.caption)
                .foregroundStyle(.green)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
    }
}
