import Foundation

enum AppInfo {
    static let name = "Portfox"
    static let summary = "Shows what is listening on your local ports."
    static let author = "Ondra Kandera"
    static let repositoryURL = URL(string: "https://github.com/xergic/portfox")!

    static let versionLabel = "v\(version)"
    static let fullVersionLabel = "Version \(version) (\(build))"

    /// `$(MARKETING_VERSION)`, which the release workflow overrides from the git tag.
    private static let version = string(for: "CFBundleShortVersionString")
    private static let build = string(for: "CFBundleVersion")

    private static func string(for key: String) -> String {
        Bundle.main.infoDictionary?[key] as? String ?? "—"
    }
}
