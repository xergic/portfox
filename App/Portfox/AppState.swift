import Foundation
import PortfoxKit
import SwiftUI

/// UI-facing state. Owns the refresh loop and forwards actions to the kit.
@MainActor
@Observable
final class AppState {
    /// Everything the scan found, before the ignore list. Private: a view drawing
    /// from it would make ignoring cosmetic in one place and real in another.
    private var rawResult: ScanResult = .empty
    /// What every surface draws.
    private(set) var result: ScanResult = .empty
    /// The ignored services that happen to be running, grouped the same way, so
    /// the dashboard's Ignored chip renders through the existing sections.
    private(set) var ignoredResult: ScanResult = .empty
    private(set) var lastError: String?
    /// Services whose Stop was delivered but which are still alive.
    private(set) var stubbornServiceIDs: Set<String> = []
    private(set) var busyServiceIDs: Set<String> = []
    /// Which services Restart could actually bring back. Settled when the scan
    /// moves, because deciding it asks the filesystem whether a directory and a
    /// binary are still there, and a menu drawn on hover must not stat anything.
    private(set) var relaunchableServiceIDs: Set<String> = []
    /// The tree from the last scan. The dashboard renders it, and stopping needs
    /// it to sweep orphans.
    private(set) var processTree: ProcessTree?
    /// Resident memory and CPU by pid. Held apart from `ScanResult` so numbers
    /// that move on every sample cannot invalidate a scan that did not move.
    private let metrics = ProcessMetrics()

    var isRefreshing: Bool { inFlightRefresh != nil }

    /// Set before the dashboard is opened, so the sheet is already requested on
    /// the window's first layout pass rather than a turn too late.
    var presentedSheet: DashboardSheet?

    enum DashboardSheet: String, Identifiable {
        case preferences
        case about
        var id: String { rawValue }
    }

    var showAllListeners: Bool {
        didSet {
            defaults.set(showAllListeners, forKey: Key.showAllListeners)
            Task { await refresh(.afterAction) }
        }
    }

    var groupSiblingRepositories: Bool {
        didSet {
            defaults.set(groupSiblingRepositories, forKey: Key.groupSiblingRepositories)
            Task { await refresh(.afterAction) }
        }
    }

    var cellLayout: ServiceCellLayout {
        didSet { defaults.set(cellLayout.rawValue, forKey: Key.cellLayout) }
    }

    var showsMenuBarCount: Bool {
        didSet { defaults.set(showsMenuBarCount, forKey: Key.showsMenuBarCount) }
    }

    var showsUptime: Bool {
        didSet { defaults.set(showsUptime, forKey: Key.showsUptime) }
    }

    /// Off costs nothing: with no reader, nothing is sampled and the deltas are
    /// dropped, so turning it back on starts from a clean pair.
    var showsCPU: Bool {
        didSet {
            defaults.set(showsCPU, forKey: Key.showsCPU)
            if !showsCPU { metrics.forgetCPU() }
        }
    }

    var editorBundleID: String? {
        didSet { defaults.set(editorBundleID, forKey: Key.editorBundleID) }
    }

    var terminalBundleID: String? {
        didSet { defaults.set(terminalBundleID, forKey: Key.terminalBundleID) }
    }

    /// Hides the standalone bucket, which is what the daemons section renders.
    /// A projection, not a scan option, so it reprojects instead of rescanning
    /// and `portfox-scan` keeps reporting the machine as it is.
    var hidesDaemons: Bool {
        didSet {
            defaults.set(hidesDaemons, forKey: Key.hidesDaemons)
            applyFilters()
        }
    }

    var automaticRefresh: Bool {
        didSet {
            defaults.set(automaticRefresh, forKey: Key.automaticRefresh)
            start()
        }
    }

    var pollingSeconds: Int {
        didSet {
            defaults.set(pollingSeconds, forKey: Key.pollingSeconds)
            start()
        }
    }

    static let pollingChoices = [1, 2, 5]

    private enum Key {
        static let showAllListeners = "showAllListeners"
        static let groupSiblingRepositories = "groupSiblingRepositories"
        static let cellLayout = "cellLayout"
        static let automaticRefresh = "automaticRefresh"
        static let pollingSeconds = "pollingSeconds"
        static let showsMenuBarCount = "showsMenuBarCount"
        static let hidesDaemons = "hidesDaemons"
        static let showsUptime = "showsUptime"
        static let showsCPU = "showsCPU"
        static let editorBundleID = "editorBundleID"
        static let terminalBundleID = "terminalBundleID"
    }

    let repository = ServiceRepository()
    let controller = ProcessController()
    let projectIcons = ProjectIcons()
    let appearance = Appearance()
    /// Which rows just appeared, and whether that is worth telling the user about.
    let arrivals = ServiceArrivals()
    private let ignoredServices = IgnoredServices()
    private let defaults = UserDefaults.standard

    /// Refreshing on the polling interval only matters while the user is looking.
    /// With every window closed the count badge is the only live element, and a
    /// badge that is a minute stale costs nobody anything.
    private let hiddenInterval = Duration.seconds(60)

    /// A set rather than a counter, so a repeated appear or a missed disappear
    /// cannot leave the app stuck on the fast interval forever.
    private enum Surface: Hashable {
        case popover
        case dashboard
    }

    private var visibleSurfaces: Set<Surface> = []
    private var refreshTask: Task<Void, Never>?
    /// The scan currently running, so a second caller joins it instead of
    /// walking away with whatever half-updated state it happened to find.
    private var inFlightRefresh: Task<Void, Never>?

    var serviceCount: Int { result.services.count }

    init() {
        defaults.register(defaults: [
            Key.groupSiblingRepositories: true,
            Key.automaticRefresh: true,
            Key.pollingSeconds: 2,
            Key.showsMenuBarCount: true,
            Key.showsUptime: true
        ])
        showAllListeners = defaults.bool(forKey: Key.showAllListeners)
        groupSiblingRepositories = defaults.bool(forKey: Key.groupSiblingRepositories)
        cellLayout = ServiceCellLayout(rawValue: defaults.string(forKey: Key.cellLayout) ?? "") ?? .serviceFirst
        automaticRefresh = defaults.bool(forKey: Key.automaticRefresh)
        pollingSeconds = defaults.integer(forKey: Key.pollingSeconds)
        showsMenuBarCount = defaults.bool(forKey: Key.showsMenuBarCount)
        hidesDaemons = defaults.bool(forKey: Key.hidesDaemons)
        showsUptime = defaults.bool(forKey: Key.showsUptime)
        showsCPU = defaults.bool(forKey: Key.showsCPU)
        editorBundleID = defaults.string(forKey: Key.editorBundleID)
        terminalBundleID = defaults.string(forKey: Key.terminalBundleID)
        Task.detached { RelaunchRunner.sweepLeftovers() }
        start()
    }

    func start() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let self, automaticRefresh else { return }
                try? await Task.sleep(for: currentInterval)
            }
        }
    }

    /// Clamped, because a stored zero would turn the loop into a spin.
    private var currentInterval: Duration {
        guard !visibleSurfaces.isEmpty else { return hiddenInterval }
        return .seconds(max(1, pollingSeconds))
    }

    func popoverDidAppear() { surfaceDidAppear(.popover) }
    func popoverDidDisappear() { surfaceDidDisappear(.popover) }
    func dashboardDidAppear() { surfaceDidAppear(.dashboard) }
    func dashboardDidDisappear() { surfaceDidDisappear(.dashboard) }

    private func surfaceDidAppear(_ surface: Surface) {
        visibleSurfaces.insert(surface)
        Task { await refresh() }
    }

    private func surfaceDidDisappear(_ surface: Surface) {
        visibleSurfaces.remove(surface)
    }

    /// What the caller needs from a refresh.
    enum RefreshKind {
        /// The polling loop. Happy with a scan that is already running, and happy
        /// with the cached result when the listening sockets have not moved.
        case tick
        /// Follows a Stop. Must be a scan that began after the process was
        /// signalled, or the service it just killed would still be on screen.
        case afterAction
        /// The Refresh button. Also drops every cache that reads from disk, which
        /// is what picks up a manifest or an icon that changed under a live process.
        case userRequested
    }

    /// Waits for the answer, always.
    ///
    /// A caller that arrives mid-scan joins the running one. Only a `tick` is then
    /// finished, because everything else asked a question that the running scan
    /// started too early to answer.
    func refresh(_ kind: RefreshKind = .tick) async {
        if let running = inFlightRefresh {
            await running.value
            if kind == .tick { return }
        }

        let task = Task { @MainActor in await self.performRefresh(kind) }
        inFlightRefresh = task
        await task.value
        if inFlightRefresh == task { inFlightRefresh = nil }
    }

    private func performRefresh(_ kind: RefreshKind) async {
        let options = ScanOptions(
            showAllListeners: showAllListeners,
            groupSiblingRepositories: groupSiblingRepositories
        )
        do {
            let update = try await repository.refresh(
                options: options,
                reloadingFromDisk: kind == .userRequested
            )
            // `@Observable` notifies on every write, equal or not, so each of these
            // is written only when it actually moved. A blind write redraws the
            // whole dashboard on every tick.
            // Hoisted out of the branch below, because it is the only moment
            // both scans exist as values, and reported after them, because the
            // ignore filter it consults is applied in `applyFilters`.
            var appeared: [RunningService] = []
            if update.didRebuild {
                // Against `rawResult`, never `result`. A fresh scan compared to the
                // filtered value would differ forever once anything is ignored,
                // and the whole point of this branch is to skip a redraw.
                if update.result != rawResult {
                    appeared = update.result.appeared(since: rawResult)
                    rawResult = update.result
                    let relaunchable = Set(update.result.services.filter(canRelaunch).map(\.id))
                    if relaunchable != relaunchableServiceIDs { relaunchableServiceIDs = relaunchable }
                    applyFilters()
                    stubbornServiceIDs.formIntersection(Set(update.result.services.map(\.id)))
                }
                processTree = update.tree
            }
            // Unconditional, so a machine with no listeners at launch still settles
            // and the first service to start afterwards is announced properly.
            noteArrivals(appeared, kind: kind)
            await sampleTasks()
            if lastError != nil { lastError = nil }
        } catch {
            lastError = "Could not read listening ports. \(error.localizedDescription)"
        }
    }

    // MARK: - Memory and CPU

    func memory(of pid: pid_t) -> UInt64? { metrics.memory(of: pid) }
    func cpu(of pid: pid_t) -> Int? { metrics.cpu(of: pid) }

    /// A service's whole share of the CPU, summed at sample time. Empty while the
    /// preference is off, so a label reads it without depending on the preference.
    func cpu(ofServiceAt pid: pid_t) -> Int? { metrics.cpuIncludingWorkers(of: pid) }

    /// Resident memory of every visible service's listener, which is what the
    /// dashboard header reports. Workers are excluded, so this is a floor.
    ///
    /// Over a set of pids, not of services. Every container behind one forwarder
    /// is its own row pointing at the same process, so summing per row would
    /// report an eight-container stack's forwarder eight times.
    var watchedMemoryBytes: UInt64 {
        Set(result.services.map(\.listenerProcess.pid))
            .reduce(0) { $0 + (metrics.memory(of: $1) ?? 0) }
    }

    /// Only the dashboard shows memory, and CPU is off until asked for, so a
    /// machine nobody is looking at is never sampled.
    private func sampleTasks() async {
        guard let tree = processTree, wantsMemory || wantsCPU else {
            metrics.forgetEverything()
            return
        }

        // Ignored services are sampled too, so one selected under the Ignored chip
        // still reports its numbers in the detail pane. They stay out of
        // `watchedMemoryBytes`, which is the total the user asked to be rid of.
        let watched = result.services + ignoredResult.services
        // A set, because relatives include ancestors and two services under one
        // shell would otherwise be asked about the same pid twice.
        let pids = Set(watched.flatMap { tree.relatives(of: $0.listenerProcess.pid) })
        guard !pids.isEmpty else {
            metrics.forgetEverything()
            return
        }

        // Walked once here rather than once per row per redraw, which is also what
        // keeps a CPU label from depending on the tree.
        var workersByListener: [pid_t: [pid_t]] = [:]
        if wantsCPU {
            for service in watched {
                let listener = service.listenerProcess.pid
                workersByListener[listener] = tree.descendants(of: listener).map(\.pid)
            }
        }

        let sampled = await repository.sampleTasks(of: pids)
        metrics.absorb(
            sampled,
            workersByListener: workersByListener,
            keepingMemory: wantsMemory,
            keepingCPU: wantsCPU
        )
    }

    private var wantsMemory: Bool { visibleSurfaces.contains(.dashboard) }
    private var wantsCPU: Bool { showsCPU && !visibleSurfaces.isEmpty }

    // MARK: - Ignored services

    var ignoredEntries: [IgnoredService] { ignoredServices.entries }
    /// Anything on the list, running or not. The Preferences inventory.
    var hasIgnoredServices: Bool { !ignoredServices.isEmpty }
    /// Only the ones actually listening. What the dashboard chip can show.
    var hasRunningIgnoredServices: Bool { !ignoredResult.services.isEmpty }

    /// Why the list is empty, when nothing is running. Shared by the popover and
    /// the dashboard so the two never explain the same state differently.
    ///
    /// The daemon filter is checked first because it is the one that can empty a
    /// machine whose only listeners are a database and a queue, and blaming that
    /// on the ignore list would send the user to the wrong preference.
    var emptyStateMessage: String {
        if hidesDaemons, !rawResult.standalone.isEmpty {
            return "Only infrastructure and daemons are running, and those are hidden"
        }
        return hasIgnoredServices ? "Every running service is ignored" : "No development services running"
    }
    func isIgnored(_ service: RunningService) -> Bool { ignoredServices.contains(service) }
    func canIgnore(_ service: RunningService) -> Bool { ignoredServices.canIgnore(service) }

    func ignore(_ service: RunningService) {
        ignoredServices.ignore(service)
        applyFilters()
    }

    func stopIgnoring(_ service: RunningService) {
        ignoredServices.stopIgnoring(service)
        applyFilters()
    }

    func stopIgnoring(_ key: IgnoreKey) {
        ignoredServices.remove(key)
        applyFilters()
    }

    /// Splits the last scan into what the user sees and what they hid.
    ///
    /// Called on every scan and on every filter change, which is what makes both
    /// ignoring and hiding daemons redraw at once rather than waiting for the
    /// next tick. No rescan is needed because `rawResult` already holds the
    /// unfiltered truth.
    ///
    /// Membership is resolved once into a set of ids. Asking the store directly in
    /// both passes would standardise every service's path twice a tick.
    ///
    /// The daemon ids come from `rawResult.standalone`, never `result.standalone`.
    /// `keeping` rebuilds the standalone list from whatever survived, so reading
    /// it off the already-filtered projection would be self-referential.
    private func applyFilters() {
        let ignoredIDs = Set(rawResult.services.filter(ignoredServices.contains).map(\.id))
        var hiddenIDs = ignoredIDs
        if hidesDaemons { hiddenIDs.formUnion(rawResult.standalone.map(\.id)) }

        let visible = rawResult.keeping { !hiddenIDs.contains($0.id) }
        if visible != result { result = visible }

        // Ignored-only, so a daemon that is also ignored stays listed on the
        // Ignored screen and the user can still un-ignore it.
        let hidden = rawResult.keeping { ignoredIDs.contains($0.id) }
        if hidden != ignoredResult { ignoredResult = hidden }
    }

    // MARK: - Actions

    func open(_ service: RunningService) {
        guard let url = service.localURL else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ service: RunningService) {
        guard let directory = service.revealDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func reveal(_ directory: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    /// The one way anything outside this file puts a message in front of the user.
    /// `lastError` stays `private(set)` so a view cannot write one directly.
    func report(_ problem: String) { lastError = problem }

    func copyURL(_ service: RunningService) {
        copy(service.localURL?.absoluteString ?? String(service.port))
    }

    func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func stop(_ service: RunningService) async {
        busyServiceIDs.insert(service.id)
        defer { busyServiceIDs.remove(service.id) }

        let tree = await repository.processTree()
        let problem = record(await controller.stop(service, tree: tree), for: service)
        await refresh(.afterAction)
        // After the refresh, never before. A successful refresh clears `lastError`,
        // which would silently swallow the reason a stop did not work.
        if let problem { lastError = problem }
    }

    /// Stops every service under one project heading.
    func stopAll(in group: ProjectGroup) async {
        await stopEach(group.services)
    }

    /// Stops every dev server on screen, and nothing else.
    ///
    /// Databases and daemons are left alone even though they are listed, for the
    /// reason on `ServiceClass.isUserManaged`. A menu bar button two presses from
    /// the user's Postgres is a bad trade for a rare want, and Restart already
    /// draws the same line.
    func stopAllVisible() async {
        await stopEach(stoppableServices)
    }

    var stoppableServices: [RunningService] {
        result.services.filter(\.classification.isUserManaged)
    }

    /// Concurrent rather than sequential, because each stop waits out a three
    /// second grace period and four in a row would freeze the popover for twelve.
    /// The tree is read once and shared, which is safe because `ProcessController`
    /// re-reads each pid's identity from the kernel immediately before it signals.
    private func stopEach(_ services: [RunningService]) async {
        guard !services.isEmpty else { return }

        busyServiceIDs.formUnion(services.map(\.id))
        defer { busyServiceIDs.subtract(services.map(\.id)) }

        let tree = await repository.processTree()
        let outcomes = await withTaskGroup(of: StopReport.self) { work in
            for service in services {
                work.addTask { [controller] in
                    StopReport(service: service, outcome: await controller.stop(service, tree: tree))
                }
            }
            var reports: [StopReport] = []
            for await report in work { reports.append(report) }
            return reports
        }

        let problems = outcomes.compactMap { record($0.outcome, for: $0.service) }
        await refresh(.afterAction)
        if !problems.isEmpty { lastError = problems.joined(separator: " ") }
    }

    private struct StopReport: Sendable {
        let service: RunningService
        let outcome: ProcessController.Outcome
    }

    /// Applies one stop outcome to the stubborn set and returns a message when the
    /// user needs to know something. `notFound` is silent on purpose, since a
    /// service can legitimately have died in a sibling's orphan sweep.
    func record(_ outcome: ProcessController.Outcome, for service: RunningService) -> String? {
        switch outcome {
        case .exited, .notFound:
            stubbornServiceIDs.remove(service.id)
            return nil
        case .exitedLeavingChildren(let pids):
            stubbornServiceIDs.remove(service.id)
            let list = pids.map(String.init).joined(separator: ", ")
            let plural = pids.count == 1 ? "" : "es"
            return "\(service.displayName) stopped. \(pids.count) child process\(plural) ignored the stop signal: PID \(list)."
        case .stillRunning:
            stubbornServiceIDs.insert(service.id)
            return nil
        case .notPermitted:
            return "\(service.displayName) belongs to another user, so Portfox cannot stop it."
        case .refused(let reason):
            return "Portfox will not signal a \(reason)."
        }
    }

    func forceStop(_ service: RunningService) async {
        busyServiceIDs.insert(service.id)
        defer { busyServiceIDs.remove(service.id) }

        guard let tree = await repository.processTree() else { return }
        var problem: String?
        if case .refused(let reason) = await controller.forceStop(service, tree: tree) {
            problem = "Portfox will not signal a \(reason)."
        }
        stubbornServiceIDs.remove(service.id)
        await refresh(.afterAction)
        if let problem { lastError = problem }
    }

    func isStubborn(_ service: RunningService) -> Bool { stubbornServiceIDs.contains(service.id) }
    func isBusy(_ service: RunningService) -> Bool { busyServiceIDs.contains(service.id) }

    /// The only way another file marks a row mid-action. `busyServiceIDs` stays
    /// `private(set)` so a view cannot dim a row it does not own.
    func markBusy(_ service: RunningService) { busyServiceIDs.insert(service.id) }
    func clearBusy(_ service: RunningService) { busyServiceIDs.remove(service.id) }
}
