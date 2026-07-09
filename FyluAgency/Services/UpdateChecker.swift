import Foundation
import AppKit
import Observation

/// Checks the app's GitHub Releases page for a newer version. Called once on
/// launch and on-demand from the "Nach Updates suchen…" menu item.
///
/// The checker is intentionally cheap and dependency-free:
///  - one anonymous GET to `api.github.com` (60 req/hour unauthenticated —
///    plenty for a per-user check).
///  - Simple SemVer compare against `CFBundleShortVersionString`.
///  - No auto-download / no auto-install — clicking "Update laden" opens the
///    release page in the default browser so macOS handles Gatekeeper the
///    same way as a fresh install.
@Observable
@MainActor
final class UpdateChecker {
    /// GitHub owner/repo, hard-coded to the public release repo.
    static let repo = "fynnoman/OverviewTool"

    var availableRelease: GitHubRelease?
    var lastError: String?
    var isChecking = false

    /// Silent check on launch — only sets `availableRelease` when a newer
    /// version was found. Failures are swallowed so a flaky network doesn't
    /// bug the user at every start.
    func checkSilently() async {
        _ = try? await runCheck(quiet: true)
    }

    /// Explicit user-initiated check — surfaces "you're up to date" and
    /// error alerts.
    func checkManually() async {
        do {
            let release = try await runCheck(quiet: false)
            if release == nil {
                presentAlert(
                    title: "Du bist auf dem neuesten Stand",
                    message: "Version \(Self.currentVersion) ist die aktuellste."
                )
            }
        } catch {
            presentAlert(
                title: "Update-Prüfung fehlgeschlagen",
                message: error.localizedDescription
            )
        }
    }

    /// Reset after the user dismisses the update banner so it doesn't
    /// re-appear until the next launch / manual check.
    func dismiss() {
        availableRelease = nil
    }

    // MARK: - Internals

    @discardableResult
    private func runCheck(quiet: Bool) async throws -> GitHubRelease? {
        guard !isChecking else { return nil }
        isChecking = true
        defer { isChecking = false }
        lastError = nil

        let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.badResponse
        }
        guard http.statusCode == 200 else {
            throw UpdateError.http(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(GitHubRelease.self, from: data)
        let latest = release.normalizedVersion
        let current = Self.currentVersion

        if compareSemver(latest, current) == .orderedDescending {
            availableRelease = release
            return release
        }
        // Only clear the banner in interactive mode — the launch-time check
        // shouldn't wipe a banner set by a previous manual check.
        if !quiet {
            availableRelease = nil
        }
        return nil
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Version helpers

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private func compareSemver(_ a: String, _ b: String) -> ComparisonResult {
        let ac = a.split(separator: ".").map { Int($0) ?? 0 }
        let bc = b.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(ac.count, bc.count)
        for i in 0..<count {
            let ai = i < ac.count ? ac[i] : 0
            let bi = i < bc.count ? bc[i] : 0
            if ai != bi { return ai < bi ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

// MARK: - GitHub types

struct GitHubRelease: Codable, Identifiable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?

    var id: String { tagName }

    /// Strip the leading "v" so we can compare against `CFBundleShortVersionString`.
    var normalizedVersion: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    enum CodingKeys: String, CodingKey {
        case tagName    = "tag_name"
        case name
        case body
        case htmlURL    = "html_url"
        case publishedAt = "published_at"
    }
}

enum UpdateError: LocalizedError {
    case badResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse: "Antwort von GitHub konnte nicht gelesen werden."
        case .http(let c): "GitHub hat mit HTTP \(c) geantwortet."
        }
    }
}
