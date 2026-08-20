import Foundation

/// One piece of scored evidence.
///
/// Signals sharing a `group` are alternatives: only the highest-weight match in a
/// group contributes, and the group contributes its best weight to the confidence
/// denominator exactly once. That models "the command identifies this, either
/// strongly via the bin path or weakly via an argument" without hand-written
/// `&& !alreadyMatched` guards.
public struct Signal: Sendable {
    public let description: String
    public let weight: Int
    /// When matched, the detector is disqualified outright regardless of score.
    public let isVeto: Bool
    /// Alternatives share a group name. `nil` means the signal scores independently.
    public let group: String?
    public let matches: @Sendable (DetectionContext) -> Bool

    public init(
        _ description: String,
        weight: Int,
        isVeto: Bool = false,
        group: String? = nil,
        matches: @escaping @Sendable (DetectionContext) -> Bool
    ) {
        self.description = description
        self.weight = weight
        self.isVeto = isVeto
        self.group = group
        self.matches = matches
    }
}

// MARK: - DSL

public extension Signal {
    /// The executable or command references `node_modules/.bin/<tool>` or a
    /// path segment ending in `/<tool>`. The strongest available signal.
    static func binPath(_ tool: String, _ weight: Int, group: String? = "command") -> Signal {
        let tool = tool.lowercased()
        // Built once when the catalogue is assembled, not per process. This is
        // the most-used helper in the DSL and it runs on every refresh tick.
        let needles = ["node_modules/.bin/\(tool)", "/bin/\(tool)", "/\(tool)/bin/", "/\(tool).mjs", "/\(tool).js"]
        return Signal("command contains node_modules/.bin/\(tool)", weight: weight, group: group) { ctx in
            needles.contains { ctx.command.containsToken($0) || ctx.executablePath.containsToken($0) }
        }
    }

    /// A process inside an application bundle belongs to that app, whatever its
    /// runtime. Detection is consulted before `ListenerClassifier`'s own bundle
    /// rule, so a generic runtime detector has to refuse these itself.
    static func vetoAppBundle() -> Signal {
        .veto("an executable inside an application bundle belongs to that app") { $0.isInsideAppBundle }
    }

    static func commandContains(_ needle: String, _ weight: Int, group: String? = "command") -> Signal {
        Signal("command contains \"\(needle)\"", weight: weight, group: group) { ctx in
            ctx.command.containsToken(needle.lowercased())
        }
    }

    /// Matches the command line of this process or any process in its tree.
    static func treeCommandContains(_ needle: String, _ weight: Int, group: String? = "command") -> Signal {
        Signal("process tree command contains \"\(needle)\"", weight: weight, group: group) { ctx in
            ctx.anyCommandContains(needle)
        }
    }

    /// Exact match on the executable's last path component.
    static func executableNamed(_ name: String, _ weight: Int, group: String? = "command") -> Signal {
        let name = name.lowercased()
        return Signal("executable is \(name)", weight: weight, group: group) { ctx in
            ctx.executableName == name
        }
    }

    static func executableNameContains(_ needle: String, _ weight: Int, group: String? = "command") -> Signal {
        let needle = needle.lowercased()
        return Signal("executable name contains \"\(needle)\"", weight: weight, group: group) { ctx in
            ctx.executableName.containsToken(needle)
        }
    }

    /// A config file whose name starts with `prefix`, so `vite.config` matches
    /// `.ts`, `.js` and `.mjs` variants.
    static func configFile(_ prefix: String, _ weight: Int, group: String? = nil) -> Signal {
        Signal("\(prefix).* exists", weight: weight, group: group) { ctx in
            ctx.project?.hasFile(prefix: prefix) ?? false
        }
    }

    static func dependency(_ name: String, _ weight: Int, group: String? = nil) -> Signal {
        Signal("manifest depends on \(name)", weight: weight, group: group) { ctx in
            ctx.project?.hasDependency(name) ?? false
        }
    }

    static func anyDependency(_ names: [String], _ weight: Int, group: String? = nil) -> Signal {
        Signal("manifest depends on one of \(names.joined(separator: ", "))", weight: weight, group: group) { ctx in
            guard let project = ctx.project else { return false }
            return names.contains { project.hasDependency($0) }
        }
    }

    /// A weak supporting hint only. Never enough to identify a service on its own.
    static func defaultPort(_ port: Int, _ weight: Int = 10, group: String? = "port") -> Signal {
        Signal("listening on default port \(port)", weight: weight, group: group) { ctx in
            ctx.ports.contains(port)
        }
    }

    static func defaultPorts(_ ports: [Int], _ weight: Int = 10, group: String? = "port") -> Signal {
        let list = ports.map(String.init).joined(separator: " or ")
        return Signal("listening on default port \(list)", weight: weight, group: group) { ctx in
            ctx.ports.contains { ports.contains($0) }
        }
    }

    /// Disqualifies the detector when matched.
    static func veto(_ description: String, _ matches: @escaping @Sendable (DetectionContext) -> Bool) -> Signal {
        Signal(description, weight: 0, isVeto: true, matches: matches)
    }

    static func vetoCommandContains(_ needle: String) -> Signal {
        .veto("command contains \"\(needle)\"") { $0.command.containsToken(needle.lowercased()) }
    }

    static func custom(
        _ description: String,
        _ weight: Int,
        group: String? = nil,
        matches: @escaping @Sendable (DetectionContext) -> Bool
    ) -> Signal {
        Signal(description, weight: weight, group: group, matches: matches)
    }
}
