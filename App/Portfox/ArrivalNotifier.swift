import AppKit
import PortfoxKit
import SwiftUI
import UserNotifications

/// Posts a banner when services appear.
///
/// Thin wrapper over one OS API that can refuse, reporting the refusal through
/// `lastError` the way `LaunchAtLogin` does, because a toggle that silently does
/// nothing is worse than one that says why.
@MainActor
@Observable
final class ArrivalNotifier {
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

    private var launchGate: LaunchGate?
    private var delegate: Delegate?
    private let defaults: UserDefaults
    private static let defaultsKey = "notifiesOnNewService"

    /// Repeats group under one heading in Notification Center.
    private static let threadIdentifier = "net.kandera.Portfox.arrivals"

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

        let delegate = Delegate { [weak self] in
            Task { @MainActor in self?.requestDashboard() }
        }
        self.delegate = delegate
        UNUserNotificationCenter.current().delegate = delegate

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
        guard isAuthorized else {
            report(Self.deniedMessage)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = digest.title
        content.body = digest.body
        content.threadIdentifier = Self.threadIdentifier

        // A fresh identifier every time, so a second arrival adds a banner rather
        // than silently replacing one the user has not read.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
        private let onDefaultAction: @Sendable () -> Void

        init(onDefaultAction: @escaping @Sendable () -> Void) {
            self.onDefaultAction = onDefaultAction
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
            guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
            onDefaultAction()
        }
    }
}
