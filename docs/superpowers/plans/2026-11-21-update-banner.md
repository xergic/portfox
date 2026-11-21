# Update Banner and Relaunch Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Installing an update always relaunches, and a scheduled check that finds an update shows a sticky accent row instead of Sparkle's window, in Portfox and Localfox.

**Architecture:** Every update entry point goes through one `AppState.checkForUpdates()`, which dismisses an open dashboard sheet and runs Sparkle's check from the sheet's `onDismiss`. `Updater` keeps `SPUStandardUserDriver`, declines to show scheduled updates itself, and publishes `pendingVersion`, which a leaf `UpdateBanner` view reads.

**Tech Stack:** Swift 6, SwiftUI, Sparkle 2.10.1, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-21-update-banner-design.md`

## Global Constraints

- macOS 15.0 deployment target. Anything newer sits behind `if #available`.
- No comments that restate the code (project CLAUDE.md).
- Do not write to `@Observable` state unless the value moved.
- `Theme.accent` fill, `Theme.onAccent` text on it. No new colour literals.
- The app target has no unit tests. Verification is `make lint`, `make run` builds, `make snapshot`, and the manual Sparkle run in Task 3.
- One commit per feature, and each commit builds and lints on its own. Conventional Commits, one short sentence, no body, no co-author.
- Localfox lives at `/Users/ondra/Work/Personal/Localfox/localfox` and mirrors Portfox file for file (`App/Localfox/...`). Its tree has unrelated uncommitted view edits: do not start Tasks 4-5 until Ondra says how to handle them.

## Review Focus

- Banner clicked while About or Preferences is open: the sheet closes, then Sparkle's window appears. Covered by Task 3 run B.
- Banner clicked from the popover while the dashboard is closed: Sparkle's window appears in front. Covered by Task 3 run C.
- User-initiated check (About, Preferences) with an update out: Sparkle's window shows as before and no banner flashes. Covered by Task 3 run A.
- User picks "Skip This Version" or closes Sparkle's window: the banner goes away. Covered by Task 3 run D.
- Localfox with services running: InstallGuard's alert still appears and Later still defers. Covered by Task 5.

---

### Task 1: Portfox relaunch fix

**Files:**
- Modify: `App/Portfox/AppState.swift` (near `presentedSheet`, line 45)
- Modify: `App/Portfox/Views/Dashboard/DashboardView.swift:24`
- Modify: `App/Portfox/Views/AboutSheet.swift:67-72`
- Modify: `App/Portfox/Views/PreferencesSheet.swift:404`
- Modify: `.claude/CLAUDE.md` (a rule under Rules, after the feed URL rule)

**Interfaces:**
- Produces: `AppState.checkForUpdates()` and `AppState.sheetDidDismiss()`, both `@MainActor`, no parameters, no return.

- [ ] **Step 1:** In `AppState`, add `@ObservationIgnored private var updateCheckQueued = false` and `func checkForUpdates()`: when `presentedSheet != nil`, set the flag and `presentedSheet = nil`. Otherwise call `Updater.shared.checkForUpdates()`. Add `func sheetDidDismiss()`: when the flag is set, clear it and call `Updater.shared.checkForUpdates()`.
- [ ] **Step 2:** `DashboardView`: use `.sheet(item:onDismiss:)` with `onDismiss: state.sheetDidDismiss`. Pass `.environment(state)` to `AboutSheet()` as Preferences already gets it.
- [ ] **Step 3:** About's button and Preferences' Check Now call `state.checkForUpdates()` (About gains `@Environment(AppState.self)`). Keep their `.disabled(!canCheckForUpdates)`.
- [ ] **Step 4:** On both sheet roots, apply `.presentationPreventsAppTermination(false)` inside `if #available(macOS 15.4, *)` through a small `View` extension in `DashboardView.swift`. If the SDK lacks the modifier, drop this step and say so in the report.
- [ ] **Step 5:** CLAUDE.md rule, in the file's voice: an update check closes the open sheet first, because AppKit refuses Sparkle's quit while a sheet is attached and the old version keeps running. Every entry point goes through `AppState.checkForUpdates()`.
- [ ] **Step 6:** Run `make lint` (clean) and `make run` (builds, app launches). Open About, click Check for Updates: the sheet closes. A local build has no feed, so nothing else happens. That is expected.
- [ ] **Step 7:** Do not commit yet. Task 3 proves the fix first.

### Task 2: Portfox update banner

**Files:**
- Modify: `App/Portfox/Updater.swift`
- Create: `App/Portfox/Views/UpdateBanner.swift`
- Modify: `App/Portfox/Views/MenuView.swift:47-48`
- Modify: `App/Portfox/Views/Dashboard/ServiceListPane.swift:22-23`
- Modify: `App/Portfox/SnapshotRenderer.swift` (flag parsing near line 40, usage comment line 8)
- Modify: `.claude/CLAUDE.md` (extend the Task 1 rule)

**Interfaces:**
- Consumes: `AppState.checkForUpdates()` from Task 1.
- Produces: `Updater.pendingVersion: String?` (`private(set)`, observable), `Updater.previewBanner(version: String)`, `struct UpdateBanner: View` (no init parameters, reads `AppState` from the environment).

- [ ] **Step 1:** `UserDriverDelegate` holds a `weak var updater: Updater?`, set in `start()`. Implement:
  - `standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)` returns `false` always. A menu bar app is never in focus in the way Sparkle means.
  - `standardUserDriverWillHandleShowingUpdate`: when `handleShowingUpdate` is false, set `updater.pendingVersion = update.displayVersionString` (compare first) and do not activate. When true, keep today's `NSApp.activate()`.
  - `standardUserDriverWillFinishUpdateSession()` sets `pendingVersion = nil` when non-nil.
  Keep the delegate main-actor isolated the way the current file compiles under Swift 6. Use `MainActor.assumeIsolated` only if the compiler needs it.
- [ ] **Step 2:** `previewBanner(version:)` sets `pendingVersion` only when `SnapshotRenderer.request != nil`.
- [ ] **Step 3:** `UpdateBanner`: draws nothing when `Updater.shared.pendingVersion` is nil. Otherwise a full-width `Button` row: `arrow.down.circle.fill`, text `"Portfox \(version) is available"`, trailing `"Update…"`, `.font(.portCaption)` or the footer's font, `Theme.onAccent` on `Theme.accent`, horizontal padding `Theme.Metrics.contentInset`, vertical padding matching the popover footer (5). The action is `state.checkForUpdates()`. Disabled while `!Updater.shared.canCheckForUpdates`.
- [ ] **Step 4:** Insert `UpdateBanner()` directly above the `Divider()` before the footer in `MenuView` and in `ServiceListPane`.
- [ ] **Step 5:** `SnapshotRenderer`: a `--update` flag calls `Updater.shared.previewBanner(version: "9.9.0")` before rendering. Add it to the usage comment.
- [ ] **Step 6:** CLAUDE.md: a scheduled update never opens Sparkle's window. It shows `UpdateBanner`, and the banner hands back to Sparkle's standard UI through `checkForUpdates()`. No own timer, because it would compete with Sparkle's scheduler.
- [ ] **Step 7:** Run `make lint` (clean), then `make snapshot` plus `./build/...Portfox --snapshot /tmp/portfox-update-banner/pop.png --demo --update` and the same with `--snapshot-dashboard` and `--light` (use the binary path `make snapshot` uses). Look at the PNGs: the row sits above the footer, text readable in dark and light.

### Task 3: Prove both fixes against a local feed (Portfox)

Scratch dir: `/tmp/portfox-update-banner`. Delete it at the end.

- [ ] **Step 1:** `make archive` into `dist/Portfox.app`. Make two copies in the scratch dir: `old/Portfox.app` (`CFBundleVersion` 1) and a zip of `new/Portfox.app` (`CFBundleVersion` 2, `CFBundleShortVersionString` 9.9.0). In both, set `SUFeedURL` to the local appcast and `SUPublicEDKey` to a test key from Sparkle's `generate_keys --account portfox-test` (find the tool under the SPM artifacts in the shared DerivedData `~/Library/Developer/Xcode/DerivedData/Portfox-agent`). Re-sign each copy ad hoc (`codesign --force --deep -s -`). Sign the zip with `sign_update --account portfox-test`, write a one-item appcast, and serve the dir on `127.0.0.1`. If Sparkle refuses a plain-HTTP feed, find the smallest workaround and record it.
- [ ] **Step 2:** Quit any running Portfox, run `old/Portfox.app`, and run these. Record the PID and `CFBundleVersion` before and after each install:
  - **A:** Dashboard → About → Check for Updates → Install and Relaunch. Expected: the sheet closes, the app relaunches as build 2, no banner flashes.
  - **B:** Set `SUScheduledCheckInterval` low or `defaults write net.kandera.Portfox SULastCheckTime` to the past, so a scheduled check fires. Expected: the banner appears in the popover and the dashboard, no Sparkle window. Open About, then click the banner: the sheet closes, Sparkle's window appears, Install relaunches as build 2.
  - **C:** Banner from the popover with the dashboard closed. Expected: Sparkle's window comes to the front.
  - **D:** Banner → Sparkle window → Skip This Version. Expected: the banner disappears.
  - **E (regression check):** revert Task 1 locally, repeat A. Expected: no relaunch. This confirms the diagnosis. Restore Task 1.
  The clicks need a person or a computer-use subagent (Terra). Ask Ondra which one.
- [ ] **Step 3:** If A fails with Task 1 in place, stop and report what you saw. Do not commit.
- [ ] **Step 4:** Commit Task 1: `git commit -m "fix(updates): close the open sheet before Sparkle quits to install"`. Then commit Task 2 with the spec and this plan: `git commit -m "feat(updates): show an update banner instead of Sparkle's window"`. Run `make lint` before each. Each commit has to build: stage Task 1's files alone first.

### Task 4: Localfox relaunch fix

Same as Task 1 in `App/Localfox/`, with these differences:

- Only Preferences has a Check Now button (`App/Localfox/Views/PreferencesSheet.swift:219`). The sheet is presented at `App/Localfox/Views/DashboardView.swift:75`.
- `Updater.start(delegate:)` already takes `InstallGuard`. Leave `InstallGuard` as is unless Task 5 shows `runModal` interferes.
- Commit: `fix(updates): close the open sheet before Sparkle quits to install`.

### Task 5: Localfox update banner and verification

Same as Tasks 2 and 3 in Localfox, with these differences:

- Banner copy: `"Localfox \(version) is available"`. Place it above the popover footer and the dashboard's equivalent bottom bar. Find it in `App/Localfox/Views/MenuView.swift` and `DashboardView.swift`.
- Verification adds **F:** with one service running, click the banner → Install. Expected: InstallGuard's alert. Later keeps services running and installs once they stop. Install Now stops them and relaunches as the new build.
- Localfox's CLAUDE.md gets the same two rules.
- Commit: `feat(updates): show an update banner instead of Sparkle's window`.
