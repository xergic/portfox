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
| `App/Portfox/ProcessMetrics.swift` | Memory and CPU by pid, deliberately outside `ScanResult`. |
| `App/Portfox/ExternalApps.swift` | Which editors and terminals are installed, and how to launch one. |
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

**Live numbers live in `ProcessMetrics`, not in `ScanResult`.** Memory and CPU
move on every sample. Inside the scan result they would make two scans of an
unchanged machine compare unequal and redraw the whole dashboard once a second.
They are read by leaf views (`MemoryLabels.swift`) so a tick redraws a `Text`.

**CPU is a delta, not a reading.** `proc_taskinfo` carries a cumulative counter,
so a percent needs two samples and a wall interval. That is why the first tick
after enabling it shows nothing, and why it stays blank with the refresh loop off.

**Compare a fresh scan against `rawResult`, never `result`.** `result` is the
ignore-filtered projection, so comparing to it differs forever once anything is
ignored, and the skip-the-redraw branch stops working.

**Nothing touches a user's dev server on the refresh tick.** `HTTPProbe` runs
only when the user presses Inspect. It refuses any host other than `localhost`,
`127.0.0.1` or `::1`, and never follows a redirect.

**A relaunch is built from the logical root, the same process Stop signals.**
`RelaunchCommand` quotes every argv entry into a `zsh -l` script, because the
command comes from another process and must never be read as shell syntax. The
login shell is what puts nvm, direnv, asdf and mise back. It refuses databases
and daemons outright: Homebrew and DBngin restart their own, and a hand-relaunched
copy ends up unmanaged beside the supervised one.

**Restart hands a `.command` file to a terminal, because a terminal cannot be
told to run something, only to open something.** Terminal, iTerm2 and Warp were
tested running one; `ExternalApp.runsHandedOverScript` records that. Anything
untested falls back to Stop and Copy Command rather than appearing to work.

**One container is one row, and none of them may be signalled.** Docker Desktop
publishes every container port through one host process, so `build` returns an
array: `ContainerAttribution` splits that process's sockets by host port and each
container gets its own `RunningService` with the forwarder as its
`listenerProcess`. That is shared, which is why `ProcessController` refuses any
row carrying a `container` outright. `ListenerClassifier` alone is not enough:
the Stop button is offered without asking whether a service is user-managed, and
an `nginx:alpine` row detects as `.web` and would otherwise be user-managed.

**`ContainerSnapshot` may hold nothing that moves while the container runs.** It
reaches `RunningService`'s synthesised `Equatable`, which is the comparison that
decides whether the dashboard repaints. `docker ps`'s `.Status` is the field this
forbids, and it is why container uptime is absent rather than approximated.

**`docker ps` runs only on a rebuild that found a forwarder listening.** The gate
is `ContainerRuntime.isForwarder` over the listener pids, so a machine with no
containers never spawns it at all, and the socket-set short circuit above means an
idle machine spawns it zero times rather than once per TTL. The known cost is that
an OrbStack container restarted on the same port produces a byte-identical socket
set, so its row stays stale until Refresh. Do not fix that by weakening the short
circuit.

**Signals go to the logical root, never to a process group.** A dev server
started from a terminal shares its group with the user's shell. `SIGKILL` only
happens when the user explicitly asks for Force Stop.

**Command matching is word-boundary aware.** Use `String.containsToken`, not
`contains`. A plain substring search labels `ngrok` as Angular via `/bin/ng`.

**`containsToken` cannot match inside a versioned filename.** Digits and `-` are
word characters, so it fails on `spring-boot-3.2.0.jar`, `net8.0` and `php8.3`.
Evidence living in one of those needs a raw `contains` behind a runtime gate from
`DetectionContextRuntimes.swift` (`isJVM`, `isPHP`, `isDotNetBuildOutput`).

**No comments that restate the code.** The existing comments explain *why* a
non-obvious choice was made, usually with the concrete bug that forced it. Match
that bar or write nothing.

## Adding a service detector

Three edits, no new code paths:

1. A case in `ServiceType` with its display name, category and default ports.
   Set `specificity` by hand: the `default: 3` arm is for frameworks, generic
   runtimes belong at 1 and application servers at 2.
2. A `RuleBasedDetector` row in the matching file under
   `Sources/PortfoxKit/Detection/Detectors/` (`NodeDetectors`, `PythonDetectors`,
   `JVMDetectors`, `DotNetDetectors`, `RubyDetectors`, `PHPDetectors`,
   `GoRustDetectors`, `DatabaseDetectors`, `InfrastructureDetectors`).
3. An entry in `Tools/fetch-icons.py`, in `ICONS` or in `NO_BRAND_ICON` with a
   reason, then `python3 Tools/fetch-icons.py`.

Then a test in the matching `Tests/PortfoxKitTests/Detection/` file.
`CatalogueGuardTests` fails the build if you skip step 1's specificity, step 2
entirely, or step 3.

Every detector needs at least one match in its `requiredGroup` (default
`command`). Project evidence alone must never identify a service. A `custom`
signal carrying command-line evidence must pass `group: "command"` explicitly,
or it does not satisfy the gate.

`defaultPorts` is ordered by usefulness, not numerically. The first bound
default wins the port pill.

**A veto only disqualifies the detector that declares it.** Shared suppression,
such as `DetectionContext.isJVMTooling`, has to be repeated on every row in the
family, or a Surefire fork whose classpath mentions Spring gets reported as a
running application.

**Detection promotes.** `ListenerClassifier` consults the detection result
before its `/usr/bin/` and `.app/Contents/` noise rules, so a new generic runtime
detector drags every matching system process out of hiding. Those rows need
explicit vetoes, not optimism. The ephemeral-port rule is what actually saves
you: anything bound only above 49152 never reaches detection.

## Arrivals

`ScanResult.appeared(since:)` is the one diff, computed at the only moment both
scans exist as values, and it feeds both the notification and the row flash.

**It diffs `everyService`, not `services`.** `hidden` holds the system noise while
"Show all listeners" is off, so diffing the visible list turns one flip of that
preference into thirty arrivals.

**It is an id diff, not a value diff.** A manual Refresh drops every cache and can
re-resolve a version, so two results compare unequal while nothing started. That
same path can also move `primarySocket` and so change an id, which is why
`.userRequested` is never announced at all.

**`busyServiceIDs` cannot suppress a restart.** It is cleared when `restart`
returns, and a relaunched server has not bound its port by then. `ServiceArrivals`
records the expected port with a deadline instead, before anything is signalled.

**The flash never inserts a row, it is a property an existing row reads.** That is
how "no lingering closed rows" falls out, and why `recentIDs` is not intersected
with the live set the way `stubbornServiceIDs` is.

## Appearance

`Theme` carries two literal palettes. Every colour token is a dynamic `NSColor`
bridged into `Color`, so it resolves against the `\.colorScheme` of whatever
surface draws it. That is what lets one palette switch reach ~200 unchanged
`Theme.background` call sites.

**A dynamic `NSColor` resolves under `ImageRenderer` too**, against the
environment's `colorScheme`, and `.opacity()` on one stays dynamic. Both were
measured, not assumed. This is why the palette is not a global the views read:
a global cannot be observed, and faking the invalidation with `.id(scheme)`
destroys the `@State` of every surface it wraps.

**Every surface root wears `themedSurface(state.appearance.colorScheme)`.**
`preferredColorScheme` is a scene preference and no-ops under `ImageRenderer`.
Sheets and popovers presented from a themed root inherit it, so they need
nothing; a surface `ImageRenderer` hosts directly does need its own.

**`Appearance` is the only writer.** It sets `NSApp.appearance` as well as the
environment, because the service logos are asset appearance variants and
`NSImage(named:)` resolves those against `NSApp.effectiveAppearance`.
`setAppearance:` re-enters through its own `effectiveAppearance` observer before
the property reads back, so `apply()` carries a reentrancy flag. Without it the
process recurses until the stack runs out.

**`NSApp` is nil while the scene builds its state**, so the AppKit half waits on
`didFinishLaunching`. The snapshot entry points build a second `AppState` from
inside that callback, where the notification has already fired, which is why
`Appearance.init` carries both branches.

**Text on an accent fill uses `onAccent`, never `background`.** Standing in
`background` for it worked only while there was one appearance. `accent` is the
brand fill; `accentText` is the accent as a glyph, darkened in light because the
brand colour scores about 2:1 on white.

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
