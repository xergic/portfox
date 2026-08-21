import Foundation
import Testing
@testable import PortfoxKit

@Suite("what Portfox may start and stop")
struct ServiceClassTests {
    /// Restart and Stop All both read this. If they ever disagree about what a
    /// daemon is, one of them is wrong.
    @Test("a dev server is the user's to manage")
    func developerProcesses() {
        #expect(ServiceClass.developmentService.isUserManaged)
        #expect(ServiceClass.probableDeveloperProcess.isUserManaged)
    }

    @Test("a database, daemon or Apple helper is not")
    func supervisedProcesses() {
        #expect(!ServiceClass.infrastructure.isUserManaged)
        #expect(!ServiceClass.systemNoise.isUserManaged)
    }
}
