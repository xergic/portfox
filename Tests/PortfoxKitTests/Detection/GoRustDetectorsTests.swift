import Foundation
import Testing
@testable import PortfoxKit

/// Compiled binaries carry no runtime evidence, so both rows key on build output
/// paths. The negatives matter more than the positives here: a path shape is
/// weaker evidence than a command name, and `target/` is shared with Maven.
@Suite("Go and Rust detectors")
struct GoRustDetectorsTests {
    private let engine = DetectionEngine(
        detectors: DetectorCatalog.compiled + DetectorCatalog.nodeEcosystem + DetectorCatalog.jvm
    )

    @Test("a binary running from the Go build cache is Go")
    func goBuildCache() {
        let path = "/private/var/folders/xy/T/go-build1234/b001/exe/main"
        let context = DetectionFixture.context(
            argv: [path],
            executablePath: path,
            ports: [8080]
        )

        #expect(engine.detect(context).type == .go)
    }

    @Test("a Delve debug build is Go")
    func delveDebugBinary() {
        let context = DetectionFixture.context(
            argv: ["/proj/__debug_bin3141592"],
            executablePath: "/proj/__debug_bin3141592",
            ports: [8080]
        )

        #expect(engine.detect(context).type == .go)
    }

    @Test("a binary rebuilt by air is Go")
    func airLiveReload() {
        let context = DetectionFixture.context(
            argv: ["/proj/tmp/main"],
            executablePath: "/proj/tmp/main",
            ports: [8080],
            relatedCommands: ["air -c .air.toml"]
        )

        #expect(engine.detect(context).type == .go)
    }

    @Test("a binary inside a Go module is Go even when the path has capitals")
    func binaryInsideModuleWithMixedCasePath() {
        // `executablePath` is lowercased at init while `project.root.path` is not,
        // so a naive prefix comparison silently never matches a real home path.
        // The fixture pins its root to /tmp, so this one builds the context directly.
        let root = URL(fileURLWithPath: "/Users/Me/Code/MyAPI")
        let project = ProjectSnapshot(
            root: root,
            serviceDirectory: root,
            name: "MyAPI",
            files: ["go.mod"],
            rootFiles: ["go.mod"]
        )
        let context = DetectionContext(
            process: ProcessSnapshot(
                pid: 4242,
                parentPID: 1,
                uid: 501,
                executablePath: "/Users/Me/Code/MyAPI/server",
                arguments: ["/Users/Me/Code/MyAPI/server"]
            ),
            project: project,
            ports: [8080]
        )

        #expect(engine.detect(context).type == .go)
    }

    @Test("a Cargo debug build is Rust")
    func cargoDebugBuild() {
        let context = DetectionFixture.context(
            argv: ["/proj/target/debug/api"],
            executablePath: "/proj/target/debug/api",
            projectFiles: ["Cargo.toml"],
            ports: [8000]
        )

        #expect(engine.detect(context).type == .rust)
    }

    @Test("a target/debug path without a Cargo.toml is not Rust")
    func targetDebugWithoutCargo() {
        // Requiring the manifest rather than assuming one is what keeps a stray
        // build tree from being claimed.
        let context = DetectionFixture.context(
            argv: ["/proj/target/debug/api"],
            executablePath: "/proj/target/debug/api",
            ports: [8000]
        )

        #expect(engine.detect(context).type != .rust)
    }

    @Test("a Cargo test harness under target/debug/deps is not the user's service")
    func cargoTestHarness() {
        let context = DetectionFixture.context(
            argv: ["/proj/target/debug/deps/api_tests-a81f2c"],
            executablePath: "/proj/target/debug/deps/api_tests-a81f2c",
            projectFiles: ["Cargo.toml"],
            ports: [3000]
        )

        #expect(engine.detect(context).type != .rust)
    }

    @Test("a jar under target/ is a Maven build, not a Cargo one")
    func mavenTargetIsNotRust() {
        let context = DetectionFixture.context(
            command: "java -jar /proj/target/api-1.0.0.jar",
            executablePath: "/opt/homebrew/opt/openjdk/bin/java",
            ports: [8000]
        )

        #expect(engine.detect(context).type != .rust)
    }

    @Test("a node server inside a Go module is still Node")
    func nodeInsideGoModule() {
        // A go.mod in the tree is not evidence about the process holding the port.
        let context = DetectionFixture.context(
            command: "node server.js",
            executablePath: "/opt/homebrew/bin/node",
            projectFiles: ["go.mod", "package.json"],
            ports: [8080]
        )
        let type = engine.detect(context).type

        #expect(type == .node)
        #expect(type != .go)
    }

    @Test("a bare binary with no build-path evidence is unknown")
    func bareBinaryStaysUnknown() {
        let context = DetectionFixture.context(
            argv: ["/opt/vendor/bin/appliance"],
            executablePath: "/opt/vendor/bin/appliance",
            ports: [8080]
        )

        #expect(engine.detect(context).type == .unknown)
    }
}
