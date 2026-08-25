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

    /// Lowercased image reference when this row is a container rather than a
    /// process on this machine. Nil for everything else.
    public let containerImage: String?

    /// The image's repository split into words, computed once. Twenty-three
    /// detectors carry an image signal and every detector's signals are evaluated,
    /// so parsing inside the signal would repeat the same split that many times
    /// per container.
    public let containerImageWords: Set<String>

    public init(
        process: ProcessSnapshot,
        project: ProjectSnapshot?,
        ports: [Int],
        relatedCommands: [String] = [],
        container: ContainerSnapshot? = nil
    ) {
        self.process = process
        self.project = project
        self.ports = ports
        self.relatedCommands = relatedCommands.map { $0.lowercased() }
        self.containerImage = container.map { $0.image.lowercased() }
        self.containerImageWords = container.map { Set(ContainerImage.repositoryComponents($0.image)) } ?? []

        // Blanked for a container, and this is what makes container detection
        // work at all. The executable on this host is `docker-proxy` or an
        // OrbStack helper, so leaving it visible lets the `.docker` detector match
        // it at full weight and beat `.postgres`, which is the exact bug being
        // fixed. `command` goes with it rather than being replaced by the image,
        // so no existing `commandContains` in the catalogue starts firing against
        // image strings it was never audited against.
        if container == nil {
            self.command = process.command.lowercased()
            self.executablePath = (process.resolvedExecutablePath ?? "").lowercased()
            self.executableName = process.executableName.lowercased()
        } else {
            self.command = ""
            self.executablePath = ""
            self.executableName = ""
        }
    }

    /// Matches against this process's command line and every related process's.
    public func anyCommandContains(_ needle: String) -> Bool {
        let needle = needle.lowercased()
        return command.containsToken(needle) || relatedCommands.contains { $0.containsToken(needle) }
    }
}
