import SwiftUI

/// Non-blocking banner shown at the very top of the main window when
/// `UpdateChecker.availableRelease` is non-nil. Click "Update laden" to
/// open the release page in the default browser (Gatekeeper-safe path —
/// user drags the new .app in themselves).
struct UpdateBanner: View {
    let release: GitHubRelease
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.white)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Neue Version \(release.normalizedVersion) verfügbar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Aktuell installiert: \(UpdateChecker.currentVersion)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Button("Update laden") {
                onOpen()
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.blue)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.blue)
    }
}
