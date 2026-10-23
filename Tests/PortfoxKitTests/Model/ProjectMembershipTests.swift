import Foundation
import Testing
@testable import PortfoxKit

@Suite("Project membership")
struct ProjectMembershipTests {
    private func service(in root: String) -> RunningService {
        makeService(port: 3000, project: makeSnapshot(root: URL(fileURLWithPath: root), name: "app"))
    }

    @Test("a service belongs to its own root and to any folder above it")
    func rootAndAncestors() {
        #expect(service(in: "/code/shop").isInProject(at: "/code/shop"))
        #expect(service(in: "/code/shop/web").isInProject(at: "/code/shop"))
    }

    @Test("a folder whose name merely starts the same is not an ancestor")
    func lookalikeFolder() {
        #expect(!service(in: "/code/shopfront").isInProject(at: "/code/shop"))
        #expect(!makeService(port: 3000, project: nil).isInProject(at: "/code/shop"))
    }
}
