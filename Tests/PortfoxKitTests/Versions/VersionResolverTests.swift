import Foundation
import Testing
@testable import PortfoxKit

@Suite("version display normalisation")
struct VersionDisplayTests {
    @Test(
        "raw version strings normalise for display",
        arguments: [
            ("v24.16.0-nightly", "24.16"),
            ("24.16.0", "24.16"),
            ("17.0", "17"),
            ("4.5.2", "4.5.2"),
            ("1.0.1", "1.0.1"),
            ("postgres (PostgreSQL) 17.4", "17.4"),
            ("  v5.2  ", "5.2"),
            ("V3.0", "3"),
            ("42", "42"),
            ("Redis server v=7.4.0 sha=00000000:0", "7.4"),
            ("unknown", nil),
            ("", nil),
            ("latest", nil),
            ("   ", nil)
        ] as [(String, String?)]
    )
    func displayNormalisesRawVersions(raw: String, expected: String?) {
        #expect(VersionResolver.display(raw) == expected)
    }
}

@Suite("framework version")
struct FrameworkVersionTests {
    private let resolver = VersionResolver()

    @Test("the real Nuxt pnpm store path from the fixture resolves to 4.5.2")
    func nuxtFromFixturePath() async {
        let command = "node /Users/ondra/Work/Wishfox/wishfox-admin/node_modules/.bin/../.pnpm/nuxt@4.5.2_@babel+plugin"
            + "-syntax-jsx@7.29.7_@babel+core@7.29.7__@babel+plugin-syntax-typ_cd5cf74929dfd41f907babafbfd60539/"
            + "node_modules/nuxt/bin/nuxt.mjs dev --dotenv .env.local"

        let version = await resolver.frameworkVersion(type: .nuxt, project: nil, command: command)

        #expect(version == "4.5.2")
    }

    @Test("a scoped package's own version is picked out among several @version segments")
    func picksRightVersionAmongDecoys() async {
        let command = "node node_modules/.bin/../.pnpm/@sveltejs+kit@2.9.1_svelte@5.1.0_vite@6.0.3/"
            + "node_modules/@sveltejs/kit/bin/svelte-kit.js dev"

        let version = await resolver.frameworkVersion(type: .svelteKit, project: nil, command: command)

        #expect(version == "2.9.1")
    }

    @Test("a plain node_modules package.json is read when the command has no pnpm store path")
    func readsPackageJSONDirectly() async {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{"version": "5.4.1"}"#, at: "node_modules/vite/package.json")
        let project = ProjectSnapshot(root: tree.root, serviceDirectory: tree.root, name: "app")

        let version = await resolver.frameworkVersion(type: .vite, project: project, command: "node vite.js dev")

        #expect(version == "5.4.1")
    }

    @Test("the service directory's node_modules wins over the project root's")
    func serviceDirectoryBeatsRoot() async {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{"version": "3.1.2"}"#, at: "node_modules/nuxt/package.json")
        tree.write(#"{"version": "4.2.5"}"#, at: "apps/web/node_modules/nuxt/package.json")
        let project = ProjectSnapshot(
            root: tree.root,
            serviceDirectory: tree.root.appendingPathComponent("apps/web"),
            name: "web"
        )

        let version = await resolver.frameworkVersion(type: .nuxt, project: project, command: "node nuxt.js dev")

        #expect(version == "4.2.5")
    }

    @Test("a type with no npm package never reports a framework version")
    func noFrameworkVersionWithoutPackage() async {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{"version": "17.4"}"#, at: "node_modules/postgres/package.json")
        let project = ProjectSnapshot(root: tree.root, serviceDirectory: tree.root, name: "db")

        let version = await resolver.frameworkVersion(type: .postgres, project: project, command: "postgres -D data")

        #expect(version == nil)
    }
}

@Suite("runtime version path extraction")
struct RuntimeVersionPathTests {
    @Test("an nvm node install path yields its version")
    func nvmNodePath() async {
        let resolver = VersionResolver()
        let version = await resolver.runtimeVersion(
            type: .node,
            executablePath: "/Users/ondra/.nvm/versions/node/v24.16.0/bin/node"
        )

        #expect(version == "24.16.0")
    }

    @Test("an fnm node install path yields its version")
    func fnmNodePath() async {
        let resolver = VersionResolver()
        let version = await resolver.runtimeVersion(
            type: .node,
            executablePath: "/Users/ondra/.local/share/fnm/node-versions/v22.11.0/installation/bin/node"
        )

        #expect(version == "22.11.0")
    }

    @Test("a Homebrew formula@version cellar path yields the major version")
    func homebrewPostgresPath() async {
        let resolver = VersionResolver()
        let version = await resolver.runtimeVersion(
            type: .postgres,
            executablePath: "/opt/homebrew/opt/postgresql@17/bin/postgres"
        )

        #expect(version == "17")
    }

    @Test("a DBngin postgres version directory yields its full version")
    func dbnginPostgresPath() async {
        let resolver = VersionResolver()
        let version = await resolver.runtimeVersion(
            type: .postgres,
            executablePath: "/Users/Shared/DBngin/postgresql/17.0/bin/postgres"
        )

        #expect(version == "17.0")
    }

    @Test("a DBngin redis version directory yields its full version")
    func dbnginRedisPath() async {
        let resolver = VersionResolver()
        let version = await resolver.runtimeVersion(
            type: .redis,
            executablePath: "/Users/Shared/DBngin/redis/7.0.0/bin/redis-server"
        )

        #expect(version == "7.0.0")
    }

    @Test("a Homebrew Cellar redis version directory yields its full version")
    func cellarRedisPath() async {
        let resolver = VersionResolver()
        let version = await resolver.runtimeVersion(
            type: .redis,
            executablePath: "/opt/homebrew/Cellar/redis/7.4.2/bin/redis-server"
        )

        #expect(version == "7.4.2")
    }
}

@Suite("runtime version spawn safety")
struct RuntimeVersionSpawnSafetyTests {
    @Test("an executable outside the allowlist is never spawned")
    func refusesNonAllowlistedExecutable() async {
        let resolver = VersionResolver()
        let version = await resolver.runtimeVersion(type: .node, executablePath: "/usr/local/bin/malicious-tool")

        #expect(version == nil)
    }

    @Test("a type with no runtime to ask is never spawned, even with an allowlisted name")
    func refusesTypeOutsideSpawnList() async {
        let resolver = VersionResolver()
        let version = await resolver.runtimeVersion(type: .unknown, executablePath: "/usr/local/bin/node")

        #expect(version == nil)
    }
}

@Suite("manifest version parsing")
struct ManifestVersionTests {
    @Test("package.json's top-level version is read")
    func packageJSONVersion() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{"name": "app", "version": "2.3.4"}"#, at: "package.json")

        #expect(ManifestReader.packageJSON(in: tree.root)?.version == "2.3.4")
    }

    @Test("pyproject.toml's version under [project] is read")
    func pyprojectProjectVersion() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("[project]\nname = \"app\"\nversion = \"1.2.3\"\n", at: "pyproject.toml")

        #expect(ManifestReader.pyproject(in: tree.root)?.version == "1.2.3")
    }

    @Test("pyproject.toml's version under [tool.poetry] is read")
    func pyprojectPoetryVersion() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("[tool.poetry]\nname = \"app\"\nversion = \"0.9.0\"\n", at: "pyproject.toml")

        #expect(ManifestReader.pyproject(in: tree.root)?.version == "0.9.0")
    }

    @Test("Expo config's version inside the expo block is read")
    func expoConfigVersion() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{"expo": {"name": "app", "version": "1.0.0"}}"#, at: "app.json")

        #expect(ManifestReader.expoConfig(in: tree.root)?.version == "1.0.0")
    }

    /// `versionByProcess` is keyed on the listener's identity, and every container
    /// row behind one forwarder shares it. Without the image branch running ahead
    /// of the cache, the first row to resolve poisons the rest of the stack.
    @Test("two containers sharing a forwarder each report their own version")
    func containersDoNotShareACachedVersion() async {
        let resolver = VersionResolver()
        func row(_ image: String, port: Int) -> RunningService {
            makeService(
                port: port,
                project: nil,
                pid: 900,
                executable: "/Applications/Docker.app/Contents/MacOS/com.docker.backend",
                id: "container-\(image)-\(port)",
                container: ContainerSnapshot(id: image, name: image, image: image)
            )
        }

        let postgres = await resolver.version(for: row("postgres:16", port: 5432))
        let redis = await resolver.version(for: row("redis:7-alpine", port: 6379))

        #expect(postgres == "16")
        #expect(redis == "7")
    }
}
