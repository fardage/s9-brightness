import AppKit
import Sparkle

/// Sparkle auto-updates. The feed URL and public signing key are in Info.plist.
@MainActor
final class Updater: NSObject, ObservableObject {
    /// A background check found an update the user hasn't acted on yet.
    @Published private(set) var updateAvailable = false

    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    func checkForUpdates() {
        // Menu bar apps aren't active by default, so bring Sparkle's window to the front.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

// Sparkle calls these on the main thread.
extension Updater: SPUStandardUserDriverDelegate {
    /// Menu bar apps should use gentle reminders: Sparkle shows the update without stealing
    /// focus, and the menu shows "Update Available…".
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        MainActor.assumeIsolated { updateAvailable = !state.userInitiated }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { updateAvailable = false }
    }
}
