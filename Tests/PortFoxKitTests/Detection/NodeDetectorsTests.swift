import Foundation
import Testing
@testable import PortFoxKit

@Suite("Node ecosystem detectors")
struct NodeDetectorsTests {
    private let engine = DetectionEngine(detectors: DetectorCatalog.nodeEcosystem)

    private func nodeContext(
        argv: String,
        exe: String? = nil,
        files: Set<String> = [],
        dependencies: Set<String> = [],
        ports: [Int] = [],
        relatedCommands: [String] = []
    ) -> DetectionContext {
        let arguments = argv.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let process = ProcessSnapshot(
            pid: 1,
            parentPID: 0,
            uid: 501,
            executablePath: exe,
            arguments: arguments,
            workingDirectory: "/tmp/project"
        )
        let project = ProjectSnapshot(
            root: URL(fileURLWithPath: "/tmp/project"),
            serviceDirectory: URL(fileURLWithPath: "/tmp/project"),
            name: "project",
            files: files,
            dependencies: dependencies
        )
        return DetectionContext(process: process, project: project, ports: ports, relatedCommands: relatedCommands)
    }

    private func detector(for type: ServiceType) -> any ServiceDetector {
        DetectorCatalog.nodeEcosystem.first { $0.type == type }!
    }

    // MARK: - The nine real argv strings from live-machine-scan.txt

    @Test("case 1: nuxt via pnpm, mangled .bin/../.pnpm path")
    func nuxtViaPnpmMangledPath() {
        let ctx = nodeContext(
            argv: "node /Users/ondra/Work/Wishfox/wishfox-admin/node_modules/.bin/../.pnpm/nuxt@4.5.2_@babel+plugin"
                + "-syntax-jsx@7.29.7_@babel+core@7.29.7__@babel+plugin-syntax-typ_cd5cf74929dfd41f907babafbfd60539/"
                + "node_modules/nuxt/bin/nuxt.mjs dev --dotenv .env.local",
            exe: "/usr/local/bin/node"
        )

        #expect(engine.detect(ctx).type == .nuxt)
    }

    @Test("case 2: nuxt with a simpler node_modules path")
    func nuxtSimplePath() {
        let ctx = nodeContext(
            argv: "node /Users/ondra/Work/Wishfox/wishfox-front/node_modules/.bin/../nuxt/bin/nuxt.mjs "
                + "dev --dotenv .env.local",
            exe: "/usr/local/bin/node"
        )

        #expect(engine.detect(ctx).type == .nuxt)
    }

    @Test("case 3: next-server rewrites argv, no bin path or \"next dev\" anywhere")
    func nextServerRewrittenTitle() {
        let ctx = nodeContext(
            argv: "next-server (v16.3.1)    ",
            exe: "/usr/local/bin/node",
            dependencies: ["next"]
        )

        #expect(engine.detect(ctx).type == .nextJS)
    }

    @Test("case 4: wrangler dev via pnpm")
    func wranglerDev() {
        let ctx = nodeContext(
            argv: "/usr/local/bin/node --no-warnings --experimental-vm-modules /Users/ondra/Work/Wishfox/"
                + "wishfox-scraper/node_modules/.pnpm/wrangler@3.83.0/node_modules/wrangler/bin/wrangler.js dev",
            exe: "/usr/local/bin/node"
        )

        #expect(engine.detect(ctx).type == .wrangler)
    }

    @Test("case 5: workerd, spawned by wrangler, identifies via its parent's command")
    func workerdViaParentCommand() {
        let ctx = nodeContext(
            argv: "/Users/ondra/Work/Wishfox/wishfox-scraper/node_modules/.pnpm/@cloudflare+workerd-darwin-arm64@"
                + "1.20241022.0/node_modules/@cloudflare/workerd-darwin-arm64/bin/workerd serve --binary "
                + "--experimental --socket-addr=entry=localhost:8793",
            exe: "/Users/ondra/Work/Wishfox/wishfox-scraper/node_modules/.pnpm/@cloudflare+workerd-darwin-arm64@"
                + "1.20241022.0/node_modules/@cloudflare/workerd-darwin-arm64/bin/workerd",
            relatedCommands: [
                "/usr/local/bin/node --no-warnings --experimental-vm-modules .../wrangler/bin/wrangler.js dev"
            ]
        )

        #expect(engine.detect(ctx).type == .wrangler)
    }

    @Test("case 6: bun dev server")
    func bunDevServer() {
        let ctx = nodeContext(argv: "bun run --hot index.ts", exe: "/Users/ondra/.bun/bin/bun")

        #expect(engine.detect(ctx).type == .bun)
    }

    @Test("case 7: tsx-based API lands on generic node, not a framework")
    func tsxBasedAPIIsGenericNode() {
        let ctx = nodeContext(
            argv: "/usr/local/bin/node --require /Users/ondra/Work/iDevBand/verisoft/omnitracker/node_modules/"
                + ".pnpm/tsx@4.23.1/node_modules/tsx/dist/preflight.cjs --import file:///.../tsx/dist/loader.mjs "
                + "src/index.ts",
            exe: "/usr/local/bin/node",
            ports: [3003]
        )

        #expect(engine.detect(ctx).type == .node)
    }

    @Test("case 8: plain script")
    func plainScript() {
        let ctx = nodeContext(argv: "node srv.mjs", exe: "/usr/local/bin/node", ports: [2525])

        #expect(engine.detect(ctx).type == .node)
    }

    @Test("case 9: bun-based daemon is not mistaken for a dev server")
    func bunDaemonIsNotADevServer() {
        let ctx = nodeContext(
            argv: "/Users/ondra/.bun/bin/bun /Users/ondra/.claude/plugins/cache/thedotmack/claude-mem/13.15.2/"
                + "scripts/worker-service.cjs --daemon",
            exe: "/Users/ondra/.bun/bin/bun"
        )

        #expect(engine.detect(ctx).type == .bun)
    }

    // MARK: - One positive test per remaining detector

    @Test("vite")
    func vite() {
        let ctx = nodeContext(
            argv: "node node_modules/.bin/vite",
            exe: "/usr/local/bin/node",
            files: ["vite.config.ts"],
            dependencies: ["vite"],
            ports: [5173]
        )

        #expect(engine.detect(ctx).type == .vite)
    }

    @Test("astro")
    func astro() {
        let ctx = nodeContext(
            argv: "node node_modules/.bin/astro dev",
            exe: "/usr/local/bin/node",
            files: ["astro.config.mjs"],
            dependencies: ["astro"],
            ports: [4321]
        )

        #expect(engine.detect(ctx).type == .astro)
    }

    @Test("svelteKit runs as vite dev inside a svelte.config project")
    func svelteKit() {
        let ctx = nodeContext(
            argv: "node node_modules/.bin/vite dev",
            exe: "/usr/local/bin/node",
            files: ["svelte.config.js"],
            dependencies: ["@sveltejs/kit"],
            ports: [5173]
        )

        #expect(engine.detect(ctx).type == .svelteKit)
    }

    @Test("remix / react-router")
    func remix() {
        let ctx = nodeContext(
            argv: "node node_modules/.bin/react-router dev",
            exe: "/usr/local/bin/node",
            files: ["react-router.config.ts"],
            dependencies: ["react-router"],
            ports: [3000]
        )

        #expect(engine.detect(ctx).type == .remix)
    }

    @Test("angular")
    func angular() {
        let ctx = nodeContext(
            argv: "node node_modules/.bin/ng serve",
            exe: "/usr/local/bin/node",
            files: ["angular.json"],
            dependencies: ["@angular/cli"],
            ports: [4200]
        )

        #expect(engine.detect(ctx).type == .angular)
    }

    @Test("nestJS")
    func nestJS() {
        let ctx = nodeContext(
            argv: "node node_modules/.bin/nest start --watch",
            exe: "/usr/local/bin/node",
            files: ["nest-cli.json"],
            dependencies: ["@nestjs/core"],
            ports: [3000]
        )

        #expect(engine.detect(ctx).type == .nestJS)
    }

    @Test("storybook")
    func storybook() {
        let ctx = nodeContext(
            argv: "node node_modules/.bin/storybook dev -p 6006",
            exe: "/usr/local/bin/node",
            files: [".storybook"],
            dependencies: ["storybook"],
            ports: [6006]
        )

        #expect(engine.detect(ctx).type == .storybook)
    }

    @Test("expo")
    func expo() {
        let ctx = nodeContext(
            argv: "node node_modules/.bin/expo start",
            exe: "/usr/local/bin/node",
            files: ["app.json"],
            dependencies: ["expo"],
            ports: [8081, 19000, 19006]
        )

        #expect(engine.detect(ctx).type == .expo)
    }

    @Test("metro")
    func metro() {
        let ctx = nodeContext(
            argv: "node node_modules/metro/bin/metro.js --port 8081",
            exe: "/usr/local/bin/node",
            files: ["metro.config.js"],
            dependencies: ["metro"],
            ports: [8081]
        )

        #expect(engine.detect(ctx).type == .metro)
    }

    @Test("deno")
    func deno() {
        let ctx = nodeContext(argv: "deno run --allow-net main.ts", exe: "/usr/local/bin/deno", ports: [8000])

        #expect(engine.detect(ctx).type == .deno)
    }

    // MARK: - Negative tests

    @Test("vitest is not reported as vite")
    func vitestIsNotVite() {
        let ctx = nodeContext(argv: "node node_modules/.bin/vitest run", exe: "/usr/local/bin/node")

        #expect(engine.detect(ctx).type != .vite)
    }

    @Test("a nuxt process's own detector table refuses to also report vite")
    func nuxtIsNeverAlsoVite() {
        let ctx = nodeContext(
            argv: "node node_modules/.bin/../nuxt/bin/nuxt.mjs dev",
            exe: "/usr/local/bin/node"
        )

        #expect(engine.detect(ctx).type == .nuxt)
        #expect(detector(for: .vite).detect(ctx) == nil)
    }

    @Test("next.js is not reported as generic node")
    func nextJSIsNotGenericNode() {
        let ctx = nodeContext(argv: "next-server (v16.3.1)", exe: "/usr/local/bin/node", dependencies: ["next"])

        #expect(engine.detect(ctx).type != .node)
    }

    @Test("plain node script with no framework deps is generic node")
    func plainNodeWithNoFrameworkDeps() {
        let ctx = nodeContext(argv: "node srv.mjs", exe: "/usr/local/bin/node")

        #expect(engine.detect(ctx).type == .node)
    }

    @Test("a bare port 3000 alone is not enough to claim next.js")
    func barePortAloneIsNotNextJS() {
        let ctx = nodeContext(argv: "unknown-process", ports: [3000])

        #expect(engine.detect(ctx).type != .nextJS)
    }

    @Test("metro defers to expo when an ancestor process is the expo cli")
    func metroDefersToExpoAncestor() {
        let ctx = nodeContext(
            argv: "node node_modules/metro/bin/metro.js --port 8081",
            exe: "/usr/local/bin/node",
            ports: [8081],
            relatedCommands: ["node node_modules/.bin/expo start"]
        )

        #expect(engine.detect(ctx).type != .metro)
    }

    // MARK: - Confidence

    @Test("a fully-evidenced next.js match has high confidence")
    func nextJSConfidenceIsHigh() {
        let ctx = nodeContext(
            argv: "node node_modules/.bin/next dev",
            exe: "/usr/local/bin/node",
            files: ["next.config.js"],
            dependencies: ["next"],
            ports: [3000]
        )

        let result = engine.detect(ctx)

        #expect(result.type == .nextJS)
        #expect(result.confidence > 0.8)
    }
}
