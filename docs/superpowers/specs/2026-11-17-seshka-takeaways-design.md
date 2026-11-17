# Seshka takeaways: freed memory, idle time, ended agent sessions

## Why

seshka.dev (a Claude-only leftover killer) makes two things visible that Portfox
already knows but does not show: how much a cleanup gave back, and that an
agent session ended while its server kept running. Portfox should show both,
for Claude Code and Codex, without growing into a session manager.

## Goals

1. **Freed memory.** After a stop, say roughly how much memory came back.
2. **Idle time.** Agent-started servers show how long they have been idle, and
   the idle warning limit is a choice, not a constant.
3. **Ended sessions.** A server whose Claude Code or Codex session is gone says
   so, and names the session.

## Non-goals and anti-goals

- No session list, no ending or resuming agent sessions, no reading
  `~/.claude/sessions/*.json` busy/idle records.
- No processes without a port. Portfox stays a listener app.
- No automatic SIGKILL escalation, no new stop path that skips `markStopping`
  or the container and database refusals.
- A freed number must never claim more than was measured. Call it an estimate.

## Approaches (item 1, chosen: A)

- **A. Badge and detail.** The origin badge reads "Claude Code · ended" in the
  warning tint. The session title shows in the badge tooltip and the detail
  pane. Small, fits the current row.
- **B. Group by session.** A "Left by agents" section with one block per session
  and "Stop all N". Rejected for now: it competes with project grouping.

## Design

### 1. Freed memory

- Measure resident bytes of the root and its descendants just before signalling
  (Stop, Stop All, Force Stop, the idle banner's Stop). Count a pid once.
- Add only the processes confirmed gone when the stop returns.
- Show "Freed ~850 MB" in the popover footer and the dashboard toolbar for a
  few seconds. Stops inside that window add up. Nothing shows for 0 bytes.
- Not persisted, not a lifetime counter.

### 2. Idle time and limit

- `IdleWatch` exposes each tracked server's `idleFor`.
- Rows of agent-started servers show "Idle 45m" once `idleFor` reaches half the
  limit. The app stores minute-rounded values and writes them only when the
  rounded value moves.
- "Warn about idle agent servers" gains a limit picker: 30m, 1h, 2h, 4h, 8h.
  Default 1h, the current value. Reuses `WarningPreferences.limitRow`.
- Sleep still never counts (suspending clock, unchanged).

### 3. Ended agent sessions

- `ProcessInspector` reads agent markers from the listener's environment, the
  same `KERN_PROCARGS2` buffer as `LOCALFOX_HOST`:
  - Claude Code: `CLAUDECODE=1` with `CLAUDE_CODE_SESSION_ID`.
  - Codex: `CODEX_THREAD_ID`.
  - Both present: Codex wins. The usual nesting is Codex started from Claude,
    which inherits Claude's variables and adds its own.
- Origin rules, in order:
  1. A live agent ancestor: `.agent(kind)`, as today.
  2. Markers present, no live agent ancestor, user-managed: ended, with the
     kind and session id. This replaces `.orphaned` for that row.
  3. Otherwise the current orphan rule.
- Ended counts as agent-started (idle warnings apply) and cannot Restart, the
  same as an orphan. The popover's "orphaned" count includes ended rows.
- The session id may sit in `RunningService`, it never moves. The title does
  move, so it stays out of the scan result. A kit lookup reads it on demand,
  cached per id, and only caches hits:
  - Claude Code: last `aiTitle` in the tail of
    `~/.claude/projects/<dir>/<sid>.jsonl`.
  - Codex: last `thread_name` for the id in `~/.codex/session_index.jsonl`.
- Missing markers, files or titles degrade silently to today's behaviour. All of
  these are undocumented formats.

## Left to the builder

- Exact type shapes (`ServiceOrigin` case layout, marker struct).
- Copy for the tooltip and detail row, within the existing style.
- Tests: marker parsing, origin precedence, `IdleWatch` exposure, title lookup
  against fixture files, freed-memory arithmetic.

## Delivery

Three commits in order: freed memory, idle time, ended sessions. Each building and
passing `make lint` and `make test`. CHANGELOG and README updated in each.
