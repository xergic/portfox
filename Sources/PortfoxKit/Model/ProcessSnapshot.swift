import Foundation

/// One TCP socket in LISTEN state, as reported by the scanner.
public struct ListeningSocket: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(pid):\(host):\(port)" }

    public let pid: pid_t
    public let port: Int
    public let host: String
    public let family: AddressFamily

    public enum AddressFamily: String, Codable, Sendable {
        case ipv4
        case ipv6
    }

    public init(pid: pid_t, port: Int, host: String, family: AddressFamily) {
        self.pid = pid
        self.port = port
        self.host = host
        self.family = family
    }

    /// True when the socket is reachable from this machine's browser.
    public var isLocallyReachable: Bool {
        host == "127.0.0.1" || host == "::1" || host == "0.0.0.0" || host == "::" || host == "localhost"
    }

    /// Host to put in a `http://` URL.
    public var displayHost: String {
        switch host {
        case "0.0.0.0", "::", "*": "localhost"
        case "::1": "localhost"
        default: host
        }
    }
}

/// Everything Portfox knows about one process. Every field except `pid` may be
/// missing, because hardened-runtime processes refuse some `proc_pidinfo` calls.
/// A missing field degrades the result, it never drops the service.
///
/// Deliberately structural. Resident memory is not here because it changes on
/// every sample, which would make two scans of an unchanged machine compare
/// unequal and redraw the whole UI. It is sampled separately, by
/// `ServiceRepository.sampleTasks`.
public struct ProcessSnapshot: Identifiable, Hashable, Codable, Sendable {
    public var id: pid_t { pid }

    public let pid: pid_t
    public let parentPID: pid_t
    public let uid: uid_t
    /// Boot-relative start time. Combined with `pid` it forms a stable identity
    /// across refreshes, so a recycled pid invalidates cached metadata.
    public let startTime: Date?
    public let executablePath: String?
    public let arguments: [String]
    public let workingDirectory: String?

    public init(
        pid: pid_t,
        parentPID: pid_t,
        uid: uid_t,
        startTime: Date? = nil,
        executablePath: String? = nil,
        arguments: [String] = [],
        workingDirectory: String? = nil
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.uid = uid
        self.startTime = startTime
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }

    /// Full command line, whitespace joined.
    public var command: String { arguments.joined(separator: " ") }

    /// `proc_pidpath` returns nothing when the binary's vnode is gone, which
    /// happens routinely after a Homebrew upgrade. argv[0] is then the best
    /// available path.
    public var resolvedExecutablePath: String? {
        if let executablePath, !executablePath.isEmpty { return executablePath }
        guard let first = arguments.first, first.hasPrefix("/") else { return nil }
        return first
    }

    /// Last path component of the executable, or the first argv entry.
    public var executableName: String {
        if let executablePath, !executablePath.isEmpty {
            return (executablePath as NSString).lastPathComponent
        }
        guard let first = arguments.first else { return "" }
        return (first as NSString).lastPathComponent
    }

    public var workingDirectoryURL: URL? {
        workingDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Identity that survives a refresh but not a pid recycle. Compared against
    /// a fresh kernel read immediately before any signal is sent.
    public var identity: String { Self.identity(pid: pid, startTime: startTime) }

    public static func identity(pid: pid_t, startTime: Date?) -> String {
        "\(pid)-\(Int(startTime?.timeIntervalSince1970 ?? 0))"
    }
}
