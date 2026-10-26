# Automatic Updates and Direct Download Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Portfox and Localfox update themselves through Sparkle 2, and both sites offer a direct DMG download.

**Architecture:** Each app gets a small `Updater` wrapper around `SPUStandardUpdaterController`. It runs only when CI injected a feed URL. The release workflow signs a one-item appcast with EdDSA and uploads it next to the versioned DMG and a version-less DMG copy. The sites redirect `/download` and `/appcast.xml` to GitHub's `releases/latest/download/` assets.

**Tech Stack:** Swift 6, SwiftUI, XcodeGen, Sparkle 2 (SPM), GitHub Actions, Cloudflare Workers static assets `_redirects`, Homebrew cask.

**Spec:** `docs/superpowers/specs/2026-10-26-auto-updates-design.md`

## Global Constraints

- Sparkle 2.10.1, pinned exactly (`SPARKLE_VERSION=2.10.1`). The SPM pin in `project.yml` (`exactVersion`) and the CI tools tarball use the same value.
- Sparkle is a dependency of the app target only. `PortfoxKit` and `LocalfoxKit` never import it.
- The updater never starts when `SUFeedURL` is empty, or under `--snapshot` or `--demo`.
- Info.plist: `SUFeedURL = $(SPARKLE_FEED_URL)`, `SUPublicEDKey` committed, `SUEnableAutomaticChecks = true`, `SUAutomaticallyUpdate = false`, `SUEnableSystemProfiling = false`.
- Public keys: Portfox `ed/Ea97ltH7dmP37EcZKCj3qcDsmK0DvDWsHpXizTRc=`, Localfox `g3YuKJdBXQOB1odD6MEGRUIOQB4cmSMjLxZmXM7Vps0=`. Task 0 is done.
- Feed URLs: `https://portfox.kandera.cz/appcast.xml` and `https://localfox.kandera.cz/appcast.xml`. Only the release workflow sets them.
- Appcast enclosures use `https://github.com/xergic/<app>/releases/download/<tag>/<App>-X.Y.Z.dmg`, never a `latest` URL. Deltas are off.
- The private key is passed only through stdin (`--ed-key-file -`), from the secret `SPARKLE_ED_PRIVATE_KEY`.
- Release notes are the `## [X.Y.Z]` section of `CHANGELOG.md`. A missing section fails the release before the archive step.
- Do not write to `@Observable` state unless the value moved.
- One commit per feature, and every commit builds and passes `make lint` on its own. Conventional Commits, one sentence, no body, no co-author trailer.
- Pushing either site repo is a deploy. A tag push is a release. Pushing the tap reaches every brew user. Each one needs Ondra's explicit go-ahead in a later message.
- No new telemetry signals.

## Review Focus

1. **A local or fork build** (empty feed) must not crash, must not log Sparkle errors, and must hide the update rows. This is verified in Task 1, step 6.
2. **A tag without a CHANGELOG section** must fail in minutes, not after notarization. This is verified in Task 2, step 2.
3. **An update found while the app is in the background** (`LSUIElement`, no active window) must still bring the Sparkle window to the front. This is verified in Task 3, step 3, and Task 9.
4. **Localfox Install with services running** must ask first, and Later must leave every service running. This is verified in Task 9.
5. **A Localfox `-rc` tag** must not move `releases/latest` and must not bump the tap. This is verified in Task 6, step 3.

---

### Task 0: Keys and secrets (Ondra)

Nothing else can be released until this is done. Tasks 1 and 2 can be built in the meantime with a placeholder public key, but they cannot be committed with it.

- [ ] **Step 1: Get the Sparkle tools at `SPARKLE_VERSION`**

```bash
mkdir -p /tmp/sparkle && cd /tmp/sparkle
curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" | tar xJ
```

- [ ] **Step 2: Generate one keypair per app, export the private keys and store them as secrets**

```bash
for app in portfox localfox; do
  ./bin/generate_keys --account "$app"            # stores in the login keychain, prints the public key
  ./bin/generate_keys --account "$app" -x "$app.key"
  gh secret set SPARKLE_ED_PRIVATE_KEY -R "xergic/$app" < "$app.key"
  rm "$app.key"
done
```

Expected: two public keys printed. The Keychain entries are the offline backup. Also store them in a password manager.

- [ ] **Step 3: Send the two public keys to the implementer.** They are not secret.

---

### Task 1: Portfox updater in the app

**Files:**
- Modify: `project.yml` (package `Sparkle`, target dependency)
- Modify: `App/Portfox/Info.plist` (the five `SU*` keys)
- Create: `App/Portfox/Updater.swift`
- Modify: `App/Portfox/AppState.swift:190` (own an `Updater`)
- Modify: `App/Portfox/Views/PreferencesSheet.swift:359-393` (`generalSection`)
- Modify: `App/Portfox/Views/AboutSheet.swift:49` (button under `repositoryButton`)
- Modify: `.claude/CLAUDE.md` (dependency count and a rule, below)

**Interfaces:**
- Produces:

```swift
@MainActor @Observable
final class Updater {
    /// False when the build has no feed URL (local, fork) or is a snapshot run.
    var isAvailable: Bool { get }
    /// Mirrors `SPUUpdater.canCheckForUpdates`, assigned only when it moves.
    private(set) var canCheckForUpdates: Bool
    /// Reads and writes `SPUUpdater.automaticallyChecksForUpdates`.
    var automaticallyChecks: Bool
    init(updaterDelegate: (any SPUUpdaterDelegate)? = nil)
    func checkForUpdates()
}
```

- [ ] **Step 1: Add Sparkle to `project.yml`**

```yaml
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    exactVersion: <SPARKLE_VERSION>
```

Add a target dependency `- package: Sparkle` with `product: Sparkle`. Run `make gen`. Expected: no error.

- [ ] **Step 2: Add the Info.plist keys** from Global Constraints. Use `SPARKLE_FEED_URL` exactly the way `TELEMETRY_APP_ID` is used.

- [ ] **Step 3: Implement `Updater` in `App/Portfox/Updater.swift`**

- `isAvailable` is true only when `Bundle.main` `SUFeedURL` is non-empty and `SnapshotRenderer.request == nil`. When it is false, create no controller.
- Use `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate:, userDriverDelegate: self-owned delegate)`.
- The user driver delegate returns `supportsGentleScheduledUpdateReminders = true`. Its `standardUserDriverWillHandleShowingUpdate(_:forUpdate:state:)` calls `NSApp.activate()`, so the window comes forward in an `LSUIElement` app. No badge and no custom reminder UI.
- Observe `canCheckForUpdates` with `publisher(for: \.canCheckForUpdates)`.

- [ ] **Step 4: Own it in `AppState`** as `let updater = Updater()`.

- [ ] **Step 5: Add the UI**, shown only when `state.updater.isAvailable`:
  - `generalSection`, after "Launch at login": a `PreferenceRow` titled "Check for updates automatically" with the subtitle "Look for a new version once a day", bound to `automaticallyChecks`. Then a `PreferenceDivider`, and a row titled "Check for updates" with an `ActionButton` labeled "Check Now", disabled when `!canCheckForUpdates`.
  - `AboutSheet`: a "Check for Updates…" button styled like `repositoryButton`, under it.

- [ ] **Step 6: Verify a build with no feed**

Run: `make lint && make test && make run`
Expected: lint is clean and all tests pass. In the running app, Preferences > General and About show no update controls. Console.app filtered to `Portfox` shows no Sparkle lines.

- [ ] **Step 7: Verify a build with a feed**

Build once with an xcodebuild override `SPARKLE_FEED_URL=https://portfox.kandera.cz/appcast.xml` and open it.
Expected: the controls appear. "Check Now" shows Sparkle's "update error" window while the site has no redirect, and that proves the wiring. Run `make snapshot` and look at the preferences PNG. The rows must be absent there, because a snapshot has no updater.

- [ ] **Step 8: Update `.claude/CLAUDE.md`**

- The app target now has four dependencies, Sparkle included.
- Add this rule under Rules: "**The feed URL is not in the source.** `SUFeedURL` is `$(SPARKLE_FEED_URL)`, which only the release workflow sets, so a local build or a fork never offers to replace itself with the release build. `Updater` creates no controller without it."

Do not commit yet. Task 2 completes the feature.

---

### Task 2: Portfox release workflow

**Files:**
- Create: `Tools/release-notes.sh`
- Modify: `.github/workflows/release.yml:38-46` (version step), after `:170` (appcast), `:172-181` (publish)
- Modify: `CHANGELOG.md` (an entry for the feature in the next version)

**Interfaces:**
- Produces: `Tools/release-notes.sh VERSION [CHANGELOG]` prints the body of `## [VERSION]` up to the next `## [`, without the heading. It exits 1 with a message on stderr when the section is missing or empty. Task 6 copies it.

- [ ] **Step 1: Write the script** with `awk`. It must be POSIX `sh` and run on both macOS and ubuntu runners.

- [ ] **Step 2: Verify it**

```bash
Tools/release-notes.sh 1.5.0 | head -1    # expected: ### Added
Tools/release-notes.sh 9.9.9; echo $?     # expected: an error on stderr, then 1
```

- [ ] **Step 3: Fail fast in "Derive the version from the tag".** After the regex check, run `Tools/release-notes.sh "$version" > "$RUNNER_TEMP/notes.md"`.

- [ ] **Step 4: Pass the feed to the archive.** Add `SPARKLE_FEED_URL="https://portfox.kandera.cz/appcast.xml"` next to `TELEMETRY_APP_ID` in the `xcodebuild archive` call (`:100`).

- [ ] **Step 5: Add a "Build the appcast" step** after the Gatekeeper check. Set job env `SPARKLE_VERSION` and the secret as `SPARKLE_ED_PRIVATE_KEY`.
  1. Download and extract `Sparkle-$SPARKLE_VERSION.tar.xz` into `$RUNNER_TEMP/sparkle`.
  2. `mkdir "$RUNNER_TEMP/feed"` and copy `$DMG` into it.
  3. Render the notes to HTML with `gh api markdown -f mode=gfm -f text="$(cat "$RUNNER_TEMP/notes.md")" > "$RUNNER_TEMP/feed/Portfox-$VERSION.html"`. The HTML has the archive's basename, so `generate_appcast` picks it up.
  4. Run: `printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$RUNNER_TEMP/sparkle/bin/generate_appcast" --ed-key-file - --embed-release-notes --maximum-deltas 0 --download-url-prefix "https://github.com/xergic/portfox/releases/download/$GITHUB_REF_NAME/" "$RUNNER_TEMP/feed"`
  5. Assert that `appcast.xml` contains `sparkle:edSignature` and the versioned enclosure URL. Fail otherwise.
  6. `cp "$DMG" "$RUNNER_TEMP/Portfox.dmg"`

- [ ] **Step 6: Publish all three assets in one `gh release create`:** `$DMG`, `$RUNNER_TEMP/Portfox.dmg` and `$RUNNER_TEMP/feed/appcast.xml`. Replace `--generate-notes` with `--notes-file "$RUNNER_TEMP/notes.md"`. Leave the `sha256` output on `$DMG`, so the tap job is unchanged.

- [ ] **Step 7: Verify the workflow statically**

Run: `actionlint .github/workflows/release.yml` (install with brew if missing), then `make lint && make test`.
Expected: clean.

- [ ] **Step 8: Add the CHANGELOG entry and commit the feature**

```bash
git add project.yml App/Portfox Tools/release-notes.sh .github/workflows/release.yml CHANGELOG.md .claude/CLAUDE.md
git commit -m "feat(app): install updates with Sparkle"
```

---

### Task 3: Portfox release with Sparkle (needs a go-ahead)

- [ ] **Step 1: Ask Ondra for the go-ahead.** Then add the version heading to CHANGELOG, commit `chore: release X.Y.0` and push the tag.

- [ ] **Step 2: Verify the release assets**

```bash
gh release view vX.Y.0 -R xergic/portfox --json assets -q '.assets[].name'
# expected: Portfox-X.Y.0.dmg, Portfox.dmg, appcast.xml
curl -fsSL https://github.com/xergic/portfox/releases/latest/download/appcast.xml | grep -c 'releases/download/vX.Y.0/Portfox-X.Y.0.dmg'
# expected: 1
```

- [ ] **Step 3: Check the background update window (Review Focus 3).** On the next release (X.Y.1), install X.Y.0, wait for the scheduled check, or trigger it with `defaults delete net.kandera.Portfox SULastCheckTime` and a relaunch. Expected: the update window appears in front, Install relaunches into X.Y.1, and About shows the new version. This is not a gate for Portfox, but record the result in the spec.

---

### Task 4: portfox-web download and feed redirects

**Files:**
- Create: `portfox-web/public/_redirects`
- Modify: `portfox-web/src/App.tsx:720-745` (`build-panel`)
- Modify: `portfox-web/src/faq.ts:10`, `src/guides.ts:21,238`, `src/GuidePages.tsx:81` (wherever install is described as brew only)

- [ ] **Step 1: Write `_redirects`**

```
/download     https://github.com/xergic/portfox/releases/latest/download/Portfox.dmg  302
/appcast.xml  https://github.com/xergic/portfox/releases/latest/download/appcast.xml  302
```

- [ ] **Step 2: Add the download link.** Under the brew command in `build-panel`, add a secondary link "Download for Mac" to `/download`. Change the requirement line to "Requires macOS 15+ and Apple Silicon." Keep the "Get Homebrew" link. The brew block stays first and visually primary. Use existing classes only.

- [ ] **Step 3: Update the install copy.** The FAQ answer and the guides say: install with brew, or download the DMG from portfox.kandera.cz/download.

- [ ] **Step 4: Verify**

```bash
bun run build && bunx wrangler dev --port 8787 &
curl -sI localhost:8787/download | grep -i '^location'
# expected: .../releases/latest/download/Portfox.dmg
curl -sI localhost:8787/appcast.xml | grep -i '^location'
```

Expected: also a visual check of the install section at desktop and mobile widths.

- [ ] **Step 5: Commit locally:** `feat: add a direct download link`. Do not push. A push deploys. Deploy only after Task 3's release exists and Ondra says so.

---

### Task 5: Homebrew cask for Portfox (needs a go-ahead to push)

**Files:** `homebrew-tap/Casks/portfox.rb`

- [ ] **Step 1: Pull first.** The local clone is behind `origin`.
- [ ] **Step 2: Edit the cask.** Add `auto_updates true` after `depends_on`. Turn `zap trash:` into an array that also covers `~/Library/Caches/net.kandera.Portfox` and `~/Library/HTTPStorages/net.kandera.Portfox`, where Sparkle keeps its downloads and its state.
- [ ] **Step 3: Verify:** `brew style Casks/portfox.rb && brew audit --cask --tap xergic/tap portfox`. Expected: no offenses.
- [ ] **Step 4: Commit** `feat(portfox): mark as auto-updating`. Push only after Task 3 has shipped and Ondra says so.

---

### Task 6: Localfox updater, install guard and release workflow

The same as Tasks 1 and 2, in `/Users/ondra/Work/Personal/Localfox/localfox`, with the Localfox names and feed URL. Copy `Tools/release-notes.sh` unchanged. Then make three additions.

**Files (beyond the Task 1 and 2 equivalents):**
- Create: `App/Localfox/InstallGuard.swift`
- Modify: `.github/workflows/release.yml` (version step, publish, `tap` job)

**Interfaces:**
- Consumes: `Updater(updaterDelegate:)` from the copied `Updater.swift`, `AppState.runningCount: Int` (`AppState.swift:400`), `AppDelegate.state` (`LocalfoxApp.swift`).
- Produces: `final class InstallGuard: NSObject, SPUUpdaterDelegate`, created with a `weak` `AppState`.

- [ ] **Step 1: Hold the relaunch while services run.** Implement `updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)`. When `runningCount == 0`, return `false`. Otherwise show an `NSAlert`, return `true`, and call the block only on "Install Now". Fixed copy:
  - message: `Installing stops \(n) running service\(n == 1 ? "" : "s").`
  - informative: `Localfox stops every service it started when it quits to install the update.`
  - buttons: `Install Now`, `Later`

- [ ] **Step 2: Add a feed override for the upgrade test.** Implement `feedURLString(for:)`. Return the user default `UpdateFeedOverride` when it is an `https` URL, otherwise `nil` (the Info.plist feed). It is safe, because every update still has to carry the app's EdDSA signature.

- [ ] **Step 3: Allow `vX.Y.Z-rc.N` tags.**
  - The version step accepts `^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$`.
  - It outputs `version` (suffix stripped, used for `MARKETING_VERSION`, the notes and the DMG name) and `prerelease=true|false`.
  - `gh release create` adds `--prerelease` for an rc.
  - The `tap` job gets `if: needs.release.outputs.prerelease != 'true'`.

  Verify: `actionlint`, and this regex check in a shell.

```bash
for t in v1.6.0 v1.6.0-rc.1 v1.6 v1.6.0-beta; do [[ "${t#v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] && echo "$t ok" || echo "$t no"; done
# expected: ok ok no no
```

- [ ] **Step 4: Verify:** `make lint && make test`, plus Task 1's steps 6 and 7 for Localfox.
- [ ] **Step 5: Update `.claude/CLAUDE.md`** with the feed URL rule from Task 1. Add one more rule: "**An update asks before it stops services.** Quitting runs `stopEverything()`, so `InstallGuard` holds Sparkle's relaunch while `runningCount > 0`."
- [ ] **Step 6: Commit** `feat(app): install updates with Sparkle`.

---

### Task 7: Localfox release N (needs a go-ahead)

Same as Task 3, step 1 and step 2, for Localfox. Release N ships without waiting for the upgrade test.

### Task 8: localfox-web and the Localfox cask

Same as Tasks 4 and 5, with these Localfox differences:
- The panel is at `localfox-web/src/App.tsx:600-640`, and `INSTALL_COMMAND` is at `:81`.
- `faq.ts:10` also changes.
- The Localfox cask keeps its `uninstall launchctl` and `zap script` stanzas. It gains `auto_updates true` and the two Sparkle paths.

Commits: `feat: add a direct download link` and `feat(localfox): mark as auto-updating`. Push each only on Ondra's go-ahead.

---

### Task 9: Localfox upgrade gate (before N+1)

This runs on a real Mac with Localfox N installed from the release DMG.

- [ ] **Step 1: Publish the release candidate.** Add CHANGELOG `## [N+1]`. On Ondra's go-ahead, push tag `vN+1-rc.1`. Expected: a prerelease, `releases/latest` still on N, and no tap commit.
- [ ] **Step 2: Point Localfox N at the candidate's feed:** `defaults write net.kandera.Localfox UpdateFeedOverride https://github.com/xergic/localfox/releases/download/vN+1-rc.1/appcast.xml`, then relaunch.
- [ ] **Step 3: Set up the test.** Start two services, one proxied over HTTPS through the helper. Trust state is as it is today.
- [ ] **Step 4: Run Check for Updates, then Install.** Expected: the prompt says "Installing stops 2 running services." Click Later. Expected: both services keep running, and the proxied URL still answers. Stop both. Expected: the update installs and Localfox relaunches on its own.
- [ ] **Step 5: Install N+1 again from N with services running, and choose Install Now.** Expected: Localfox relaunches as N+1.
  - The helper reports N+1 without Reinstall.
  - Starting the services again works.
  - The proxied HTTPS URL answers with no certificate warning.
  - `security find-certificate -c "Localfox"` shows the same CA hash as before.
  - Either no approval prompt appears, or the app explains it.
- [ ] **Step 6: Test the background window.** Repeat with no window open and the scheduled check (Review Focus 3).
- [ ] **Step 7: Clean up and record.** `defaults delete net.kandera.Localfox UpdateFeedOverride`. Record the results in the spec.
  - If the helper needed re-registration: fix it per the spec, keep the XPC protocol backward compatible, then cut `rc.2` and repeat.
  - If everything passed: on Ondra's go-ahead, tag `vN+1`.
