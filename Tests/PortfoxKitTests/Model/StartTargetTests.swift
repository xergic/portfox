import Foundation
import Testing
@testable import PortfoxKit

@Suite("Answering a start wait")
struct StartTargetTests {
    private func detected(_ type: ServiceType) -> DetectionResult {
        DetectionResult(type: type, score: 100, confidence: 1, evidence: [])
    }

    private func scan(_ services: [RunningService]) -> ScanResult {
        ScanResult(services: services, groups: [], standalone: [], allSockets: [], hidden: [])
    }

    private func project(_ root: String) -> ProjectSnapshot {
        makeSnapshot(root: URL(fileURLWithPath: root), name: (root as NSString).lastPathComponent)
    }

    @Test("a project wait prefers the service the user will open over its database")
    func projectPrefersWebServer() {
        let database = makeService(port: 5432, project: project("/code/shop"), pid: 1,
                                   detection: detected(.postgres), classification: .infrastructure)
        let web = makeService(port: 5173, project: project("/code/shop"), pid: 2, detection: detected(.vite))
        let result = scan([database, web])

        #expect(result.service(answering: .project(root: "/code/shop"), appeared: [])?.port == 5173)
        #expect(scan([database]).service(answering: .project(root: "/code/shop"), appeared: []) == nil)
    }

    @Test("a project wait matches a repository inside a pinned sibling group, not a lookalike folder")
    func projectMatchesNestedRoots() {
        let nested = makeService(port: 3000, project: project("/code/shop/api"), pid: 1, detection: detected(.vite))
        let lookalike = makeService(port: 3001, project: project("/code/shopfront"), pid: 2, detection: detected(.vite))

        #expect(scan([nested]).service(answering: .project(root: "/code/shop"), appeared: [])?.port == 3000)
        #expect(scan([lookalike]).service(answering: .project(root: "/code/shop"), appeared: []) == nil)
    }

    @Test("a port wait matches any socket, not only the primary")
    func portMatchesAnySocket() {
        let service = makeService(port: 3000, project: nil, hosts: [("127.0.0.1", 3000), ("127.0.0.1", 9229)])
        #expect(scan([service]).service(answering: .port(9229), appeared: []) != nil)
        #expect(scan([service]).service(answering: .port(4000), appeared: []) == nil)
    }

    @Test("the next agent server is an arrival an agent started, never one already running")
    func agentWaitReadsArrivalsOnly() {
        let agentServer = makeService(port: 5173, project: nil, pid: 1, origin: .agent(.claudeCode))
        let byHand = makeService(port: 3000, project: nil, pid: 2)
        let agentDaemon = makeService(port: 37701, project: nil, pid: 3,
                                      classification: .agentTool, origin: .agent(.claudeCode))
        let result = scan([agentServer, byHand, agentDaemon])

        #expect(result.service(answering: .nextAgentServer, appeared: []) == nil)
        #expect(result.service(answering: .nextAgentServer, appeared: [byHand, agentDaemon]) == nil)
        #expect(result.service(answering: .nextAgentServer, appeared: [byHand, agentServer])?.port == 5173)
    }
}
