# Seshka Takeaways Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show memory freed by a stop, idle time on agent servers with a configurable limit, and ended Claude Code / Codex sessions with their titles.

**Architecture:** Pure logic and file reading go in `PortfoxKit` with Swift Testing tests. `AppState` and small `@Observable` holders wire them into the popover and dashboard. Session titles stay out of `ScanResult`, in an app-side dictionary filled off the main actor.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, Swift Testing, `make lint`, `make test`, `make app`, `make snapshot`.

**Spec:** `docs/superpowers/specs/2026-11-17-seshka-takeaways-design.md`

## Global Constraints

- The kit never imports SwiftUI or AppKit.
- Never write to `@Observable` state unless the value moved.
- Every signal still goes through `markStopping`. No new SIGKILL path.
- Telemetry signals unchanged. No names, paths or session ids in any signal.
- Undocumented sources (env markers, `~/.claude/projects`, `~/.codex/session_index.jsonl`) degrade silently to today's behaviour.
- No comments that restate code. Commits: Conventional Commits, one short sentence, no body.
- Each task ends with `make lint` clean, `make test` green, `make app` succeeding, and one commit.

## Review Focus

1. A pid recycled between the memory sample and the stop must not count as freed. (Task 1, `freedSkipsRecycledPid`)
2. A server that daemonized away from a live Claude session must not read as ended. (Task 3, `liveClaudePidKeepsAgent`)
3. Marker text inside argv, such as `grep CODEX_THREAD_ID=x`, must not count. (Task 3, `markerInArgvIgnored`)
4. A Claude session file without any `aiTitle` returns nil, and a missing `~/.codex` does not throw. (Task 3, `titleMissingIsNil`)
5. Turning idle warnings off clears every idle label. (Task 2, `IdleAlerts.reset` clears `idleMinutes`, checked by snapshot with the preference off)

---

### Task 1: Freed memory after a stop

**Files:**
- Create: `Sources/PortfoxKit/Actions/StopFootprint.swift`
- Create: `App/Portfox/FreedMemory.swift`
- Modify: `App/Portfox/AppState.swift` (`stop`, `stopEach`, `forceStop`, around lines 436-540)
- Modify: `App/Portfox/Views/MenuView.swift` (`footer`, line 221), `App/Portfox/Views/Dashboard/DashboardContent.swift` (`topBar`, beside `WatchedMemoryLabel`)
- Test: `Tests/PortfoxKitTests/Actions/StopFootprintTests.swift`
- Also: `CHANGELOG.md` (new `## [Unreleased]` / `### Added`), `README.md` features list, and the spec file from `docs/superpowers/specs/`

**Interfaces:**
- Produces:
  - `public struct StopFootprint: Sendable, Equatable` with `public let residentByIdentity: [String: UInt64]` (key: `ProcessSnapshot.identity`).
  - `public static func measure(_ service: RunningService, tree: ProcessTree, sample: (pid_t) -> UInt64?) -> StopFootprint`: root plus `tree.descendants(of: root.pid)`, each pid once. Returns empty for a service with a `container`.
  - `public func freed(isAlive: (String) -> Bool) -> UInt64`: sums entries whose identity is no longer alive.
  - App: `@MainActor @Observable final class FreedMemory` with `private(set) var bytes: UInt64` and `func add(_ bytes: UInt64)`. A non-zero add accumulates and restarts a 6 s hide timer. When it expires, `bytes` goes back to 0.
  - `AppState.freedMemory: FreedMemory`.

- [ ] **Step 1: Write the failing tests** in `StopFootprintTests.swift`:
  - `measureCountsRootAndDescendantsOnce`: a tree root 10 → child 11 → grandchild 12, sample returns 100 for each. Expect the sum of `residentByIdentity` to be 300 and its count to be 3.
  - `freedCountsOnlyExited`: footprint {a: 100, b: 50}, `isAlive` true for "b". Expect `freed == 100`.
  - `freedSkipsRecycledPid`: identity "10@1000" sampled. `isAlive` is called with that identity, and a new process on pid 10 has a different identity, so it reads as gone. Expect 100. Also check the inverse: same identity alive, expect 0.
  - `containerRowMeasuresNothing`: a service with a `container`. Expect an empty footprint.
- [ ] **Step 2:** `swift test --filter StopFootprintTests`. Expected: fails to compile (`StopFootprint` undefined).
- [ ] **Step 3:** Implement `StopFootprint` with the signatures above. `isAlive` in the app is `{ id in inspector.currentIdentity(pid: pidOf(id)) == id }`. Keep a pid next to each identity (`[String: (pid: pid_t, bytes: UInt64)]` is fine internally), so `freed` can take `isAlive: (pid_t, String) -> Bool` if that reads better. Pick one and keep it consistent.
- [ ] **Step 4:** `swift test --filter StopFootprintTests`. Expected: PASS.
- [ ] **Step 5:** Wire `AppState`:
  - In `stop`, `forceStop` and inside each `stopEach` task, measure right after the tree is read and before the controller signals. Sample with `ProcessInspector().taskSample(pid:)?.residentBytes`.
  - After the outcomes are in and before `refresh`, call `freedMemory.add` with the sum of `freed(...)`.
  - The idle banner's `stop(identifiedBy:)` and `stopAndCopyCommand` reach `stop`, so they need nothing extra. Confirm that `stopAndCopyCommand` does.
- [ ] **Step 6:** Views:
  - Add `FreedMemoryLabel` (in `MenuView.swift` or `Components.swift`). It shows "Freed ~850 MB", formatted with `ByteCountFormatter` `.memory`, in `Theme.success` or the existing positive tint. It renders `EmptyView` at 0.
  - Popover: in `footer`, before `Spacer()`.
  - Dashboard: in `topBar`, after `WatchedMemoryLabel()`.
- [ ] **Step 7:** `make lint && make test && make app`. Then `make snapshot` with a temporary `freedMemory.add(850 << 20)` in the snapshot path. Look at the popover and dashboard PNGs, then revert the temporary line.
- [ ] **Step 8:** CHANGELOG `## [Unreleased]` → `### Added`: "After a stop, the popover and dashboard say roughly how much memory came back." Add a README line. Commit with the spec file:
  `git commit -m "feat(stop): show memory freed after stopping services"`

### Task 2: Idle time on rows and a configurable limit

**Files:**
- Modify: `Sources/PortfoxKit/Alerts/IdleWatch.swift`
- Modify: `App/Portfox/IdleAlerts.swift`, `App/Portfox/AppStateIdleAlerts.swift`
- Modify: `App/Portfox/Views/WarningPreferences.swift`, `App/Portfox/Views/ServiceRowView.swift` (badge area near line 187), `App/Portfox/Views/Dashboard/ServiceDetailPane.swift` (origin rows near line 62)
- Test: `Tests/PortfoxKitTests/Alerts/IdleWatchTests.swift`

**Interfaces:**
- Produces:
  - `IdleWatch.public func idleMinutes(atLeast floor: Duration) -> [String: Int]`: whole minutes idle for every tracked id whose `idleFor >= floor`.
  - `IdleWatch.public static func label(minutes: Int) -> String`: `"Idle 45m"` under 60. `"Idle 2h"` on whole hours. `"Idle 2h 15m"` otherwise.
  - App: `IdleAlerts.limitMinutes: Int` persisted under key `"idleAlertLimitMinutes"`, default 60. `static let limitChoices = [30, 60, 120, 240, 480]`. `threshold` becomes a computed `Duration.seconds(limitMinutes * 60)`.
  - App: `IdleAlerts.idleMinutes: [String: Int]` (observable, keyed by `RunningService.id`), written only when it changes. `reset()` empties it.

- [ ] **Step 1: Write the failing tests** in `IdleWatchTests.swift`:
  - `idleMinutesReportsFromFloor`: 29 quiet minutes → `idleMinutes(atLeast: 30 min)` is empty. One more minute → `["next": 30]`.
  - `idleMinutesResetsOnBusy`: after 40 quiet minutes and one busy sample → empty.
  - `labelFormats`: `label(minutes: 45) == "Idle 45m"`, `label(minutes: 120) == "Idle 2h"`, `label(minutes: 135) == "Idle 2h 15m"`.
- [ ] **Step 2:** `swift test --filter IdleWatchTests`. Expected: compile failure.
- [ ] **Step 3:** Implement both members on `IdleWatch`.
- [ ] **Step 4:** `swift test --filter IdleWatchTests`. Expected: PASS.
- [ ] **Step 5:** App wiring:
  - In `checkIdle`, measure whenever `idleAlerts.isEnabled` and automatic refresh is on. Post banners only when `notifier.isAuthorized`.
  - Afterwards, set `idleMinutes` from `watch.idleMinutes(atLeast: threshold / 2)`, assigning only on change.
  - `IdleAlerts.idle` uses the computed `threshold`.
- [ ] **Step 6:** Preferences:
  - Under "Warn about idle agent servers", add a `SegmentedControl` row "Idle for" with `limitChoices`. Labels: `30m`, `1h`, `2h`, `4h`, `8h`.
  - Disable it when the warning is off, the same as `limitRow` does for memory. Generalise `limitRow` to take the enabled flag and label formatter instead of duplicating it.
  - `idleSubtitle` says "…has been idle for the limit below".
- [ ] **Step 7:** Row and detail:
  - When `state.idleAlerts.idleMinutes[service.id]` is set, the row shows `TintedBadge(text: IdleWatch.label(minutes:), tint: Theme.tertiaryText)` after the origin badge, and it counts in the badge-presence check at `ServiceRowView.swift:180`.
  - The detail pane adds a `LabeledRow(label: "Idle", value: "45 minutes"…)` under the origin row.
- [ ] **Step 8:** `make lint && make test && make app`. Then `make snapshot` with a temporary `idleMinutes` entry on the fixture's Claude Code row. Check the popover, dashboard and preferences, then revert.
- [ ] **Step 9:** CHANGELOG `### Added`: idle label on agent servers, and an idle limit picker (30 minutes to 8 hours, default 1 hour). Update the README line on idle warnings. Commit:
  `git commit -m "feat(idle): show idle time on agent servers and make the limit configurable"`

### Task 3: Ended agent sessions with titles

**Files:**
- Create: `Sources/PortfoxKit/Scanning/AgentSession.swift` (marker type, env parsing helper, title lookup)
- Modify: `Sources/PortfoxKit/Scanning/Lineage.swift` (`AgentKind: Codable`, `ServiceOrigin.agentEnded`, `Lineage.origin(...)`)
- Modify: `Sources/PortfoxKit/Model/ProcessSnapshot.swift` (new field), `Sources/PortfoxKit/Scanning/ProcessInspector.swift` (`snapshot(pid:)` line 49, env-only parsing)
- Modify: `Sources/PortfoxKit/ServiceRepository.swift` (`hostService`, lines 441-462), `Sources/PortfoxKit/Model/RunningService.swift` (`canRestart`, `isAgentStarted`)
- Modify: `App/Portfox/AppState.swift` (+ `sessionTitles`), `App/Portfox/Views/Components.swift` (`OriginBadge`), `App/Portfox/Views/ServiceRowView.swift`, `App/Portfox/Views/MenuView.swift:169`, `App/Portfox/Views/Dashboard/ServiceDetailPane.swift:62`
- Test: `Tests/PortfoxKitTests/Scanning/AgentSessionTests.swift`, `Tests/PortfoxKitTests/Scanning/LineageTests.swift`
- Docs: `.claude/CLAUDE.md` (extend "Origin walks plain ancestors" with the marker rule), CHANGELOG, README

**Interfaces:**
- Produces:
  - `public struct AgentSessionMarker: Hashable, Codable, Sendable { public let kind: AgentKind; public let sessionID: String; public let agentPID: pid_t? }`.
  - `static func agentSession(inEnvironment entries: [String]) -> AgentSessionMarker?` on `AgentSessionMarker`:
    - Codex: `CODEX_THREAD_ID`, with `agentPID` nil.
    - Claude Code: `CLAUDECODE=1` plus `CLAUDE_CODE_SESSION_ID`, with `agentPID` from `CLAUDE_PID`.
    - Codex wins when both are present.
  - `ProcessInspector.static func environment(in buffer: [UInt8]) -> [String]`: the entries after `argc` arguments only. `parseProcArgs` and this share the walk.
  - `ProcessSnapshot.agentSession: AgentSessionMarker?` (init param, default nil), set in `snapshot(pid:)`.
  - `ServiceOrigin.agentEnded(AgentKind)`, with label `"\(kind.displayName) · ended"`. `public var isAbandoned: Bool` is true for `.orphaned` and `.agentEnded`.
  - `Lineage.static func origin(isOrphaned: Bool, isUserManaged: Bool, liveAncestor: AgentKind?, marker: AgentSessionMarker?, tree: ProcessTree) -> ServiceOrigin?`, rules in this order:
    1. The marker's agent is alive: `liveAncestor != nil`, or `marker.agentPID` resolves in `tree` to a process `AgentKind.of` returns `marker.kind` for. With `isUserManaged && !isOrphaned`, return `.agent(liveAncestor ?? marker.kind)`.
    2. The marker is present, no agent is alive, and `isUserManaged || isOrphaned`: return `.agentEnded(marker.kind)`.
    3. `isOrphaned`: return `.orphaned`.
    4. Otherwise nil.
  - `RunningService.isAgentStarted` is true for `.agent` and `.agentEnded`. `canRestart` is false when `origin?.isAbandoned == true`.
  - `public struct AgentSessionTitles: Sendable { public init(home: URL); public func title(for marker: AgentSessionMarker) -> String? }`:
    - Claude Code: `<home>/.claude/projects/*/<sid>.jsonl`. Read at most the last 2 MiB, and take the last line containing `"ai-title"` whose JSON `aiTitle` is a non-empty string.
    - Codex: `<home>/.codex/session_index.jsonl`. Take the last line whose JSON `id == sid`, and return its non-empty `thread_name`.
  - App: `AppState.sessionTitles: [String: String]` keyed by session id. After each applied scan, ids from rows with markers and no cached title are looked up in a detached task, then assigned on the main actor only for new hits.

- [ ] **Step 1: Write the failing tests:**
  - `AgentSessionTests`:
    - `claudeMarkerParsed`: env `["CLAUDECODE=1", "CLAUDE_CODE_SESSION_ID=abc", "CLAUDE_PID=42"]` → `.claudeCode`, `"abc"`, `42`.
    - `codexMarkerParsed`: `["CODEX_THREAD_ID=t1"]` → `.codex`, `"t1"`, nil.
    - `codexWinsWhenNested`: both sets → `.codex`.
    - `claudeNeedsFlag`: a session id without `CLAUDECODE=1` → nil.
    - `markerInArgvIgnored`: a procargs buffer with argc 2, argv `["grep", "CODEX_THREAD_ID=x"]` and env `["PATH=/usr/bin"]` → `environment(in:)` has no `CODEX_` entry.
    - Title tests use a temporary home directory:
      - `claudeTitleFromTail`: two `ai-title` lines → the last one.
      - `codexTitleFromIndex`: two lines for the same id → the last `thread_name`.
      - `titleMissingIsNil`: no file, an empty `aiTitle`, and no `~/.codex` all return nil.
  - `LineageTests`, new `@Suite("session origin")`:
    - `liveAncestorIsAgent`: a live ancestor → `.agent`.
    - `endedClaudeSession`: marker present, no ancestor, `CLAUDE_PID` absent from the tree → `.agentEnded(.claudeCode)`.
    - `liveClaudePidKeepsAgent`: no ancestor, but `agentPID` resolves to a `claude` process → `.agent(.claudeCode)`.
    - `recycledClaudePid`: `agentPID` resolves to a `zsh` process → `.agentEnded`.
    - `endedReplacesOrphaned`: `isOrphaned` and a marker → `.agentEnded`.
    - `orphanWithoutMarker` → `.orphaned`.
    - `notUserManagedNoMarkerOrigin`: a not user-managed, non-orphan row with a marker → nil.
- [ ] **Step 2:** `swift test --filter "AgentSessionTests|LineageTests"`. Expected: compile failure.
- [ ] **Step 3:** Implement the kit pieces with the signatures above. In `hostService`, replace the inline `origin` expression with `Lineage.origin(...)`, passing `Lineage.agent(among: ancestors)` and `listener.agentSession`.
- [ ] **Step 4:** `swift test`. Expected: all pass, including the existing orphan and agent suites unchanged.
- [ ] **Step 5:** App:
  - `OriginBadge`: warning tint when `origin.isAbandoned`, and `.help(title)` when `state.sessionTitles` has the row's session.
  - The `MenuView` summary counts `origin?.isAbandoned == true` and keeps the label "orphaned".
  - Detail pane case `.agentEnded(let kind)`: `LabeledRow(label: "Started by", value: "\(kind.displayName), session ended", valueColor: Theme.warning)`, plus `LabeledRow(label: "Session", value: title)` when a title is known. Show the title row for live `.agent` rows too.
  - Add `sessionTitles` to `AppState`, filled as described in Interfaces.
- [ ] **Step 6:** `make lint && make test && make app`. Then `make scan` while a Claude-started server runs, and check that it shows Claude Code. `make snapshot` with a temporary `.agentEnded(.claudeCode)` fixture row and a fake title. Check the badge tint and detail rows, then revert.
- [ ] **Step 7:** Docs:
  - CHANGELOG `### Added`: a server whose Claude Code or Codex session ended shows "Claude Code · ended" or "Codex · ended" instead of Orphaned, with the session title in the tooltip and the dashboard.
  - Add a README line.
  - Add a `.claude/CLAUDE.md` rule covering: markers come from the env block only, Codex wins when nested, `CLAUDE_PID` guards against daemonized servers, and titles stay out of `ScanResult`.
  - Commit: `git commit -m "feat(origin): mark servers whose Claude Code or Codex session ended"`
