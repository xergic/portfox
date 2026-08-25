import AppKit

/// Runs a block once `NSApplication` exists.
///
/// `AppState` and everything it owns is built from the scene, which happens
/// before there is an `NSApplication`. Anything AppKit-side has to wait, or it
/// writes into nothing. The snapshot entry points build a second `AppState` from
/// inside `applicationDidFinishLaunching`, where the notification has already
/// fired and will never fire again, so both branches here stay live.
///
/// Held as a property by whoever needs it. The observer is removed when it fires;
/// a gate that never fires is one that outlived the launch it was waiting for,
/// which only happens at process exit.
@MainActor
final class LaunchGate {
    private var observer: (any NSObjectProtocol)?

    init(_ work: @escaping @MainActor () -> Void) {
        guard NSApp == nil else {
            work()
            return
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stop()
                work()
            }
        }
    }

    private func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}
