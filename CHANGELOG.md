# Changelog

Notable changes to Portfox. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-10-01

### Added
- Orphaned dev servers are flagged. A server whose launcher exited, such as a `workerd` left behind by a dead `wrangler dev`, gets an "Orphaned" badge and a count in the popover. It shows even when it only binds high ports. Restart is not offered for it.
- Dev servers started by Claude Code or Codex get a badge naming the agent.
- Claude Code plugin daemons, such as the `claude-mem` worker, are recognized. They list under a new "Agent tools" section with the plugin name and version. Restart and Stop All skip them.

### Changed
- The menu bar popover is redesigned. It has a header with the app icon, a status summary line, and services shown as cards.
- The dashboard is redesigned to match the popover, with a segmented filter, lighter cards and a cleaner process tree.
- Section titles and labels use sentence case in the system font. Versions, ports, PIDs and paths stay monospace.

### Fixed
- A plugin worker no longer lands in the project group of whichever Claude Code session started it.
- A process whose parent exited is no longer kept with its stale parent in the process cache.
- The scan rebuilds when a launcher exits but its server keeps running, so Stop no longer targets the dead launcher.
