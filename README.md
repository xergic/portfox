# Portfox

A macOS menu bar app that shows what is listening on your local ports, which project it belongs to, and lets you stop it.

Discovery works from processes, not from port numbers, so custom ports need no configuration.

There is no signed release yet, so Portfox is built from source.

## Requirements

- macOS 15 or later
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) and [SwiftLint](https://github.com/realm/SwiftLint), both via `brew install xcodegen swiftlint`

## Build and run

```sh
make run      # build and launch the menu bar app
make test     # run the core test suite
make scan     # resolve services on this machine, no GUI
make lint     # SwiftLint
make archive  # package a universal build to hand to someone
```

`Portfox.xcodeproj` is generated from `project.yml` and is not in version control. Run `make gen` after changing the project definition.

## Packaging a build to share

```sh
make archive              # version from the latest git tag
make archive VERSION=0.2.0
```

This writes `dist/Portfox.app` and `dist/Portfox-<version>.dmg`, both universal, and fails if either the arm64 or the x86_64 slice is missing. `dist/` is wiped on each run and is not in version control.

The build is ad hoc signed, not notarized, so macOS blocks it on another machine and offers no right-click Open. Whoever receives it clears the quarantine flag once:

```sh
xattr -dr com.apple.quarantine /Applications/Portfox.app
```

Launch at login also needs a real signature, so it fails on this build. Push a `vMAJOR.MINOR.PATCH` tag instead when either matters. `.github/workflows/release.yml` signs with a Developer ID, notarizes, staples and publishes a DMG that installs with no warnings.

## Layout

`PortfoxKit` is a SwiftPM library holding the whole pipeline. The app target is a thin SwiftUI shell.

| Path | Holds |
| --- | --- |
| `Sources/PortfoxKit/` | The pipeline. No SwiftUI and no UI state. |
| `Sources/portfox-scan/` | The command line tool over the same pipeline. |
| `App/Portfox/` | The SwiftUI app: state, views, theme, snapshot renderer. |
| `Tests/PortfoxKitTests/` | Tests for the kit. |
| `Tools/` | Icon fetching, app icon generation, and release packaging. |

## Architecture

One scan runs one pipeline. Each stage narrows raw sockets into something the UI can name.

```
ListenerScanner → ProcessInspector → ProcessTree → ProjectResolver
    → DetectionEngine → ListenerClassifier → IconResolver → ServiceRepository → SwiftUI
```

- **ListenerScanner** asks `lsof` for TCP sockets in LISTEN state. It needs no privileges and only ever returns the current user's processes.
- **ProcessInspector** reads every process's parent, owner and start time from `sysctl`, then reads the expensive fields (executable, argv, working directory) for listeners and their ancestors only.
- **ProcessTree** answers ancestors, descendants and the logical root, stopping at a shell, a terminal or an app bundle.
- **ProjectResolver** walks up from the working directory looking for a manifest such as `package.json` or `pyproject.toml`.
- **DetectionEngine** scores every detector and takes the winner, breaking ties toward the more specific service type.
- **ListenerClassifier** sorts each service into a development service, infrastructure, a probable developer process, or system noise.
- **ServiceRepository** is an actor that owns the pipeline and its caches. A tick whose socket set has not moved returns the previous result instead of rebuilding it.

Every stage takes and returns plain value types, and no stage imports SwiftUI. `portfox-scan` drives the identical pipeline from the command line, so detection can be developed and verified without launching the GUI.

## The dashboard

The popover footer opens a dashboard window.

A searchable, filterable service list sits on the left. The right pane shows everything known about the selected service: process metadata (PID, executable, working directory, resident memory), an HTTP inspection panel, and the process ancestry with its child workers, one row per process, each labelled by its role:

- Parent Shell for a boundary process (a shell, terminal or supervisor), never walked through or signalled.
- Runner for a wrapper such as `pnpm` or `nodemon`.
- Listener for the service itself.

The row Portfox would actually signal on Stop is badged "stops here".

## Settings

Settings live in a sheet inside the dashboard, replacing the old Settings window. The dashboard's toolbar opens it, and so does the popover footer, which opens the window and the sheet together.

- **Automatic refresh loop**: poll listening TCP sockets while a window is open. Off stops the timer entirely. With every window closed the loop drops to one scan a minute, which is only there to keep the menu bar count current.
- **Polling interval**: 1s, 2s or 5s, used while a window is open. Disabled while automatic refresh is off.
- **Show count in menu bar**: draw the number of active services next to the icon. Off leaves the glyph alone.
- **Service list layout**: Service or Project, which fact leads each row. Daemons and databases always stay service-first, since their resolved project is an accident of where they run.
- **Show uptime**: how long each service has been running, beside its folder. Read at scan time, so it ages in jumps rather than counting seconds.
- **Show CPU usage**: percent of one core, listener and workers together, as Activity Monitor counts it. It is measured between two scans, so it stays blank with the refresh loop off.
- **Show all listeners**: include background system ports such as CUPS or mDNSResponder.
- **Hide infrastructure and daemons**: leave out databases, daemons and anything without a project, and drop them from the counts. Hides the whole *Infrastructure & Daemons* section and the dashboard's DB chip along with it. Like ignoring, it is a preference of the app, so `portfox-scan` still lists them.
- **Group related services by project**: fold sibling repositories under their shared parent directory.
- **Ignored services**: the list of services you have hidden, each with a remove button. Right-click any service and choose *Ignore Service* to add one. Ignored services leave the popover, the dashboard, the menu bar count and the memory total. An ignored service that is running can also be un-ignored from the *Ignored* chip in the dashboard sidebar.
- **Editor** and **Terminal**: which app *Open in…* uses. Only apps installed on this Mac are listed. The editor opens the repository, the terminal opens the directory the service actually runs in.
- **Launch at login**: start Portfox automatically when you log in.

## Stopping and restarting

Right-click a service for *Restart*, or press it in the dashboard header. Portfox
stops the service, then hands its own command line to your terminal, which opens
a window running it again in the same directory.

The command is rebuilt from the service's *logical root*, the same process Stop
signals, so `pnpm dev` comes back as `pnpm dev` rather than as the inner node
server. It runs through `zsh -l`, so nvm, direnv, asdf and mise are all back in
place. A plain respawn would inherit Portfox's own environment, and a
version-managed runtime would simply be missing.

Relaunching in a terminal rather than in the background is deliberate. The logs
stay visible, Ctrl-C still stops it, and the server does not die with Portfox.

Portfox refuses to restart rather than guess:

- Databases and daemons. Homebrew, DBngin and Docker bring their own back, so a
  hand-relaunched copy would end up unmanaged beside the supervised one.
- Anything whose working directory or command line could not be read, whose
  directory has been deleted, or whose binary is gone after an upgrade.
- A shell or terminal session, which Stop already refuses to signal.

Restart needs a terminal that runs a script handed to it. Terminal, iTerm2 and
Warp were tested doing so. For any other terminal the menu offers *Stop and Copy
Command* instead, which stops the service and leaves the command on the
pasteboard.

**Stop All** sits in the popover footer once two or more services are listed. It
arms on the first press and fires on the second, because a `MenuBarExtra` popover
closes the moment focus leaves it and a modal confirmation would arrive after the
list it was asking about had gone.

## The scan CLI

```sh
swift run portfox-scan             # grouped service list, the popover's view
swift run portfox-scan --raw       # every listener with pid, port, exe, argv, cwd
swift run portfox-scan --diagnose  # explain how each listener was resolved
swift run portfox-scan --all       # include listeners classified as system noise
swift run portfox-scan --json      # machine readable
swift run portfox-scan --stop 3000 # SIGTERM the service on a port
```

## Adding a service detector

Detectors are declarative rows, not code. Adding one costs three edits:

1. A case in `ServiceType`, with its display name, category and default ports.
2. A row in the relevant file under `Sources/PortfoxKit/Detection/Detectors/`.
3. An entry in `Tools/fetch-icons.py`, either in `ICONS` or in `NO_BRAND_ICON` with a reason, then `python3 Tools/fetch-icons.py`.

`CatalogueGuardTests` fails the build if a type has no detector, no icon decision, or a threshold no combination of its signals can reach.

A row looks like this:

```swift
RuleBasedDetector(type: .nextJS, threshold: standardThreshold, signals: [
    .binPath("next", 100),
    .commandContains("next-server", 90),
    .configFile("next.config", 70),
    .dependency("next", 60),
    .defaultPort(3000)
])
```

Signals sharing a `group` are alternatives, so only the strongest match scores and the group counts once toward confidence. Command-ish helpers default to the `command` group, port helpers to `port`.

Command matching is word-boundary aware. A command line is mostly filesystem paths, so plain substring search labels `ngrok` as Angular (`/bin/ng`) and `vitepress` as Vite. `String.containsToken` requires a non-word character on each side of the match.

`defaultPorts` is ordered by usefulness, not numerically. When a service binds several of its own defaults, the first one wins the port pill, so Mailpit shows its web UI on 8025 rather than SMTP on 1025.

Every detector must produce at least one match in its `requiredGroup`, which defaults to `command`. Project evidence alone never identifies a service. Without that rule, `adb` running inside an Expo project was reported as Expo.

## How stopping works

Stop sends `SIGTERM` to the service's *logical root*, not to the process holding the socket. For `pnpm dev` that is the `pnpm` process, so the task runner does not survive its child.

The walk up the process tree stops hard at an interactive shell, a terminal emulator or any application bundle. Signals are never sent to a process group, because a dev server started from a terminal shares its group with your shell.

Children that outlive their parent are swept with the same `SIGTERM`. Anything that ignores that is reported by pid rather than escalated automatically. `SIGKILL` only ever happens when you ask for it.

## HTTP inspection

Inspecting a service sends one GET request to it and reads back the status, page title, `Server` header and latency. It only runs when you press Inspect. It never runs on the refresh tick, so opening the dashboard never touches a service that happens to be listening.

The request is refused unless the URL's host is `localhost`, `127.0.0.1` or `::1`, and it never follows a redirect. A 3xx response shows its `Location` header instead. Together those two rules mean a dev server cannot walk the probe off the machine or trap it in a redirect loop.

## Snapshots

Three flags render a surface to a file and exit, without a pointer or Screen Recording permission:

```sh
Portfox --snapshot out.png [--hover]        # the popover
Portfox --snapshot-dashboard out.png        # the dashboard window
Portfox --snapshot-prefs out.png            # the preferences sheet
```

Preferences needs its own flag rather than sharing the dashboard's, because it is a sheet, and a sheet is a separate window that never renders inside its parent.

`ImageRenderer` lays out in a single pass and never draws scroll content, so every snapshot renders without its scroll container: the popover's list, the dashboard's panes, and the preferences sheet all carry the same `scrolls` escape hatch. That is also why the popover measures its own list height rather than letting the `ScrollView` size itself: inside a `MenuBarExtra` window a `ScrollView` has no intrinsic height and collapses to nothing. A `TextField` is NSTextField-backed and renders as a placeholder block under `ImageRenderer`, so the dashboard's search box draws its contents as flat text in snapshots instead.

## Known limitations

- Only processes owned by the current user are visible. A database installed as a root daemon will not appear.
- Working directory and resident memory lookups fail for hardened-runtime processes, along with the other libproc fields. Those services still appear, without a project or a memory reading.
- A service whose type is `.unknown` never gets a `localURL`, so it can never be HTTP-inspected even when it obviously serves HTTP.
- Dynamic `app.config.js` and `app.config.ts` are not evaluated, only their static JSON equivalents.
- Ignoring is a preference of the menu bar app, so `portfox-scan` still lists and can still stop an ignored service. That is deliberate: the CLI reports the machine, not your filters.
- An ignore is matched by port plus project directory, or port plus executable path for a service with no project. Move a project or change its port and the ignore no longer applies.
- A service whose ports are all ephemeral is hidden by default. That is what orphaned `workerd` children look like. Turn on *Show all listeners* to see them.
- Launch at login needs a signed build. It fails on a local ad hoc one.
- Restart only works with a terminal that runs a script handed to it. Terminal, iTerm2 and Warp do. Anything else gets *Stop and Copy Command*.
- CPU is measured between two scans, so it reads blank while automatic refresh is off.

## Contributing

Portfox will be open sourced. Issues and pull requests are welcome now.

### Getting set up

```sh
brew install xcodegen swiftlint
make test     # confirm the toolchain works
make run      # build and launch
```

`make scan` runs the whole detection pipeline in the terminal. Use it while working on detection, because it is far faster than launching the GUI.

### Before you open a pull request

```sh
make lint     # must be clean
make test     # must pass
make snapshot # after any UI change, then look at snapshots/
```

New behaviour in `PortfoxKit` needs a test. The kit is pure value types with injectable dependencies, so nearly everything is testable without a running machine. `Tests/PortfoxKitTests/Fixtures/live-machine-scan.txt` is a recorded `lsof` sweep used by the regression tests, so detection changes can be checked against a real machine.

The app target has no tests. Verify UI changes with `make snapshot`.

### House rules

- Swift 6 language mode with complete strict concurrency. Do not weaken either.
- `PortfoxKit` never imports SwiftUI or AppKit. If a change needs UI types in the kit, the change belongs in the app.
- Preferences belong to the app, not the kit. The kit reports the machine as it is, which is why `portfox-scan` still lists a service you ignored in the app.
- Nothing touches a user's dev server on the refresh tick. The HTTP probe only runs when the user presses Inspect.
- Comments explain a non-obvious *why*, usually naming the bug that forced the decision. Do not add comments that restate the code.
- `Portfox.xcodeproj` is generated and not in version control. Change `project.yml` and run `make gen`.

### Commits and pull requests

Commit messages use [Conventional Commits](https://www.conventionalcommits.org/), one short sentence, no body:

```
feat(dashboard): add a process tree card
fix(detection): stop labelling ngrok as Angular
```

A pull request should say what the change does and why, not how. Mention any trade-off you made.

The easiest first contribution is a new service detector. See *Adding a service detector* above.

## License

[MIT](LICENSE). Copyright (c) 2026 Ondra Kandera.

## Icons

Framework logos come from [simple-icons](https://github.com/simple-icons/simple-icons), whose icon paths are CC0. The trademarks belong to their owners and are used only to identify the software each service is running. Regenerate with `python3 Tools/fetch-icons.py`.
