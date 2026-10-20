import Foundation
import Testing
@testable import PortfoxKit

@Suite("Container runtime names")
struct ContainerRuntimeTests {
    private func forwarder(_ path: String) -> ProcessSnapshot {
        ProcessSnapshot(pid: 1, parentPID: 1, uid: 501, executablePath: path, arguments: [])
    }

    @Test("OrbStack is named from its bundle path")
    func orbStack() {
        #expect(ContainerRuntime.displayName(of: forwarder("/Applications/OrbStack.app/Contents/MacOS/xbin/vmgr")) == "OrbStack")
    }

    @Test("Docker Desktop is the fallback")
    func docker() {
        let path = "/Applications/Docker.app/Contents/MacOS/com.docker.backend"
        #expect(ContainerRuntime.displayName(of: forwarder(path)) == "Docker")
    }
}
