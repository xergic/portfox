import Foundation
import Testing
@testable import PortfoxKit

private func process(
    _ pid: pid_t,
    parent: pid_t,
    group: pid_t? = nil,
    executable: String?,
    arguments: [String] = [],
    directory: String? = "/repo"
) -> ProcessSnapshot {
    ProcessSnapshot(
        pid: pid,
        parentPID: parent,
        processGroupID: group ?? pid,
        uid: 501,
        startTime: Date(timeIntervalSince1970: 1_000),
        executablePath: executable,
        arguments: arguments,
        workingDirectory: directory
    )
}

private let node = "/usr/local/bin/node"

@Suite("agent attribution")
struct AgentAttributionTests {
    private func agent(above pid: pid_t, in tree: ProcessTree) -> AgentKind? {
        Lineage.agent(among: tree.ancestors(of: pid, limit: Lineage.ancestorDepth))
    }

    @Test("a dev server is attributed to Claude Code through the shell it ran in")
    func claudeThroughShell() {
        let tree = ProcessTree(processes: [
            process(10, parent: 1, executable: "/opt/homebrew/Caskroom/claude-code@latest/2.1.285/claude"),
            process(20, parent: 10, executable: "/bin/zsh", arguments: ["/bin/zsh", "-c", "pnpm dev"]),
            process(30, parent: 20, executable: node, arguments: ["node", "pnpm", "dev"]),
            process(40, parent: 30, executable: node, arguments: ["node", "vite"])
        ])

        #expect(agent(above: 40, in: tree) == .claudeCode)
    }

    @Test("a dev server is attributed to Codex")
    func codex() {
        let tree = ProcessTree(processes: [
            process(5, parent: 1, executable: node, arguments: ["node", "/usr/local/bin/codex"]),
            process(10, parent: 5, executable: "/opt/homebrew/Caskroom/codex/0.159.2/bin/codex"),
            process(20, parent: 10, executable: "/bin/bash", arguments: ["bash", "-c", "npm run dev"]),
            process(30, parent: 20, executable: node, arguments: ["node", "next", "dev"])
        ])

        #expect(agent(above: 30, in: tree) == .codex)
    }

    @Test(
        "a name that only contains an agent's name is not that agent",
        arguments: [
            "/Users/me/.claude/plugins/cache/thedotmack/claude-mem/13.15.2/bin/claude-mem",
            "/opt/homebrew/Caskroom/claude-code@latest/2.1.285/node",
            "/opt/homebrew/Caskroom/codex/0.159.2/bin/codex-code-mode-host",
            "/Applications/Claude.app/Contents/MacOS/Claude"
        ]
    )
    func noFalseMatch(executable: String) {
        let tree = ProcessTree(processes: [
            process(10, parent: 1, executable: executable),
            process(20, parent: 10, executable: node, arguments: ["node", "server.js"])
        ])

        #expect(agent(above: 20, in: tree) == nil)
    }

    @Test("the listener itself is never its own agent")
    func listenerIsNotItsOwnAgent() {
        let tree = ProcessTree(processes: [process(10, parent: 1, executable: "/opt/homebrew/bin/claude")])

        #expect(agent(above: 10, in: tree) == nil)
    }
}

@Suite("orphaned services")
struct OrphanTests {
    private static let wishfox = "/Users/me/Work/Wishfox/wishfox-front"
    private static let workerd = wishfox
        + "/node_modules/.pnpm/@cloudflare+workerd-darwin-arm64@1.20260820.1"
        + "/node_modules/@cloudflare/workerd-darwin-arm64/bin/workerd"

    private func project(_ path: String, rootKind: ProjectSnapshot.RootKind = .git) -> ProjectSnapshot {
        makeSnapshot(root: URL(fileURLWithPath: path), name: (path as NSString).lastPathComponent, rootKind: rootKind)
    }

    /// The group leader is absent from the tree unless `alive` names it.
    private func isOrphaned(
        _ listener: ProcessSnapshot,
        category: ServiceCategory = .tooling,
        alive: [ProcessSnapshot] = [],
        cwdProject: ProjectSnapshot?,
        executableProject: ProjectSnapshot? = nil
    ) -> Bool {
        Lineage.isOrphaned(
            root: listener,
            category: category,
            tree: ProcessTree(processes: [listener] + alive),
            cwdProject: cwdProject,
            executableProject: executableProject
        )
    }

    @Test("a workerd whose wrangler died is orphaned")
    func workerdIsOrphaned() {
        let workerd = process(12891, parent: 1, group: 24049, executable: Self.workerd, directory: Self.wishfox)

        #expect(isOrphaned(workerd, cwdProject: project(Self.wishfox)))
    }

    /// launchd `setsid`s every job, so a LaunchAgent leads its own group. On the
    /// machine this was measured on, all 923 ppid 1 jobs did.
    @Test("a LaunchAgent running a project's server is not orphaned")
    func launchAgentIsNotOrphaned() {
        let agent = process(900, parent: 1, executable: "/opt/homebrew/bin/node", directory: "/Users/me/Work/api")

        #expect(!isOrphaned(agent, cwdProject: project("/Users/me/Work/api")))
    }

    @Test("a process whose group leader is still alive is not orphaned")
    func liveGroupLeader() {
        let leader = process(24049, parent: 500, executable: "/bin/zsh")
        let workerd = process(12891, parent: 1, group: 24049, executable: Self.workerd, directory: Self.wishfox)

        #expect(!isOrphaned(workerd, alive: [leader], cwdProject: project(Self.wishfox)))
    }

    @Test("an executable inside a project counts when the working directory does not")
    func executableProjectCounts() {
        let server = process(
            10, parent: 1, group: 7, executable: "/Users/me/Work/api/target/debug/api", directory: "/"
        )

        #expect(isOrphaned(server, cwdProject: nil, executableProject: project("/Users/me/Work/api")))
    }

    @Test("a live parent means not orphaned")
    func liveParent() {
        let workerd = process(12891, parent: 400, group: 24049, executable: Self.workerd, directory: Self.wishfox)

        #expect(!isOrphaned(workerd, cwdProject: project(Self.wishfox)))
    }

    @Test("a bare directory is not a project")
    func bareDirectory() {
        let server = process(10, parent: 1, group: 7, executable: node, directory: "/Users/me/Downloads")

        #expect(!isOrphaned(server, cwdProject: project("/Users/me/Downloads", rootKind: .directory)))
    }

    @Test(
        "an application launched by launchd is not orphaned, whatever its working directory",
        arguments: [
            "/Applications/OpenUsage.app/Contents/MacOS/OpenUsage",
            "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
            "/usr/libexec/rapportd"
        ]
    )
    func applicationIsNotOrphaned(executable: String) {
        let app = process(10, parent: 1, group: 7, executable: executable, directory: Self.wishfox)

        #expect(!isOrphaned(app, cwdProject: project(Self.wishfox)))
    }

    /// `brew services` runs Postgres with launchd as its parent and its data
    /// directory under the Homebrew prefix, which is itself a git repository.
    @Test("a Homebrew daemon is not orphaned")
    func homebrewDaemon() {
        let postgres = process(
            81233,
            parent: 1,
            group: 7,
            executable: "/opt/homebrew/Cellar/postgresql@17/17.11/bin/postgres",
            directory: "/opt/homebrew/var/postgresql@17"
        )

        #expect(!isOrphaned(postgres, category: .database, cwdProject: project("/opt/homebrew")))
        #expect(!isOrphaned(postgres, category: .web, cwdProject: project("/opt/homebrew")))
    }

    @Test("a tool installed in a hidden folder under home is not a project")
    func hiddenToolInstall() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let server = process(10, parent: 1, group: 7, executable: node, directory: "\(home)/.vscode/extensions/x")

        #expect(!isOrphaned(server, cwdProject: project("\(home)/.vscode/extensions/x", rootKind: .manifest)))
    }

    @Test("an orphan bound only to ephemeral ports still reaches the list")
    func ephemeralOrphanIsShown() {
        let classifier = ListenerClassifier(codeDirectories: [])
        let workerd = process(12891, parent: 1, group: 24049, executable: Self.workerd, directory: Self.wishfox)
        let detection = DetectionResult(type: .wrangler, score: 100, confidence: 1, evidence: [])
        let ports = [53671, 54249]

        #expect(isOrphaned(workerd, cwdProject: project(Self.wishfox)))
        #expect(classifier.classify(process: workerd, detection: detection, project: nil, ports: ports) == .systemNoise)
        // `hostService` passes an orphan no ports, which is what lifts the rule.
        let orphan = classifier.classify(process: workerd, detection: detection, project: project(Self.wishfox), ports: [])
        #expect(orphan == .developmentService)
        #expect(orphan.isUserManaged)

        let sockets = ports.map { ListeningSocket(pid: 12891, port: $0, host: "127.0.0.1", family: .ipv4) }
        #expect(ServiceRepository.primarySocket(from: sockets, type: .wrangler).port == 53671)
    }
}

@Suite("ungrouped services")
struct UngroupedTests {
    @Test("a service in no group, not standalone and not an agent tool is ungrouped")
    func ungrouped() {
        let grouped = makeService(port: 3000, project: nil, id: "a")
        let standalone = makeService(port: 5432, project: nil, id: "b")
        let tool = makeService(port: 37701, project: nil, id: "c")
        let stray = makeService(port: 4000, project: nil, id: "d")
        let project = Project(root: URL(fileURLWithPath: "/repo"), name: "repo")
        let result = ScanResult(
            services: [grouped, standalone, tool, stray],
            groups: [ProjectGroup(project: project, services: [grouped])],
            standalone: [standalone],
            agentTools: [tool],
            allSockets: [],
            hidden: []
        )

        #expect(result.ungrouped.map(\.id) == ["d"])
    }
}
