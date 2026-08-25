import Foundation

/// One running container, as `docker ps` reported it.
///
/// Structural only, and that is a hard rule rather than a style choice. This type
/// reaches `RunningService`, whose synthesised `Equatable` is what
/// `AppState.performRefresh` compares to decide whether to redraw. A field that
/// moved while the container ran, `docker ps`'s own `.Status` being the obvious
/// one, would make two scans of an unchanged machine compare unequal and repaint
/// the whole dashboard once a second. That is why the format string asks for
/// neither `.Status` nor `.RunningFor`, and why container uptime is absent.
public struct ContainerSnapshot: Identifiable, Hashable, Codable, Sendable {
    /// The full 64-hex id, never the 12-character prefix, because this is the
    /// stable half of the row's identity across a forwarder pid change.
    public let id: String
    public let name: String
    /// The image reference exactly as docker reported it, such as `postgres:16`.
    public let image: String
    public let composeProject: String?
    public let composeService: String?
    /// Where the compose file lives on this machine, when compose set the label.
    /// The only host directory a container row can honestly point at.
    public let composeWorkingDirectory: String?
    public let publishedPorts: [PublishedPort]

    public init(
        id: String,
        name: String,
        image: String,
        composeProject: String? = nil,
        composeService: String? = nil,
        composeWorkingDirectory: String? = nil,
        publishedPorts: [PublishedPort] = []
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.composeProject = composeProject
        self.composeService = composeService
        self.composeWorkingDirectory = composeWorkingDirectory
        self.publishedPorts = publishedPorts
    }

    /// The folder line under a container row's name. The image is left out, it is
    /// already implied by the detected service name and its version.
    public var displayLabel: String {
        if let composeProject, let composeService { return "\(composeProject) · \(composeService)" }
        return composeService ?? composeProject ?? name
    }

    public var workingDirectoryURL: URL? {
        composeWorkingDirectory.map { URL(fileURLWithPath: $0) }
    }
}

/// One `-p` mapping, host side and container side.
public struct PublishedPort: Hashable, Codable, Sendable {
    public let hostAddress: String
    public let hostPort: Int
    public let containerPort: Int
    /// `tcp` or `udp`. Named for the field rather than `protocol`, which is a keyword.
    public let transport: String

    public init(hostAddress: String, hostPort: Int, containerPort: Int, transport: String) {
        self.hostAddress = hostAddress
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.transport = transport
    }
}
