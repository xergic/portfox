# PortFox

A macOS menu bar app that shows what is listening on your local ports, which project it belongs to, and lets you stop it.

Discovery works from processes, not from port numbers, so custom ports need no configuration.

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
```

`PortFox.xcodeproj` is generated from `project.yml` and is not in version control. Run `make gen` after changing the project definition.

## Layout

`PortFoxKit` is a SwiftPM library holding the whole pipeline. The app target is a thin SwiftUI shell.

```
ListenerScanner → ProcessInspector → ProcessTree → ProjectResolver
    → DetectionEngine → ListenerClassifier → IconResolver → ServiceRepository → SwiftUI
```

Every stage takes and returns plain value types, and no stage imports SwiftUI. `portfox-scan` drives the identical pipeline from the command line, so detection can be developed and verified without launching the GUI.

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
2. A row in the relevant file under `Sources/PortFoxKit/Detection/Detectors/`.
3. An entry in `Tools/fetch-icons.py`, then `python3 Tools/fetch-icons.py`.

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

## Snapshots

`PortFox --snapshot out.png [--hover]` renders the popover to a file. It needs no Screen Recording permission and no pointer, so the design can be iterated on directly.

It renders the list without its scroll container, because `ImageRenderer` lays out in a single pass and never draws scroll content. That is also why the popover measures its own list height rather than letting the `ScrollView` size itself: inside a `MenuBarExtra` window a `ScrollView` has no intrinsic height and collapses to nothing.

## Known limitations

- Only processes owned by the current user are visible. A database installed as a root daemon will not appear.
- Working directory lookups fail for hardened-runtime processes. Those services still appear, without a project.
- Dynamic `app.config.js` and `app.config.ts` are not evaluated, only their static JSON equivalents.
- A service whose ports are all ephemeral is hidden by default. That is what orphaned `workerd` children look like. Turn on *Show all listeners* to see them.
- Launch at login needs a signed build. It fails on a local ad hoc one.

## Icons

Framework logos come from [simple-icons](https://github.com/simple-icons/simple-icons), whose icon paths are CC0. The trademarks belong to their owners and are used only to identify the software each service is running. Regenerate with `python3 Tools/fetch-icons.py`.
