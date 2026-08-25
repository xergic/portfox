import Foundation
@testable import PortfoxKit

/// Builds and tears down real directory trees for project-resolution tests, so
/// the resolver and manifest reader are exercised against actual filesystem
/// calls rather than mocks.
struct TempTree {
    let root: URL

    init() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("portfox-tests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = base
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func makeDirectory(_ path: String) -> URL {
        let url = root.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func write(_ contents: String, at path: String) {
        let url = root.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

func makeService(
    port: Int,
    project: ProjectSnapshot?,
    pid: pid_t = 1,
    executable: String? = nil,
    arguments: [String] = [],
    id: String? = nil,
    detection: DetectionResult = .unknown(),
    classification: ServiceClass = .developmentService,
    container: ContainerSnapshot? = nil
) -> RunningService {
    let process = ProcessSnapshot(
        pid: pid,
        parentPID: 1,
        uid: 501,
        executablePath: executable,
        arguments: arguments
    )
    let socket = ListeningSocket(pid: pid, port: port, host: "127.0.0.1", family: .ipv4)
    return RunningService(
        id: id ?? "\(pid)",
        listenerProcess: process,
        rootProcess: process,
        sockets: [socket],
        primarySocket: socket,
        detection: detection,
        classification: classification,
        project: project,
        container: container
    )
}

func makeSnapshot(
    root: URL,
    name: String,
    iconPath: String? = nil,
    rootKind: ProjectSnapshot.RootKind = .directory
) -> ProjectSnapshot {
    ProjectSnapshot(root: root, serviceDirectory: root, name: name, rootKind: rootKind, iconPath: iconPath)
}
