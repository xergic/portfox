import AppKit
import PortfoxKit
import SwiftUI
import UserNotifications

/// Posts a banner when services appear, when a watched one stops, and when
/// something the user is waiting on comes up.
///
/// Thin wrapper over one OS API that can refuse, reporting the refusal through
/// `lastError` the way `LaunchAtLogin` does, because a toggle that silently does
/// nothing is worse than one that says why.
@MainActor
@Observable
final class ServiceNotifier {
    private(set) var lastError: String?
    private(set) var isAuthorized = false

    /// Off by default. An app that starts notifying the day it is installed gets
    /// its notifications switched off in System Settings, not read.
    ///
    /// Here rather than beside the flash state, because switching it on asks
    /// macOS for permission, and the answer to that is `isAuthorized` and
    /// `lastError`, which live here too. Split across two types, the sheet reads a
    /// stale copy of the refusal.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.defaultsKey)
            if isEnabled { Task { await requestAuthorization() } }
        }
    }

    /// Bumped when the user clicks a banner. `WindowPresenter` needs an
    /// `OpenWindowAction`, which only exists in the SwiftUI environment, and the
    /// notification delegate is AppKit. `PortfoxApp` watches this instead.
    private(set) var dashboardRequests = 0

    /// Runs when the user presses Start Again on a stop banner. Set by `AppState`,
    /// which owns the relaunch.
    var onStartAgain: ((RunningService) -> Void)?

    /// The last stop of each watched service that offered Start Again. In memory
    /// only, because the relaunch needs the dead process's argv, which no banner
    /// can carry. Keyed by service rather than banner, so dismissed banners
    /// cannot pile up.
    @ObservationIgnored private var departures: [ServiceKey: RunningService] = [:]

    private var launchGate: LaunchGate?
    private var delegate: Delegate?
    private let defaults: UserDefaults
    private static let defaultsKey = "notifiesOnNewService"

    /// Repeats group under one heading in Notification Center.
    private static let threadIdentifier = "net.kandera.Portfox.arrivals"
    private static let departureThreadIdentifier = "net.kandera.Portfox.departures"
    private static let startThreadIdentifier = "net.kandera.Portfox.starts"
    private static let departureCategory = "departure"
    private static let startAgainAction = "startAgain"
    fileprivate nonisolated static let portInfoKey = "port"
    fileprivate nonisolated static let anchorInfoKey = "anchor"
    fileprivate nonisolated static let urlInfoKey = "url"

    private static let deniedMessage = "macOS is not delivering notifications from Portfox. "
        + "Turn them on in System Settings › Notifications."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `didSet` does not fire from `init`, so reading the preference here never
        // prompts. The prompt belongs to the user switching it on.
        isEnabled = defaults.bool(forKey: Self.defaultsKey)

        // `UNUserNotificationCenter.current()` wants a real running application.
        launchGate = LaunchGate { [weak self] in self?.activate() }
    }

    /// Sets the delegate and reads the current grant, but never prompts. The SDK
    /// requires a delegate before launch returns, and setting one neither asks
    /// the user for anything nor registers for anything. Prompting here, for a
    /// feature that ships off, is how an app gets its notifications switched off
    /// in System Settings before it has ever sent one.
    private func activate() {
        // A snapshot run scans once and exits. Nothing it does should reach the
        // notification daemon, the same reason `WindowPresenter` refuses to open
        // a real window during one.
        guard SnapshotRenderer.requestedPath == nil else { return }

        let delegate = Delegate { [weak self] action, key, url in
            Task { @MainActor in self?.respond(to: action, key: key, url: url) }
        }
        self.delegate = delegate
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        let startAgain = UNNotificationAction(identifier: Self.startAgainAction, title: "Start Again")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.departureCategory, actions: [startAgain], intentIdentifiers: [])
        ])

        Task { await readSettings() }
    }

    /// Asked only when the preference is switched on, never at launch.
    func requestAuthorization() async {
        do {
            // No sound: a port binding is not worth a chime. No badge: Portfox is
            // an `LSUIElement`, so there is no dock tile to badge.
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
            isAuthorized = granted
            report(granted ? nil : Self.deniedMessage)
        } catch {
            isAuthorized = false
            report("\(Self.deniedMessage) \(error.localizedDescription)")
        }
    }

    func post(_ digest: ServiceArrivalDigest) {
        let content = UNMutableNotificationContent()
        content.title = digest.title
        content.body = digest.body
        content.threadIdentifier = Self.threadIdentifier
        add(content)
    }

    /// One banner per service, unlike arrivals, because each carries its own
    /// Start Again and a watched server stopping is rare.
    func postDeparture(of service: RunningService, offersStartAgain: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "\(service.displayName) stopped"
        content.body = ["Port \(service.port)", service.project?.name ?? service.subtitle]
            .compactMap { $0 }
            .joined(separator: " · ")
        content.threadIdentifier = Self.departureThreadIdentifier
        if offersStartAgain, let key = ServiceKey(service) {
            content.categoryIdentifier = Self.departureCategory
            content.userInfo = [Self.portInfoKey: key.port, Self.anchorInfoKey: key.anchor]
            departures[key] = service
        }
        add(content)
    }

    /// Clicking it opens the server, which is what the user was waiting to do.
    func postStarted(_ service: RunningService) {
        let content = UNMutableNotificationContent()
        content.title = "\(service.project?.name ?? service.displayName) is up"
        content.body = [service.displayName, "Port \(service.port)"].joined(separator: " · ")
        content.threadIdentifier = Self.startThreadIdentifier
        if let url = service.localURL {
            content.userInfo = [Self.urlInfoKey: url.absoluteString]
        }
        add(content)
    }

    func postGaveUp(waitingFor label: String, afterMinutes minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Stopped waiting for \(label)"
        content.body = "Nothing came up within \(minutes) minutes."
        content.threadIdentifier = Self.startThreadIdentifier
        add(content)
    }

    /// A fresh identifier every time, so a second banner adds to the first rather
    /// than silently replacing one the user has not read.
    private func add(_ content: UNNotificationContent) {
        guard isAuthorized else {
            report(Self.deniedMessage)
            return
        }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    private func respond(to action: String, key: ServiceKey?, url: URL?) {
        if action == Self.startAgainAction, let key, let service = departures.removeValue(forKey: key) {
            onStartAgain?(service)
        } else if action == UNNotificationDefaultActionIdentifier {
            if let url { NSWorkspace.shared.open(url) } else { requestDashboard() }
        }
    }

    private func readSettings() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Guarded, because a denied grant would otherwise rewrite observable state
    /// on every arrival and repaint the preferences sheet for nothing.
    private func report(_ message: String?) {
        if lastError != message { lastError = message }
    }

    private func requestDashboard() { dashboardRequests += 1 }

    /// `UNUserNotificationCenterDelegate` carries no main-actor annotation, so the
    /// conformance is `nonisolated` and both callbacks hop, exactly as the
    /// `Appearance` observers do.
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        /// A closure rather than a back reference, because the callbacks arrive
        /// nonisolated and the delegate itself is not `Sendable`. The hop to the
        /// main actor is written once, at the point where the owner is known.
        private let onResponse: @Sendable (_ action: String, _ key: ServiceKey?, _ url: URL?) -> Void

        init(onResponse: @escaping @Sendable (_ action: String, _ key: ServiceKey?, _ url: URL?) -> Void) {
            self.onResponse = onResponse
        }

        /// Without this, macOS suppresses the banner whenever Portfox is
        /// frontmost, which is precisely when the dashboard is open.
        nonisolated func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            [.banner, .list]
        }

        nonisolated func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse
        ) async {
            // Unpacked here, because `userInfo` is not `Sendable` and cannot cross
            // to the main actor as it is.
            let info = response.notification.request.content.userInfo
            let key = (info[ServiceNotifier.portInfoKey] as? Int).flatMap { port in
                (info[ServiceNotifier.anchorInfoKey] as? String).map { ServiceKey(port: port, anchor: $0) }
            }
            let url = (info[ServiceNotifier.urlInfoKey] as? String).flatMap(URL.init(string:))
            onResponse(response.actionIdentifier, key, url)
        }
    }
}
