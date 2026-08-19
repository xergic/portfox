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

    private enum Key {
        static let showAllListeners = "showAllListeners"
        static let groupSiblingRepositories = "groupSiblingRepositories"
    }

    private let repository = ServiceRepository()
    private let controller = ProcessController()
    private let defaults = UserDefaults.standard

    /// Refreshing every two seconds only matters while the user is looking. When
    /// the popover is closed the count badge is the only live element.
    private let visibleInterval = Duration.seconds(2)
    private let hiddenInterval = Duration.seconds(15)

    private var isPopoverVisible = false
    private var refreshTask: Task<Void, Never>?

    var serviceCount: Int { result.services.count }

    init() {
        defaults.register(defaults: [Key.groupSiblingRepositories: true])
        showAllListeners = defaults.bool(forKey: Key.showAllListeners)
        groupSiblingRepositories = defaults.bool(forKey: Key.groupSiblingRepositories)
        start()
    }

    func start() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.currentInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    private var currentInterval: Duration { isPopoverVisible ? visibleInterval : hiddenInterval }

    func popoverDidAppear() {
        isPopoverVisible = true
        Task { await refresh() }
    }

    func popoverDidDisappear() {
        isPopoverVisible = false
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

    func copyURL(_ service: RunningService) {
        let value = service.localURL?.absoluteString ?? String(service.port)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func stop(_ service: RunningService) async {
        busyServiceIDs.insert(service.id)
        defer { busyServiceIDs.remove(service.id) }

        let tree = await repository.processTree()
        switch await controller.stop(service, tree: tree) {
        case .exited:
            stubbornServiceIDs.remove(service.id)
        case .exitedLeavingChildren(let pids):
            stubbornServiceIDs.remove(service.id)
            let list = pids.map(String.init).joined(separator: ", ")
            let plural = pids.count == 1 ? "" : "es"
            lastError = "\(service.displayName) stopped. \(pids.count) child process\(plural) ignored the stop signal: PID \(list)."
        case .stillRunning:
            stubbornServiceIDs.insert(service.id)
        case .notPermitted:
            lastError = "\(service.displayName) belongs to another user, so PortFox cannot stop it."
        case .notFound:
            stubbornServiceIDs.remove(service.id)
        case .refused(let reason):
            lastError = "PortFox will not signal a \(reason)."
        }
        await refresh()
    }

    func forceStop(_ service: RunningService) async {
        busyServiceIDs.insert(service.id)
        defer { busyServiceIDs.remove(service.id) }

        guard let tree = await repository.processTree() else { return }
        if case .refused(let reason) = await controller.forceStop(service, tree: tree) {
            lastError = "PortFox will not signal a \(reason)."
        }
        stubbornServiceIDs.remove(service.id)
        await refresh()
    }

    func isStubborn(_ service: RunningService) -> Bool { stubbornServiceIDs.contains(service.id) }
    func isBusy(_ service: RunningService) -> Bool { busyServiceIDs.contains(service.id) }
}
