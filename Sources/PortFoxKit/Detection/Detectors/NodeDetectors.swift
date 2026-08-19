import Foundation

public extension DetectorCatalog {
    /// Node, Bun and Deno frameworks, plus the runtimes themselves as fallbacks.
    static let nodeEcosystem: [any ServiceDetector] = [
        RuleBasedDetector(
            type: .vite,
            threshold: standardThreshold,
            signals: [
                .binPath("vite", 100),
                .commandContains("vite", 85),
                .configFile("vite.config", 70),
                .dependency("vite", 60),
                .defaultPorts([5173, 4173]),
                .vetoCommandContains("vitest"),
                .veto("command mentions nuxt, which owns its own vite dev server") { $0.command.contains("nuxt") },
                .veto("project has svelte.config, so vite dev belongs to SvelteKit") {
                    $0.project?.hasFile(prefix: "svelte.config") ?? false
                },
                .veto("project is a Remix or React Router framework app, which runs vite dev itself") {
                    $0.project?.isRemixFramework ?? false
                }
            ]
        ),
        RuleBasedDetector(
            type: .nextJS,
            threshold: standardThreshold,
            signals: [
                .binPath("next", 100),
                .commandContains("next-server", 90),
                .configFile("next.config", 70),
                .dependency("next", 60),
                .defaultPort(3000)
            ]
        ),
        RuleBasedDetector(
            type: .nuxt,
            threshold: standardThreshold,
            signals: [
                .binPath("nuxt", 100),
                .commandContains("nuxt", 85),
                .configFile("nuxt.config", 70),
                .dependency("nuxt", 60),
                .defaultPort(3000)
            ]
        ),
        RuleBasedDetector(
            type: .astro,
            threshold: standardThreshold,
            signals: [
                .binPath("astro", 100),
                .commandContains("astro dev", 88),
                .configFile("astro.config", 70),
                .dependency("astro", 60),
                .defaultPort(4321)
            ]
        ),
        RuleBasedDetector(
            type: .svelteKit,
            threshold: standardThreshold,
            signals: [
                .binPath("svelte-kit", 90),
                .custom("vite dev running in a project with svelte.config", 90, group: "command") { ctx in
                    ctx.command.contains("vite") && (ctx.project?.hasFile(prefix: "svelte.config") ?? false)
                },
                .configFile("svelte.config", 70),
                .dependency("@sveltejs/kit", 60),
                .defaultPort(5173)
            ]
        ),
        RuleBasedDetector(
            type: .remix,
            threshold: standardThreshold,
            signals: [
                .binPath("react-router", 100),
                .binPath("remix", 100),
                .commandContains("react-router dev", 88),
                // The documented dev command is `remix vite:dev`, which is why
                // Vite must lose this one rather than merely score lower.
                .custom("vite dev running in a Remix or React Router framework app", 95, group: "command") { ctx in
                    ctx.command.containsToken("vite") && (ctx.project?.isRemixFramework ?? false)
                },
                .configFile("react-router.config", 70, group: "config"),
                .configFile("remix.config", 70, group: "config"),
                .anyDependency(["@remix-run/dev", "@react-router/dev", "react-router"], 60),
                .defaultPorts([5173, 3000])
            ]
        ),
        RuleBasedDetector(
            type: .angular,
            threshold: standardThreshold,
            signals: [
                .binPath("ng", 100),
                .commandContains("ng serve", 88),
                .vetoCommandContains("storybook"),
                .configFile("angular.json", 70),
                .dependency("@angular/cli", 60),
                .defaultPort(4200)
            ]
        ),
        RuleBasedDetector(
            type: .nestJS,
            threshold: standardThreshold,
            signals: [
                .binPath("nest", 100),
                .commandContains("nest start", 88),
                .custom("a compiled entry point in a NestJS project", 60, group: "command") { ctx in
                    guard let project = ctx.project else { return false }
                    let isCompiledEntry = ["dist/main", "build/main"].contains { ctx.command.contains($0) }
                    return isCompiledEntry && (project.hasFile(prefix: "nest-cli.json") || project.hasDependency("@nestjs/core"))
                },
                .configFile("nest-cli.json", 70),
                .dependency("@nestjs/core", 60),
                .defaultPort(3000)
            ]
        ),
        RuleBasedDetector(
            type: .storybook,
            threshold: standardThreshold,
            signals: [
                .binPath("storybook", 100),
                .commandContains("storybook", 85),
                .configFile(".storybook", 70),
                .dependency("storybook", 60),
                .defaultPort(6006)
            ]
        ),
        RuleBasedDetector(
            type: .expo,
            threshold: standardThreshold,
            signals: [
                .binPath("expo", 100),
                .commandContains("expo start", 88),
                .treeCommandContains("expo start", 86),
                .configFile("app.json", 70, group: "config"),
                .configFile("app.config", 70, group: "config"),
                .dependency("expo", 60),
                .defaultPorts([8081, 19000])
            ]
        ),
        RuleBasedDetector(
            type: .metro,
            threshold: standardThreshold,
            signals: [
                .binPath("metro", 100),
                .commandContains("react-native start", 88),
                .configFile("metro.config", 70),
                .dependency("metro", 60),
                .defaultPort(8081),
                .veto("process tree indicates Expo, which owns the metro bundler it spawns") { $0.anyCommandContains("expo") }
            ]
        ),
        RuleBasedDetector(
            type: .wrangler,
            threshold: standardThreshold,
            signals: [
                .binPath("wrangler", 100),
                .binPath("workerd", 100),
                .treeCommandContains("wrangler", 90),
                .commandContains("wrangler dev", 88),
                .configFile("wrangler.toml", 70, group: "config"),
                .configFile("wrangler.json", 70, group: "config"),
                .dependency("wrangler", 60),
                .defaultPort(8787)
            ]
        ),
        RuleBasedDetector(
            type: .node,
            threshold: 20,
            signals: [
                .executableNamed("node", 30),
                .defaultPorts([3000, 4000, 8000, 8080]),
                .veto("executable is node but argv is a package manager wrapper script") { ctx in
                    ["npm-cli.js", "pnpm.cjs", "pnpm-cli.js", "yarn.js", "npx-cli.js", "corepack"]
                        .contains { ctx.command.contains($0) }
                }
            ]
        ),
        RuleBasedDetector(
            type: .bun,
            threshold: 20,
            signals: [
                .executableNamed("bun", 30),
                .defaultPort(3000)
            ]
        ),
        RuleBasedDetector(
            type: .deno,
            threshold: 20,
            signals: [
                .executableNamed("deno", 30),
                .defaultPort(8000)
            ]
        )
    ]
}
