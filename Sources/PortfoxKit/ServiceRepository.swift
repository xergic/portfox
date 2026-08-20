import Foundation

public struct ScanResult: Sendable, Equatable {
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

extension ScanResult {
    /// The same result narrowed to the services that pass `isIncluded`, with the
    /// project headings and the standalone list rebuilt so neither can reference
    /// a service that is no longer in `services`.
    ///
    /// `allSockets` and `hidden` carry through untouched. They describe the
    /// machine, not the view, which is why the sidebar footer keeps counting
    /// every listener the same way it already counts the filtered-out ones.
    ///
    /// Returns `self` when nothing was removed, without having allocated. The
    /// no-op is the common case, and it runs on every redraw of the sidebar.
    public func keeping(_ isIncluded: (RunningService) -> Bool) -> ScanResult {
        guard let firstDropped = services.firstIndex(where: { !isIncluded($0) }) else { return self }

        var kept = Array(services[..<firstDropped])
        kept.append(contentsOf: services[services.index(after: firstDropped)...].filter(isIncluded))

        let allowed = Set(kept.map(\.id))
        return ScanResult(
            services: kept,
            groups: groups
                .map { ProjectGroup(project: $0.project, services: $0.services.filter { allowed.contains($0.id) }) }
                .filter { !$0.services.isEmpty },
            standalone: standalone.filter { allowed.contains($0.id) },
            allSockets: allSockets,
            hidden: hidden
        )
    }
}

/// One turn of the scan loop.
///
/// `didRebuild` is false when the listening sockets had not moved since the last
/// call, so `result` and `tree` are the same values the caller already holds and
/// it has nothing to apply.
public struct ScanUpdate: Sendable {
    public let result: ScanResult
    public let tree: ProcessTree?
    public let didRebuild: Bool

    public init(result: ScanResult, tree: ProcessTree?, didRebuild: Bool) {
        self.result = result
        self.tree = tree
        self.didRebuild = didRebuild
    }
}

public struct ScanOptions: Sendable, Equatable {
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
    private let versionResolver = VersionResolver()

    /// Project metadata keyed by directory. Filesystem walks are the expensive
    /// part of a refresh, and project layout almost never changes between scans.
    private var projectCache: [String: (snapshot: ProjectSnapshot?, expires: ContinuousClock.Instant)] = [:]
    private let projectCacheTTL: Duration

    /// Process metadata keyed by pid and start time, so a recycled pid misses.
    private var processCache: [String: ProcessSnapshot] = [:]

    /// Most recent tree, kept so a Force Stop can reach descendants that have
    /// already reparented to launchd.
    private var lastTree: ProcessTree?

    /// Inputs and output of the last full pipeline run. A tick whose sockets and
    /// options match returns this result instead of rebuilding it.
    private var lastRun: CompletedScan?

    private struct CompletedScan {
        let sockets: Set<ListeningSocket>
        let options: ScanOptions
        let result: ScanResult
    }

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

    /// Runs the pipeline and reports what the UI should show.
    ///
    /// The socket set is read on every call, because it is the only cheap thing
    /// that says whether anything changed. When it matches the last run, and the
    /// options do too, nothing downstream of `lsof` can have moved, so the cached
    /// result comes back with `didRebuild` false and the caller can leave its own
    /// state alone.
    ///
    /// `reloadingFromDisk` is the manual Refresh button. It drops every cache that
    /// reads the filesystem, which is the only way to pick up a manifest, an icon
    /// or an installed dependency that changed under a process that kept running.
    public func refresh(
        options: ScanOptions = .default,
        reloadingFromDisk: Bool = false
    ) async throws -> ScanUpdate {
        let sockets = try scanner.scan()
        guard !sockets.isEmpty else {
            await forgetEverything()
            return ScanUpdate(result: .empty, tree: nil, didRebuild: true)
        }

        let socketSet = Set(sockets)
        if reloadingFromDisk {
            await forgetEverything()
        } else if let last = lastRun, last.sockets == socketSet, last.options == options {
            return ScanUpdate(result: last.result, tree: lastTree, didRebuild: false)
        }

        let listenerPIDs = Set(sockets.map(\.pid))
        let tree = buildTree(listenerPIDs: listenerPIDs)
        lastTree = tree

        let services = await withVersions(
            assembleServices(sockets: sockets, listenerPIDs: listenerPIDs, tree: tree)
        )
        let visible = services.filter { options.showAllListeners || $0.classification != .systemNoise }
        let hidden = services.filter { !options.showAllListeners && $0.classification == .systemNoise }

        let (projectServices, standalone) = split(visible)
        let grouper = ProjectGrouper(groupSiblingRepositories: options.groupSiblingRepositories)

        let result = ScanResult(
            services: visible,
            groups: grouper.group(projectServices),
            standalone: standalone,
            allSockets: sockets,
            hidden: hidden
        )

        lastRun = CompletedScan(sockets: socketSet, options: options, result: result)
        return ScanUpdate(result: result, tree: tree, didRebuild: true)
    }

    /// Resident memory for the pids the caller asked about, sampled fresh. One
    /// `proc_pidinfo` call per pid, so the caller passes only what it will draw.
    public func sampleResidentMemory(of pids: some Collection<pid_t>) -> [pid_t: UInt64] {
        var sampled: [pid_t: UInt64] = [:]
        sampled.reserveCapacity(pids.count)
        for pid in pids {
            if let bytes = inspector.residentMemory(pid: pid) { sampled[pid] = bytes }
        }
        return sampled
    }

    /// Versions are resolved concurrently because one of them may have to ask a
    /// binary for its version, and a slow interpreter must not hold up the rest.
    private func withVersions(_ services: [RunningService]) async -> [RunningService] {
        await withTaskGroup(of: (Int, String?).self) { group in
            for (index, service) in services.enumerated() {
                group.addTask { [versionResolver] in
                    (index, await versionResolver.version(for: service))
                }
            }

            var resolved = services
            for await (index, version) in group { resolved[index].version = version }
            return resolved
        }
    }

    // MARK: - Pipeline

    /// Full metadata is only read for listener processes and their ancestors.
    /// Everything else gets the cheap parent link needed to walk the tree.
    private func buildTree(listenerPIDs: Set<pid_t>) -> ProcessTree {
        var tree = ProcessTree(processes: inspector.processSkeleton())

        var detailed = listenerPIDs
        for pid in listenerPIDs {
            for ancestor in tree.ancestors(of: pid) { detailed.insert(ancestor.pid) }
        }

        for pid in detailed {
            guard let light = tree.process(pid) else { continue }
            let key = light.identity
            if let cached = processCache[key] {
                tree.replace(cached)
            } else if let full = inspector.snapshot(pid: pid) {
                processCache[key] = full
                tree.replace(full)
            }
        }

        pruneProcessCache(against: tree)
        return tree
    }

    private func assembleServices(
        sockets: [ListeningSocket],
        listenerPIDs: Set<pid_t>,
        tree: ProcessTree
    ) -> [RunningService] {
        var socketsByRepresentative: [pid_t: [ListeningSocket]] = [:]

        for socket in sockets {
            let representative = Self.representative(for: socket.pid, listenerPIDs: listenerPIDs, tree: tree)
            socketsByRepresentative[representative, default: []].append(socket)
        }

        let serviceRoots = Set(socketsByRepresentative.keys)
        return socketsByRepresentative.compactMap { representative, owned in
            build(representative: representative, sockets: owned, tree: tree, serviceRoots: serviceRoots)
        }
        .sorted { lhs, rhs in
            if lhs.classification != rhs.classification { return lhs.classification < rhs.classification }
            return lhs.port < rhs.port
        }
    }

    /// A listener whose ancestor is also a listener in the same directory is part
    /// of that ancestor's service, not a service of its own. This is what folds
    /// `workerd` into the `wrangler` process that spawned it.
    ///
    /// Two rules keep this from over-merging. The walk stops at a shell, terminal
    /// or application bundle, so a dev server is never absorbed into the editor
    /// that happens to sit above it. And both working directories must be known
    /// and equal, because an unknown directory is not evidence of anything.
    public static func representative(for pid: pid_t, listenerPIDs: Set<pid_t>, tree: ProcessTree) -> pid_t {
        guard let start = tree.process(pid), let directory = start.workingDirectory else { return pid }
        var best = pid

        for ancestor in tree.ancestors(of: pid) {
            guard ProcessRole.of(ancestor) != .boundary else { break }
            guard listenerPIDs.contains(ancestor.pid),
                  ancestor.uid == start.uid,
                  ancestor.workingDirectory == directory
            else { continue }
            best = ancestor.pid
        }
        return best
    }

    private func build(
        representative: pid_t,
        sockets: [ListeningSocket],
        tree: ProcessTree,
        serviceRoots: Set<pid_t>
    ) -> RunningService? {
        guard let listener = tree.process(representative) else { return nil }

        let project = listener.workingDirectoryURL.flatMap { cachedProject(for: $0) }
        let ports = Set(sockets.map(\.port)).sorted()
        let related = (tree.ancestors(of: representative, limit: 4) + tree.descendants(of: representative, limit: 12))
            .map(\.command)
            .filter { !$0.isEmpty }

        let context = DetectionContext(process: listener, project: project, ports: ports, relatedCommands: related)
        let detection = engine.detect(context)
        let root = tree.logicalRoot(of: representative, serviceRoots: serviceRoots) ?? listener
        let primary = Self.primarySocket(from: sockets, type: detection.type)

        return RunningService(
            id: "\(listener.identity)-\(primary.port)",
            listenerProcess: listener,
            rootProcess: root,
            sockets: sockets.sorted { $0.port < $1.port },
            primarySocket: primary,
            detection: detection,
            classification: classifier.classify(process: listener, detection: detection, project: project, ports: ports),
            project: project
        )
    }

    /// Debug and inspector ports are never the port a user wants to see.
    static let demotedPorts: Set<Int> = [9229, 9230, 9231, 5858, 6499, 19001]
    /// macOS hands out ephemeral source ports from here up.
    static let ephemeralPortFloor = 49152

    static func primarySocket(from sockets: [ListeningSocket], type: ServiceType) -> ListeningSocket {
        precondition(!sockets.isEmpty, "a service is only built from at least one socket")

        // A default port ranks by its position in the type's list rather than by
        // its number, so Mailpit shows its web UI on 8025 and not SMTP on 1025.
        func rank(_ socket: ListeningSocket) -> (Int, Int) {
            if let preference = type.defaultPorts.firstIndex(of: socket.port) {
                return (0, preference)
            }
            if demotedPorts.contains(socket.port) { return (3, socket.port) }
            if socket.port >= ephemeralPortFloor { return (2, socket.port) }
            return (1, socket.port)
        }

        return sockets.min { rank($0) < rank($1) } ?? sockets[0]
    }

    private func split(_ services: [RunningService]) -> (project: [RunningService], standalone: [RunningService]) {
        var project: [RunningService] = []
        var standalone: [RunningService] = []
        for service in services {
            let isInfrastructure = service.type.category == .database || service.type.category == .infrastructure
            // A bare directory is not a project. Grouping under it produces
            // headings like "ondra ~" for anything started from the home folder.
            let hasProject = service.project.map { $0.rootKind != .directory } ?? false
            if hasProject && !isInfrastructure {
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

    /// The live pid set is only needed when the cache is actually over its bound,
    /// which is rare, so it is built inside the guard rather than at every scan.
    private func pruneProcessCache(against tree: ProcessTree) {
        guard processCache.count > 512 else { return }
        let live = Set(tree.allProcesses.map(\.pid))
        processCache = processCache.filter { _, snapshot in live.contains(snapshot.pid) }
    }

    /// The one place that drops cached state. Everything that resets anything goes
    /// through here, so a new cache cannot be forgotten by one caller and cleared
    /// by another.
    public func forgetEverything() async {
        projectCache.removeAll()
        processCache.removeAll()
        lastRun = nil
        lastTree = nil
        await versionResolver.invalidate()
    }
}
