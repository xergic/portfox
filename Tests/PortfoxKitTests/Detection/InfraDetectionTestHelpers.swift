import Foundation
@testable import PortfoxKit

/// Builds `DetectionContext` values from realistic argv strings without going
/// through the real scanner, so detector tests read like the process list they model.
enum DetectionFixture {
    static func context(
        argv: [String],
        executablePath: String? = nil,
        projectFiles: Set<String> = [],
        dependencies: Set<String> = [],
        ports: [Int] = [],
        relatedCommands: [String] = []
    ) -> DetectionContext {
        let process = ProcessSnapshot(
            pid: 4242,
            parentPID: 1,
            uid: 501,
            executablePath: executablePath,
            arguments: argv
        )
        let project: ProjectSnapshot? = (projectFiles.isEmpty && dependencies.isEmpty) ? nil : ProjectSnapshot(
            root: URL(fileURLWithPath: "/tmp/portfox-fixture"),
            serviceDirectory: URL(fileURLWithPath: "/tmp/portfox-fixture"),
            name: "fixture",
            files: projectFiles,
            rootFiles: projectFiles,
            dependencies: dependencies
        )
        return DetectionContext(
            process: process,
            project: project,
            ports: ports,
            relatedCommands: relatedCommands
        )
    }

    /// A container row. `executablePath` is the forwarder's on purpose, so a test
    /// can prove the image won and the `.docker` detector did not.
    static func containerContext(
        image: String,
        ports: [Int] = [],
        composeProject: String? = nil,
        executablePath: String = "/Applications/Docker.app/Contents/MacOS/com.docker.backend"
    ) -> DetectionContext {
        let process = ProcessSnapshot(
            pid: 4242,
            parentPID: 1,
            uid: 501,
            executablePath: executablePath,
            arguments: [executablePath]
        )
        return DetectionContext(
            process: process,
            project: nil,
            ports: ports,
            container: ContainerSnapshot(
                id: "c0ffee",
                name: "fixture",
                image: image,
                composeProject: composeProject
            )
        )
    }

    static func context(
        command: String,
        executablePath: String? = nil,
        projectFiles: Set<String> = [],
        dependencies: Set<String> = [],
        ports: [Int] = [],
        relatedCommands: [String] = []
    ) -> DetectionContext {
        context(
            argv: command.split(separator: " ", omittingEmptySubsequences: true).map(String.init),
            executablePath: executablePath,
            projectFiles: projectFiles,
            dependencies: dependencies,
            ports: ports,
            relatedCommands: relatedCommands
        )
    }
}
