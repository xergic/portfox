import Foundation
import Testing
@testable import PortfoxKit

/// Builds process snapshots without touching the machine.
private func process(
    _ pid: pid_t,
    parent: pid_t = 1,
    executable: String? = nil,
    arguments: [String] = [],
    directory: String? = "/repo",
    uid: uid_t = 501
) -> ProcessSnapshot {
    ProcessSnapshot(
        pid: pid,
        parentPID: parent,
        uid: uid,
        startTime: Date(timeIntervalSince1970: 1_000),
        executablePath: executable,
        arguments: arguments,
        workingDirectory: directory
    )
}

private let node = "/usr/local/bin/node"
private let zsh = "/bin/zsh"

@Suite("process roles")
struct ProcessRoleTests {
    @Test("a task runner is a wrapper")
    func taskRunnerIsWrapper() {
        let pnpm = process(10, executable: "/usr/local/bin/pnpm", arguments: ["pnpm", "dev"])

        #expect(ProcessRole.of(pnpm) == .wrapper)
    }

    @Test("a runtime running a task runner script is that task runner")
    func runtimeRunningRunnerIsWrapper() {
        let wrapped = process(10, executable: node, arguments: ["node", "/usr/local/bin/pnpm", "dev"])

        #expect(ProcessRole.effectiveToolName(wrapped) == "pnpm")
        #expect(ProcessRole.of(wrapped) == .wrapper)
    }

    @Test("a shell running a command string is a wrapper")
    func shellWithCommandIsWrapper() {
        let shell = process(10, executable: "/bin/sh", arguments: ["sh", "-c", "pnpm dev"])

        #expect(ProcessRole.of(shell) == .wrapper)
    }

    @Test("an interactive shell is a boundary and is never signalled")
    func interactiveShellIsBoundary() {
        let interactive = process(10, executable: zsh, arguments: ["-zsh"])

        #expect(ProcessRole.of(interactive) == .boundary)
    }

    @Test("anything inside an application bundle is a boundary")
    func applicationBundleIsBoundary() {
        let editor = process(
            10,
            executable: "/Applications/Visual Studio Code.app/Contents/MacOS/Code Helper",
            arguments: ["Code Helper"]
        )

        #expect(ProcessRole.of(editor) == .boundary)
    }

    @Test("a boundary is still recognised when proc_pidpath returns nothing")
    func boundaryRecognisedFromArgv() {
        // Homebrew upgrades and deleted binaries make proc_pidpath fail, and a
        // missing path must not turn a terminal into a signalling target.
        let editor = process(
            10,
            executable: nil,
            arguments: ["/Applications/iTerm.app/Contents/MacOS/iTerm2"]
        )

        #expect(ProcessRole.of(editor) == .boundary)
    }

    @Test("a dev server is a service")
    func serverIsService() {
        let server = process(10, executable: node, arguments: ["node", "server.mjs"])

        #expect(ProcessRole.of(server) == .service)
    }
}

@Suite("logical root selection")
struct LogicalRootTests {
    /// zsh → pnpm → node, the shape of every `pnpm dev` on a real machine.
    private var standardTree: ProcessTree {
        ProcessTree(processes: [
            process(100, parent: 1, executable: zsh, arguments: ["-zsh"]),
            process(200, parent: 100, executable: node, arguments: ["node", "/usr/local/bin/pnpm", "dev"]),
            process(300, parent: 200, executable: node, arguments: ["node", "server.mjs"])
        ])
    }

    @Test("stopping a server targets the task runner that launched it")
    func targetsTaskRunner() {
        #expect(standardTree.logicalRoot(of: 300)?.pid == 200)
    }

    @Test("the walk never reaches the user's interactive shell")
    func stopsBelowInteractiveShell() {
        let root = standardTree.logicalRoot(of: 300)

        #expect(root?.pid != 100)
        #expect(ProcessRole.of(standardTree.process(100)!) == .boundary)
    }

    @Test("the walk stops below a terminal or editor")
    func stopsBelowEditor() {
        let tree = ProcessTree(processes: [
            process(100, parent: 1, executable: "/Applications/iTerm.app/Contents/MacOS/iTerm2"),
            process(200, parent: 100, executable: node, arguments: ["node", "/usr/local/bin/pnpm", "dev"]),
            process(300, parent: 200, executable: node, arguments: ["node", "server.mjs"])
        ])

        #expect(tree.logicalRoot(of: 300)?.pid == 200)
    }

    @Test("a wrapper working in an unrelated directory is not the service's runner")
    func stopsWhenDirectoriesDiverge() {
        let tree = ProcessTree(processes: [
            process(200, parent: 1, executable: node, arguments: ["node", "/usr/local/bin/pnpm", "dev"], directory: "/elsewhere"),
            process(300, parent: 200, executable: node, arguments: ["node", "server.mjs"], directory: "/repo")
        ])

        #expect(tree.logicalRoot(of: 300)?.pid == 300)
    }

    @Test("a runner owning several services is never the stop target")
    func refusesSharedOrchestrator() {
        // `concurrently` launching a web server and an API. Signalling it would
        // stop the sibling service the user did not ask about.
        let tree = ProcessTree(processes: [
            process(200, parent: 1, executable: "/repo/node_modules/.bin/concurrently", arguments: ["concurrently", "dev:web", "dev:api"]),
            process(300, parent: 200, executable: node, arguments: ["node", "web.mjs"]),
            process(400, parent: 200, executable: node, arguments: ["node", "api.mjs"])
        ])

        #expect(tree.logicalRoot(of: 300, serviceRoots: [300, 400])?.pid == 300)
        // With one service below it, the same runner is a legitimate target.
        #expect(tree.logicalRoot(of: 300, serviceRoots: [300])?.pid == 200)
    }

    @Test("a process whose parent has died is its own root")
    func reparentedProcessIsItsOwnRoot() {
        let tree = ProcessTree(processes: [process(300, parent: 1, executable: node, arguments: ["node", "server.mjs"])])

        #expect(tree.logicalRoot(of: 300)?.pid == 300)
    }

    @Test("a parent cycle terminates instead of looping")
    func survivesCycles() {
        let tree = ProcessTree(processes: [
            process(200, parent: 300, executable: node, arguments: ["node", "/usr/local/bin/pnpm", "dev"]),
            process(300, parent: 200, executable: node, arguments: ["node", "/usr/local/bin/pnpm", "dev"])
        ])

        #expect(tree.ancestors(of: 300).count <= 2)
        #expect(tree.logicalRoot(of: 300) != nil)
    }

    @Test("an unknown pid has no root")
    func unknownPIDHasNoRoot() {
        #expect(standardTree.logicalRoot(of: 999) == nil)
    }

    @Test("descendants are collected breadth first without revisiting")
    func collectsDescendants() {
        let tree = ProcessTree(processes: [
            process(100, parent: 1),
            process(200, parent: 100),
            process(300, parent: 200),
            process(400, parent: 100)
        ])

        #expect(Set(tree.descendants(of: 100).map(\.pid)) == [200, 300, 400])
        #expect(tree.descendants(of: 300).isEmpty)
    }
}

@Suite("service representative selection")
struct RepresentativeTests {
    /// wrangler spawns workerd, and both hold listening sockets in one directory.
    private var wranglerTree: ProcessTree {
        ProcessTree(processes: [
            process(100, parent: 1, executable: node, arguments: ["node", "wrangler.js", "dev"], directory: "/repo"),
            process(200, parent: 100, executable: "/repo/node_modules/.../workerd", directory: "/repo")
        ])
    }

    @Test("a child listener in the same directory folds into its parent listener")
    func foldsChildIntoParent() {
        #expect(ServiceRepository.representative(for: 200, listenerPIDs: [100, 200], tree: wranglerTree) == 100)
    }

    @Test("a listener whose parent does not listen stands alone")
    func standsAloneWithoutParentListener() {
        #expect(ServiceRepository.representative(for: 200, listenerPIDs: [200], tree: wranglerTree) == 200)
    }

    @Test("merging never crosses a shell or editor")
    func doesNotMergeAcrossBoundary() {
        // An editor that listens on its own extension port must not absorb the
        // dev server running in its integrated terminal.
        let tree = ProcessTree(processes: [
            process(100, parent: 1, executable: "/Applications/Code.app/Contents/MacOS/Code Helper", directory: "/repo"),
            process(200, parent: 100, executable: zsh, arguments: ["-zsh"], directory: "/repo"),
            process(300, parent: 200, executable: node, arguments: ["node", "server.mjs"], directory: "/repo")
        ])

        #expect(ServiceRepository.representative(for: 300, listenerPIDs: [100, 300], tree: tree) == 300)
    }

    @Test("an unknown working directory is not evidence of a shared service")
    func doesNotMergeOnMissingDirectory() {
        let tree = ProcessTree(processes: [
            process(100, parent: 1, executable: node, arguments: ["node", "thing.js"], directory: nil),
            process(200, parent: 100, executable: node, arguments: ["node", "server.mjs"], directory: "/repo")
        ])

        #expect(ServiceRepository.representative(for: 200, listenerPIDs: [100, 200], tree: tree) == 200)
    }

    @Test("a listener owned by another user is never merged in")
    func doesNotMergeAcrossUsers() {
        let tree = ProcessTree(processes: [
            process(100, parent: 1, executable: node, arguments: ["node", "thing.js"], directory: "/repo", uid: 0),
            process(200, parent: 100, executable: node, arguments: ["node", "server.mjs"], directory: "/repo")
        ])

        #expect(ServiceRepository.representative(for: 200, listenerPIDs: [100, 200], tree: tree) == 200)
    }
}

@Suite("stop safety")
struct ProcessControllerSafetyTests {
    private let controller = ProcessController()

    @Test("Portfox refuses to signal an interactive shell")
    func refusesInteractiveShell() {
        let shell = process(getpid() + 1, executable: zsh, arguments: ["-zsh"], uid: getuid())

        #expect(controller.safetyCheck(shell) == .refused(reason: "shell or terminal session"))
    }

    @Test("Portfox refuses to signal itself")
    func refusesItself() {
        let itself = process(getpid(), executable: node, arguments: ["node"], uid: getuid())

        #expect(controller.safetyCheck(itself) == .refused(reason: "Portfox itself"))
    }

    @Test("Portfox refuses to signal launchd")
    func refusesSystemProcess() {
        #expect(controller.safetyCheck(process(1, executable: "/sbin/launchd")) == .refused(reason: "system process"))
    }

    @Test("another user's process is reported as not permitted, not refused")
    func reportsForeignOwnership() {
        let foreign = process(getpid() + 1, executable: node, arguments: ["node", "x.js"], uid: getuid() + 1)

        #expect(controller.safetyCheck(foreign) == .notPermitted)
    }

    @Test("a recycled pid is treated as gone rather than signalled")
    func rejectsRecycledPID() {
        // Same pid as this test process, but a start time from 1970. This is what
        // a stale snapshot looks like after the kernel reuses a pid.
        let stale = ProcessSnapshot(
            pid: getpid(),
            parentPID: 1,
            uid: getuid(),
            startTime: Date(timeIntervalSince1970: 1),
            executablePath: node,
            arguments: ["node", "server.mjs"],
            workingDirectory: "/repo"
        )

        #expect(controller.verify(stale) == .notFound)
    }

    @Test("a pid that no longer exists is reported as gone")
    func rejectsDeadPID() {
        let dead = process(0x7FFF_FFF0, executable: node, arguments: ["node", "server.mjs"], uid: getuid())

        #expect(controller.verify(dead) == .notFound)
    }
}

@Suite("primary port selection")
struct PrimarySocketTests {
    private func socket(_ port: Int) -> ListeningSocket {
        ListeningSocket(pid: 1, port: port, host: "127.0.0.1", family: .ipv4)
    }

    @Test("a framework's default port wins")
    func prefersDefaultPort() {
        let chosen = ServiceRepository.primarySocket(from: [socket(51234), socket(3000)], type: .nextJS)

        #expect(chosen.port == 3000)
    }

    @Test("a stable port beats an ephemeral one")
    func prefersStablePort() {
        let chosen = ServiceRepository.primarySocket(from: [socket(60806), socket(8793)], type: .wrangler)

        #expect(chosen.port == 8793)
    }

    @Test("a debug port is never primary")
    func demotesDebugPort() {
        let chosen = ServiceRepository.primarySocket(from: [socket(9229), socket(4000)], type: .node)

        #expect(chosen.port == 4000)
    }

    @Test("with nothing to prefer, the lowest port wins")
    func fallsBackToLowestPort() {
        let chosen = ServiceRepository.primarySocket(from: [socket(8080), socket(4000)], type: .unknown)

        #expect(chosen.port == 4000)
    }
}
