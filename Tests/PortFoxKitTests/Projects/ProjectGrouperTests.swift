import Foundation
import Testing
@testable import PortFoxKit

@Suite("service grouping")
struct ProjectGrouperTests {
    @Test("four sibling repos under the same parent merge into one group")
    func siblingReposMergeUnderParent() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        let parent = tree.makeDirectory("Wishfox")
        let repos = ["wishfox-admin", "wishfox-front", "wishfox-api", "wishfox-scraper"]
            .map { parent.appendingPathComponent($0) }

        let services = repos.enumerated().map { index, repo in
            makeService(port: 4000 + index, project: makeSnapshot(root: repo, name: repo.lastPathComponent))
        }

        let grouper = ProjectGrouper(codeCollectionRoots: [])
        let groups = grouper.group(services)

        #expect(groups.count == 1)
        #expect(groups.first?.project.root.path == parent.path)
        #expect(groups.first?.project.name == "Wishfox")
        #expect(groups.first?.project.isSiblingGroup == true)
        #expect(groups.first?.services.count == 4)
    }

    @Test("a lone repo under a parent is not merged")
    func loneRepoIsNotMerged() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        let parent = tree.makeDirectory("Solo")
        let repo = parent.appendingPathComponent("only-repo")

        let service = makeService(port: 4000, project: makeSnapshot(root: repo, name: "only-repo"))

        let grouper = ProjectGrouper(codeCollectionRoots: [])
        let groups = grouper.group([service])

        #expect(groups.count == 1)
        #expect(groups.first?.project.root.path == repo.path)
        #expect(groups.first?.project.isSiblingGroup == false)
    }

    @Test("repos directly under a code collection root are not merged")
    func codeCollectionRootPreventsMerging() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        let work = tree.makeDirectory("Work")
        let repoA = work.appendingPathComponent("repo-a")
        let repoB = work.appendingPathComponent("repo-b")

        let services = [
            makeService(port: 4000, project: makeSnapshot(root: repoA, name: "repo-a")),
            makeService(port: 4001, project: makeSnapshot(root: repoB, name: "repo-b"))
        ]

        let grouper = ProjectGrouper(codeCollectionRoots: [work.path])
        let groups = grouper.group(services)

        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.project.isSiblingGroup == false })
    }

    @Test("toggling grouping off leaves sibling repos separate")
    func toggleOffDisablesMerging() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        let parent = tree.makeDirectory("Wishfox")
        let repoA = parent.appendingPathComponent("wishfox-admin")
        let repoB = parent.appendingPathComponent("wishfox-front")

        let services = [
            makeService(port: 4000, project: makeSnapshot(root: repoA, name: "wishfox-admin")),
            makeService(port: 4001, project: makeSnapshot(root: repoB, name: "wishfox-front"))
        ]

        let grouper = ProjectGrouper(groupSiblingRepositories: false, codeCollectionRoots: [])
        let groups = grouper.group(services)

        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.project.isSiblingGroup == false })
    }

    @Test("groups sort by name case-insensitively, services within a group sort by port")
    func sortsGroupsAndServices() {
        let tree = TempTree()
        defer { tree.cleanUp() }
        let zebraRoot = tree.makeDirectory("zebra")
        let appleRoot = tree.makeDirectory("apple")

        let services = [
            makeService(port: 5000, project: makeSnapshot(root: zebraRoot, name: "Zebra")),
            makeService(port: 3000, project: makeSnapshot(root: appleRoot, name: "apple")),
            makeService(port: 3001, project: makeSnapshot(root: appleRoot, name: "apple"))
        ]

        let groups = ProjectGrouper(groupSiblingRepositories: false, codeCollectionRoots: []).group(services)

        #expect(groups.map(\.project.name) == ["apple", "Zebra"])
        #expect(groups.first?.services.map(\.port) == [3000, 3001])
    }

    @Test("services without a project are ignored")
    func servicesWithoutProjectAreIgnored() {
        let service = makeService(port: 4000, project: nil)

        let groups = ProjectGrouper().group([service])

        #expect(groups.isEmpty)
    }
}
