# RackPulse restyle: Portfox and Localfox

## Intent

Ondra thinks the RackPulse panel (https://en3sis.com/tools/rackpulse, hero
mockup) looks more polished than Portfox and Localfox. This is a visual
restyle of both apps to match the RackPulse look. Nothing is wrong with
how the apps work.

Success: put the popover next to the RackPulse panel and they look like they
come from the same designer. Every surface also stays recognisably Portfox or
Localfox, with the same content and the same brand colour.

Reference mockup (style A) and the side-by-side with today's popover:
`/tmp/portfox-rackpulse/.superpowers/brainstorm/*/content/popover-style.html`.
Today's look: `snapshots/popover-demo.png`, `dashboard-demo.png`,
`preferences.png`, `about.png`.

## Goals

- Restyle every surface in both apps: popover, dashboard, preferences, About.
- Style A (flat, two-line rows) is the default.
- Style B (flat, one-line rows) is a new preference. This is the only new
  behaviour.
- Dark and light mode both get the restyle.

## Non-goals

- No new content. RackPulse has a status banner, sparklines and a tab bar.
  None of these are added.
- No content is removed either. Hover actions, pins, the arrival flash,
  context menus, origin and container badges, uptime and CPU all stay.
- No change to the brand accent colours (Portfox teal, Localfox purple), the
  app icons or the service logos.
- The marketing sites (`portfox-web`, `localfox-web`) are not part of this
  work.

## Anti-goals

- A redesign that changes where things are. Users must find every control
  where it was.
- A blind write to `@Observable` state, or anything else that makes the
  dashboard redraw on the refresh tick. The rule in `.claude/CLAUDE.md` still
  applies.
- A row height or width that changes on hover. Today the hover actions take
  the port pill's slot without moving anything. This must still be true.

## The look (decided)

These come from the RackPulse panel and the approved mockup.

- **Flat rows.** A service is no longer a separate card. Rows sit directly on
  the panel surface. A 1px hairline (`Theme.separator`) goes between two rows
  of the same group. There is no hairline above the first row of a group.
- **Group headers.** A project or section label is uppercase, 10.5pt semibold,
  with about 0.07em letter spacing, in `secondaryText`. The right side shows
  the project path (in mono, `tertiaryText`) or a count such as "3 services".
  The project icon and the project hover actions stay.
- **Ports.** Plain right-aligned mono text (`portPort`) with a `tertiaryText`
  colon. No box. The fixed width stays, so ports still line up and the hover
  actions keep their slot.
- **Badges** (origin such as "Claude Code", container runtime, LAN share):
  9pt bold, uppercase, radius 3, tinted fill at about 16% opacity.
- **Header.** An 18pt app icon, then the app name at 13pt semibold. There is
  no subtitle line. The counts line stays below at 11pt. The header buttons
  become borderless 22pt icon buttons, with a faint fill on hover.
- **Search field.** 26pt high, radius 6, `pill` fill, no border.
- **Footer.** A single 11pt line with `secondaryText` labels and
  `tertiaryText` shortcut hints, for example "Settings ⌘," and "Quit ⌘Q".
  Only show a shortcut that already exists. The version is shown in mono.
- **Surface.** Every surface (popover, dashboard, Preferences, About) moves
  from today's near-black `background` to a mid grey, about `#1c1c1e`. Light
  mode uses white. Contained elements step one shade lighter to stay visible:
  the search field and `pill` at about `#2a2a2d`, plus the dashboard fact
  tables and the process tree. Retune `cardHover`, `separator` and `border`
  to match. Ondra chose this over a popover-only change.
- **Typography.** The scale in `Theme.swift` mostly stays. Service names
  become 12.5pt semibold. Versions, ports, PIDs and paths stay mono, and
  labels stay in the system font.

### Style A: two lines (default)

- Line 1 has the name, the version and the badges.
- Line 2 has the subtitle (folder, role or Homebrew), uptime and CPU.
- The icon is 16pt. Vertical padding is about 8pt.

### Style B: one line

- The same content runs on one line: name, version, subtitle, then badges.
- Badges never disappear. Origin, container and share badges carry warnings
  such as an orphan or a public tunnel.
- When the line does not fit, the subtitle truncates first, then the name.
  If it still does not fit, that row falls back to the style A layout
  (`ViewThatFits`).
- In Localfox the domain is the subtitle and it never truncates. The name
  gives way first, because the domain is what the row exists to show.
- The icon is 14pt. Vertical padding is about 6pt.

### Project-first layout (Portfox)

- Keep today's order: the project name and version lead, and the service,
  with its small icon, follows.
- Style A puts these on two lines, as today. Style B puts them on one line.
- The project name is not dropped, even under a group header. In a sibling
  group the header reads `Wishfox`, while each row names its own repository.
- Pinned rows follow the same rules.

### The setting

- Add a "Compact rows" toggle to the Appearance section of Preferences in
  both apps. It is stored in `UserDefaults`, and the default is off (style A).
- It applies to the popover and to the dashboard sidebar list.
- In Portfox it combines with the existing "Service list layout"
  (Service/Project) setting, so there are four combinations. All four must
  look right.

## Surfaces

- **Popover:** as described above, matching the mockup.
- **Dashboard sidebar:** the same rows as the popover. The selected row gets
  an accent-tinted fill (`selectedRow`) and no border.
- **Dashboard header and detail pane:**
  - The same compact header treatment as the popover.
  - Section titles such as "Process metadata" become the uppercase group label
    style.
  - Fact tables keep their container, but rows get hairlines and the tighter
    type.
  - Action buttons become 24pt high with 12pt text. The primary action keeps
    the accent fill.
- **Preferences:**
  - Section titles become the uppercase label style.
  - Rows inside a group get the same hairlines and tighter padding.
  - Use the small control size for toggles and segmented pickers.
- **About:** the same type scale and a smaller button. The layout stays.
- **Localfox:**
  - The same rules apply.
  - Status words (Stopped, Failed, Waiting) become plain coloured text in the
    port slot, with no box.
  - The HTTP status codes (200, 500) become tinted badges.
  - Its `Theme.swift` is a near copy of Portfox's, so mirror the token changes
    there.

## Process constraints

- Portfox first, then Localfox. Use the Portfox result as the reference.
- Each app gets exactly one commit per feature, and each commit builds on its
  own. Use two commits per repo:
  - `feat(app): restyle surfaces after RackPulse`
  - `feat(app): add compact rows preference`
- The compact snapshot variant and the regenerated README images go in the
  second commit, because only then do the final images exist.
- Run `make lint`, `make test` and `make snapshot` in each repo. Check every
  PNG in dark and light mode.
- Add a compact snapshot variant of the popover.
- Regenerate the README images in `docs/images/` from the new demo snapshots,
  so the README matches the app.
- Update `.claude/CLAUDE.md` in each repo. Note the flat row rule and the
  compact setting.

## Left to the builder

- Exact hover treatment on a flat row. The row must visibly highlight, the
  hover actions must appear in the port slot, and nothing may move.
- Exact light-mode values, as long as they follow the same structure and pass
  the existing contrast reasoning in `Theme.swift`.
- Whether `CardBackground` and the card tokens are kept for the dashboard
  detail containers or retired.
- Spacing details that the mockup does not pin down.

## My calls (Claude), not confirmed by Ondra

- Drop the header subtitle ("Local services").
- Name the setting "Compact rows", put it in Appearance, and apply it to the
  dashboard sidebar too.
- Regenerate the README images as part of this work.
- Show Localfox statuses as plain text, not pills.
