# Update banner and relaunch fix

Portfox and Localfox. Follows `2026-10-26-auto-updates-design.md`.

## Why

A scheduled Sparkle check opens a window that steals focus from a menu bar app,
and the user often misses it or dismisses it. Ondra wants the app to say an
update is out in its own UI, quietly, and install on one click.

Separately, installing from About (Portfox) or Preferences (both apps) never
relaunches: the old version keeps running in the dashboard.

## Goals

- When a scheduled check finds an update, show a sticky accent row with
  "<App> X.Y.Z is available" and "Update…". No Sparkle window, no activation.
- The row sits above the bottom bar in the popover (above the footer) and in the
  dashboard (above the sidebar footer, my call: the dashboard has no window-wide
  bottom bar).
- Clicking it opens Sparkle's standard window (release notes, Install, progress,
  errors). The row disappears once that window is opened or the session ends,
  so it never offers a window with nothing left to do.
- Installing relaunches the new version, whether or not a sheet is open.
- Localfox's InstallGuard alert keeps working.

## Non-goals

- Menu bar icon indicator. Revisit after the banner ships.
- A custom Sparkle user driver or inline download progress.
- Our own check timer. Sparkle's daily scheduler stays.
- A shared Swift package for the two `Updater.swift` copies.

## Approaches

- **Chosen: standard user driver with gentle reminders.**
  `standardUserDriverShouldHandleShowingScheduledUpdate` returns false for
  scheduled checks, `standardUserDriverWillHandleShowingUpdate` publishes the
  version to `Updater`, `standardUserDriverWillFinishUpdateSession` clears it.
  The row calls `checkForUpdates()`, which brings up the pending standard UI.
- Rejected: custom `SPUUserDriver`. Rebuilds download, install, error and retry UI.
- Rejected: own timer plus `checkForUpdatesInBackground()`. Competes with
  Sparkle's scheduler and can still pop the standard window.

## Relaunch fix

Most likely cause (from source, not yet reproduced): the About or Preferences
sheet stays attached to the dashboard while Sparkle sends the quit request, and
AppKit refuses to terminate with a sheet attached. Fix:

- Every update entry point (About, Preferences, banner) dismisses
  `presentedSheet` first and runs `checkForUpdates()` once the sheet is gone.
- Sheets also get `.presentationPreventsAppTermination(false)` if the SDK has it
  on the deployment target, which covers a sheet opened during the download.

Verify by reproducing with a local appcast, test EdDSA key and two builds with
ascending build numbers, sheet open versus closed.

## Left to the builder

- Banner copy, icon and exact padding, within `Theme` tokens (`accent` fill,
  `onAccent` text).
- How the deferred check after sheet dismissal is plumbed.
- Localfox: making the InstallGuard alert asynchronous is optional, only if the
  test shows `runModal` interferes.
