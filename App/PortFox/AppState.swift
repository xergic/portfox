import Foundation
import PortFoxKit
import SwiftUI

/// UI-facing state. Owns the refresh loop and forwards actions to the kit.
@MainActor
@Observable
final class AppState {
    private(set) var result: ScanResult = .empty
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    /// Services whose Stop was delivered but which are still alive.
    private(set) var stubbornServiceIDs: Set<String> = []
    private(set) var busyServiceIDs: Set<String> = []
    /// The tree from the last scan. The dashboard renders it, and stopping needs
    /// it to sweep orphans.
    private(set) var processTree: ProcessTree?

    /// Set before the dashboard is opened, so the sheet is already requested on
    /// the window's first layout pass rather than a turn too late.
    var presentedSheet: DashboardSheet?

    enum DashboardSheet: String, Identifiable {
        case preferences
        var id: String { rawValue }
    }

    var showAllListeners: Bool {
        didSet {
            defaults.set(showAllListeners, forKey: Key.showAllListeners)
            Task { await refresh() }
        }
    }

    var groupSiblingRepositories: Bool {
        didSet {
            defaults.set(groupSiblingRepositories, forKey: Key.groupSiblingRepositories)
            Task { await refresh() }
        }
    }

    var cellLayout: ServiceCellLayout {
        didSet { defaults.set(cellLayout.rawValue, forKey: Key.cellLayout) }
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
    }

    private let repository = ServiceRepository()
    private let controller = ProcessController()
    private let assetScanner = ProjectAssetScanner()
    private let iconOverrides = ProjectIconOverrides()
    private let defaults = UserDefaults.standard

    /// Refreshing on the polling interval only matters while the user is looking.
    /// With every window closed the count badge is the only live element.
    private let hiddenInterval = Duration.seconds(15)

    /// A set rather than a counter, so a repeated appear or a missed disappear
    /// cannot leave the app stuck on the fast interval forever.
    private enum Surface: Hashable {
        case popover
        case dashboard
    }

    private var visibleSurfaces: Set<Surface> = []
    private var refreshTask: Task<Void, Never>?

    var serviceCount: Int { result.services.count }

    init() {
        defaults.register(defaults: [
            Key.groupSiblingRepositories: true,
            Key.automaticRefresh: true,
            Key.pollingSeconds: 2
        ])
        showAllListeners = defaults.bool(forKey: Key.showAllListeners)
        groupSiblingRepositories = defaults.bool(forKey: Key.groupSiblingRepositories)
        cellLayout = ServiceCellLayout(rawValue: defaults.string(forKey: Key.cellLayout) ?? "") ?? .serviceFirst
        automaticRefresh = defaults.bool(forKey: Key.automaticRefresh)
        pollingSeconds = defaults.integer(forKey: Key.pollingSeconds)
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

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let options = ScanOptions(
            showAllListeners: showAllListeners,
            groupSiblingRepositories: groupSiblingRepositories
        )
        do {
            result = try await repository.refresh(options: options)
            processTree = await repository.processTree()
            lastError = nil
            stubbornServiceIDs.formIntersection(Set(result.services.map(\.id)))
        } catch {
            lastError = "Could not read listening ports. \(error.localizedDescription)"
        }
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
        await refresh()
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
        await refresh()
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
            return "\(service.displayName) belongs to another user, so PortFox cannot stop it."
        case .refused(let reason):
            return "PortFox will not signal a \(reason)."
        }
    }

    func forceStop(_ service: RunningService) async {
        busyServiceIDs.insert(service.id)
        defer { busyServiceIDs.remove(service.id) }

        guard let tree = await repository.processTree() else { return }
        var problem: String?
        if case .refused(let reason) = await controller.forceStop(service, tree: tree) {
            problem = "PortFox will not signal a \(reason)."
        }
        stubbornServiceIDs.remove(service.id)
        await refresh()
        if let problem { lastError = problem }
    }

    func isStubborn(_ service: RunningService) -> Bool { stubbornServiceIDs.contains(service.id) }
    func isBusy(_ service: RunningService) -> Bool { busyServiceIDs.contains(service.id) }
}
