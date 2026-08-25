import Foundation

/// Asks the local container daemon what is running.
///
/// One `docker ps` per call, never on a tick that found no forwarder listening
/// and never more often than `ServiceRepository`'s own container cache allows.
/// The daemon is read over its own unix socket, so this touches no container and
/// opens no connection to anything the user is running.
///
/// Podman is out of scope. Its `-p` semantics and its rootless socket differ
/// enough that guessing would be worse than the single Docker row it gets today.
public struct ContainerLister: Sendable {
    /// Absolute paths only, in preference order, first executable one wins.
    ///
    /// Never resolved through `PATH` and never through `env` or `which`. Portfox
    /// spawns this on a timer, and a shim named `docker` early on a user's `PATH`
    /// would then be run by a background app. Same rule, and the same reason, as
    /// `VersionResolver.runtimeSpawnAllowlist`.
    ///
    /// One binary, not all of them. Docker Desktop, OrbStack and Colima all speak
    /// the same protocol and the CLI follows whichever context is current, so a
    /// second candidate would only ask the same daemon twice. Colima ships no
    /// `docker` of its own and is covered by the Homebrew path.
    public static func defaultCandidatePaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/Applications/OrbStack.app/Contents/MacOS/xbin/docker",
            "\(home)/.orbstack/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "\(home)/.docker/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker"
        ]
    }

    /// Field separator. No container name, image reference or port string can
    /// hold a control byte, and unlike a tab it survives a copy into a test
    /// fixture visibly.
    static let separator = "\u{1F}"

    static let format = [
        "{{.ID}}", "{{.Names}}", "{{.Image}}",
        "{{.Label \"com.docker.compose.project\"}}",
        "{{.Label \"com.docker.compose.service\"}}",
        "{{.Label \"com.docker.compose.project.working_dir\"}}",
        "{{.Ports}}"
    ].joined(separator: separator)

    /// A published range wider than this is refused outright, so `-p 1-65535`
    /// cannot turn one container into sixty-five thousand rows.
    static let maximumRangeWidth = 512

    private let candidatePaths: [String]
    private let timeout: Duration

    public init(
        candidatePaths: [String] = ContainerLister.defaultCandidatePaths(),
        timeout: Duration = .seconds(2)
    ) {
        self.candidatePaths = candidatePaths
        self.timeout = timeout
    }

    /// Nothing to list, rather than a thrown error, for every failure: no CLI, no
    /// daemon, a non-zero exit, a timeout. An unattributed socket falls to the
    /// residual row either way, which is exactly today's single Docker row.
    ///
    /// A `DOCKER_HOST` exported only from a shell rc is not found, because Portfox
    /// spawns without a login shell and starting one on a refresh tick is the sort
    /// of thing this app does not do. Such a machine keeps the row it has now.
    public func list() async -> [ContainerSnapshot] {
        guard let executable = resolvedExecutable() else { return [] }
        guard let output = await run(executable) else { return [] }
        return Self.parse(output)
    }

    /// Two seconds rather than the one `VersionResolver` allows itself, because a
    /// cold Docker Desktop or OrbStack VM answers far slower than `node --version`.
    private func run(_ executable: String) async -> String? {
        let deadline = timeout
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["ps", "--no-trunc", "--format", Self.format]
            process.standardInput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            let stdout = Pipe()
            process.standardOutput = stdout

            let finisher = ContinuationGate(continuation)

            process.terminationHandler = { finished in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                // A daemon that is not running exits non-zero with nothing on
                // stdout. Partial output from a healthy run cannot happen here,
                // `docker ps` writes the whole table or none of it.
                guard finished.terminationStatus == 0 else { return finisher.finish(nil) }
                finisher.finish(String(decoding: data, as: UTF8.self))
            }

            do {
                try process.run()
            } catch {
                finisher.finish(nil)
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + deadline.timeInterval) {
                if process.isRunning { process.terminate() }
                finisher.finish(nil)
            }
        }
    }

    /// The last path component must still be `docker` after symlinks resolve.
    /// `~/.orbstack/bin` and `~/.docker/bin` are user-writable, so the check is
    /// what stops a renamed binary in one of them from being spawned.
    private func resolvedExecutable() -> String? {
        for path in candidatePaths {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            guard resolved.lastPathComponent == "docker" else { continue }
            return path
        }
        return nil
    }

    // MARK: - Parsing

    /// One container per line. A line with the wrong field count is skipped and
    /// the lines around it survive, the same forgiveness `ListenerScanner.parse`
    /// shows a socket it cannot read.
    public static func parse(_ output: String) -> [ContainerSnapshot] {
        output.split(separator: "\n").compactMap { line -> ContainerSnapshot? in
            let fields = line.components(separatedBy: separator)
            guard fields.count == 7, !fields[0].isEmpty, !fields[2].isEmpty else { return nil }
            return ContainerSnapshot(
                id: fields[0],
                name: fields[1],
                image: fields[2],
                composeProject: optional(fields[3]),
                composeService: optional(fields[4]),
                composeWorkingDirectory: optional(fields[5]),
                publishedPorts: parsePorts(fields[6])
            )
        }
    }

    private static func optional(_ field: String) -> String? {
        let trimmed = field.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The published-port cell, which is the only place every shape docker emits
    /// has to be understood.
    ///
    /// Deduplicated by host port. A dual-stack publish is reported twice, once for
    /// IPv4 and once for IPv6, and it is one mapping.
    static func parsePorts(_ raw: String) -> [PublishedPort] {
        var seen: Set<Int> = []
        var ports: [PublishedPort] = []

        for entry in raw.components(separatedBy: ",") {
            for port in parseEntry(entry.trimmingCharacters(in: .whitespaces)) where !seen.contains(port.hostPort) {
                seen.insert(port.hostPort)
                ports.append(port)
            }
        }
        return ports
    }

    private static func parseEntry(_ entry: String) -> [PublishedPort] {
        // No arrow means exposed but not published. Nothing is listening on the
        // host, so lsof will never have a socket to match it against.
        let sides = entry.components(separatedBy: "->")
        guard sides.count == 2 else { return [] }

        let target = sides[1].components(separatedBy: "/")
        guard target.count == 2 else { return [] }
        // lsof reports only TCP, so a UDP publish must never claim a socket.
        let transport = target[1].lowercased()
        guard transport == "tcp" else { return [] }

        guard let (address, hostSpec) = splitAddress(sides[0]) else { return [] }
        let hostPorts = expand(hostSpec)
        let containerPorts = expand(target[0])
        guard !hostPorts.isEmpty, hostPorts.count == containerPorts.count else { return [] }

        return zip(hostPorts, containerPorts).map {
            PublishedPort(hostAddress: address, hostPort: $0, containerPort: $1, transport: transport)
        }
    }

    /// The host side is an address and a port separated by the last colon, which
    /// is what makes `:::5432` and `[::]:8080` fall out without special cases.
    private static func splitAddress(_ side: String) -> (address: String, ports: String)? {
        guard let colon = side.lastIndex(of: ":") else { return nil }
        let address = String(side[side.startIndex..<colon])
        let ports = String(side[side.index(after: colon)...])
        guard !ports.isEmpty else { return nil }
        let normalised = address == "[::]" ? "::" : address
        return (normalised.isEmpty ? "0.0.0.0" : normalised, ports)
    }

    private static func expand(_ spec: String) -> [Int] {
        if let single = Int(spec) { return [single] }

        let bounds = spec.components(separatedBy: "-")
        guard bounds.count == 2, let low = Int(bounds[0]), let high = Int(bounds[1]), low <= high else { return [] }
        guard high - low < maximumRangeWidth else { return [] }
        return Array(low...high)
    }
}
