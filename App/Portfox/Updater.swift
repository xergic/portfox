import AppKit
import Combine
import Sparkle

@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    private(set) var isAvailable = false
    private(set) var canCheckForUpdates = false

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

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

/// An `LSUIElement` app is never active on its own, so without this a scheduled
/// update opens its window behind whatever the user is working in.
private final class UserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        NSApp.activate()
    }
}
