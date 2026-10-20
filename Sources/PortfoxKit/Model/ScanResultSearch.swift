import Foundation

extension ScanResult {
    /// The result narrowed to services whose port, name, project, folder, binary
    /// or container contains `query`, case-insensitively. Shared by the popover
    /// and the dashboard so one search box never finds what the other misses.
    public func matching(_ query: String) -> ScanResult {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return self }
        return keeping { $0.matches(needle) }
    }

    /// Every service in the order both surfaces draw them: project groups, then
    /// infrastructure, agent tools and the rest. The order the arrow keys walk.
    public var drawingOrder: [RunningService] {
        groups.flatMap(\.services) + standalone + agentTools + ungrouped
    }
}

extension RunningService {
    fileprivate func matches(_ needle: String) -> Bool {
        let haystack = [
            String(port),
            displayName,
            project?.name,
            subtitle,
            listenerProcess.executableName,
            container?.name,
            container?.image
        ]
        return haystack.contains { $0?.range(of: needle, options: .caseInsensitive) != nil }
    }
}
