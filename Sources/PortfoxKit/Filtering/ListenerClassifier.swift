import Foundation

/// Sorts listeners into the four buckets of spec section 16, so the popover shows
/// ten real services instead of ninety raw listeners.
public struct ListenerClassifier: Sendable {
    /// Directories whose contents are the user's own code. Used only as a
    /// fallback, a resolved project is far stronger evidence.
    private let codeDirectories: [String]

    public init(codeDirectories: [String] = ListenerClassifier.defaultCodeDirectories()) {
        self.codeDirectories = codeDirectories.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
    }

    public static func defaultCodeDirectories() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let names = [
            "Code", "Coding", "Projects", "Project", "Work", "dev", "Dev", "Developer",
            "src", "Sites", "repos", "Repos", "git", "GitHub", "Documents"
        ]
        return names.map { "\(home)/\($0)" } + ["/tmp", "/private/tmp"]
    }

    /// macOS allocates ephemeral source ports from here up.
    public static let ephemeralPortFloor = 49152

    public func classify(
        process: ProcessSnapshot,
        detection: DetectionResult,
        project: ProjectSnapshot?,
        ports: [Int],
        isContainer: Bool = false
    ) -> ServiceClass {
        // First, above everything, because a container row's `rootProcess` is a
        // port forwarder shared with every other container on the machine. An
        // `nginx:alpine` row would otherwise detect as `.nginx`, whose category is
        // `.web`, fall to `.developmentService` below, and let Stop All SIGTERM
        // the forwarder for the whole machine.
        if isContainer { return .infrastructure }

        // Nothing a developer opens lives only on an ephemeral port. The caller
        // passes no ports for an orphan, the one exception, see `Lineage`.
        if !ports.isEmpty, ports.allSatisfy({ $0 >= Self.ephemeralPortFloor }) { return .systemNoise }

        if detection.type != .unknown {
            switch detection.type.category {
            case .database, .infrastructure: return .infrastructure
            case .agent: return .agentTool
            default: return .developmentService
            }
        }

        let executable = process.executablePath ?? ""
        if SystemPaths.isShippedWithSystem(executable) || SystemPaths.isInsideAppBundle(executable) {
            return .systemNoise
        }

        if let project, project.rootKind != .directory { return .probableDeveloperProcess }
        if let directory = process.workingDirectory, isUserCode(directory) { return .probableDeveloperProcess }

        return .systemNoise
    }

    func isUserCode(_ directory: String) -> Bool {
        let path = directory.hasSuffix("/") ? directory : directory + "/"
        return codeDirectories.contains { path.hasPrefix($0) }
    }
}
