import Foundation

/// Why a service cannot be brought back the way it was started.
///
/// Each case is a refusal, not a failure. Relaunching the wrong thing is worse
/// than relaunching nothing, so anything ambiguous stops here.
public enum RelaunchRefusal: Error, Equatable, Sendable {
    case noWorkingDirectory
    case workingDirectoryGone(String)
    case noCommand
    case executableGone(String)
    case boundaryProcess
    case managedService

    public var reason: String {
        switch self {
        case .noWorkingDirectory:
            "its working directory could not be read"
        case .workingDirectoryGone(let path):
            "its working directory no longer exists (\(path))"
        case .noCommand:
            "its command line could not be read"
        case .executableGone(let path):
            "its executable is gone (\(path))"
        case .boundaryProcess:
            "it is a shell or terminal session, not a service Portfox started"
        case .managedService:
            "it is a database or daemon, restarted by whatever installed it rather than from a terminal"
        }
    }
}

/// The command that brings a stopped service back, as a script a terminal can run.
///
/// Built from the *logical root*, never the listener. `pnpm dev` runs a node
/// process that owns the socket, and relaunching that node argv would restart the
/// inner server without its task runner.
public struct RelaunchCommand: Equatable, Sendable {
    public let directory: String
    public let arguments: [String]

    /// What a terminal is handed: a login shell, so nvm, direnv, asdf and mise are
    /// back in place. A plain respawn inherits Portfox's environment instead, and
    /// a version-managed runtime is then simply missing.
    public var script: String {
        """
        #!/bin/zsh -l
        cd \(Self.quote(directory)) || exit 1
        exec \(arguments.map(Self.quote).joined(separator: " "))
        """
    }

    /// What Copy Command puts on the pasteboard, for a terminal that cannot be
    /// handed a script.
    public var clipboardText: String {
        "cd \(Self.quote(directory)) && \(arguments.map(Self.quote).joined(separator: " "))"
    }

    /// Databases and daemons are excluded on purpose. Homebrew, DBngin and Docker
    /// all bring their own back, so relaunching one by hand leaves a second copy
    /// nobody is managing the moment the supervisor notices the first is gone.
    public static func make(
        for service: RunningService,
        directoryExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Result<RelaunchCommand, RelaunchRefusal> {
        switch service.classification {
        case .infrastructure, .systemNoise:
            return .failure(.managedService)
        case .developmentService, .probableDeveloperProcess:
            return make(
                forRoot: service.rootProcess,
                directoryExists: directoryExists,
                fileExists: fileExists
            )
        }
    }

    public static func make(
        forRoot root: ProcessSnapshot,
        directoryExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Result<RelaunchCommand, RelaunchRefusal> {
        guard ProcessRole.of(root) != .boundary else { return .failure(.boundaryProcess) }

        let arguments = root.arguments.filter { !$0.isEmpty }
        guard !arguments.isEmpty else { return .failure(.noCommand) }

        guard let directory = root.workingDirectory, !directory.isEmpty else {
            return .failure(.noWorkingDirectory)
        }
        guard directoryExists(directory) else { return .failure(.workingDirectoryGone(directory)) }

        // A Homebrew upgrade unlinks the binary under a running process, and the
        // relaunch would fail in the terminal with a bare "command not found".
        // Only an absolute path is checked: a bare argv[0] is resolved through the
        // login shell's PATH, which is the point of using one.
        if let executable = root.resolvedExecutablePath, executable.hasPrefix("/"),
           !fileExists(executable) {
            return .failure(.executableGone(executable))
        }

        return .success(RelaunchCommand(directory: directory, arguments: arguments))
    }

    /// Single quotes, because the argv being wrapped comes from another process
    /// and must never be read as shell syntax. Inside single quotes every
    /// character is literal, so the only escape needed is for the quote itself.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
