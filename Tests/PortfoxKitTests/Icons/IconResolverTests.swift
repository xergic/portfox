import Foundation
import Testing
@testable import PortfoxKit

@Suite("icon resolution")
struct IconResolverTests {
    private let resolver = IconResolver()

    @Test("with no project, a known type resolves to its bundled framework icon")
    func noProjectResolvesToFramework() {
        #expect(resolver.resolve(project: nil, type: .nextJS) == .framework(.nextJS))
    }

    @Test("with no project, an unknown type resolves to its fallback symbol")
    func noProjectResolvesToSymbolForUnknownType() {
        #expect(resolver.resolve(project: nil, type: .unknown) == .symbol(ServiceType.unknown.fallbackSymbol))
    }

    @Test(
        "projectIconPath finds an icon at each of the documented locations",
        arguments: ["public/favicon.ico", "app/icon.png", "static/favicon.svg", "favicon.png"]
    )
    func projectIconPathFindsKnownLocations(relative: String) {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("icon-bytes", at: relative)

        let project = makeSnapshot(root: tree.root, name: "demo")

        #expect(resolver.projectIconPath(for: project) == tree.root.appendingPathComponent(relative).path)
    }

    @Test("the earlier entry in the declared search order wins when two icons exist")
    func searchOrderIsHonoured() {
        let tree = TempTree()
        defer { tree.cleanUp() }

        let candidateA = "app/icon.png"
        let candidateB = "public/favicon.ico"
        let paths = IconResolver.searchPaths
        guard let indexA = paths.firstIndex(of: candidateA), let indexB = paths.firstIndex(of: candidateB) else {
            Issue.record("expected search paths to contain both candidates")
            return
        }
        let winner = indexA < indexB ? candidateA : candidateB

        tree.write("icon-bytes", at: candidateA)
        tree.write("icon-bytes", at: candidateB)

        let project = makeSnapshot(root: tree.root, name: "demo")

        #expect(resolver.projectIconPath(for: project) == tree.root.appendingPathComponent(winner).path)
    }

    @Test("in a monorepo, the service directory is searched before the project root")
    func monorepoSearchesServiceDirectoryFirst() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        let serviceDirectory = tree.makeDirectory("apps/web")
        tree.write("root-icon", at: "public/favicon.ico")
        tree.write("service-icon", at: "apps/web/app/icon.png")

        let project = ProjectSnapshot(root: tree.root, serviceDirectory: serviceDirectory, name: "web")

        #expect(resolver.projectIconPath(for: project) == serviceDirectory.appendingPathComponent("app/icon.png").path)
    }

    @Test("a framework's own generic icon is skipped rather than claimed as the project icon")
    func genericFrameworkIconIsSkipped() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("vite-logo", at: "public/vite.svg")
        #expect(IconResolver.genericIconNames.contains("vite.svg"))

        let project = makeSnapshot(root: tree.root, name: "demo")

        #expect(resolver.projectIconPath(for: project) == nil)
        #expect(resolver.resolve(project: project, type: .vite) == .framework(.vite))
    }

    @Test("an Expo app.json icon resolves when the declared file exists")
    func expoIconResolvesWhenDeclaredFileExists() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{ "expo": { "name": "demo", "icon": "./assets/icon.png" } }"#, at: "app.json")
        tree.write("icon-bytes", at: "assets/icon.png")

        let project = makeSnapshot(root: tree.root, name: "demo")

        #expect(resolver.projectIconPath(for: project) == tree.root.appendingPathComponent("assets/icon.png").path)
    }

    @Test("an Expo app.json icon is ignored when the declared file is missing")
    func expoIconIgnoredWhenDeclaredFileMissing() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{ "expo": { "name": "demo", "icon": "./assets/icon.png" } }"#, at: "app.json")
        tree.write("icon-bytes", at: "public/favicon.ico")

        let project = makeSnapshot(root: tree.root, name: "demo")

        #expect(resolver.projectIconPath(for: project) == tree.root.appendingPathComponent("public/favicon.ico").path)
    }

    @Test("a declared Expo icon beats a favicon sitting in the same project")
    func expoIconBeatsFavicon() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{ "expo": { "name": "demo", "icon": "./assets/icon.png" } }"#, at: "app.json")
        tree.write("icon-bytes", at: "assets/icon.png")
        tree.write("icon-bytes", at: "public/favicon.ico")

        let project = makeSnapshot(root: tree.root, name: "demo")

        #expect(resolver.projectIconPath(for: project) == tree.root.appendingPathComponent("assets/icon.png").path)
    }

    @Test("resolve prefers an already-populated project icon path over searching again")
    func resolvePrefersPopulatedIconPath() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("icon-bytes", at: "public/favicon.ico")

        let explicitPath = tree.root.appendingPathComponent("cached-icon.png").path
        let project = makeSnapshot(root: tree.root, name: "demo", iconPath: explicitPath)

        #expect(resolver.resolve(project: project, type: .vite) == .projectFile(path: explicitPath))
    }
}
