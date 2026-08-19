import Foundation
import Testing
@testable import PortFoxKit

/// Builds process snapshots without touching the machine.
private func process(
    _ pid: pid_t,
    executable: String? = nil,
    directory: String? = nil
) -> ProcessSnapshot {
    ProcessSnapshot(
        pid: pid,
        parentPID: 1,
        uid: 501,
        startTime: Date(timeIntervalSince1970: 1_000),
        executablePath: executable,
        arguments: [],
        workingDirectory: directory
    )
}

private func detected(_ type: ServiceType) -> DetectionResult {
    DetectionResult(type: type, score: 100, confidence: 1, evidence: [])
}

private func snapshot(rootKind: ProjectSnapshot.RootKind) -> ProjectSnapshot {
    let url = URL(fileURLWithPath: "/repo")
    return ProjectSnapshot(root: url, serviceDirectory: url, name: "repo", rootKind: rootKind)
}

@Suite("listener classification")
struct ListenerClassifierTests {
    private let classifier = ListenerClassifier(codeDirectories: ["/Users/x/Work"])

    @Test(
        "a recognised web, api or tooling framework is a development service",
        arguments: [ServiceType.vite, .nestJS, .expo]
    )
    func frameworkIsDevelopmentService(type: ServiceType) {
        let result = classifier.classify(process: process(10), detection: detected(type), project: nil, ports: [3000])

        #expect(result == .developmentService)
    }

    @Test(
        "a recognised database or daemon type is infrastructure",
        arguments: [ServiceType.postgres, .redis, .minio]
    )
    func databaseOrDaemonIsInfrastructure(type: ServiceType) {
        let result = classifier.classify(process: process(10), detection: detected(type), project: nil, ports: [5432])

        #expect(result == .infrastructure)
    }

    @Test("a service bound only to ephemeral ports is system noise even when confidently detected")
    func ephemeralOnlyPortsAreSystemNoise() {
        // The orphaned-workerd case: wrangler's parent died but the child kept
        // listening on a port the OS handed out, not one the framework chose.
        let result = classifier.classify(
            process: process(10),
            detection: detected(.wrangler),
            project: nil,
            ports: [ListenerClassifier.ephemeralPortFloor, ListenerClassifier.ephemeralPortFloor + 1_000]
        )

        #expect(result == .systemNoise)
    }

    @Test("a mix of one stable and several ephemeral ports is not downgraded")
    func mixedPortsAreNotDowngraded() {
        let result = classifier.classify(
            process: process(10),
            detection: detected(.vite),
            project: nil,
            ports: [3000, ListenerClassifier.ephemeralPortFloor, ListenerClassifier.ephemeralPortFloor + 1_000]
        )

        #expect(result == .developmentService)
    }

    @Test("an empty ports array does not trigger the ephemeral rule")
    func emptyPortsDoesNotTriggerEphemeralRule() {
        let result = classifier.classify(process: process(10), detection: detected(.vite), project: nil, ports: [])

        #expect(result == .developmentService)
    }

    @Test(
        "an undetected process under a system directory is system noise",
        arguments: [
            "/System/Library/CoreServices/rapportd",
            "/usr/libexec/rapportd",
            "/usr/sbin/cupsd",
            "/usr/bin/tailspind",
            "/sbin/launchd",
            "/bin/bash"
        ]
    )
    func systemDirectoryIsSystemNoise(executable: String) {
        let result = classifier.classify(
            process: process(10, executable: executable),
            detection: .unknown(),
            project: nil,
            ports: [3000]
        )

        #expect(result == .systemNoise)
    }

    @Test(
        "an undetected process inside an application bundle is system noise",
        arguments: [
            "/Applications/Raycast.app/Contents/MacOS/Raycast",
            "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper",
            "/Applications/Figma.app/Contents/Frameworks/Figma Agent.app/Contents/MacOS/Figma Agent"
        ]
    )
    func applicationBundleIsSystemNoise(executable: String) {
        let result = classifier.classify(
            process: process(10, executable: executable),
            detection: .unknown(),
            project: nil,
            ports: [3000]
        )

        #expect(result == .systemNoise)
    }

    @Test("system directory and application bundle path matching is case-insensitive")
    func pathMatchingIsCaseInsensitive() {
        let systemResult = classifier.classify(
            process: process(10, executable: "/USR/LIBEXEC/rapportd"),
            detection: .unknown(),
            project: nil,
            ports: [3000]
        )
        let bundleResult = classifier.classify(
            process: process(11, executable: "/Applications/Raycast.App/Contents/MacOS/Raycast"),
            detection: .unknown(),
            project: nil,
            ports: [3000]
        )

        #expect(systemResult == .systemNoise)
        #expect(bundleResult == .systemNoise)
    }

    @Test(
        "an undetected process with a project rooted in git, a workspace or a manifest is a probable developer process",
        arguments: [ProjectSnapshot.RootKind.git, .workspace, .manifest]
    )
    func strongRootKindIsProbableDeveloperProcess(rootKind: ProjectSnapshot.RootKind) {
        let result = classifier.classify(
            process: process(10),
            detection: .unknown(),
            project: snapshot(rootKind: rootKind),
            ports: [3000]
        )

        #expect(result == .probableDeveloperProcess)
    }

    @Test("a project resolved only from a bare directory falls through to the code-directory check")
    func directoryRootKindFallsThroughToCodeDirectoryCheck() {
        let unmatched = classifier.classify(
            process: process(10, directory: "/elsewhere"),
            detection: .unknown(),
            project: snapshot(rootKind: .directory),
            ports: [3000]
        )
        let matched = classifier.classify(
            process: process(11, directory: "/Users/x/Work/repo"),
            detection: .unknown(),
            project: snapshot(rootKind: .directory),
            ports: [3000]
        )

        #expect(unmatched == .systemNoise)
        #expect(matched == .probableDeveloperProcess)
    }

    @Test("an undetected process with no project but a working directory under a code directory is a probable developer process")
    func codeDirectoryWithoutProjectIsProbableDeveloperProcess() {
        let result = classifier.classify(
            process: process(10, directory: "/Users/x/Work/repo"),
            detection: .unknown(),
            project: nil,
            ports: [3000]
        )

        #expect(result == .probableDeveloperProcess)
    }

    @Test("isUserCode does not match a directory name that merely shares a prefix")
    func isUserCodeRespectsPathBoundary() {
        // "/Users/x/Workshop" shares every character of "/Users/x/Work" but is a
        // sibling directory, not something inside it.
        #expect(classifier.isUserCode("/Users/x/Workshop") == false)
        #expect(classifier.isUserCode("/Users/x/Workshop/project") == false)
        #expect(classifier.isUserCode("/Users/x/Work/project") == true)
    }

    @Test("an undetected process with nothing going for it is system noise")
    func nothingGoingForItIsSystemNoise() {
        let result = classifier.classify(
            process: process(10, executable: "/opt/homebrew/bin/mystery", directory: "/elsewhere"),
            detection: .unknown(),
            project: nil,
            ports: [3000]
        )

        #expect(result == .systemNoise)
    }
}
