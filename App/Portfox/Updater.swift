import AppKit
import Combine
import Sparkle

@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    private(set) var isAvailable = false
    private(set) var canCheckForUpdates = false
    /// A scheduled check found this version and left it to `UpdateBanner`.
    fileprivate(set) var pendingVersion: String?

    var automaticallyChecks = false {
        didSet {
            guard let updater = controller?.updater, updater.automaticallyChecksForUpdates != automaticallyChecks
            else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    /// Sparkle holds its delegates weakly.
    @ObservationIgnored private let userDriverDelegate = UserDriverDelegate()
    @ObservationIgnored private var observation: AnyCancellable?

    /// Empty unless the release workflow sets `SPARKLE_FEED_URL`, so a local build
    /// or a fork never offers to replace itself with the release build.
    private static let hasFeed = !(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "").isEmpty

    private init() {}

    func start() {
        guard controller == nil, Self.hasFeed, SnapshotRenderer.request == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: userDriverDelegate
        )
        userDriverDelegate.updater = self
        self.controller = controller
        isAvailable = true
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self, canCheckForUpdates != value else { return }
                canCheckForUpdates = value
            }
    }

    /// Activates first, as the dashboard does. Sparkle's own activation is
    /// unreliable from a menu bar app, so a click on the banner opened the
    /// update window behind the frontmost app.
    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    func previewBanner(version: String) {
        pendingVersion = version
    }
}

/// A scheduled update never opens Sparkle's window. It shows `UpdateBanner`,
/// which hands back to the standard UI through `checkForUpdates`.
@MainActor
private final class UserDriverDelegate: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    weak var updater: Updater?

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else {
            if updater?.pendingVersion != update.displayVersionString {
                updater?.pendingVersion = update.displayVersionString
            }
            return
        }
        // An `LSUIElement` app is never active on its own, so the window would
        // open behind the frontmost app.
        NSApp.activate()
    }

    /// Cleared here rather than at the session's end, because after Install the
    /// banner would offer a window with nothing left to do.
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        clearBanner()
    }

    func standardUserDriverWillFinishUpdateSession() {
        clearBanner()
    }

    private func clearBanner() {
        if updater?.pendingVersion != nil { updater?.pendingVersion = nil }
    }
}
