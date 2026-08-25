import Foundation
import Testing
@testable import PortfoxKit

@Suite("What an arrival notification says")
struct ServiceArrivalDigestTests {
    private func service(_ name: ServiceType, port: Int, project: String? = nil) -> RunningService {
        makeService(
            port: port,
            project: project.map {
                makeSnapshot(root: URL(fileURLWithPath: "/tmp/\($0)"), name: $0, rootKind: .git)
            },
            pid: pid_t(port),
            id: "\(port)",
            detection: DetectionResult(type: name, score: 100, confidence: 1, evidence: [])
        )
    }

    @Test("nothing arrived, nothing to say")
    func emptyIsNil() {
        #expect(ServiceArrivalDigest([]) == nil)
    }

    @Test("one service is named with its port")
    func oneService() {
        let digest = ServiceArrivalDigest([service(.nextJS, port: 3000, project: "shop")])

        #expect(digest?.title == "Next.js on port 3000")
        #expect(digest?.body == "shop")
    }

    @Test("several are counted in the title and listed in the body")
    func severalServices() {
        let digest = ServiceArrivalDigest([
            service(.nextJS, port: 3000),
            service(.postgres, port: 5432),
            service(.vite, port: 5173)
        ])

        #expect(digest?.title == "3 new services")
        #expect(digest?.body == "Next.js :3000, PostgreSQL :5432, Vite :5173")
    }

    /// A compose stack coming up all at once must not produce a body that runs
    /// off the end of the banner.
    @Test("a long list names three and counts the rest")
    func longListIsCapped() {
        let digest = ServiceArrivalDigest([
            service(.nextJS, port: 3000),
            service(.postgres, port: 5432),
            service(.vite, port: 5173),
            service(.redis, port: 6379),
            service(.nginx, port: 8080)
        ])

        #expect(digest?.title == "5 new services")
        #expect(digest?.body == "Next.js :3000, PostgreSQL :5432, Vite :5173, and 2 more")
    }
}
