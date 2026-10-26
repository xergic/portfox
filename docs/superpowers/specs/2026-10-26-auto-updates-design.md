# Automatic updates and direct download

Portfox and Localfox, plus their sites and the Homebrew tap.

## Why

Not every user has Homebrew. Today the only install path on either site is
`brew install --cask`, and a user who installs the DMG from GitHub Releases
stays on that version forever, because neither app checks for updates. Ondra
wants this as a convenience feature: a download button on each site, and an
app that keeps itself current.

## Goals

- Both apps use Sparkle 2 to check for updates once a day. When an update is
  out, the standard Sparkle window shows the release notes and an Install
  button. The user decides when to install. (Confirmed by Ondra.)
- Each site has a download button that always serves the latest DMG.
- Brew users keep their current path, and brew and Sparkle do not fight.
- A release is still just pushing a `vX.Y.Z` tag. No site deploy is needed per
  release.

## Non-goals

- Installing updates silently.
- Delta updates.
- Beta or pre-release channels.
- An update server or any infrastructure beyond GitHub Releases and the
  existing Cloudflare sites.
- Telemetry about updates.
- Intel builds.

## Anti-goals

These count as failures even if updates technically work.

- An update that leaves Localfox's helper on an old version, makes the user
  approve the helper again without explanation, or touches the root CA or the
  user's trust in it.
- Any Sparkle private key that shows up in a log, a command line or the repo.
- A release that needs a site deploy to reach users.
- Download replacing brew as the main CTA. Developers should still see brew
  first.

## Current state

- Both release workflows (`.github/workflows/release.yml`) archive, export with
  Developer ID, notarize and staple the app, then build, notarize and staple
  `<App>-<version>.dmg`. Then `gh release create ... --generate-notes` uploads
  it, and a `tap` job bumps `xergic/homebrew-tap/Casks/<app>.rb`.
- `CFBundleVersion` is the Actions run number, so it only goes up.
- Both apps have App Sandbox off and hardened runtime on, so Sparkle needs no
  XPC services.
- Both app repos are public. Both site repos are private, Vite + React, deployed
  as Cloudflare Workers static assets (`wrangler.jsonc`) on push to `main`.
- Localfox embeds a privileged LaunchDaemon helper via SMAppService
  (`BundleProgram` inside the bundle), vendored `caddy` and `cloudflared`, and a
  root CA stored outside the bundle. `HelperClient.replaceOutdatedHelper`
  already retires an old helper after the bundle changes, which is the path
  `brew upgrade` exercises today.

## Design

### In the apps

- Sparkle 2 as an SPM dependency of the app target only. The kits never import
  it. Pin an exact version.
- `SPUStandardUpdaterController`, started at launch only when `SUFeedURL` is
  non-empty, and never under `--snapshot` or `--demo`.
- *My call:* `SUFeedURL` is `$(SPARKLE_FEED_URL)`, which only the release
  workflow sets, the same pattern as `TELEMETRY_APP_ID`. A `make run`, a
  `make archive` or a fork has no feed and never offers to replace itself with
  the release build. `SUPublicEDKey` is committed, because it is public by
  design.
- Info.plist: `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks = YES`
  (daily check without Sparkle's "may we check?" prompt),
  `SUAutomaticallyUpdate = NO`, system profiling off. *Builder's call: the
  interval stays at Sparkle's 24h default.*
- UI: a "Check for Updates…" button and a "Check for updates automatically"
  toggle in Preferences. The toggle is how a brew user turns Sparkle off.
  *My call: also a "Check for Updates…" button in the About sheet. Exact
  placement and copy match the existing Preferences controls.*
- One EdDSA keypair per app. The public key goes in Info.plist. The private key
  goes only in that repo's Actions secrets and an offline backup.

### Feed and archives

- Archive format: the stapled DMG CI already builds.
- `SUFeedURL` is `https://<app>.kandera.cz/appcast.xml`. The site's
  `_redirects` sends that with a 302 to
  `https://github.com/xergic/<app>/releases/latest/download/appcast.xml`.
  *My call:* the feed URL is compiled into every copy forever, so it lives on
  Ondra's domain. Where it points can change later without an app release. The
  appcast itself is a release asset, so publishing never touches the site.
- The appcast holds only the latest version. Enclosure URLs are the versioned
  `releases/download/vX.Y.Z/<App>-X.Y.Z.dmg`, never a `latest` URL.
- The update window shows that version's `CHANGELOG.md` section. *My call:*
  `--generate-notes` produces only a compare link, because commits go straight
  to `main`. The workflow extracts the `## [X.Y.Z]` section, fails the release
  when it is missing, and uses it for both the appcast and the GitHub release
  body. *Builder's call:* embedded HTML or Markdown, whichever the pinned
  Sparkle renders.

### Release workflow, per app

After the DMG is stapled and validated:

1. Copy the DMG to `<App>.dmg` (no version) for the download link.
2. Run Sparkle's `generate_appcast`, from the release tarball pinned to the same
   Sparkle version as the app. Pass the private key through stdin
   (`--ed-key-file -`), never as an argument. Set the download URL prefix to the
   versioned release path. Delta generation off.
3. `gh release create` uploads `<App>-X.Y.Z.dmg`, `<App>.dmg` and
   `appcast.xml` together, so `latest` never points at a release with a missing
   asset.

New secret per repo: `SPARKLE_ED_PRIVATE_KEY`.

### Sites

- `public/_redirects` in each site repo:
  - `/download` → 302 → `https://github.com/xergic/<app>/releases/latest/download/<App>.dmg`
  - `/appcast.xml` → 302 → `https://github.com/xergic/<app>/releases/latest/download/appcast.xml`
- A "Download for Mac" button next to the brew command, secondary to it, with
  "macOS 15+, Apple silicon" under it.
- The FAQ and guides that say "install with brew" mention the download as the
  other way.
- Ondra must give an explicit go-ahead before either site is pushed. A push is a
  deploy.

### Homebrew

- Add `auto_updates true` to both casks. Keep the versioned URLs, sha256 and
  livecheck. The existing `tap` job keeps bumping them.

### Localfox running services

Quitting Localfox stops every service it runs (`applicationShouldTerminate`
calls `stopEverything()`), and installing an update quits the app. When the
user clicks Install while services run, Localfox asks first, for example
"Installing stops 3 running services. Install now?" Cancel postpones the
install. There is no automatic restart after the relaunch. (Decided by Ondra.)
Builder's call: the Sparkle delegate hook that holds the relaunch.

### Localfox gate

Localfox gets the same changes. *My call:* the first Sparkle release (N) can
ship, because it reaches users through brew or a manual install, the same
bundle swap that works today. The second (N+1) ships only after a signed
N→N+1 Sparkle upgrade on a real Mac, with the helper running and at least one
service proxied. It passes when:

- the running-services prompt appears, and Cancel leaves everything running,
- the helper reports the new version without manual Reinstall,
- `caddy` and `cloudflared` come back and proxied services answer,
- the root CA and the user's trust in it are unchanged,
- and either no new approval prompt appears, or the app explains it.

Unverified: whether a bundle swap with an unchanged launchd plist needs
SMAppService re-registration. If the test shows it does, fix that before
shipping N+1. *My call:* the fix may add UI that explains a re-approval, and
must keep the helper XPC protocol backward compatible, so an old helper can
still be retired.

## Order

1. Ondra generates both keypairs and adds the secrets.
2. Portfox: Sparkle, UI and release workflow, released as the next minor.
3. portfox-web: `_redirects` and the button. Deploy right after step 2's
   release exists, so `/download` never points at a missing asset. *My call:*
   the feed 404s for that short gap. Scheduled checks fail silently, and only a
   manual check would show an error.
4. Tap: `auto_updates true` for Portfox.
5. Localfox: same as step 2. The upgrade test runs before N+1 goes out.
6. localfox-web and the Localfox cask, same as steps 3 and 4.

Every user must install the first Sparkle version by hand or through brew.
After that, updates come through Sparkle.

## Left to the builder

- Sparkle version, and how CI fetches its tools.
- Whether `generate_appcast` or `sign_update` plus a template is simpler for a
  one-item feed.
- Release notes format in the appcast.
- Exact button styling on both sites, within the existing design.
- How to stage the Localfox upgrade test (a local feed, or a test release).
