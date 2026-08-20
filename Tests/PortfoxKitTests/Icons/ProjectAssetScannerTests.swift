import Foundation
import Testing
@testable import PortfoxKit

@Suite("project asset scanning")
struct ProjectAssetScannerTests {
    private let scanner = ProjectAssetScanner()

    @Test("finds images across several search directories and ignores non-image files")
    func findsImagesAcrossDirectoriesAndIgnoresOthers() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("bytes", at: "favicon.ico")
        tree.write("bytes", at: "public/logo.png")
        tree.write("bytes", at: "assets/mark.svg")
        tree.write("not an image", at: "README.md")
        tree.write("bytes", at: "public/notes.txt")

        let assets = scanner.assets(in: makeSnapshot(root: tree.root, name: "demo"))

        #expect(Set(assets.map(\.relativePath)) == ["favicon.ico", "public/logo.png", "assets/mark.svg"])
    }

    @Test("a node_modules directory inside the project is never scanned")
    func neverScansNodeModules() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("bytes", at: "public/logo.png")
        tree.write("bytes", at: "node_modules/some-package/icon.png")

        let assets = scanner.assets(in: makeSnapshot(root: tree.root, name: "demo"))

        #expect(assets.map(\.relativePath) == ["public/logo.png"])
    }

    @Test("a project root that is itself named like an excluded directory is not scanned")
    func rootNamedLikeExcludedDirectoryIsSkipped() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        let root = tree.makeDirectory("node_modules")
        tree.write("bytes", at: "node_modules/logo.png")

        let assets = scanner.assets(in: makeSnapshot(root: root, name: "demo"))

        #expect(assets.isEmpty)
    }

    @Test("a real favicon outranks an arbitrary screenshot")
    func faviconOutranksScreenshot() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("bytes", at: "public/screenshot.png")
        tree.write("bytes", at: "public/favicon.ico")

        let assets = scanner.assets(in: makeSnapshot(root: tree.root, name: "demo"))

        #expect(assets.first?.relativePath == "public/favicon.ico")
    }

    @Test("a logo outranks an arbitrary banner")
    func logoOutranksBanner() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("bytes", at: "assets/banner.png")
        tree.write("bytes", at: "assets/logo.svg")

        let assets = scanner.assets(in: makeSnapshot(root: tree.root, name: "demo"))

        #expect(assets.first?.relativePath == "assets/logo.svg")
    }

    @Test("a framework scaffold logo is present but ranked below a real icon")
    func genericScaffoldLogoRanksLast() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("bytes", at: "public/vite.svg")
        tree.write("bytes", at: "public/icon.png")

        let assets = scanner.assets(in: makeSnapshot(root: tree.root, name: "demo"))

        #expect(assets.map(\.relativePath) == ["public/icon.png", "public/vite.svg"])
    }

    @Test("within a tier, svg outranks png")
    func svgOutranksPngWithinATier() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("bytes", at: "assets/banner.png")
        tree.write("bytes", at: "assets/other.svg")

        let assets = scanner.assets(in: makeSnapshot(root: tree.root, name: "demo"))

        #expect(assets.map(\.relativePath) == ["assets/other.svg", "assets/banner.png"])
    }

    @Test("in a monorepo, both the service directory and root are searched, service directory first, without duplicates")
    func monorepoSearchesBothDirectoriesWithoutDuplicates() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        let serviceDirectory = tree.makeDirectory("apps/web")
        tree.write("bytes", at: "public/root-logo.png")
        tree.write("bytes", at: "apps/web/public/service-logo.png")

        let project = ProjectSnapshot(root: tree.root, serviceDirectory: serviceDirectory, name: "web")
        let assets = scanner.assets(in: project)

        #expect(assets.map(\.relativePath) == ["apps/web/public/service-logo.png", "public/root-logo.png"])
    }

    @Test("a file over 4 MB is excluded")
    func oversizedFileIsExcluded() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write(String(repeating: "a", count: 5 * 1024 * 1024), at: "public/huge.png")
        tree.write("bytes", at: "public/small.png")

        let assets = scanner.assets(in: makeSnapshot(root: tree.root, name: "demo"))

        #expect(assets.map(\.relativePath) == ["public/small.png"])
    }

    @Test("a zero-byte file is excluded")
    func zeroByteFileIsExcluded() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("", at: "public/empty.png")
        tree.write("bytes", at: "public/small.png")

        let assets = scanner.assets(in: makeSnapshot(root: tree.root, name: "demo"))

        #expect(assets.map(\.relativePath) == ["public/small.png"])
    }

    @Test("relativePath is correct for a root file, a subdirectory file and a monorepo service directory file")
    func relativePathIsCorrectInEachLocation() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        let serviceDirectory = tree.makeDirectory("apps/web")
        tree.write("bytes", at: "favicon.ico")
        tree.write("bytes", at: "public/logo.png")
        tree.write("bytes", at: "apps/web/icon.png")

        let project = ProjectSnapshot(root: tree.root, serviceDirectory: serviceDirectory, name: "web")
        let assets = scanner.assets(in: project)

        #expect(Set(assets.map(\.relativePath)) == ["favicon.ico", "public/logo.png", "apps/web/icon.png"])
    }

    @Test("maximumResults is respected")
    func maximumResultsIsRespected() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        for index in 0..<(ProjectAssetScanner.maximumResults + 20) {
            tree.write("bytes", at: "assets/image-\(index).png")
        }

        let assets = scanner.assets(in: makeSnapshot(root: tree.root, name: "demo"))

        #expect(assets.count == ProjectAssetScanner.maximumResults)
    }

    @Test("a project directory that does not exist returns an empty array rather than crashing")
    func missingProjectDirectoryReturnsEmpty() {
        let missing = URL(fileURLWithPath: "/tmp/portfox-does-not-exist-\(UUID().uuidString)")

        let assets = scanner.assets(in: makeSnapshot(root: missing, name: "demo"))

        #expect(assets.isEmpty)
    }

    @Test("ordering is deterministic across repeated calls")
    func orderingIsDeterministic() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        tree.write("bytes", at: "favicon.ico")
        tree.write("bytes", at: "public/favicon.ico")
        tree.write("bytes", at: "public/logo.png")
        tree.write("bytes", at: "assets/mark.svg")
        tree.write("bytes", at: "assets/banner.jpg")

        let project = makeSnapshot(root: tree.root, name: "demo")
        let first = scanner.assets(in: project)
        let second = scanner.assets(in: project)

        #expect(first == second)
    }
}

@Suite("asset ranking adjustments")
struct ProjectAssetRankingTests {
    private func makeProject(files: [String]) throws -> (ProjectSnapshot, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("portfox-rank-\(UUID().uuidString)")
        for file in files {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(repeating: 0x1, count: 64).write(to: url)
        }
        let snapshot = ProjectSnapshot(root: root, serviceDirectory: root, name: "rank")
        return (snapshot, root)
    }

    @Test("a sized icon variant still ranks as an icon")
    func sizedVariantRanksAsIcon() throws {
        let (project, root) = try makeProject(files: ["public/icon-192.png", "public/banner.png"])
        defer { try? FileManager.default.removeItem(at: root) }

        let assets = ProjectAssetScanner().assets(in: project)

        #expect(assets.first?.filename == "icon-192.png")
    }

    @Test("an apple touch icon with a size suffix ranks as an icon")
    func appleTouchVariantRanksAsIcon() throws {
        let (project, root) = try makeProject(files: ["public/apple-touch-icon-180.png", "public/photo.png"])
        defer { try? FileManager.default.removeItem(at: root) }

        let assets = ProjectAssetScanner().assets(in: project)

        #expect(assets.first?.filename == "apple-touch-icon-180.png")
    }

    @Test("a name that merely starts with the same letters is not an icon")
    func unrelatedPrefixIsNotAnIcon() throws {
        let (project, root) = try makeProject(files: ["public/iconography-guide.png", "public/logo.svg"])
        defer { try? FileManager.default.removeItem(at: root) }

        let assets = ProjectAssetScanner().assets(in: project)

        #expect(assets.first?.filename == "logo.svg")
    }

    @Test("a flood of images earlier in the scan cannot bury the real favicon")
    func rankingHappensBeforeTruncation() throws {
        // The root is scanned before `public`, so without ranking-then-truncating
        // these screenshots would fill the results and hide the favicon.
        var files = (0..<(ProjectAssetScanner.maximumResults + 20)).map { "screenshot-\($0).png" }
        files.append("public/favicon.ico")
        let (project, root) = try makeProject(files: files)
        defer { try? FileManager.default.removeItem(at: root) }

        let assets = ProjectAssetScanner().assets(in: project)

        #expect(assets.count == ProjectAssetScanner.maximumResults)
        #expect(assets.first?.filename == "favicon.ico")
    }
}
