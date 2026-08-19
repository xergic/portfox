import Foundation

/// How interesting a listener is. Strict mode shows everything except `.systemNoise`.
public enum ServiceClass: String, Codable, Sendable, Comparable {
    /// A detector claimed it with a framework or runtime identity.
    case developmentService
    /// A detector claimed it as a database or daemon.
    case infrastructure
    /// No detector claimed it, but it is owned by the user and rooted in a code directory.
    case probableDeveloperProcess
    /// Apple daemons, agents and helpers.
    case systemNoise

    private var rank: Int {
        switch self {
        case .developmentService: 0
        case .infrastructure: 1
        case .probableDeveloperProcess: 2
        case .systemNoise: 3
        }
    }

    public static func < (lhs: ServiceClass, rhs: ServiceClass) -> Bool { lhs.rank < rhs.rank }
}

/// One logical service. May own several listening sockets and several processes.
public struct RunningService: Identifiable, Hashable, Sendable {
    /// Stable across refreshes as long as the process tree root survives.
    public let id: String

    /// Process that actually holds the listening socket.
    public let listenerProcess: ProcessSnapshot
    /// Process a Stop action should signal. Often an npm or pnpm wrapper above
    /// `listenerProcess`, so the wrapper does not survive its child.
    public let rootProcess: ProcessSnapshot
    /// Every listening socket owned by this logical service.
    public let sockets: [ListeningSocket]
    /// The socket to show and open.
    public let primarySocket: ListeningSocket

    public let detection: DetectionResult
    public let classification: ServiceClass
    public let project: ProjectSnapshot?

    public init(
        id: String,
        listenerProcess: ProcessSnapshot,
        rootProcess: ProcessSnapshot,
        sockets: [ListeningSocket],
        primarySocket: ListeningSocket,
        detection: DetectionResult,
        classification: ServiceClass,
        project: ProjectSnapshot?
    ) {
        self.id = id
        self.listenerProcess = listenerProcess
        self.rootProcess = rootProcess
        self.sockets = sockets
        self.primarySocket = primarySocket
        self.detection = detection
        self.classification = classification
        self.project = project
    }

    public var type: ServiceType { detection.type }
    public var port: Int { primarySocket.port }
    public var displayName: String { detection.type.displayName }

    /// Extra ports beyond the primary, ascending. A service usually binds the
    /// same port on IPv4 and IPv6, so ports are deduplicated. Ephemeral ports are
    /// dropped, they are internal plumbing the user never types.
    public var secondaryPorts: [Int] {
        Set(sockets.map(\.port))
            .subtracting([primarySocket.port])
            .filter { $0 < ListenerClassifier.ephemeralPortFloor }
            .sorted()
    }

    /// Monorepo subpath such as `apps/web`, or the service directory name.
    ///
    /// A database's working directory is its data directory, often a bare UUID,
    /// so infrastructure is labelled with its installed package instead.
    public var subtitle: String? {
        if type.category == .database || type.category == .infrastructure {
            return Self.packageLabel(for: listenerProcess.resolvedExecutablePath) ?? listenerProcess.executableName
        }
        if let subpath = project?.subpath, !subpath.isEmpty { return subpath }
        guard let cwd = listenerProcess.workingDirectoryURL else { return nil }
        return cwd.lastPathComponent
    }

    /// Turns `/opt/homebrew/opt/postgresql@17/bin/postgres` into `postgresql@17`
    /// and `/Users/Shared/DBngin/postgresql/17.0/bin/postgres` into `postgresql 17.0`.
    static func packageLabel(for executablePath: String?) -> String? {
        guard let executablePath else { return nil }
        let components = executablePath.split(separator: "/").map(String.init)
        guard let binIndex = components.lastIndex(of: "bin"), binIndex > 0 else { return nil }

        let name = components[binIndex - 1]
        guard let first = name.first, first.isNumber, binIndex > 1 else { return name }
        return "\(components[binIndex - 2]) \(name)"
    }

    public var localURL: URL? {
        guard type.isHTTP else { return nil }
        return URL(string: "http://\(primarySocket.displayHost):\(primarySocket.port)")
    }

    /// Directory to reveal in Finder.
    public var revealDirectory: URL? {
        listenerProcess.workingDirectoryURL ?? project?.serviceDirectory ?? project?.root
    }
}
