import Foundation

/// Finds the version of the software a service is running.
///
/// Three sources, cheapest first. The executable path often encodes the version
/// outright, a framework's version sits in its own `package.json`, and only as a
/// last resort is the binary asked directly.
public actor VersionResolver {
    private var cache: [String: String?] = [:]

    public init() {}

    /// Version to show beside the service name, or nil when nothing reliable was
    /// found. Never blocks on an unknown binary.
    public func version(for service: RunningService) async -> String? {
        nil
    }

    /// Version of the framework package itself, read from `node_modules`.
    public func frameworkVersion(type: ServiceType, project: ProjectSnapshot?, command: String) -> String? {
        nil
    }

    /// Version of the interpreter or daemon behind `executablePath`.
    public func runtimeVersion(type: ServiceType, executablePath: String?) async -> String? {
        nil
    }

    /// Trims a reported version to what is worth showing. `v24.16.0` becomes
    /// `24.16`, because a trailing zero patch is noise, while `4.5.2` is kept.
    public static func display(_ raw: String) -> String? {
        nil
    }

    public func invalidate() {
        cache.removeAll()
    }
}
