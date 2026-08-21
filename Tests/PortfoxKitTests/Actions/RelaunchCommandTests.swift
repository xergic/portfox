import Foundation
import Testing
@testable import PortfoxKit

@Suite("relaunch command")
struct RelaunchCommandTests {
    private func root(
        arguments: [String] = ["/opt/homebrew/bin/node", "/opt/homebrew/lib/pnpm.cjs", "dev"],
        workingDirectory: String? = "/Users/dev/app",
        executablePath: String? = "/opt/homebrew/bin/node"
    ) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: 4242,
            parentPID: 1,
            uid: 501,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            executablePath: executablePath,
            arguments: arguments,
            workingDirectory: workingDirectory
        )
    }

    private func make(_ process: ProcessSnapshot) -> Result<RelaunchCommand, RelaunchRefusal> {
        RelaunchCommand.make(forRoot: process, directoryExists: { _ in true }, fileExists: { _ in true })
    }

    // MARK: - The script

    @Test("the script runs the root's own argv in its own directory")
    func buildsScript() throws {
        let command = try make(root()).get()
        #expect(command.script == """
        #!/bin/zsh -l
        cd '/Users/dev/app' || exit 1
        exec '/opt/homebrew/bin/node' '/opt/homebrew/lib/pnpm.cjs' 'dev'
        """)
    }

    /// nvm, asdf and mise all live in the login shell. A relaunch that skipped it
    /// would fail with "command not found" on a version-managed runtime.
    @Test("the script asks for a login shell")
    func loginShell() throws {
        let command = try make(root()).get()
        #expect(command.script.hasPrefix("#!/bin/zsh -l\n"))
    }

    @Test("a failed cd stops the script rather than running the command somewhere else")
    func guardsTheDirectory() throws {
        let command = try make(root()).get()
        #expect(command.script.contains("|| exit 1"))
    }

    @Test("copying gives a single line that can be pasted into any shell")
    func clipboard() throws {
        let command = try make(root()).get()
        #expect(command.clipboardText ==
            "cd '/Users/dev/app' && '/opt/homebrew/bin/node' '/opt/homebrew/lib/pnpm.cjs' 'dev'")
    }

    // MARK: - Quoting

    @Test("a space in a path cannot split into two arguments")
    func quotesSpaces() {
        #expect(RelaunchCommand.quote("/Users/dev/My Projects/app") == "'/Users/dev/My Projects/app'")
    }

    @Test("shell metacharacters stay literal")
    func quotesMetacharacters() {
        #expect(RelaunchCommand.quote("a;id;b") == "'a;id;b'")
        #expect(RelaunchCommand.quote("$(whoami)") == "'$(whoami)'")
        #expect(RelaunchCommand.quote("a`id`b") == "'a`id`b'")
        #expect(RelaunchCommand.quote("a&&b") == "'a&&b'")
        #expect(RelaunchCommand.quote("a|b") == "'a|b'")
        #expect(RelaunchCommand.quote("a>b") == "'a>b'")
        #expect(RelaunchCommand.quote("a\nb") == "'a\nb'")
    }

    /// The one character single quotes cannot hold. Closing, escaping and
    /// reopening is the only correct form, and getting it wrong turns another
    /// process's argv into shell syntax.
    @Test("a single quote is closed, escaped and reopened")
    func quotesTheQuote() {
        #expect(RelaunchCommand.quote("it's") == #"'it'\''s'"#)
        #expect(RelaunchCommand.quote("'; id; '") == #"''\''; id; '\'''"#)
    }

    @Test("an argument built to break out of the quoting stays one argument")
    func injectionAttempt() throws {
        let hostile = "'; touch /tmp/portfox-escaped; echo '"
        let command = try make(root(arguments: ["/bin/echo", hostile])).get()
        #expect(command.script.hasSuffix(
            "exec '/bin/echo' ''\\''; touch /tmp/portfox-escaped; echo '\\'''"
        ))
    }

    // MARK: - Refusals

    @Test("a service with no readable working directory is refused")
    func refusesWithoutDirectory() {
        #expect(make(root(workingDirectory: nil)) == .failure(.noWorkingDirectory))
    }

    @Test("a directory that has since been deleted is refused")
    func refusesMissingDirectory() {
        let result = RelaunchCommand.make(
            forRoot: root(),
            directoryExists: { _ in false },
            fileExists: { _ in true }
        )
        #expect(result == .failure(.workingDirectoryGone("/Users/dev/app")))
    }

    @Test("a service with no readable command line is refused")
    func refusesWithoutCommand() {
        #expect(make(root(arguments: [])) == .failure(.noCommand))
        #expect(make(root(arguments: ["", ""])) == .failure(.noCommand))
    }

    /// What a Homebrew upgrade leaves behind: the process runs on, its binary does not.
    @Test("a service whose binary is gone is refused")
    func refusesMissingExecutable() {
        let result = RelaunchCommand.make(
            forRoot: root(),
            directoryExists: { _ in true },
            fileExists: { _ in false }
        )
        #expect(result == .failure(.executableGone("/opt/homebrew/bin/node")))
    }

    /// The login shell resolves it through PATH, which is the whole point of using one.
    @Test("a bare argv[0] is not checked against the filesystem")
    func allowsBareCommand() throws {
        let result = RelaunchCommand.make(
            forRoot: root(arguments: ["node", "server.js"], executablePath: nil),
            directoryExists: { _ in true },
            fileExists: { _ in false }
        )
        #expect(try result.get().script.hasSuffix("exec 'node' 'server.js'"))
    }

    @Test("a shell session is refused, the same process Stop refuses to signal")
    func refusesBoundary() {
        let shell = ProcessSnapshot(
            pid: 900,
            parentPID: 1,
            uid: 501,
            executablePath: "/bin/zsh",
            arguments: ["-zsh"],
            workingDirectory: "/Users/dev"
        )
        #expect(make(shell) == .failure(.boundaryProcess))
    }

    // MARK: - What a service is

    private func service(_ classification: ServiceClass) -> RunningService {
        let process = root()
        let socket = ListeningSocket(pid: process.pid, port: 3000, host: "127.0.0.1", family: .ipv4)
        return RunningService(
            id: "test",
            listenerProcess: process,
            rootProcess: process,
            sockets: [socket],
            primarySocket: socket,
            detection: .unknown(),
            classification: classification,
            project: nil
        )
    }

    private func make(_ service: RunningService) -> Result<RelaunchCommand, RelaunchRefusal> {
        RelaunchCommand.make(for: service, directoryExists: { _ in true }, fileExists: { _ in true })
    }

    @Test("a dev server is relaunched from its own command line")
    func relaunchesDevelopmentServices() throws {
        #expect(try make(service(.developmentService)).get().directory == "/Users/dev/app")
        #expect(try make(service(.probableDeveloperProcess)).get().directory == "/Users/dev/app")
    }

    /// Homebrew, DBngin and Docker all bring their own back. Relaunching one by
    /// hand leaves a second copy the moment the supervisor notices the first died.
    @Test("a database or daemon is refused, because something else already restarts it")
    func refusesManagedServices() {
        #expect(make(service(.infrastructure)) == .failure(.managedService))
        #expect(make(service(.systemNoise)) == .failure(.managedService))
    }

    @Test("every refusal explains itself, and reads as the tail of a sentence")
    func refusalsReadWell() {
        let refusals: [RelaunchRefusal] = [
            .noWorkingDirectory,
            .workingDirectoryGone("/gone"),
            .noCommand,
            .executableGone("/gone/node"),
            .boundaryProcess,
            .managedService
        ]
        for refusal in refusals {
            #expect(!refusal.reason.isEmpty)
            #expect(refusal.reason.first?.isUppercase == false)
        }
    }
}
