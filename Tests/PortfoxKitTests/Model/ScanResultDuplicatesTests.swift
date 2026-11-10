import Foundation
import Testing
@testable import PortfoxKit

@Suite("Spotting a second copy of a dev server")
struct ScanResultDuplicatesTests {
    private let shop = URL(fileURLWithPath: "/Users/me/shop")

    private func service(
        _ type: ServiceType,
        port: Int,
        directory: String = "",
        startedAt seconds: TimeInterval? = nil,
        classification: ServiceClass = .developmentService
    ) -> RunningService {
        let serviceDirectory = directory.isEmpty ? shop : shop.appendingPathComponent(directory)
        return makeService(
            port: port,
            project: ProjectSnapshot(root: shop, serviceDirectory: serviceDirectory, name: "shop", rootKind: .git),
            pid: pid_t(port),
            detection: DetectionResult(type: type, score: 100, confidence: 1, evidence: []),
            classification: classification,
            startTime: seconds.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private func duplicates(_ services: [RunningService]) -> [String: Int] {
        ScanResult(services: services, groups: [], standalone: [], allSockets: [], hidden: []).duplicateOriginalPorts
    }

    @Test("the later copy points at the port of the first")
    func laterCopyIsTheDuplicate() {
        let original = service(.nextJS, port: 3000, startedAt: 100)
        let copy = service(.nextJS, port: 3001, startedAt: 200)

        #expect(duplicates([copy, original]) == [copy.id: 3000])
    }

    @Test("age decides the original, not the port")
    func ageBeatsPort() {
        let original = service(.nextJS, port: 3001, startedAt: 100)
        let copy = service(.nextJS, port: 3000, startedAt: 200)

        #expect(duplicates([copy, original]) == [copy.id: 3001])
    }

    @Test("an unknown start time never wins the original")
    func unknownAgeLoses() {
        let original = service(.vite, port: 5174, startedAt: 100)
        let copy = service(.vite, port: 5173)

        #expect(duplicates([copy, original]) == [copy.id: 5174])
    }

    @Test("two packages of one monorepo are not copies")
    func differentDirectoriesAreDistinct() {
        let web = service(.nextJS, port: 3000, directory: "apps/web", startedAt: 100)
        let docs = service(.nextJS, port: 3001, directory: "apps/docs", startedAt: 200)

        #expect(duplicates([web, docs]).isEmpty)
    }

    @Test("different frameworks in one folder are not copies")
    func differentTypesAreDistinct() {
        let app = service(.vite, port: 5173, startedAt: 100)
        let storybook = service(.storybook, port: 6006, startedAt: 200)

        #expect(duplicates([app, storybook]).isEmpty)
    }

    @Test("databases are never called duplicates")
    func infrastructureIsSkipped() {
        let first = service(.postgres, port: 5432, startedAt: 100, classification: .infrastructure)
        let second = service(.postgres, port: 5433, startedAt: 200, classification: .infrastructure)

        #expect(duplicates([first, second]).isEmpty)
    }

    @Test("a third copy points at the first as well")
    func everyLaterCopyIsMarked() {
        let original = service(.nuxt, port: 3000, startedAt: 100)
        let second = service(.nuxt, port: 3001, startedAt: 200)
        let third = service(.nuxt, port: 3002, startedAt: 300)

        #expect(duplicates([third, original, second]) == [second.id: 3000, third.id: 3000])
    }
}
