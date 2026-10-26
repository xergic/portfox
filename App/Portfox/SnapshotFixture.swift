import Foundation
import PortfoxKit

/// The machine `--demo` renders instead of this one: a monorepo with an agent
/// started server and the daemons most machines carry. The README screenshot
/// comes from here, so it never shows a real project. The project icon is a
/// bundled PNG, because a real one is read from the project folder on disk.
enum SnapshotFixture {
    static func result() -> ScanResult {
        let projects = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects")
        let wishfox = projects.appendingPathComponent("wishfox")

        let developed = [
            service(
                .nuxt, "4.2.1", pid: 4242, port: 3000,
                command: ["/opt/homebrew/bin/node", "node_modules/.bin/nuxt", "dev"],
                project: project(wishfox, subpath: "web"), origin: .agent(.claudeCode)
            ),
            service(
                .bun, "1.3.2", pid: 4243, port: 4000,
                command: ["/opt/homebrew/bin/bun", "--watch", "src/index.ts"],
                project: project(wishfox, subpath: "api")
            )
        ]
        let daemons = [
            service(
                .postgres, "17.6", pid: 812, port: 5432,
                command: ["/opt/homebrew/opt/postgresql@17/bin/postgres", "-D", "/opt/homebrew/var/postgresql@17"]
            ),
            service(.redis, "8.2.1", pid: 815, port: 6379, command: ["/opt/homebrew/opt/redis/bin/redis-server"]),
            service(.mongodb, "8.0.13", pid: 821, port: 27017, command: ["/opt/homebrew/opt/mongodb-community/bin/mongod"])
        ]

        let services = developed + daemons
        return ScanResult(
            services: services,
            groups: ProjectGrouper().group(developed),
            standalone: daemons,
            allSockets: services.flatMap(\.sockets),
            hidden: []
        )
    }

    private static func project(_ root: URL, subpath: String? = nil) -> ProjectSnapshot {
        ProjectSnapshot(
            root: root,
            serviceDirectory: subpath.map(root.appendingPathComponent) ?? root,
            name: root.lastPathComponent,
            subpath: subpath,
            rootKind: .workspace,
            iconPath: Bundle.main.path(forResource: "DemoProjectIcon", ofType: "png")
        )
    }

    private static func service(
        _ type: ServiceType,
        _ version: String,
        pid: pid_t,
        port: Int,
        command: [String],
        project: ProjectSnapshot? = nil,
        origin: ServiceOrigin? = nil
    ) -> RunningService {
        let isDevelopment = project != nil
        let process = ProcessSnapshot(
            pid: pid,
            parentPID: 1,
            processGroupID: pid,
            uid: getuid(),
            startTime: .now.addingTimeInterval(isDevelopment ? -12 * 60 : -2 * 86_400),
            executablePath: command[0],
            arguments: command,
            workingDirectory: project?.serviceDirectory.path
        )
        let socket = ListeningSocket(pid: pid, port: port, host: "127.0.0.1", family: .ipv4)
        return RunningService(
            id: "demo-\(pid)",
            listenerProcess: process,
            rootProcess: process,
            sockets: [socket],
            primarySocket: socket,
            detection: DetectionResult(type: type, score: 100, confidence: 1, evidence: []),
            classification: isDevelopment ? .developmentService : .infrastructure,
            project: project,
            origin: origin,
            version: version
        )
    }
}
