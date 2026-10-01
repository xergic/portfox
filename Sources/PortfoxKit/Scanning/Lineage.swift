import Foundation

/// A coding agent CLI that can sit above a dev server it started.
public enum AgentKind: String, Sendable, Hashable {
    case claudeCode
    case codex

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// Exact basenames, so `claude-mem`, `codex-code-mode-host` and a
    /// `claude-code@latest` directory never match. Case-sensitive on purpose:
    /// the desktop app's binary is `Claude`, and it is not the CLI.
    private static let byName: [String: AgentKind] = ["claude": .claudeCode, "codex": .codex]

    static func of(_ process: ProcessSnapshot) -> AgentKind? {
        byName[process.executableName]
            ?? process.arguments.first.flatMap { byName[($0 as NSString).lastPathComponent] }
    }
}

/// Who started a service, when that is worth telling the user.
public enum ServiceOrigin: Sendable, Hashable {
    /// The launcher died and launchd adopted the service, so nothing will ever
    /// stop it on its own.
    case orphaned
    case agent(AgentKind)

    /// Sentence case, the text of the row badge.
    public var label: String {
        switch self {
        case .orphaned: "Orphaned"
        case .agent(let agent): agent.displayName
        }
    }
}

/// Where a service came from: the agent that launched it, or the fact that
/// whatever launched it is gone.
public enum Lineage {
    /// Deep enough for `claude → zsh → pnpm → sh -c → node → node`, shallow
    /// enough that a terminal several sessions up is never reached by accident.
    public static let ancestorDepth = 12

    /// The nearest agent among a listener's ancestors, nearest first.
    ///
    /// Plain ancestors rather than `logicalRoot`, because an agent runs every
    /// command through a shell, and the shell is a boundary that the logical
    /// root walk refuses to cross.
    public static func agent(among ancestors: [ProcessSnapshot]) -> AgentKind? {
        ancestors.lazy.compactMap(AgentKind.of).first
    }

    /// Whether launchd adopted the service's root because its launcher died, and
    /// the root belongs to one of the user's projects. The root is the process
    /// launchd adopted, so its executable is the one the location rules judge.
    ///
    /// Plenty of processes have launchd as their parent on purpose: GUI apps,
    /// LaunchAgents, Homebrew services. launchd `setsid`s every job it starts,
    /// so each of those leads its own process group. A process whose group
    /// leader has exited was started by something that is gone. The project
    /// requirement and the location exclusions then keep out anything that is
    /// not the user's own code.
    public static func isOrphaned(
        root: ProcessSnapshot,
        category: ServiceCategory,
        tree: ProcessTree,
        cwdProject: ProjectSnapshot?,
        executableProject: @autoclosure () -> ProjectSnapshot?
    ) -> Bool {
        guard root.parentPID == 1,
              let group = root.processGroupID, group != root.pid, tree.process(group) == nil,
              category != .database, category != .infrastructure, category != .agent,
              let executable = root.resolvedExecutablePath,
              !isPackagedExecutable(executable)
        else { return false }

        return isUserProject(cwdProject) || isUserProject(executableProject())
    }

    private static func isUserProject(_ project: ProjectSnapshot?) -> Bool {
        guard let project, project.rootKind != .directory else { return false }
        return !isPackagedLocation(project.root.path)
    }

    /// `/usr/local/bin/node` is where the nodejs.org installer puts Node, and a
    /// Homebrew Node is just as much the user's runtime, so neither is excluded
    /// here. A Homebrew daemon is caught by `isPackagedLocation` instead, since
    /// its working directory resolves to the Homebrew prefix's own git repository.
    static func isPackagedExecutable(_ path: String) -> Bool {
        let path = path.lowercased()
        if SystemPaths.isInsideAppBundle(path) || SystemPaths.isShippedWithSystem(path) { return true }
        if path.hasPrefix("/usr/local/") { return false }
        return path.hasPrefix("/library/") || path.hasPrefix("/usr/")
    }

    /// Package managers whose prefix is somebody else's install. asdf and mise
    /// are left out: they hold the user's runtimes, never a project root.
    private static let packageManagerMarkers = RunningService.installationSources
        .filter { ["Homebrew", "MacPorts", "Nix"].contains($0.name) }
        .map(\.marker)

    /// Project roots that are somebody else's install rather than the user's code.
    static func isPackagedLocation(_ path: String) -> Bool {
        let lowered = path.lowercased()
        let path = lowered.hasSuffix("/") ? lowered : lowered + "/"
        if path.contains(".app/") { return true }
        if ["/system/", "/library/", "/usr/", "\(SystemPaths.home)/library/"].contains(where: path.hasPrefix) {
            return true
        }
        if packageManagerMarkers.contains(where: path.contains) { return true }

        // `~/.vscode/extensions`, `~/.cursor`, `~/.claude/plugins`: tool installs,
        // each with a manifest, none of them a project the user is working on.
        guard path.hasPrefix(SystemPaths.home + "/") else { return false }
        return path.dropFirst(SystemPaths.home.count).contains("/.")
    }
}
