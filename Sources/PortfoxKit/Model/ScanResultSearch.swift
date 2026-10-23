import Foundation

extension ScanResult {
    /// The result narrowed to services matching `query`, case-insensitively.
    /// Shared by the popover and the dashboard so one search box never finds what
    /// the other misses.
    ///
    /// A number matches a port or an exact pid, and `3000-3999` matches a port in
    /// that range. Only any other query reaches the command line, because every
    /// argv is full of digits and a port search would match them all.
    public func matching(_ query: String) -> ScanResult {
        guard let search = ServiceSearch(query) else { return self }
        return keeping(search.accepts)
    }

    /// Every service in the order both surfaces draw them: project groups, then
    /// infrastructure, agent tools and the rest. The order the arrow keys walk.
    public var drawingOrder: [RunningService] {
        groups.flatMap(\.services) + standalone + agentTools + ungrouped
    }
}

private enum ServiceSearch {
    case number(String)
    case portRange(ClosedRange<Int>)
    case text(String)

    init?(_ query: String) {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return nil }
        if needle.allSatisfy(\.isNumber) {
            self = .number(needle)
        } else if let range = Self.portRange(needle) {
            self = .portRange(range)
        } else {
            self = .text(needle)
        }
    }

    private static func portRange(_ needle: String) -> ClosedRange<Int>? {
        let bounds = needle.split(separator: "-", omittingEmptySubsequences: false)
            .map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard bounds.count == 2, let lower = bounds[0], let upper = bounds[1], lower <= upper else { return nil }
        return lower...upper
    }

    /// Every socket, ephemeral ones included. `secondaryPorts` drops those from
    /// the row, but a port read off a log line still has to find its service.
    func accepts(_ service: RunningService) -> Bool {
        switch self {
        case .number(let digits):
            let pid = pid_t(digits)
            return service.sockets.contains { String($0.port).contains(digits) }
                || service.listenerProcess.pid == pid || service.rootProcess.pid == pid
        case .portRange(let range):
            return service.sockets.contains { range.contains($0.port) }
        case .text(let needle):
            func has(_ text: String?) -> Bool { text?.range(of: needle, options: .caseInsensitive) != nil }
            // The command lines last, because joining an argv is the one costly field.
            return has(service.displayName) || has(service.project?.name) || has(service.subtitle)
                || has(service.listenerProcess.executableName)
                || has(service.container?.name) || has(service.container?.image)
                || has(service.listenerProcess.command) || has(service.rootProcess.command)
        }
    }
}
