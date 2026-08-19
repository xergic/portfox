import Foundation

public struct ScanResult: Sendable {
    /// Everything that survived filtering, best first.
    public let services: [RunningService]
    /// Project headings for services that belong to a project.
    public let groups: [ProjectGroup]
    /// Databases, daemons and anything without a project.
    public let standalone: [RunningService]
    /// Every listener seen, including the ones filtered out.
    public let allSockets: [ListeningSocket]
    /// Services rejected by the filter. Shown when "Show all listeners" is on.
    public let hidden: [RunningService]

    public init(
        services: [RunningService],
        groups: [ProjectGroup],
        standalone: [RunningService],
        allSockets: [ListeningSocket],
        hidden: [RunningService]
    ) {
        self.services = services
        self.groups = groups
        self.standalone = standalone
        self.allSockets = allSockets
        self.hidden = hidden
    }

    public static let empty = ScanResult(services: [], groups: [], standalone: [], allSockets: [], hidden: [])
}

public struct ScanOptions: Sendable {
    public var showAllListeners: Bool
    public var groupSiblingRepositories: Bool

    public init(showAllListeners: Bool = false, groupSiblingRepositories: Bool = true) {
        self.showAllListeners = showAllListeners
        self.groupSiblingRepositories = groupSiblingRepositories
    }

    public static let `default` = ScanOptions()
}

/// Owns the whole pipeline and its caches.
///
/// An actor because the app refreshes on a timer while the user can also refresh
/// by hand, and both paths share the project metadata cache.
public actor ServiceRepository {
    private let scanner: ListenerScanner
    private let inspector: ProcessInspector
    private let resolver: any ProjectResolving
    private let engine: DetectionEngine
    private let classifier: ListenerClassifier
    private let iconResolver: IconResolver

    /// Project metadata keyed by directory. Filesystem walks are the expensive
    /// part of a refresh, and project layout almost never changes between scans.
    private var projectCache: [String: (snapshot: ProjectSnapshot?, expires: ContinuousClock.Instant)] = [:]
    private let projectCacheTTL: Duration

    /// Process metadata keyed by pid and start time, so a recycled pid misses.
    private var processCache: [String: ProcessSnapshot] = [:]

    /// Most recent tree, kept so a Force Stop can reach descendants that have
    /// already reparented to launchd.
    private var lastTree: ProcessTree?

    public init(
        scanner: ListenerScanner = ListenerScanner(),
        inspector: ProcessInspector = ProcessInspector(),
        resolver: any ProjectResolving = ProjectResolver(),
        engine: DetectionEngine = DetectionEngine(),
        classifier: ListenerClassifier = ListenerClassifier(),
        iconResolver: IconResolver = IconResolver(),
        projectCacheTTL: Duration = .seconds(60)
    ) {
        self.scanner = scanner
        self.inspector = inspector
        self.resolver = resolver
        self.engine = engine
        self.classifier = classifier
        self.iconResolver = iconResolver
        self.projectCacheTTL = projectCacheTTL
    }

    public func processTree() -> ProcessTree? { lastTree }

    public func refresh(options: ScanOptions = .default) throws -> ScanResult {
        let sockets = try scanner.scan()
        guard !sockets.isEmpty else { return .empty }

        let tree = buildTree(listenerPIDs: Set(sockets.map(\.pid)))
        lastTree = tree

        let services = assembleServices(sockets: sockets, tree: tree)
        let visible = services.filter { options.showAllListeners || $0.classification != .systemNoise }
        let hidden = services.filter { !options.showAllListeners && $0.classification == .systemNoise }

        let (projectServices, standalone) = split(visible)
        let grouper = ProjectGrouper(groupSiblingRepositories: options.groupSiblingRepositories)

        return ScanResult(
            services: visible,
            groups: grouper.group(projectServices),
            standalone: standalone,
            allSockets: sockets,
            hidden: hidden
        )
    }

    // MARK: - Pipeline

    /// Full metadata is only read for listener processes and their ancestors.
    /// Everything else gets the cheap parent link needed to walk the tree.
    private func buildTree(listenerPIDs: Set<pid_t>) -> ProcessTree {
        var byPID: [pid_t: ProcessSnapshot] = [:]
        for pid in inspector.allPIDs() {
            if let light = inspector.lightweightSnapshot(pid: pid) { byPID[pid] = light }
        }

        let lightweightTree = ProcessTree(processes: Array(byPID.values))
        var detailed = listenerPIDs
        for pid in listenerPIDs {
            for ancestor in lightweightTree.ancestors(of: pid) { detailed.insert(ancestor.pid) }
        }

        for pid in detailed {
            guard let light = byPID[pid] else { continue }
            let key = light.identity
            if let cached = processCache[key] {
                byPID[pid] = cached
            } else if let full = inspector.snapshot(pid: pid) {
                processCache[key] = full
                byPID[pid] = full
            }
        }

        pruneProcessCache(livePIDs: Set(byPID.keys))
        return ProcessTree(processes: Array(byPID.values))
    }

    private func assembleServices(sockets: [ListeningSocket], tree: ProcessTree) -> [RunningService] {
        let listenerPIDs = Set(sockets.map(\.pid))
        var socketsByRepresentative: [pid_t: [ListeningSocket]] = [:]

        for socket in sockets {
            let representative = Self.representative(for: socket.pid, listenerPIDs: listenerPIDs, tree: tree)
            socketsByRepresentative[representative, default: []].append(socket)
        }

        return socketsByRepresentative.compactMap { representative, owned in
            build(representative: representative, sockets: owned, tree: tree)
        }
        .sorted { lhs, rhs in
            if lhs.classification != rhs.classification { return lhs.classification < rhs.classification }
            return lhs.port < rhs.port
        }
    }

    /// A listener whose ancestor is also a listener in the same directory is part
    /// of that ancestor's service, not a service of its own. This is what folds
    /// `workerd` into the `wrangler` process that spawned it.
    static func representative(for pid: pid_t, listenerPIDs: Set<pid_t>, tree: ProcessTree) -> pid_t {
        guard let start = tree.process(pid) else { return pid }
        var best = pid

        for ancestor in tree.ancestors(of: pid) {
            guard listenerPIDs.contains(ancestor.pid), ancestor.uid == start.uid else { continue }
            let sameDirectory = ancestor.workingDirectory == nil
                || start.workingDirectory == nil
                || ancestor.workingDirectory == start.workingDirectory
            if sameDirectory { best = ancestor.pid }
        }
        return best
    }

    private func build(representative: pid_t, sockets: [ListeningSocket], tree: ProcessTree) -> RunningService? {
        guard let listener = tree.process(representative) else { return nil }

        let project = listener.workingDirectoryURL.flatMap { cachedProject(for: $0) }
        let ports = sockets.map(\.port).sorted()
        let related = (tree.ancestors(of: representative, limit: 4) + tree.descendants(of: representative, limit: 12))
            .map(\.command)
            .filter { !$0.isEmpty }

        let context = DetectionContext(process: listener, project: project, ports: ports, relatedCommands: related)
        let detection = engine.detect(context)
        let root = tree.logicalRoot(of: representative) ?? listener
        let primary = Self.primarySocket(from: sockets, type: detection.type)

        return RunningService(
            id: "\(listener.identity)-\(primary.port)",
            listenerProcess: listener,
            rootProcess: root,
            sockets: sockets.sorted { $0.port < $1.port },
            primarySocket: primary,
            detection: detection,
            classification: classifier.classify(process: listener, detection: detection, project: project),
            project: project
        )
    }

    /// Debug and inspector ports are never the port a user wants to see.
    static let demotedPorts: Set<Int> = [9229, 9230, 9231, 5858, 6499, 19001]
    /// macOS hands out ephemeral source ports from here up.
    static let ephemeralPortFloor = 49152

    static func primarySocket(from sockets: [ListeningSocket], type: ServiceType) -> ListeningSocket {
        precondition(!sockets.isEmpty, "a service is only built from at least one socket")

        func rank(_ socket: ListeningSocket) -> (Int, Int) {
            let tier: Int
            if type.defaultPorts.contains(socket.port) {
                tier = 0
            } else if demotedPorts.contains(socket.port) {
                tier = 3
            } else if socket.port >= ephemeralPortFloor {
                tier = 2
            } else {
                tier = 1
            }
            return (tier, socket.port)
        }

        return sockets.min { rank($0) < rank($1) } ?? sockets[0]
    }

    private func split(_ services: [RunningService]) -> (project: [RunningService], standalone: [RunningService]) {
        var project: [RunningService] = []
        var standalone: [RunningService] = []
        for service in services {
            let isInfrastructure = service.type.category == .database || service.type.category == .infrastructure
            if service.project != nil && !isInfrastructure {
                project.append(service)
            } else {
                standalone.append(service)
            }
        }
        return (project, standalone)
    }

    // MARK: - Caches

    private func cachedProject(for directory: URL) -> ProjectSnapshot? {
        let key = directory.path
        if let entry = projectCache[key], entry.expires > .now { return entry.snapshot }

        let resolved = resolver.resolve(serviceDirectory: directory)
            .map { snapshot in snapshot.withIcon(path: iconResolver.projectIconPath(for: snapshot)) }
        projectCache[key] = (resolved, .now + projectCacheTTL)
        return resolved
    }

    private func pruneProcessCache(livePIDs: Set<pid_t>) {
        guard processCache.count > 512 else { return }
        processCache = processCache.filter { _, snapshot in livePIDs.contains(snapshot.pid) }
    }

    public func invalidateCaches() {
        projectCache.removeAll()
        processCache.removeAll()
    }
}
