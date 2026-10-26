# RackPulse Restyle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle every surface of Portfox and Localfox after the RackPulse panel. The look is flat rows, uppercase group labels, plain ports and a mid-grey surface. The only new behaviour is a "Compact rows" preference.

**Architecture:** This is a token and component change. `Theme.swift` and the shared views in `Views/Components.swift`, `PortPill.swift`, `StatusPill.swift` and `SearchField.swift` carry most of the look. Rows stop drawing their own card. Instead, the group that holds them draws hairlines between them. Portfox goes first and becomes the reference. Localfox mirrors it.

**Tech Stack:** Swift 6, SwiftUI, macOS 15+, XcodeGen, SwiftLint. `ImageRenderer` snapshots are the visual check.

**Spec:** `docs/superpowers/specs/2026-10-26-rackpulse-restyle-design.md`. Read it first. Every value below comes from it.

## Global Constraints

- **Visual only.** Do not add or remove content. Hover actions, pins, the arrival flash, context menus, origin, container and share badges, uptime and CPU all stay.
- **Brand stays.** The accent colours, app icons and service logos do not change.
- **Surface.** The base is mid grey `#1c1c1e` in dark mode and white in light mode. Contained elements (search field, `pill`, dashboard fact tables, process tree) are about `#2a2a2d` in dark mode.
- **Fonts.** Versions, ports, PIDs and paths are mono (`Font.mono`). Labels use the system font.
- **No moving rows on hover.** A row's height and the width of its text must not change when it is hovered, selected, flashing or showing actions. The hover actions take the port's fixed-width slot.
- **No blind writes.** Do not write to `@Observable` state unless the value changed. See the rule in `.claude/CLAUDE.md`.
- **Shortcut hints.** Show only shortcuts that exist. Today only Quit ⌘Q exists in both apps.
- **Comments.** Add none that restate the code. Fix or delete any existing comment that the restyle makes wrong. For example, `CardBackground` is described as "the popover row's resting card", and `ProjectSectionView` says "a card header above cards".
- **Commits.** Each repo gets exactly two commits, and each one builds on its own:
  1. `feat(app): restyle surfaces after RackPulse`
  2. `feat(app): add compact rows preference`

  Use Conventional Commits with no body and no co-author trailer. Work on `main`.
- **Verification.** There are no app-target tests. After every task, run `make lint` and `make test` (both must be clean) and `make snapshot`. Then open the PNGs it names. A task is done only when its snapshot checklist passes.
- **Scratch files** go in `/tmp/portfox-rackpulse`.

## Review Focus

These are the five conditions most likely to bite a user that the demo fixture does not show. Each one is checked in the task that owns it.

1. **Long names and paths.** In both row styles, a long project name, service name or path must truncate. It must never push the port off the row or wrap the row. Checked in Task 2 and Task 5.
2. **A service on two or more ports.** The `+N` corner badge on the port must still be visible and must not clip once the pill box is gone. Checked in Task 2.
3. **Hover, arrival flash and selection on a flat row.** Each must visibly mark the row without moving anything. The arrival wash must still read over the hover fill. Checked in Task 2 (popover) and Task 3 (dashboard sidebar).
4. **Project-first layout.** It must look right with compact rows both off and on. Checked in Task 2 and Task 5.
5. **Light mode.** Hairlines, the hover fill and contained elements must stay visible on white. Text must keep the contrast that `Theme.swift` documents. Checked in every task through the `-light` snapshots.

To check items 1 and 2, start two real listeners before running `make snapshot`, so the non-demo snapshots show them:

```sh
mkdir -p "/tmp/portfox-rackpulse/a-really-long-project-name-for-truncation-checks" && cd "$_" \
  && echo '{"name":"a-really-long-project-name-for-truncation-checks"}' > package.json \
  && (python3 -m http.server 4321 & python3 -m http.server 4322 &)
```

Kill them when the task is done.

To check items 4 and 5 without touching the user's saved settings, pass the setting in the NSArgumentDomain. `AppState` reads `UserDefaults.standard`, so the setting applies to that run only and is never persisted:

```sh
APP=~/Library/Developer/Xcode/DerivedData/<derived>/Build/Products/Debug/Portfox.app/Contents/MacOS/Portfox  # path from the Makefile's DERIVED
$APP --snapshot /tmp/portfox-rackpulse/pf-project.png --demo -cellLayout projectFirst
```

---

## Portfox, commit 1: restyle

### Task 1: Tokens and shared components

**Files:**
- Modify: `App/Portfox/Theme.swift`
- Modify: `App/Portfox/Views/Components.swift`
- Modify: `App/Portfox/Views/PortPill.swift`
- Modify: `App/Portfox/Views/StatusPill.swift`
- Modify: `App/Portfox/Views/SearchField.swift`

**Interfaces:**
- Produces:
  - `Font.portGroupLabel`: system 10.5pt, semibold.
  - `View.groupLabelStyle()`: applies `portGroupLabel`, `.textCase(.uppercase)`, `.tracking(0.7)` and `secondaryText`. This is the uppercase label used everywhere.
  - `Theme.Metrics.rowRadius: CGFloat = 6`: the hover and selection fill on a flat row.
  - `Theme.Metrics.headerButtonSize = 22`.
  - `CardBackground` is still used for contained elements only, never for rows.

- [ ] **Step 1: Retune the palette in `Theme.swift`.**
  - Dark mode values: `background` = `#1c1c1e`, `card` = `#2a2a2d`, `pill` = `#2a2a2d`, `cardHover` about `#333336`.
  - Retune `separator` and `border` alpha so a hairline is visible on `#1c1c1e`. Start at white 0.07 and 0.10.
  - Light mode: `background` = white, `card` and `pill` about `#f2f2f4`, black hairlines at 0.08 and 0.12.
  - Re-derive the opaque `selectedRow` over the new `background`. Its comment says it is "the accent mixed into `card`". Keep that the truth for whatever it now mixes into.
  - `portName` becomes 12.5pt semibold. Add `portGroupLabel`.
  - Metrics: `headerButtonSize` 22, `controlHeight` stays 28 for buttons, add `rowRadius` 6.
- [ ] **Step 2: Restyle `TintedBadge`.**
  - 9pt bold, uppercase, tracking 0.45, horizontal padding 4, vertical padding 1, radius 3, fill `tint.opacity(0.16)`.
  - This one change restyles the origin, container, LAN and process-role badges.
- [ ] **Step 3: Remove the box from `PortPill`.**
  - Remove the `ControlBackground`. Keep the fixed `portPillWidth` and trailing-align the text inside it.
  - Keep the `+N` corner badge.
  - `HealthPill` keeps `statusPillWidth` and moves to the `TintedBadge` look: radius 3, fill 0.16.
- [ ] **Step 4: Restyle `SearchField`.**
  - Height 26, radius 6, `pill` fill, no stroke, prompt 12pt.
  - Add `Theme.Metrics.searchHeight = 26`. Leave `controlHeight` alone, because buttons use it.
- [ ] **Step 5: Restyle `IconButton` and `AppHeader`.**
  - `IconButton(filled: true)` draws no stroke. It shows a faint `cardHover` fill on hover only, and `frameSize` defaults to 22.
  - `AppHeader` shows an 18pt `AppIconView` and the name at 13pt semibold. Remove its `subtitle` parameter and update every caller.
  - Spacing: `SummaryCount` uses 11pt (`portCaption`). Keep the dot at 6pt.
- [ ] **Step 6: Restyle `ControlBackground` and `ActionButton`.**
  - `ControlBackground` keeps its radius (8) and its hairline for buttons.
  - `ActionButton` becomes 24 high, with a 12pt label and padding 9.
  - `SegmentedControl` keeps the accent fill. The spec does not change it.
- [ ] **Step 7: Build and check.**
  - Run `make lint && make test && make snapshot`.
  - Expected: lint clean, tests pass, and `popover.png` renders with the new surface colour.
  - Rows still look like cards at this point, which is fine. Task 2 makes them flat.

### Task 2: Flat rows and the popover

**Files:**
- Modify: `App/Portfox/Views/ServiceRowView.swift` (`rowBackground`, padding, icon size)
- Modify: `App/Portfox/Views/ServiceSections.swift`
- Modify: `App/Portfox/Views/ProjectSectionView.swift` (header and `SectionHeader`)
- Modify: `App/Portfox/Views/PinPlaceholderRow.swift`
- Modify: `App/Portfox/Views/HoverActionsView.swift` (only if its background no longer matches)
- Modify: `App/Portfox/Views/MenuView.swift` (header, search padding, footer)

**Interfaces:**
- Consumes: `groupLabelStyle()`, `Theme.Metrics.rowRadius` and `searchHeight` from Task 1.
- Produces: `RowList<Data, Row>`, a `View` in `ServiceSections.swift`. It lays out rows in a `VStack(spacing: 0)` and draws a 1px `Theme.separator` hairline between neighbours, never above the first row. `ServiceSections` and `ProjectSectionView` both use it, so the hairline rule lives in one place.

- [ ] **Step 1: Make `ServiceRowView` flat.**
  - There is no fill at rest.
  - On hover, when highlighted or showing actions, draw `RoundedRectangle(cornerRadius: rowRadius).fill(Theme.cardHover)`.
  - When selected, draw `selectedRow` with no border.
  - Keep the arrival overlay, using the same `rowRadius` shape.
  - Inset: the row keeps its 12pt horizontal padding, so the fill extends about 6pt past the hairlines' text edge. The hairline then starts at the text edge.
  - Vertical padding is 8. The service icon is 16pt (`Theme.Metrics.serviceIcon` becomes 16). Keep the project icon in the group header at 16 too.
- [ ] **Step 2: Add `RowList` and use it.**
  - In `ServiceSections`, use it for the pinned, standalone, agent and ungrouped sections, and the placeholders.
  - In `ProjectSectionView.services`, use it for the project's own rows.
  - Hide a hairline next to a hovered or selected row, so the fill does not look cut. The simple way is to draw the hairline with `opacity(0)` when either neighbour is highlighted. If neighbour state is awkward to reach, draw the hairline inside each row's top edge, inset to the text, and let the row's fill cover it.
- [ ] **Step 3: Restyle the group headers.**
  - `SectionHeader(title:trailing:)` gets a new optional `trailing: String?`. The title uses `groupLabelStyle()`. The trailing text is right-aligned at 11pt in `tertiaryText`.
  - Infrastructure and the other standalone sections pass `"\(count) services"`, or `"1 service"` for one.
  - In the `ProjectSectionView` header:
    - The name uses `groupLabelStyle()`.
    - The path is right-aligned in mono 11 (`portSubtitle`) in `tertiaryText`, truncating at the head.
    - Keep the 16pt icon, the pin glyph and the hover actions overlay, with the path's trailing reserve unchanged.
- [ ] **Step 4: Restyle the `MenuView` chrome.**
  - The header uses the new `AppHeader` with the summary stacked, and the subtitle gone.
  - The buttons are borderless `IconButton(filled: true)`.
  - Outer padding is 14 horizontal, 12 top and 8 bottom.
  - The search field sits 14pt from the edges.
  - The footer is one 11pt line. `FooterButton` loses its SF Symbol, and its label is `secondaryText` at 11pt.
    - The order is Dashboard, Stop all, then a spacer, then the mono version, Settings…, and "Quit ⌘Q" with the `⌘Q` in `tertiaryText`.
    - Padding is 9 vertical and 14 horizontal.
- [ ] **Step 5: Restyle `PinPlaceholderRow`.** It follows the same flat-row treatment as Step 1.
- [ ] **Step 6: Check the snapshots.**
  - Start the two listeners from Review Focus.
  - Run `make lint && make test && make snapshot`.
  - Render the project-first popover with the argument-domain command from Review Focus, in dark and light.
  - Open `popover.png`, `popover-light.png`, `popover-demo.png`, `popover-demo-light.png`, `arrived.png`, `arrived-light.png` and `pf-project*.png`.
  - Then run `--snapshot … --demo --hover`. Pass when all of these hold:
    - It matches the A panel of the approved mockup: flat rows, hairlines, uppercase labels, plain ports and the compact header and footer.
    - The long-name project truncates, and its port stays aligned with the others.
    - The listener on two ports shows a visible `+1`.
    - The hover snapshot shows the actions in the port slot, with every row the same height as at rest.
    - The arrived row is visibly washed in both appearances.
    - Light mode hairlines and the search field are visible.

### Task 3: Dashboard

**Files:**
- Modify: `App/Portfox/Views/Dashboard/DashboardContent.swift` (header)
- Modify: `App/Portfox/Views/Dashboard/ServiceListPane.swift` (sidebar padding, filter, footer line)
- Modify: `App/Portfox/Views/Dashboard/ServiceHeaderView.swift`
- Modify: `App/Portfox/Views/Dashboard/DetailCard.swift`
- Modify: `App/Portfox/Views/Dashboard/ProcessTreeCard.swift`
- Modify: `App/Portfox/Views/Dashboard/ServiceDetailPane.swift`

**Interfaces:**
- Consumes: `RowList`, `SectionHeader`, `groupLabelStyle()`, and the restyled `ActionButton` and `AppHeader`.

- [ ] **Step 1: Restyle the header.**
  - It uses `AppHeader` with the summary inline and the subtitle gone.
  - The buttons are borderless 22pt icons.
  - Vertical padding is 12, and there is one hairline below.
- [ ] **Step 2: Restyle the sidebar.**
  - It already renders `ServiceSections`, so the rows come out flat. The selected row shows the `selectedRow` fill with no border.
  - The search field is 26pt.
  - The bottom count line is 11pt `secondaryText`.
- [ ] **Step 3: Restyle the detail pane.**
  - Section titles such as "Process metadata", "HTTP inspection" and "Process ancestry & child workers" use `groupLabelStyle()` and drop their SF Symbol.
  - `DetailCard` keeps its container (`card` fill, radius 10, `separator` stroke). Its rows get 12pt type, hairlines between them and 8pt vertical padding.
  - `ServiceHeaderView`: the service icon box goes and a bare 28pt icon is used. The name is 16pt semibold. The "Project: wishfox" chip becomes a `TintedBadge` with the tint `secondaryText`.
  - The process tree keeps its listener wash and border, with the restyled badges.
- [ ] **Step 4: Check the snapshots.**
  - Run `make lint && make test && make snapshot`.
  - Open `dashboard.png`, `dashboard-light.png` and `dashboard-demo.png`.
  - Pass when all of these hold:
    - The sidebar matches the popover rows.
    - The selected row is visibly marked and the same height as its neighbours.
    - The detail containers are distinguishable from the `#1c1c1e` surface in dark mode and from white in light mode.
    - No control moved to a different place.

### Task 4: Preferences and About, then commit

**Files:**
- Modify: `App/Portfox/Views/PreferencesSheet.swift`
- Modify: `App/Portfox/Views/PreferencesControls.swift`
- Modify: `App/Portfox/Views/AboutSheet.swift`
- Modify: `.claude/CLAUDE.md`

- [ ] **Step 1: Restyle Preferences.**
  - The sheet header uses the compact header treatment.
  - Section titles use `groupLabelStyle()` with no SF Symbol.
  - Grouped rows keep their container, with hairlines between rows.
  - Row title is 12.5pt medium, description is 11pt `secondaryText`, and vertical padding is 8.
  - Toggles and pickers use `.controlSize(.small)` where they are system controls. The custom `SegmentedControl` gets a 22pt height.
  - The Done button is the restyled `ActionButton`.
- [ ] **Step 2: Restyle About.**
  - Keep the layout. The name is 15pt semibold.
  - The version stays mono at 11pt in `secondaryText`.
  - The GitHub and Done buttons use the restyled `ActionButton`.
- [ ] **Step 3: Update `.claude/CLAUDE.md`.**
  - In the "Appearance" section, add a paragraph on the flat row rule:
    - A row never draws its own card.
    - `RowList` owns the hairlines.
    - Hover and selection are a `rowRadius` fill.
  - Fix any text that says "card per row".
- [ ] **Step 4: Check the snapshots.**
  - Run `make lint && make test && make snapshot`.
  - Open `preferences.png`, `preferences-light.png`, `ignored.png`, `about.png` and `about-light.png`.
  - Pass when every setting is still present, in its old order, and readable in both appearances.
- [ ] **Step 5: Commit.**

  ```bash
  git pull --rebase
  git add App/Portfox .claude/CLAUDE.md
  git commit -m "feat(app): restyle surfaces after RackPulse"
  ```

## Portfox, commit 2: compact rows

### Task 5: Compact rows preference

**Files:**
- Modify: `App/Portfox/AppState.swift` (property, `Key`, init read)
- Modify: `App/Portfox/Views/PreferencesSheet.swift` (Appearance section)
- Modify: `App/Portfox/Views/ServiceRowView.swift`
- Modify: `App/Portfox/Views/PinPlaceholderRow.swift`
- Modify: `App/Portfox/Views/ServiceSections.swift` (pass the flag)
- Modify: `App/Portfox/Views/ProjectSectionView.swift` (pass the flag)
- Modify: `Makefile` (snapshot target)
- Modify: `docs/images/popover-dark.png`, `docs/images/popover-light.png`
- Modify: `.claude/CLAUDE.md`

**Interfaces:**
- Produces: `AppState.compactRows: Bool`. It is stored under the `UserDefaults` key `"compactRows"`, defaults to `false`, and is written in `didSet` like `cellLayout`.

- [ ] **Step 1: Add `compactRows` to `AppState`.**
  - Add `Key.compactRows = "compactRows"`.
  - Read it in `init` with `defaults.bool(forKey:)`, so the argument domain `-compactRows YES` works for snapshots.
- [ ] **Step 2: Add the Preferences toggle.**
  - Put a row in Appearance, directly below "Service list layout".
  - Title: "Compact rows". Description: "One line per service, so more fit before the list scrolls".
- [ ] **Step 3: Add the one-line layout to `ServiceRowView`.**
  - When `state.compactRows` is on, the row is one line.
  - Service-first order: icon (14pt), name, version, subtitle in `secondaryText` at 11pt, uptime and CPU, then badges.
  - Project-first order: project name, project version, small service icon and service name, then badges.
  - Vertical padding is 6.
  - Build it as `ViewThatFits(in: .horizontal) { oneLine; twoLine }`, where `twoLine` is the existing style A body:
    - Inside `oneLine`, the subtitle has the lowest `layoutPriority`, the name is next, and the badges are `fixedSize()`.
    - Badges are never dropped. A row whose one line cannot fit falls back to the two-line layout.
  - `PinPlaceholderRow` follows the same rule.
- [ ] **Step 4: Add the compact snapshots to the `Makefile`.**
  - `popover-compact.png`: `--snapshot … --demo -compactRows YES`
  - `popover-compact-light.png`: the same, plus `--light`
  - `popover-compact-project.png`: `--demo -compactRows YES -cellLayout projectFirst`
- [ ] **Step 5: Check the snapshots.**
  - Start the Review Focus listeners.
  - Run `make lint && make test && make snapshot`.
  - Also render a non-demo `-compactRows YES` popover with the listeners running.
  - Pass when all of these hold:
    - The compact popovers match the B panel of the mockup.
    - The long-name row falls back to two lines with its badge intact, or truncates its subtitle, and never loses the badge.
    - Project-first compact shows the project name.
    - `preferences.png` shows the new toggle.
- [ ] **Step 6: Regenerate the README images and update `.claude/CLAUDE.md`.**
  - Copy `snapshots/popover-demo.png` to `docs/images/popover-dark.png`.
  - Copy `snapshots/popover-demo-light.png` to `docs/images/popover-light.png`.
  - In `.claude/CLAUDE.md`, add a line that compact rows fall back per row through `ViewThatFits` and never drop a badge.
- [ ] **Step 7: Commit.**

  ```bash
  git pull --rebase
  git add App/Portfox Makefile docs/images .claude/CLAUDE.md
  git commit -m "feat(app): add compact rows preference"
  ```

## Localfox (repo `/Users/ondra/Work/Personal/Localfox/localfox`)

The look is already settled by the Portfox result. Read the Portfox diff (`git -C <portfox> show HEAD~1 HEAD`) before starting.

### Task 6: Localfox restyle, then commit

**Files:**
- Modify: `App/Localfox/Theme.swift`
- Modify: `App/Localfox/Views/Components.swift` (`AppHeader`, `CardBackground`, `ControlBackground`, `TintedBadge`, `PortPill`, `ActionButton`, `IconButton`)
- Modify: `App/Localfox/Views/SearchField.swift`
- Modify: `App/Localfox/Views/ServiceRow.swift`
- Modify: `App/Localfox/Views/MenuView.swift` (including `ProjectSection`)
- Modify: `App/Localfox/Views/DashboardView.swift` (`DetailCard`, `LabeledRow`, `CardDivider`, header)
- Modify: `App/Localfox/Views/ServiceDetailPane.swift`
- Modify: `App/Localfox/Views/PreferencesSheet.swift` (its private `SegmentedControl` and `PreferenceRow` too)
- Modify: `App/Localfox/Views/AddProjectSheet.swift`, `EditProjectSheet.swift` (only `ControlBackground` and `CardBackground` callers that break)
- Modify: `.claude/CLAUDE.md`

- [ ] **Step 1: Mirror Portfox Task 1** in `Theme.swift` and `Components.swift`, using the same values. Keep Localfox's purple accent and its own `selectedRow` mix.
- [ ] **Step 2: Mirror Portfox Task 2** in `ServiceRow`, `MenuView` and `ProjectSection`. Add a `RowList` in `MenuView.swift` next to `ProjectSection`.
  - Localfox-specific rules:
    - The status words "Stopped", "Failed" and "Waiting" become plain text in the port slot, with no box. Use the status colour that the pill uses today, and keep the same fixed width.
    - The HTTP status codes "200" and "500" become `TintedBadge`s.
    - The project header dot overlay on the icon stays.
- [ ] **Step 3: Mirror Portfox Tasks 3 and 4** in the dashboard, Preferences and About.
- [ ] **Step 4: Check the snapshots.**
  - Run `make lint && make test && make snapshot`.
  - Open every PNG the target writes, including `popover-hover.png` and `add-route-demo.png`.
  - Use the same pass rules as Portfox Tasks 2–4. Also check that every status (running, waiting, stopped, failed, shared) is still told apart at a glance.
- [ ] **Step 5: Update `.claude/CLAUDE.md`** with the flat row rule, then commit:

  ```bash
  git pull --rebase
  git add App/Localfox .claude/CLAUDE.md
  git commit -m "feat(app): restyle surfaces after RackPulse"
  ```

### Task 7: Localfox compact rows, then commit

**Files:**
- Modify: `App/Localfox/Preferences.swift` (a new `Bool` preference, key `"compactRows"`, default `false`, through the existing `write` helper)
- Modify: `App/Localfox/Views/PreferencesSheet.swift` (Appearance row, same title and description as Portfox)
- Modify: `App/Localfox/Views/ServiceRow.swift`
- Modify: `Makefile`, `docs/images/popover-dark.png`, `docs/images/popover-light.png`, `.claude/CLAUDE.md`

- [ ] **Step 1: Add the preference and its toggle,** as in Portfox Task 5 Steps 1–2.
- [ ] **Step 2: Add the one-line `ServiceRow`.**
  - Order: icon, name, domain (mono), then badges.
  - The domain never truncates and the name gives way first. This is the rule in the spec.
  - A row that cannot fit falls back to two lines through `ViewThatFits`.
- [ ] **Step 3: Add the compact snapshots and check them.**
  - Add `popover-compact.png` and `popover-compact-light.png` with `--demo -compactRows YES`.
  - Run `make lint && make test && make snapshot` and check the B look.
- [ ] **Step 4: Regenerate the README images and update `.claude/CLAUDE.md`,** as in Portfox Task 5 Step 6, then commit:

  ```bash
  git pull --rebase
  git add App/Localfox Makefile docs/images .claude/CLAUDE.md
  git commit -m "feat(app): add compact rows preference"
  ```

## After all tasks

- Run `/simplify` over each repo's two commits.
- Run one independent review of the whole diff, either an Opus or a Sol review, for blocking issues only.
- Delete `/tmp/portfox-rackpulse` and stop the mockup server.
- Do not push. Ondra decides on push and release.
