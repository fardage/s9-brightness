import Foundation
import Security

/// Tells users of the DMG build when a newer release is on GitHub. The App Store updates its
/// installs itself, so those never check.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Release {
        let version: String
        let url: URL
    }

    /// A newer release than the running one, once a check found it.
    @Published private(set) var available: Release?

    private static let latestURL = URL(string: "https://api.github.com/repos/fardage/s9-brightness/releases/latest")!
    private static let interval: Duration = .seconds(24 * 60 * 60)

    /// The App Store re-signs apps with an Apple certificate that carries the Mac App Store
    /// extension; the DMG build is signed with Developer ID.
    private nonisolated static let isAppStoreInstall: Bool = {
        var code: SecCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9] exists" as CFString,
                                             [], &requirement) == errSecSuccess, let requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }()

    /// `checking: false` gives an inert checker, e.g. for rendering the menu.
    init(checking: Bool = true) {
        guard checking else { return }
        Task {
            // Validating the signature waits on trustd, so keep it off the main thread at launch.
            guard await !Task.detached(operation: { Self.isAppStoreInstall }).value else { return }
            while true {
                await check()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    private func check() async {
        var request = URLRequest(url: Self.latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return }
        let version = String(release.tag_name.trimmingPrefix("v"))
        available = Self.isNewer(version, than: current) ? Release(version: version, url: release.html_url) : nil
    }

    /// Compares dotted versions numerically, so 1.10 is newer than 1.9.
    nonisolated static func isNewer(_ version: String, than current: String) -> Bool {
        version.compare(current, options: .numeric) == .orderedDescending
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: URL
    }
}
