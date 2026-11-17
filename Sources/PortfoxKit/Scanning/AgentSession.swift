import Foundation

/// The agent session a process was started from, read from the variables the
/// agent puts in the environment of everything it runs. It outlives the agent,
/// which is how a server can say its session ended rather than just "orphaned".
public struct AgentSessionMarker: Hashable, Codable, Sendable {
    public let kind: AgentKind
    public let sessionID: String
    /// Claude Code's own pid. Codex records none.
    public let agentPID: pid_t?

    public init(kind: AgentKind, sessionID: String, agentPID: pid_t?) {
        self.kind = kind
        self.sessionID = sessionID
        self.agentPID = agentPID
    }

    /// Codex wins when both are present: Codex started from Claude Code inherits
    /// Claude's variables and adds its own, and that is the usual nesting.
    init?(environment entries: [String]) {
        var values: [Substring: Substring] = [:]
        for entry in entries {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            values[entry[..<equals]] = entry[entry.index(after: equals)...]
        }
        if let thread = values["CODEX_THREAD_ID"], !thread.isEmpty {
            self.init(kind: .codex, sessionID: String(thread), agentPID: nil)
        } else if values["CLAUDECODE"] == "1", let session = values["CLAUDE_CODE_SESSION_ID"], !session.isEmpty {
            self.init(kind: .claudeCode, sessionID: String(session), agentPID: values["CLAUDE_PID"].flatMap { pid_t($0) })
        } else {
            return nil
        }
    }
}

/// A session's title, from the agents' own files. Neither format is documented,
/// so anything unexpected is nil rather than an error.
public struct AgentSessionTitles: Sendable {
    /// Claude Code appends a new `ai-title` line as the title changes, and a
    /// session file can run to hundreds of megabytes.
    static let tailBytes: UInt64 = 2 << 20

    private let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func title(for marker: AgentSessionMarker) -> String? {
        switch marker.kind {
        case .claudeCode: claudeTitle(sessionID: marker.sessionID)
        case .codex: codexTitle(threadID: marker.sessionID)
        }
    }

    private func claudeTitle(sessionID: String) -> String? {
        let projects = home.appendingPathComponent(".claude/projects")
        guard let folders = try? FileManager.default.contentsOfDirectory(atPath: projects.path) else { return nil }
        for folder in folders {
            let file = projects.appendingPathComponent(folder).appendingPathComponent("\(sessionID).jsonl")
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            return lastValue(in: tail(of: file), key: "aiTitle") { $0.contains("\"ai-title\"") }
        }
        return nil
    }

    private func codexTitle(threadID: String) -> String? {
        let index = home.appendingPathComponent(".codex/session_index.jsonl")
        guard let data = FileManager.default.contents(atPath: index.path) else { return nil }
        return lastValue(in: data, key: "thread_name") { line in
            line.contains(threadID) && (Self.object(line)?["id"] as? String) == threadID
        }
    }

    private func tail(of file: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return Data() }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > Self.tailBytes ? size - Self.tailBytes : 0)
        return (try? handle.readToEnd()) ?? Data()
    }

    private func lastValue(in data: Data, key: String, where matches: (String) -> Bool) -> String? {
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        for line in lines.reversed() {
            let text = String(line)
            guard matches(text), let value = Self.object(text)?[key] as? String, !value.isEmpty else { continue }
            return value
        }
        return nil
    }

    private static func object(_ line: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    }
}
