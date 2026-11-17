import Foundation
import Testing
@testable import PortfoxKit

@Suite("agent session markers")
struct AgentSessionMarkerTests {
    @Test("Claude Code's session id and pid are read")
    func claudeMarkerParsed() {
        let marker = AgentSessionMarker(environment: ["CLAUDECODE=1", "CLAUDE_CODE_SESSION_ID=abc", "CLAUDE_PID=42"])
        #expect(marker == AgentSessionMarker(kind: .claudeCode, sessionID: "abc", agentPID: 42))
    }

    @Test("Codex's thread id is read")
    func codexMarkerParsed() {
        let marker = AgentSessionMarker(environment: ["PATH=/usr/bin", "CODEX_THREAD_ID=t1"])
        #expect(marker == AgentSessionMarker(kind: .codex, sessionID: "t1", agentPID: nil))
    }

    @Test("Codex wins when it ran inside Claude Code")
    func codexWinsWhenNested() {
        let marker = AgentSessionMarker(environment: [
            "CLAUDECODE=1", "CLAUDE_CODE_SESSION_ID=abc", "CLAUDE_PID=42", "CODEX_THREAD_ID=t1",
        ])
        #expect(marker?.kind == .codex)
        #expect(marker?.sessionID == "t1")
    }

    @Test("a Claude session id without CLAUDECODE=1 is not a marker")
    func claudeNeedsFlag() {
        #expect(AgentSessionMarker(environment: ["CLAUDE_CODE_SESSION_ID=abc"]) == nil)
        #expect(AgentSessionMarker(environment: ["CODEX_THREAD_ID="]) == nil)
    }

    @Test("marker text in argv is not the environment")
    func markerInArgvIgnored() {
        var buffer = withUnsafeBytes(of: Int32(2)) { Array($0) }
        buffer += Array("/usr/bin/grep".utf8) + [0, 0, 0]
        for entry in ["grep", "CODEX_THREAD_ID=x", "PATH=/usr/bin"] { buffer += Array(entry.utf8) + [0] }

        #expect(ProcessInspector.environment(in: buffer) == ["PATH=/usr/bin"])
        #expect(ProcessInspector.parseProcArgs(buffer) == ["grep", "CODEX_THREAD_ID=x"])
    }
}

@Suite("agent session titles")
struct AgentSessionTitleTests {
    private func line(_ object: [String: String]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data ?? Data(), as: UTF8.self)
    }

    @Test("Claude Code's title is the last ai-title in the session file")
    func claudeTitleFromTail() {
        let home = TempTree()
        defer { home.cleanUp() }
        let lines = [
            line(["type": "ai-title", "aiTitle": "First idea"]),
            line(["type": "user", "message": "hi"]),
            line(["type": "ai-title", "aiTitle": "Fix flaky payment tests"]),
        ]
        home.write(lines.joined(separator: "\n") + "\n", at: ".claude/projects/-Users-me-shop/abc.jsonl")

        let titles = AgentSessionTitles(home: home.root)
        let marker = AgentSessionMarker(kind: .claudeCode, sessionID: "abc", agentPID: nil)
        #expect(titles.title(for: marker) == "Fix flaky payment tests")
    }

    @Test("Codex's title is the last thread name for the id")
    func codexTitleFromIndex() {
        let home = TempTree()
        defer { home.cleanUp() }
        let lines = [
            line(["id": "t1", "thread_name": "Old name"]),
            line(["id": "t2", "thread_name": "Someone else"]),
            line(["id": "t1", "thread_name": "Checkout flow redesign"]),
        ]
        home.write(lines.joined(separator: "\n") + "\n", at: ".codex/session_index.jsonl")

        let titles = AgentSessionTitles(home: home.root)
        let marker = AgentSessionMarker(kind: .codex, sessionID: "t1", agentPID: nil)
        #expect(titles.title(for: marker) == "Checkout flow redesign")
    }

    @Test("a missing file, an empty title or no ~/.codex gives nil")
    func titleMissingIsNil() {
        let home = TempTree()
        defer { home.cleanUp() }
        home.write(line(["type": "ai-title", "aiTitle": ""]) + "\n", at: ".claude/projects/p/empty.jsonl")

        let titles = AgentSessionTitles(home: home.root)
        #expect(titles.title(for: AgentSessionMarker(kind: .claudeCode, sessionID: "empty", agentPID: nil)) == nil)
        #expect(titles.title(for: AgentSessionMarker(kind: .claudeCode, sessionID: "absent", agentPID: nil)) == nil)
        #expect(titles.title(for: AgentSessionMarker(kind: .codex, sessionID: "t1", agentPID: nil)) == nil)
    }
}
