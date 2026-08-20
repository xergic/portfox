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
    /// The tree from the last scan. The dashboard renders it, and stopping needs
    /// it to sweep orphans.
    private(set) var processTree: ProcessTree?
    /// Resident memory by pid. Held apart from `ScanResult` so a number that moves
    /// on every sample cannot invalidate a scan that did not move.
    private var memoryByPID: [pid_t: UInt64] = [:]

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
    }

    private let repository = ServiceRepository()
    private let controller = ProcessController()
    private let assetScanner = ProjectAssetScanner()
    private let iconOverrides = ProjectIconOverrides()
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
            Key.showsMenuBarCount: true
        ])
        showAllListeners = defaults.bool(forKey: Key.showAllListeners)
        groupSiblingRepositories = defaults.bool(forKey: Key.groupSiblingRepositories)
        cellLayout = ServiceCellLayout(rawValue: defaults.string(forKey: Key.cellLayout) ?? "") ?? .serviceFirst
        automaticRefresh = defaults.bool(forKey: Key.automaticRefresh)
        pollingSeconds = defaults.integer(forKey: Key.pollingSeconds)
        showsMenuBarCount = defaults.bool(forKey: Key.showsMenuBarCount)
        hidesDaemons = defaults.bool(forKey: Key.hidesDaemons)
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
            if update.didRebuild {
                // Against `rawResult`, never `result`. A fresh scan compared to the
                // filtered value would differ forever once anything is ignored,
                // and the whole point of this branch is to skip a redraw.
                if update.result != rawResult {
                    rawResult = update.result
                    applyFilters()
                    stubbornServiceIDs.formIntersection(Set(update.result.services.map(\.id)))
                }
                processTree = update.tree
            }
            await sampleMemory()
            if lastError != nil { lastError = nil }
        } catch {
            lastError = "Could not read listening ports. \(error.localizedDescription)"
        }
    }

    // MARK: - Memory

    func memory(of pid: pid_t) -> UInt64? { memoryByPID[pid] }

    /// Resident memory of every visible service's listener, which is what the
    /// dashboard header reports. Workers are excluded, so this is a floor.
    var watchedMemoryBytes: UInt64 {
        result.services.reduce(0) { $0 + (memoryByPID[$1.listenerProcess.pid] ?? 0) }
    }

    /// Only the dashboard shows memory, so nothing is sampled while it is closed.
    private func sampleMemory() async {
        guard visibleSurfaces.contains(.dashboard), let tree = processTree else {
            if !memoryByPID.isEmpty { memoryByPID = [:] }
            return
        }

        // Ignored services are sampled too, so one selected under the Ignored chip
        // still reports resident memory in its detail pane. They stay out of
        // `watchedMemoryBytes`, which is the number the user asked to be rid of.
        let watched = result.services + ignoredResult.services
        // A set, because relatives include ancestors and two services under one
        // shell would otherwise be asked about the same pid twice.
        let pids = Set(watched.flatMap { tree.relatives(of: $0.listenerProcess.pid) })
        let sampled = await repository.sampleResidentMemory(of: pids)
        if sampled != memoryByPID { memoryByPID = sampled }
    }

    // MARK: - Ignored services

    var ignoredEntries: [IgnoredService] { ignoredServices.entries }
    /// Anything on the list, running or not. The Preferences inventory.
    var hasIgnoredServices: Bool { !ignoredServices.isEmpty }
    /// Only the ones actually listening. What the dashboard chip can show.
    var hasRunningIgnoredServices: Bool { !ignoredResult.services.isEmpty }

    /// Why the list is empty, when nothing is running. Shared by the popover and
    /// the dashboard so the two never explain the same state differently.
    var emptyStateMessage: String {
        hasIgnoredServices ? "Every running service is ignored" : "No development services running"
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

    // MARK: - Project icons

    /// The user's chosen icon, or whatever the resolver found on disk.
    func iconPath(for group: ProjectGroup) -> String? {
        iconOverrides.iconPath(forProjectAt: group.project.root) ?? group.project.iconPath
    }

    func hasIconOverride(for group: ProjectGroup) -> Bool {
        iconOverrides.hasOverride(forProjectAt: group.project.root)
    }

    func setIcon(_ path: String?, for group: ProjectGroup) {
        iconOverrides.set(path, forProjectAt: group.project.root)
    }

    /// Images the user could pick. A sibling group has no manifests of its own,
    /// so every member project is scanned and the results merged.
    func projectAssets(for group: ProjectGroup) -> [ProjectAsset] {
        var seen: Set<String> = []
        var found: [ProjectAsset] = []

        for snapshot in group.services.compactMap(\.project) {
            for asset in assetScanner.assets(in: snapshot) where seen.insert(asset.path).inserted {
                found.append(asset)
            }
        }
        return found
    }

    func copyURL(_ service: RunningService) {
        let value = service.localURL?.absoluteString ?? String(service.port)
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
    ///
    /// Concurrent rather than sequential, because each stop waits out a three
    /// second grace period and four in a row would freeze the popover for twelve.
    /// The tree is read once and shared, which is safe because `ProcessController`
    /// re-reads each pid's identity from the kernel immediately before it signals.
    func stopAll(in group: ProjectGroup) async {
        let services = group.services
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
    private func record(_ outcome: ProcessController.Outcome, for service: RunningService) -> String? {
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
}
