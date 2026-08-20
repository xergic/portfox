# CLAUDE.md

Project instructions for Portfox. Read `README.md` for the user-facing description.

## What this is

A macOS 15+ menu bar app that lists local TCP listeners, identifies which dev
service each one is, resolves its project, and can stop it. Swift 6, SwiftUI,
strict concurrency, no third-party dependencies.

## Commands

```sh
make run      # regenerate the project, build, relaunch the app
make test     # swift test, the whole kit suite
make scan     # run the pipeline headless (./.build/debug/portfox-scan)
make lint     # SwiftLint, must stay clean
make gen      # regenerate Portfox.xcodeproj from project.yml
make snapshot # render popover, dashboard, preferences and about to snapshots/
make archive  # universal ad hoc signed Release app and DMG into dist/
```

Run `make lint` and `make test` after every code change. Run `make snapshot`
after a UI change and look at the PNGs.

`Portfox.xcodeproj` is generated and git-ignored. Never edit it. Change
`project.yml` and run `make gen`.

`snapshots/` and `dist/` are git-ignored. Do not commit PNGs or build output.

## Layout

| Path | Holds |
|---|---|
| `Sources/PortfoxKit/` | The whole pipeline. No SwiftUI, no AppKit, no UI state. |
| `Sources/portfox-scan/` | CLI over the same pipeline. |
| `App/Portfox/` | SwiftUI shell: `AppState`, `DashboardState`, views, theme. |
| `Tests/PortfoxKitTests/` | Tests for the kit only. The app target has none. |
| `.github/` | CI on every push, the signed release pipeline on a tag. |
| `Tools/` | `fetch-icons.py` (simple-icons), `make-appicon.swift`, `make-dmg.sh`, `archive.sh`. |

## Architecture

```
ListenerScanner → ProcessInspector → ProcessTree → ProjectResolver
    → DetectionEngine → ListenerClassifier → IconResolver → ServiceRepository
```

- **ListenerScanner** shells out to `lsof -iTCP -sTCP:LISTEN -F pcntR`. Only the
  current user's sockets come back, which is the app's permission scope.
- **ProcessInspector** reads `sysctl(KERN_PROC_ALL)` for the skeleton, then
  libproc for the listeners and their ancestors only. Every field is optional,
  because hardened-runtime processes refuse `proc_pidinfo`.
- **ProcessTree** answers ancestors, descendants and the logical root. It stops
  at a *boundary* process (shell, terminal, `.app` bundle).
- **ProjectResolver** walks up from the working directory looking for manifests
  (`package.json`, `pyproject.toml`, and so on) and returns a `ProjectSnapshot`.
- **DetectionEngine** runs every `RuleBasedDetector` and takes the highest score,
  breaking ties toward the more specific `ServiceType`.
- **ListenerClassifier** buckets each service into `developmentService`,
  `infrastructure`, `probableDeveloperProcess` or `systemNoise`.
- **ServiceRepository** is the actor that owns the pipeline and every cache. It
  is the only stateful piece of the kit.

Every stage takes and returns plain `Sendable` value types. `portfox-scan`
drives the identical pipeline, so detection can be developed without the GUI.

## Rules

**The kit never imports SwiftUI.** If a change needs UI types in `PortfoxKit`,
the change is in the wrong layer.

**Preferences live in the app, not the kit.** `IgnoredServices` and
`ProjectIconOverrides` are `UserDefaults`-backed app state. The kit reports the
machine as it is. This is why `portfox-scan` still lists an ignored service.

**Do not write to `@Observable` state unless the value moved.** `AppState`
compares before assigning. A blind write redraws the whole dashboard on a 1-2s
tick. New observable properties follow the same rule.

**Compare a fresh scan against `rawResult`, never `result`.** `result` is the
ignore-filtered projection, so comparing to it differs forever once anything is
ignored, and the skip-the-redraw branch stops working.

**Nothing touches a user's dev server on the refresh tick.** `HTTPProbe` runs
only when the user presses Inspect. It refuses any host other than `localhost`,
`127.0.0.1` or `::1`, and never follows a redirect.

**Signals go to the logical root, never to a process group.** A dev server
started from a terminal shares its group with the user's shell. `SIGKILL` only
happens when the user explicitly asks for Force Stop.

**Command matching is word-boundary aware.** Use `String.containsToken`, not
`contains`. A plain substring search labels `ngrok` as Angular via `/bin/ng`.

**No comments that restate the code.** The existing comments explain *why* a
non-obvious choice was made, usually with the concrete bug that forced it. Match
that bar or write nothing.

## Adding a service detector

Three edits, no new code paths:

1. A case in `ServiceType` with its display name, category and default ports.
2. A `RuleBasedDetector` row in `Sources/PortfoxKit/Detection/Detectors/`.
3. An entry in `Tools/fetch-icons.py`, then `python3 Tools/fetch-icons.py`.

Then a test in the matching `Tests/PortfoxKitTests/Detection/` file.

Every detector needs at least one match in its `requiredGroup` (default
`command`). Project evidence alone must never identify a service.

`defaultPorts` is ordered by usefulness, not numerically. The first bound
default wins the port pill.

## Snapshots

`ImageRenderer` lays out in one pass and never draws scroll content, so every
scrollable surface carries a `scrolls` escape hatch that the snapshot path turns
off. A `TextField` renders as an empty placeholder block, which is why the
dashboard's search box draws flat text under a snapshot.

The popover measures its own list height. Inside a `MenuBarExtra` window a
`ScrollView` has no intrinsic height and collapses to nothing.

## Releases

Push a `vMAJOR.MINOR.PATCH` tag. `.github/workflows/release.yml` archives,
signs with Developer ID, notarizes, staples, builds the DMG and publishes it.

`MARKETING_VERSION` comes from the tag and `CURRENT_PROJECT_VERSION` from the
run number, so `project.yml` stays at its placeholder and nobody edits a version
by hand.

**A release build must archive, never build.** `xcodebuild build` resolves the
destination to the runner's own arch and silently ships arm64 only. Only
`archive -destination 'generic/platform=macOS'` produces the universal binary,
which is why the workflow fails the job when a slice is missing.

**Both the app and the DMG get notarized and stapled.** A ticket stapled to the
DMG alone leaves the copied app waiting on an online check at first launch.

### A local build to hand to someone

`make archive` (or `Tools/archive.sh 0.2.0`) runs the same archive invocation
without a Developer ID, and writes `dist/Portfox.app` and `dist/Portfox-<v>.dmg`.
It fails the run when either architecture slice is missing, exactly as CI does.

Version defaults to the latest git tag, build number to `git rev-list --count
HEAD`. Locally there is no run number to borrow, and the commit count is the
cheapest value that only ever goes up, which is what `CFBundleVersion` needs.

The script skips `-exportArchive` and copies the app out of the archive instead.
Export wants a team and an export plist, and `project.yml` signs ad hoc.

The result is not notarized, so macOS 15 blocks it and offers no right-click
Open. The recipient runs `xattr -dr com.apple.quarantine`. Tag a release when
that is not acceptable.

## Git

Conventional Commits, single short sentence, no body, no co-author trailer.
Work on `main` unless the change is large enough to want review in isolation.
