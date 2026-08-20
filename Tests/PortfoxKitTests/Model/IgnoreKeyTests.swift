import Foundation
import Testing
@testable import PortfoxKit

@Suite("durable ignore keys")
struct IgnoreKeyTests {
    private func project(_ path: String) -> ProjectSnapshot {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return makeSnapshot(root: url, name: url.lastPathComponent)
    }

    @Test("a service with a project keys on its service directory, not its binary")
    func projectServiceKeysOnDirectory() {
        let service = makeService(
            port: 3000,
            project: project("/Users/me/work/shop"),
            executable: "/opt/homebrew/bin/node"
        )
        #expect(IgnoreKey(service)?.anchor == "/Users/me/work/shop")
    }

    @Test("a daemon with no project keys on its executable path")
    func daemonKeysOnExecutable() {
        let service = makeService(port: 5432, project: nil, executable: "/opt/homebrew/bin/postgres")
        #expect(IgnoreKey(service)?.anchor == "/opt/homebrew/bin/postgres")
    }

    /// `resolvedExecutablePath` falls back to argv[0] when the binary's vnode is
    /// gone, which happens routinely after a Homebrew upgrade.
    @Test("a projectless service with no executable path falls back to argv[0]")
    func fallsBackToArgumentZero() {
        let service = makeService(
            port: 6379,
            project: nil,
            arguments: ["/usr/local/bin/redis-server", "--port", "6379"]
        )
        #expect(IgnoreKey(service)?.anchor == "/usr/local/bin/redis-server")
    }

    @Test("a relative argv[0] falls back to the executable name")
    func fallsBackToExecutableName() {
        let service = makeService(port: 8080, project: nil, arguments: ["caddy", "run"])
        #expect(IgnoreKey(service)?.anchor == "caddy")
    }

    @Test("a service with no project, no path and no arguments has no durable key")
    func noDurableIdentityYieldsNil() {
        #expect(IgnoreKey(makeService(port: 1234, project: nil)) == nil)
    }

    /// The whole point of the type. `RunningService.id` embeds the pid and the
    /// start time, so it cannot survive the restart this test describes.
    @Test("the same service restarted under a new pid keeps its key")
    func survivesRestart() {
        let snapshot = project("/Users/me/work/shop")
        let before = makeService(port: 3000, project: snapshot, pid: 400, executable: "/opt/homebrew/bin/node")
        let after = makeService(port: 3000, project: snapshot, pid: 9114, executable: "/opt/homebrew/bin/node")

        #expect(before.id != after.id)
        #expect(IgnoreKey(before) == IgnoreKey(after))
    }

    @Test("two projects sharing a binary and a port get different keys")
    func projectsSharingBinaryStayDistinct() {
        let one = makeService(port: 3000, project: project("/Users/me/work/shop"), executable: "/opt/homebrew/bin/node")
        let two = makeService(port: 3000, project: project("/Users/me/work/blog"), executable: "/opt/homebrew/bin/node")
        #expect(IgnoreKey(one) != IgnoreKey(two))
    }

    @Test("the same anchor on a different port is a different key")
    func portParticipatesInTheKey() {
        let snapshot = project("/Users/me/work/shop")
        #expect(IgnoreKey(makeService(port: 3000, project: snapshot)) != IgnoreKey(makeService(port: 3001, project: snapshot)))
    }

    @Test("a redundant path separator does not make a second key")
    func pathsAreStandardised() {
        #expect(
            IgnoreKey(port: 3000, anchor: "/opt//homebrew/bin/node")
                == IgnoreKey(port: 3000, anchor: "/opt/homebrew/bin/node")
        )
    }

    @Test("an entry round-trips through JSON, because that is how it is stored")
    func entryRoundTrips() throws {
        let entry = IgnoredService(
            key: IgnoreKey(port: 5432, anchor: "/opt/homebrew/bin/postgres"),
            name: "PostgreSQL",
            detail: "Homebrew"
        )
        let decoded = try JSONDecoder().decode(
            [IgnoredService].self,
            from: try JSONEncoder().encode([entry])
        )
        #expect(decoded == [entry])
    }

    @Test("an entry built from a service carries its name and subtitle")
    func entryDescribesTheService() {
        let root = URL(fileURLWithPath: "/Users/me/work/shop", isDirectory: true)
        let snapshot = ProjectSnapshot(
            root: root,
            serviceDirectory: root.appendingPathComponent("apps/web"),
            name: "shop",
            subpath: "apps/web"
        )
        let service = makeService(port: 3000, project: snapshot)
        let entry = IgnoredService(service)

        #expect(entry?.port == 3000)
        #expect(entry?.name == service.displayName)
        #expect(entry?.detail == service.subtitle)
        #expect(entry?.detail == "apps/web")
    }

    /// A preferences row must never render blank, so the anchor stands in when
    /// the service had no subtitle to describe it with.
    @Test("an entry with no subtitle falls back to the anchor name")
    func entryFallsBackToAnchorName() {
        let service = makeService(port: 5432, project: nil, executable: "/opt/homebrew/bin/postgres")
        #expect(service.subtitle == nil)
        #expect(IgnoredService(service)?.detail == "postgres")
    }
}
