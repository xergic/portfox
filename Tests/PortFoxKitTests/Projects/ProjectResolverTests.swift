import Foundation
import Testing
@testable import PortFoxKit

@Suite("project root resolution")
struct ProjectResolverTests {
    @Test("a workspace root beats an inner package.json, and picks the highest one")
    func workspaceRootWinsOverInnerPackage() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{ "name": "monorepo" }"#, at: "pnpm-workspace.yaml")
        tree.write(#"{ "name": "monorepo" }"#, at: "package.json")
        let service = tree.makeDirectory("apps/api")
        tree.write(#"{ "name": "api" }"#, at: "apps/api/package.json")

        let snapshot = ProjectResolver().resolve(serviceDirectory: service)

        #expect(snapshot?.root.path == tree.root.path)
        #expect(snapshot?.rootKind == .workspace)
    }

    @Test("a workspace root wins even when a git root sits above it")
    func workspaceBeatsGit() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("", at: ".git/HEAD")
        let workspaceRoot = tree.makeDirectory("nested-monorepo")
        tree.write(#"{ "name": "nested" }"#, at: "nested-monorepo/turbo.json")
        let service = tree.makeDirectory("nested-monorepo/apps/web")

        let snapshot = ProjectResolver().resolve(serviceDirectory: service)

        #expect(snapshot?.root.path == workspaceRoot.path)
        #expect(snapshot?.rootKind == .workspace)
    }

    @Test("falls back to the git root when there is no workspace marker")
    func gitRootWhenNoWorkspace() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("", at: ".git/HEAD")
        tree.write(#"{ "name": "repo-root" }"#, at: "package.json")
        let service = tree.makeDirectory("src")

        let snapshot = ProjectResolver().resolve(serviceDirectory: service)

        #expect(snapshot?.root.path == tree.root.path)
        #expect(snapshot?.rootKind == .git)
    }

    @Test("falls back to the nearest manifest when there is no git root")
    func nearestManifestWhenNoGit() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{ "name": "outer" }"#, at: "package.json")
        let inner = tree.makeDirectory("inner")
        tree.write(#"{ "name": "inner-project" }"#, at: "inner/package.json")
        let service = tree.makeDirectory("inner/src")

        let snapshot = ProjectResolver().resolve(serviceDirectory: service)

        #expect(snapshot?.root.path == inner.path)
        #expect(snapshot?.rootKind == .manifest)
    }

    @Test("falls back to the service directory itself when nothing is found")
    func bareDirectoryFallback() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        let service = tree.makeDirectory("just-a-folder")

        let snapshot = ProjectResolver().resolve(serviceDirectory: service)

        #expect(snapshot?.root.path == service.path)
        #expect(snapshot?.rootKind == .directory)
    }

    @Test("subpath is the monorepo-relative path, nil when the service directory is the root")
    func subpathReflectsMonorepoLayout() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("", at: "pnpm-workspace.yaml")
        let service = tree.makeDirectory("apps/api")

        let nested = ProjectResolver().resolve(serviceDirectory: service)
        let atRoot = ProjectResolver().resolve(serviceDirectory: tree.root)

        #expect(nested?.subpath == "apps/api")
        #expect(atRoot?.subpath == nil)
    }

    @Test("strips an npm scope so @acme/api displays as api")
    func scopedNameStripsScope() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{ "name": "@acme/api" }"#, at: "package.json")

        let snapshot = ProjectResolver().resolve(serviceDirectory: tree.root)

        #expect(snapshot?.name == "api")
    }

    @Test("prefers the root manifest name when the nearest name is generic")
    func genericNamePrefersRootManifest() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{ "name": "wishfox" }"#, at: "package.json")
        tree.write("", at: ".git/HEAD")
        let service = tree.makeDirectory("apps/api")
        tree.write(#"{ "name": "api" }"#, at: "apps/api/package.json")

        let snapshot = ProjectResolver().resolve(serviceDirectory: service)

        #expect(snapshot?.name == "wishfox")
    }

    @Test("keeps a non-generic nearest name even when a root manifest name exists")
    func nonGenericNameIsKept() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(#"{ "name": "wishfox" }"#, at: "package.json")
        tree.write("", at: ".git/HEAD")
        let service = tree.makeDirectory("apps/scraper")
        tree.write(#"{ "name": "scraper" }"#, at: "apps/scraper/package.json")

        let snapshot = ProjectResolver().resolve(serviceDirectory: service)

        #expect(snapshot?.name == "scraper")
    }

    @Test("returns nil when the service directory does not exist")
    func missingDirectoryReturnsNil() {
        let tree = TempTree()
        defer { tree.cleanUp() }

        let snapshot = ProjectResolver().resolve(serviceDirectory: tree.root.appendingPathComponent("nope"))

        #expect(snapshot == nil)
    }

    @Test("the ancestor walk never yields a directory above the home directory")
    func ancestorWalkNeverExceedsHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath()
        let deepPath = home.appendingPathComponent("a/b/c/d/e/f/g/h")

        let chain = ProjectResolver(maximumDepth: 50).ancestorChain(from: deepPath, home: home)

        #expect(chain.last?.path == home.path)
        #expect(chain.allSatisfy { $0.path == home.path || $0.path.hasPrefix(home.path + "/") })
    }

    @Test("the ancestor walk stops at the filesystem root")
    func ancestorWalkStopsAtRoot() {
        let unrelatedRoot = URL(fileURLWithPath: "/private/tmp/portfox-does-not-exist-\(UUID().uuidString)")
        let deepPath = unrelatedRoot.appendingPathComponent("a/b/c/d/e/f/g/h")

        let chain = ProjectResolver(maximumDepth: 50).ancestorChain(from: deepPath, home: URL(fileURLWithPath: "/nonexistent-home"))

        #expect(chain.last?.path == "/")
    }
}
