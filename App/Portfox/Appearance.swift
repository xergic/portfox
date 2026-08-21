import AppKit
import SwiftUI

/// Which appearance the app draws in. `system` follows macOS, the other two pin
/// it, so a user on a light Mac can still keep the dark design they installed.
enum AppAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Owns the appearance preference and resolves `system` against macOS.
/// A `UserDefaults`-backed app concern like `IgnoredServices`, so the kit still
/// has no idea the app has a theme.
@MainActor
@Observable
final class Appearance {
    var preference: AppAppearance {
        didSet {
            defaults.set(preference.rawValue, forKey: Key.appearance)
            apply()
        }
    }

    /// What the surfaces actually draw in, with `system` already resolved. Views
    /// observe this rather than `preference`, so a macOS theme change reaches
    /// them without the preference moving.
    private(set) var colorScheme: ColorScheme = .dark

    /// `colorScheme` in AppKit's terms, for the window chrome. Never nil, unlike
    /// `AppAppearance.nsAppearance`: by here `system` has already been resolved.
    var nsAppearance: NSAppearance? { NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) }

    /// Set by the snapshot path only. Wins over the preference, so the observer
    /// firing on the appearance it just set cannot undo it.
    private var forced: AppAppearance?
    private var observation: NSKeyValueObservation?
    private var isApplying = false
    private var launchObserver: (any NSObjectProtocol)?
    private let defaults = UserDefaults.standard

    private enum Key {
        static let appearance = "appearance"
    }

    init() {
        defaults.register(defaults: [Key.appearance: AppAppearance.system.rawValue])
        preference = AppAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        // Before the first body runs, or the first frame is drawn in whichever
        // palette the enum happened to default to.
        apply()

        // `NSApp` is still nil here: the scene builds its state before there is
        // an `NSApplication` to hand it. Everything AppKit-side has to wait, or
        // it writes into nothing and the asset variants never follow the pin.
        // Portfox builds its state from the scene, before `NSApplication` exists.
        // The snapshot entry points build a second one from inside
        // `applicationDidFinishLaunching`, where the notification has already
        // fired and will never fire again, so both branches are live.
        if NSApp == nil {
            launchObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didFinishLaunchingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.activate() }
            }
        } else {
            activate()
        }
    }

    private func activate() {
        if let launchObserver {
            NotificationCenter.default.removeObserver(launchObserver)
            self.launchObserver = nil
        }
        observation = NSApp?.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.apply() }
        }
        apply()
    }

    /// Snapshots only. Renders in an appearance without writing the preference,
    /// so `make snapshot` cannot leave the user pinned to light.
    func force(_ appearance: AppAppearance) {
        forced = appearance
        apply()
    }

    /// `NSApp.appearance` has to move too, not just the SwiftUI environment: the
    /// service logos and the window chrome are AppKit, and both resolve against
    /// `NSApp.effectiveAppearance` rather than against `\.colorScheme`.
    private func apply() {
        // `setAppearance:` invalidates the effective appearance synchronously,
        // which fires the observer below before the property reads back as the
        // value being set. Comparing the two is not enough to stop it: without
        // this flag the write recurses until the stack runs out.
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        let appearance = forced ?? preference
        NSApp?.appearance = appearance.nsAppearance
        let resolved = resolve(appearance)
        if colorScheme != resolved { colorScheme = resolved }
    }

    /// `system` is the only case that has to ask anybody: the other two carry
    /// their own `NSAppearance` and answer themselves.
    private func resolve(_ appearance: AppAppearance) -> ColorScheme {
        let effective = appearance.nsAppearance ?? NSApp?.effectiveAppearance ?? .currentDrawing()
        return effective.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}
