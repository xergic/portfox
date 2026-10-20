import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Not ⌥⌘P, which Xcode binds to resuming SwiftUI previews.
    static let togglePopover = Self("togglePopover", default: .init(.p, modifiers: [.control, .option]))
}
