import Foundation
import Testing
@testable import PortfoxKit

/// Cases found by an adversarial review of the detector catalogue. Each one is a
/// label a real user would have seen and reported as wrong.
@Suite("detection regressions")
struct DetectionRegressionTests {
    private let engine = DetectionEngine()

    private func type(_ context: DetectionContext) -> ServiceType {
        engine.detect(context).type
    }

    // MARK: - Substring matching

    @Test("ngrok is not Angular")
    func ngrokIsNotAngular() {
        // `/bin/ng` is a substring of `/bin/ngrok`. This scored Angular 100 with
        // no Angular evidence at all, the worst false positive in the catalogue.
        let context = DetectionFixture.context(
            command: "/opt/homebrew/bin/ngrok http 3000",
            executablePath: "/opt/homebrew/bin/ngrok",
            ports: [4040]
        )

        #expect(type(context) != .angular)
    }

    @Test("nginx is not Angular")
    func nginxIsNotAngular() {
        let context = DetectionFixture.context(
            command: "/opt/homebrew/bin/nginx -g daemon off;",
            executablePath: "/opt/homebrew/bin/nginx",
            ports: [8080]
        )

        #expect(type(context) != .angular)
    }

    @Test("VitePress is not Vite")
    func vitePressIsNotVite() {
        let context = DetectionFixture.context(
            command: "node /repo/node_modules/.bin/vitepress dev docs",
            executablePath: "/usr/local/bin/node",
            ports: [5173]
        )

        #expect(type(context) != .vite)
    }

    @Test("a project directory named after a framework does not identify the service")
    func projectDirectoryNameIsNotEvidence() {
        // Someone whose code lives in ~/Code/vitesse has "vite" in every argv.
        let context = DetectionFixture.context(
            command: "node /Users/me/Code/vitesse/server.js",
            executablePath: "/usr/local/bin/node",
            ports: [5173]
        )

        #expect(type(context) == .node)
    }

    @Test("a python file inside a fastapi-named directory is not FastAPI")
    func pythonDirectoryNameIsNotEvidence() {
        let context = DetectionFixture.context(
            command: "python /Users/me/Code/fastapi-notes/server.py",
            executablePath: "/usr/bin/python3",
            ports: [8000]
        )

        #expect(type(context) != .fastAPI)
    }

    @Test("a node process in an elasticsearch-named directory is not Elasticsearch")
    func elasticsearchDirectoryNameIsNotEvidence() {
        let context = DetectionFixture.context(
            command: "node /Users/me/Code/elasticsearch-notes/server.js",
            executablePath: "/usr/local/bin/node",
            ports: [9200]
        )

        #expect(type(context) != .elasticsearch)
    }

    // MARK: - Frameworks that run another framework's dev server

    @Test("React Router running its own vite dev server is not reported as Vite")
    func remixViteDevIsRemix() {
        // The documented dev command is literally `remix vite:dev`, and it binds
        // Vite's port in a project that also has vite.config.
        let context = DetectionFixture.context(
            command: "node /repo/node_modules/.bin/remix vite:dev",
            executablePath: "/usr/local/bin/node",
            projectFiles: ["vite.config.ts", "package.json"],
            dependencies: ["@remix-run/dev", "vite"],
            ports: [5173]
        )

        #expect(type(context) == .remix)
    }

    @Test("a plain Vite app that uses react-router for routing is still Vite")
    func plainViteWithRouterIsVite() {
        let context = DetectionFixture.context(
            command: "node /repo/node_modules/.bin/vite",
            executablePath: "/usr/local/bin/node",
            projectFiles: ["vite.config.ts", "package.json"],
            dependencies: ["vite", "react-router-dom"],
            ports: [5173]
        )

        #expect(type(context) == .vite)
    }

    @Test("Storybook launched through the Angular CLI is Storybook")
    func angularStorybookIsStorybook() {
        let context = DetectionFixture.context(
            command: "node /repo/node_modules/.bin/ng run app:storybook",
            executablePath: "/usr/local/bin/node",
            projectFiles: ["angular.json", ".storybook", "package.json"],
            dependencies: ["@angular/cli", "storybook"],
            ports: [6006]
        )

        #expect(type(context) == .storybook)
    }

    @Test("an ordinary Angular dev server is still Angular")
    func angularServeIsAngular() {
        let context = DetectionFixture.context(
            command: "node /repo/node_modules/.bin/ng serve",
            executablePath: "/usr/local/bin/node",
            projectFiles: ["angular.json", "package.json"],
            dependencies: ["@angular/cli"],
            ports: [4200]
        )

        #expect(type(context) == .angular)
    }

    @Test("a compiled NestJS server is not reported as generic Node")
    func compiledNestIsNest() {
        // Production-style `node dist/main.js` carries no trace of the Nest CLI.
        let context = DetectionFixture.context(
            command: "node dist/main.js",
            executablePath: "/usr/local/bin/node",
            projectFiles: ["nest-cli.json", "package.json"],
            dependencies: ["@nestjs/core"],
            ports: [3000]
        )

        #expect(type(context) == .nestJS)
    }

    @Test("a compiled entry point without NestJS evidence stays generic Node")
    func compiledEntryWithoutNestIsNode() {
        let context = DetectionFixture.context(
            command: "node dist/main.js",
            executablePath: "/usr/local/bin/node",
            projectFiles: ["package.json"],
            dependencies: ["express"],
            ports: [3000]
        )

        #expect(type(context) == .node)
    }

    @Test("Django served by uvicorn is Django, not Uvicorn")
    func djangoBehindUvicornIsDjango() {
        // This is Django's own documented ASGI deployment command.
        let context = DetectionFixture.context(
            command: "python -m uvicorn myproject.asgi:application",
            executablePath: "/repo/.venv/bin/python",
            projectFiles: ["manage.py", "pyproject.toml"],
            dependencies: ["django", "uvicorn"],
            ports: [8000]
        )

        #expect(type(context) == .django)
    }

    @Test("uvicorn with no framework evidence is still Uvicorn")
    func bareUvicornIsUvicorn() {
        let context = DetectionFixture.context(
            command: "uvicorn main:app --reload",
            executablePath: "/repo/.venv/bin/uvicorn",
            ports: [8000]
        )

        #expect(type(context) == .uvicorn)
    }

    @Test("the metro bundler Expo spawns is reported as Expo, not as Node")
    func expoMetroChildIsExpo() {
        // Metro vetoes itself when Expo is in the tree. Without a tree-aware Expo
        // signal that veto downgraded a real Expo server to generic Node.
        let context = DetectionFixture.context(
            command: "node /repo/node_modules/metro/bin/metro.js --port 8081",
            executablePath: "/usr/local/bin/node",
            projectFiles: ["app.json", "metro.config.js", "package.json"],
            dependencies: ["expo", "metro"],
            ports: [8081],
            relatedCommands: ["node /repo/node_modules/.bin/expo start"]
        )

        #expect(type(context) == .expo)
    }

    // MARK: - Infrastructure identity

    @Test("a RabbitMQ node is recognised through its Erlang VM executable")
    func rabbitmqRunsAsBeam() {
        let context = DetectionFixture.context(
            command: "/opt/homebrew/Cellar/rabbitmq/4.0.5/libexec/erts/bin/beam.smp -W w -MBas ageffcbf",
            executablePath: "/opt/homebrew/Cellar/rabbitmq/4.0.5/libexec/erts/bin/beam.smp",
            ports: [5672, 15672]
        )

        #expect(type(context) == .rabbitmq)
    }

    @Test("an Erlang VM on an unrelated port is not RabbitMQ")
    func plainBeamIsNotRabbitmq() {
        let context = DetectionFixture.context(
            command: "/usr/local/lib/erlang/erts/bin/beam.smp -W w",
            executablePath: "/usr/local/lib/erlang/erts/bin/beam.smp",
            ports: [4369]
        )

        #expect(type(context) != .rabbitmq)
    }

    @Test("a process on 5432 that is not postgres is not PostgreSQL")
    func portAloneIsNotPostgres() {
        let context = DetectionFixture.context(
            command: "node proxy.js --target 5432",
            executablePath: "/usr/local/bin/node",
            ports: [5432]
        )

        #expect(type(context) != .postgres)
    }
}

@Suite("primary port preference")
struct PrimaryPortPreferenceTests {
    private func socket(_ port: Int) -> ListeningSocket {
        ListeningSocket(pid: 1, port: port, host: "127.0.0.1", family: .ipv4)
    }

    @Test("Mailpit shows its web UI rather than its SMTP port")
    func mailpitPrefersWebUI() {
        // Both are default ports, so numeric ordering used to pick SMTP on 1025.
        let chosen = ServiceRepository.primarySocket(from: [socket(1025), socket(8025)], type: .mailpit)

        #expect(chosen.port == 8025)
    }

    @Test("MinIO shows its console rather than its API")
    func minioPrefersConsole() {
        let chosen = ServiceRepository.primarySocket(from: [socket(9000), socket(9001)], type: .minio)

        #expect(chosen.port == 9001)
    }

    @Test("RabbitMQ shows its management UI rather than AMQP")
    func rabbitmqPrefersManagementUI() {
        let chosen = ServiceRepository.primarySocket(from: [socket(5672), socket(15672)], type: .rabbitmq)

        #expect(chosen.port == 15672)
    }
}

@Suite("word boundary matching")
struct TokenMatchingTests {
    @Test(
        "a needle only matches on a word boundary",
        arguments: [
            ("/opt/homebrew/bin/ngrok", "/bin/ng", false),
            ("/opt/homebrew/bin/nginx", "/bin/ng", false),
            ("/opt/homebrew/bin/ng serve", "/bin/ng", true),
            ("/repo/node_modules/.bin/vitest run", "node_modules/.bin/vite", false),
            ("/repo/node_modules/.bin/vitepress dev", "node_modules/.bin/vite", false),
            ("/repo/node_modules/.bin/vite", "node_modules/.bin/vite", true),
            ("/users/me/code/vitesse/server.js", "vite", false),
            ("/users/me/code/mynuxt/server.js", "nuxt", false),
            ("node /repo/nuxt/bin/nuxt.mjs dev", "nuxt", true),
            ("uvicorn-experiments/app.py", "uvicorn", false),
            ("python -m uvicorn app:main", "uvicorn", true)
        ]
    )
    func matchesOnBoundary(haystack: String, needle: String, expected: Bool) {
        #expect(haystack.containsToken(needle) == expected)
    }

    @Test("a needle ending in a separator needs no trailing boundary")
    func separatorNeedleNeedsNoTrailingBoundary() {
        #expect("node /repo/nuxt/bin/nuxt.mjs".containsToken("/nuxt/bin/"))
    }

    @Test("an empty needle never matches")
    func emptyNeedleNeverMatches() {
        #expect(!"anything".containsToken(""))
    }
}
