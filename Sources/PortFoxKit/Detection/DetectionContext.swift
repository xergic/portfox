import Foundation

/// Everything a detector may look at. All string fields are pre-lowercased once
/// per process so signals stay cheap, and detectors stay pure functions.
public struct DetectionContext: Sendable {
    public let process: ProcessSnapshot
    public let project: ProjectSnapshot?
    /// Every port this logical service listens on.
    public let ports: [Int]
    /// Lowercased command lines of the ancestors and descendants of `process`.
    /// Needed for cases like `workerd`, whose identity lives on its `wrangler` parent.
    public let relatedCommands: [String]

    public let command: String
    public let executablePath: String
    public let executableName: String

    public init(
        process: ProcessSnapshot,
        project: ProjectSnapshot?,
        ports: [Int],
        relatedCommands: [String] = []
    ) {
        self.process = process
        self.project = project
        self.ports = ports
        self.relatedCommands = relatedCommands.map { $0.lowercased() }
        self.command = process.command.lowercased()
        self.executablePath = (process.executablePath ?? "").lowercased()
        self.executableName = process.executableName.lowercased()
    }

    /// Matches against this process's command line and every related process's.
    public func anyCommandContains(_ needle: String) -> Bool {
        let needle = needle.lowercased()
        return command.contains(needle) || relatedCommands.contains { $0.contains(needle) }
    }
}
