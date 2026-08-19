import Foundation

/// Parent and child relationships for every visible process, built once per scan.
public struct ProcessTree: Sendable {
    private let byPID: [pid_t: ProcessSnapshot]
    private let childrenByPID: [pid_t: [pid_t]]

    public init(processes: [ProcessSnapshot]) {
        var byPID: [pid_t: ProcessSnapshot] = [:]
        var children: [pid_t: [pid_t]] = [:]
        for process in processes {
            byPID[process.pid] = process
            children[process.parentPID, default: []].append(process.pid)
        }
        self.byPID = byPID
        self.childrenByPID = children
    }

    public var allProcesses: [ProcessSnapshot] { Array(byPID.values) }

    public func process(_ pid: pid_t) -> ProcessSnapshot? { byPID[pid] }

    /// Nearest ancestor first. Stops at pid 1 and at any cycle.
    public func ancestors(of pid: pid_t, limit: Int = 16) -> [ProcessSnapshot] {
        var result: [ProcessSnapshot] = []
        var seen: Set<pid_t> = [pid]
        var current = byPID[pid]?.parentPID ?? 0

        while current > 1, result.count < limit, !seen.contains(current), let parent = byPID[current] {
            result.append(parent)
            seen.insert(current)
            current = parent.parentPID
        }
        return result
    }

    public func children(of pid: pid_t) -> [ProcessSnapshot] {
        (childrenByPID[pid] ?? []).compactMap { byPID[$0] }
    }

    /// Breadth-first, excluding `pid` itself.
    public func descendants(of pid: pid_t, limit: Int = 256) -> [ProcessSnapshot] {
        var result: [ProcessSnapshot] = []
        var queue = childrenByPID[pid] ?? []
        var seen: Set<pid_t> = [pid]

        while let next = queue.popLast(), result.count < limit {
            guard !seen.contains(next), let process = byPID[next] else { continue }
            seen.insert(next)
            result.append(process)
            queue.append(contentsOf: childrenByPID[next] ?? [])
        }
        return result
    }

    /// The process a Stop action should signal.
    ///
    /// Walks up from the listener while each parent is a task runner that only
    /// exists to launch the child, such as `pnpm dev` or `sh -c`. Walking up
    /// means the runner does not survive its child. The walk stops hard at an
    /// interactive shell, a terminal emulator or `launchd`, so a Stop can never
    /// reach the user's own shell session.
    ///
    /// `serviceRoots` guards the other direction. A multiplexing runner such as
    /// `concurrently`, `turbo` or `make -j` is a wrapper by name but owns several
    /// unrelated services, so stopping one would take down the others. The walk
    /// refuses to enter any parent that owns more than one service.
    public func logicalRoot(of pid: pid_t, serviceRoots: Set<pid_t> = []) -> ProcessSnapshot? {
        guard let start = byPID[pid] else { return nil }
        var best = start
        var seen: Set<pid_t> = [pid]

        for parent in ancestors(of: pid) {
            guard !seen.contains(parent.pid) else { break }
            seen.insert(parent.pid)

            guard parent.pid > 1,
                  parent.uid == start.uid,
                  ProcessRole.of(parent) == .wrapper,
                  sharesDirectorySubtree(parent: parent, child: best),
                  !ownsSeveralServices(parent, serviceRoots: serviceRoots, current: pid)
            else { break }

            best = parent
        }
        return best
    }

    private func ownsSeveralServices(_ parent: ProcessSnapshot, serviceRoots: Set<pid_t>, current: pid_t) -> Bool {
        guard !serviceRoots.isEmpty else { return false }
        let owned = descendants(of: parent.pid)
            .map(\.pid)
            .filter { serviceRoots.contains($0) && $0 != current }
        return !owned.isEmpty
    }

    /// A wrapper only counts when it is working in the same place as its child.
    /// A parent that has moved elsewhere is a session, not a task runner.
    private func sharesDirectorySubtree(parent: ProcessSnapshot, child: ProcessSnapshot) -> Bool {
        guard let parentDirectory = parent.workingDirectory,
              let childDirectory = child.workingDirectory
        else {
            // Missing cwd on either side is common for wrappers. Do not block on it.
            return true
        }
        return childDirectory == parentDirectory || childDirectory.hasPrefix(parentDirectory + "/")
    }
}

/// What a process is doing in a service's process tree.
public enum ProcessRole: Sendable, Equatable {
    /// A task runner that exists only to launch the real service.
    case wrapper
    /// A shell session, terminal or system supervisor. Never walked through, never signalled.
    case boundary
    /// Anything else.
    case service

    private static let taskRunners: Set<String> = [
        "npm", "npm-cli.js", "pnpm", "yarn", "npx", "pnpx", "bunx", "corepack",
        "nodemon", "tsx", "ts-node", "turbo", "concurrently", "cross-env", "dotenv",
        "env", "make", "just", "task", "foreman", "overmind", "air", "watchexec",
        "uv", "poetry", "pipenv", "rye", "hatch", "mise", "asdf", "direnv", "rerun"
    ]

    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "ksh", "csh", "tcsh"]

    private static let supervisors: Set<String> = [
        "launchd", "login", "tmux", "tmux: server", "screen", "sshd", "ssh-agent", "systemd"
    ]

    public static func of(_ process: ProcessSnapshot) -> ProcessRole {
        let name = process.executableName.lowercased()

        if supervisors.contains(name) { return .boundary }
        if isTerminalOrEditor(process) { return .boundary }

        if shells.contains(name) {
            // `sh -c "pnpm dev"` is a task runner. A bare interactive shell is the
            // user's session and must never be signalled.
            return process.arguments.contains("-c") ? .wrapper : .boundary
        }

        if taskRunners.contains(name) { return .wrapper }
        if taskRunners.contains(effectiveToolName(process)) { return .wrapper }

        return .service
    }

    /// A runtime launched with a task runner script is that task runner.
    /// `node /path/node_modules/.bin/pnpm dev` is pnpm, not Node.
    static func effectiveToolName(_ process: ProcessSnapshot) -> String {
        let runtimes: Set<String> = ["node", "bun", "deno", "python", "python3"]
        guard runtimes.contains(process.executableName.lowercased()),
              process.arguments.count > 1
        else { return process.executableName.lowercased() }

        var script = (process.arguments[1] as NSString).lastPathComponent.lowercased()
        for suffix in [".js", ".mjs", ".cjs"] where script.hasSuffix(suffix) {
            script = String(script.dropLast(suffix.count))
        }
        return script
    }

    private static func isTerminalOrEditor(_ process: ProcessSnapshot) -> Bool {
        guard let path = process.resolvedExecutablePath?.lowercased() else { return false }
        // Anything living inside an application bundle or shipped by the system is
        // a session owner, not a task runner.
        return path.contains(".app/contents/") || path.hasPrefix("/system/") || path.hasPrefix("/usr/libexec/")
    }
}
