# UPD lane report: Updating & YouTube Integration (2026-11-22)

Static review only (no Swift toolchain, no Mac). Every `path:line` below was read in
/home/user/LocalTube. Web facts are cited with the date of the source. Status labels:
confirmed / suspected / fixed-already.

## 0. Verdict

The app-update plumbing (Sparkle + GitHub Actions) is surprisingly complete and mostly
sane, but has ordering/race holes, ships arm64-only, and has never been proven end to end
on a clean Mac. The YouTube side is the real danger: the live React UI has NO way to
install yt-dlp/ffmpeg, nothing ever updates or version-checks yt-dlp, the channel-add form
stores a raw string with no validation, and the first sync of a source channel queues
every video on the channel with no cap. Several "fixed" items in old docs are fixed in the
Swift service but the fix lives in legacy SwiftUI Views that the AppKit entry point never
shows (resolver, dependency installer).

---

## 1. App updates: release/update risk register

Files read: RELEASING.md, .github/workflows/release.yml + build.yml, Scripts/package_app.sh,
release.sh, setup-sparkle.sh, enable-auto-updates.sh, appcast.xml, version.env, Package.swift,
Package.resolved, AppDelegate.swift:20-23, 245-253, 341-345.

Facts established
- Sparkle app dependency resolves to 2.9.1 (Package.resolved) but release/setup/enable scripts
  download Sparkle *tools* 2.6.4 (release.sh:40, setup-sparkle.sh:17, enable-auto-updates.sh:24). Skew; EdDSA is
  compatible, so harmless today.
- Info.plist (package_app.sh:44-69) has SUFeedURL, SUPublicEDKey, SUEnableAutomaticChecks=true.
  Absent: SUAutomaticallyUpdate, SUAllowsAutomaticUpdates, SUScheduledCheckInterval (default 24h),
  SUVerifyUpdateBeforeExtraction. `SPUStandardUpdaterController(... userDriverDelegate: nil)`
  (AppDelegate.swift:22-23) = stock Sparkle alert UI.
- Appcast: 33 items; releases v1.0.34 and v1.0.35 exist on GitHub (list_releases) but have NO appcast
  entries (published before the signing key reached CI). Latest release v1.0.37 = 2026-09-11, 10 weeks ago.
  Sparkle picks the highest sparkle:version regardless of item order, so prepend ordering is fine.
- `version.env` IS tracked (git ls-files) even though `.gitignore` lists `version.env` (.gitignore line "version.env").
  Harmless because tracked files ignore .gitignore, but misleading and fragile (a fresh `git init`/copy loses it).
- Release triggers on every push to master not matching `**.md` (release.yml:25-29). A change to a script or workflow
  file alone cuts a user-visible release. Sep 6 to Sep 11 shipped 4 releases (1.0.34 to 1.0.37).
- CI pushes the release commit with GITHUB_TOKEN: no re-trigger loop (GITHUB_TOKEN pushes do not start workflows) plus the
  `startsWith(head_commit.message,'Release ')` guard (release.yml:48). Side effect: a human PR whose squash title starts with
  "Release " is silently skipped.
- Universal binary: package_app.sh:27-31 defaults `ARCH_LIST` to `uname -m`; neither release.sh nor release.yml sets ARCHES;
  runner is `macos-15` (Apple Silicon). So releases are arm64 only. Spec (LocalTube_Parameters.md:306) says universal.
  The lipo path already exists (package_app.sh:94-96), so the fix is `ARCHES="arm64 x86_64"` in release.sh.
- Ad-hoc signing, empty entitlements, no hardened runtime (package_app.sh:175-211). No notarization. Min OS 14.0 in both
  Info.plist and appcast.

### Risk register

| ID | Risk | Likelihood | Impact | Evidence | Mitigation (effort) |
|---|---|---|---|---|---|
| R1 | Appcast + tag pushed BEFORE the GitHub Release/zip exists. If `gh release create` fails or lags, the appcast head points at a 404 zip; because Sparkle offers the highest version, EVERY install sees a broken update until the next successful release. raw.githubusercontent also caches ~5 min. | Med | High | release.sh:192-221 (commit, push, tag push, then `gh release create`) | Create a draft release and upload the zip first, verify with `curl -I`, then push commit+appcast, then publish. (S) |
| R2 | Stale-master push race: checkout is `ref: master` at start; build takes 5-8 min; `git push origin HEAD` is rejected if another PR merged meanwhile. Script dies after local commit+tag, nothing published. Self-heals only if the second merge triggers a run (a docs-only second merge does not, leaving code unreleased). | Med | Low-Med | release.yml:51-54, release.sh:200-203 | `git pull --rebase` + retry, or publish from the tagged SHA and push only version.env/appcast with rebase. (S) |
| R3 | No safety net on bad releases: every merge auto-ships to all installs within 24h; no phased rollout, no staging, no kill switch besides publishing a higher version or hand-editing appcast. Sparkle supports `sparkle:phasedRolloutInterval` (7 groups over the interval; Sparkle docs, Publishing page) and critical-update flags. | Med | High (a TV box stops playing) | release.sh:158-169 item template has none | Add phasedRolloutInterval=86400*3; gate releases behind `workflow_dispatch` or a `release` label; keep a documented "pull an item from appcast" runbook. (S) |
| R4 | arm64-only build vs "drag to target machine" and the spec's universal claim. Any Intel Mac that supports macOS 14 (2018+ Mac mini/MBP/iMac, popular as TV boxes) cannot launch it. | Med | High for those users | package_app.sh:27-31 | `ARCHES="arm64 x86_64"` in release.sh/CI; CI time roughly doubles. (S) |
| R5 | First launch on another Mac: zip downloaded in a browser gets com.apple.quarantine; ad-hoc + not notarized. Since macOS Sequoia (15) the Control-click Open bypass is gone; user must go System Settings > Privacy & Security > Open Anyway (Apple developer news / Eclectic Light, 2024). AirDrop also quarantines; USB/SMB copies usually do not. A `.zip` containing only the .app is Sparkle's recommended layout but lands in Downloads. | High | High (first-run wall for a non-technical parent) | package_app.sh:191-195, RELEASING.md "install any older zip" | Short term: README/onboarding page with exact steps + `xattr -dr com.apple.quarantine` fallback. Medium: ship a DMG with /Applications alias. Long: Developer ID + notarization (see 1.2). (S/M/L) |
| R6 | App Translocation: a quarantined app launched from Downloads runs from a randomized read-only path; Sparkle cannot replace it ("opened from a read-only or temporary location"; Sparkle docs note by default it does not notify the user). The app never checks. | High if the user does not move it | Med (updates silently never apply) | No code in Sources/ checks translocation (grep) | In AppDelegate, detect `/AppTranslocation/` in `Bundle.main.bundlePath` and show an Editor banner "Move LocalTube to Applications". (S) |
| R7 | Update UX interrupts a kid-facing screen. Stock Sparkle shows its alert at "opportune times": shortly after launch, when the system has been idle and no display-sleep assertion exists, and when returning to the app (Sparkle Gentle Reminders doc). A TV idling between videos matches "idle". No gentle-reminder delegate, no auto-install, no Settings toggle (Settings.tsx only has "Check for Updates…", lines 352-365). | Med | Med | AppDelegate.swift:22-23 | Implement `SPUStandardUserDriverDelegate.supportsGentleScheduledUpdateReminders=true` and `standardUserDriverShouldHandleShowingScheduledUpdate` returning false while in Viewer mode/player; surface an Editor-only "Update ready" badge; set `SUAutomaticallyUpdate=YES` so installs happen on quit/relaunch; add a Settings toggle bound to `SPUUpdater.automaticallyDownloadsUpdates`. (M) |
| R8 | Standard (non-admin) macOS user + app in /Applications owned by admin: Sparkle needs an admin authorization prompt to replace the bundle; a child account cannot satisfy it so updates silently stall. | Low-Med | Med | n/a (Sparkle behaviour) | Document "install into ~/Applications for a kid account" or run as admin. needs real Mac |
| R9 | Private EdDSA key single point of failure: lives in one Mac's Keychain + a repo secret. Losing both bricks auto-update for all installs (must reinstall manually). RELEASING.md has no backup instruction. SUVerifyUpdateBeforeExtraction not set. | Low | High | RELEASING.md, enable-auto-updates.sh | Export the key once to a password manager; set SUVerifyUpdateBeforeExtraction=YES. (S) |
| R10 | Supply chain nits: Sparkle tools tarball downloaded with no checksum, extraction errors swallowed (`2>/dev/null \|\| true`) (release.sh:67-70); `sign_update` stderr discarded (release.sh:124); Sparkle nested-signing loop swallows codesign failures (`\|\| true`, package_app.sh:203) and the `find ... -o` expression precedence signs every regular file under the framework, not just helpers (package_app.sh:200-202). CI `codesign --verify --deep --strict` (release.sh:107) is the only backstop. | Low | Low-Med | as cited | Pin SHA-256 for tools; fix find parentheses; fail on codesign error. (S) |
| R11 | Legacy Gist feed (installs <= 1.0.33). Needs GIST_TOKEN or a manual `gh gist edit` per release; setup-sparkle.sh still instructs creating a Gist (lines 55-62) which contradicts the repo-hosted feed. Unknown how many installs remain. | Low | Low | RELEASING.md, release.sh:223-239 | Ask the known families to update manually, then delete GIST_ID and the code path. (S) |
| R12 | Appcast feed hosted on raw.githubusercontent.com master: works only while repo is public; any force-push/history rewrite or repo rename breaks every install's feed with no way to push a new one (the feed URL is baked in Info.plist). | Low | High | version.env APPCAST_URL | Consider a stable custom domain / GitHub Pages URL you control, redirectable later. (S) |
| R13 | Rollback story is manual only (install older zip; DB backups documented in AUDIT_2026-09.md). Sparkle will never downgrade. | n/a | Med | RELEASING.md "Rolling back" | Runbook: remove the bad appcast item AND publish a higher version containing the revert. (S) |
| R14 | Sparkle EdDSA-only update of an ad-hoc signed app has never been demonstrated in this repo. Sparkle's own docs say library validation can block ad-hoc builds from loading Sparkle (only relevant if hardened runtime were enabled; it is not) and recommend Developer ID "if possible". Whether Sparkle strips quarantine on the installed bundle is from my knowledge of Sparkle's installer, not verified. | Med | High | package_app.sh:191-195 | One manual test 1.0.36 to 1.0.37 on a clean Mac, record result in RELEASING.md. needs real Mac |

### 1.1 Entitlements / hardened runtime
Today: none, which is fine for a non-sandboxed ad-hoc app that spawns subprocesses and loads WKWebView. If Developer ID is
adopted, hardened runtime is mandatory for notarization; WKWebView needs no extra entitlement; launching child processes
(yt-dlp, ffmpeg) is unaffected by hardened runtime; library validation only affects dlopen of the app's own frameworks (Sparkle is
re-signed with the same identity). Sparkle XPC helpers need `--preserve-metadata=entitlements` when re-signed with a real identity
(Sparkle docs "Code signing requirements"). The existing script's nested-sign loop would need to be rewritten.

### 1.2 Developer ID + notarization: cost/benefit
- Cost: $99/yr Apple Developer Program (individuals cannot get the fee waived); notarization itself has no extra fee (Apple DTS forum).
  CI work: import cert + notarytool credentials as secrets, sign inside-out with hardened runtime, `notarytool submit --wait`, `stapler staple`,
  re-zip. Roughly 1-2 days, plus a pending-enrollment wait (several 2026 forum threads report delays).
- Benefit: removes the Sequoia Open Anyway wall (R5), reduces translocation grief (stapled ticket does not remove quarantine, but Gatekeeper
  passes silently), lets Sparkle also check code-signing identity, and removes "damaged/cannot verify" support burden.
- Verdict: worth it the moment the app goes to anyone beyond the author's own Macs. Until then do the cheap mitigations (DMG, translocation banner, written first-launch steps).

---

## 2. yt-dlp / ffmpeg lifecycle (the #1 reliability risk)

### 2.1 What the code does today
- Resolution only: DependencyService.checkYtDlp/checkFfmpeg test `/opt/homebrew/bin`, `/usr/local/bin`, then `which`
  (DependencyService.swift:92-106); DownloadService.resolveToolPaths does `which` then the same fallbacks (DownloadService.swift:462-469).
  ShellRunner prepends `/opt/homebrew/bin:/usr/local/bin` to PATH (ShellRunner.swift:294), so Finder-launched yt-dlp can find ffmpeg and a Homebrew deno. Good.
- No version check anywhere (grep `--version`: only python3). Settings shows a binary Installed/Missing pill (Settings.tsx:297-312, DepStatus 473-498).
  `checkDepsOnLaunch=false` leaves status at the default `false`, so both show "Missing" even when installed (AppDelegate.swift:73-76, AppState.swift:115).
- Installer exists only in legacy SwiftUI: `installMissing()` is referenced solely from `Views/Onboarding/DependencyCheckView.swift:65,94`.
  grep "brew" in WebUI/src returns nothing. So in the shipped app a missing tool yields: red "Missing" pill in Settings, and per-video text
  "Failed to launch process: yt-dlp could not be launched (yt-dlp). Check Settings → Dependencies." (DownloadService.swift:356-358, ShellRunner.swift:13)
  rendered at 11px, 3-line clamp (VideoCard.tsx:250-266). Settings gives no remedy. LocalTube_Parameters.md:307 promises "dependencies installed
  ... by the app itself on first launch": NOT met in the live UI.
- C3 (`curl | bash` Homebrew): fixed-already in Swift (DependencyService.swift:56-64 now refuses and tells the user to install Homebrew), but TODO.md:224
  still lists it open (stale doc). The replacement is worse for users: Homebrew itself needs Xcode CLT + admin + 10-30 min.
- python3 is a hard requirement of `allSatisfied` and is checked at every launch with `/usr/bin/python3 --version` (DependencyService.swift:82).
  On a Mac without Command Line Tools that shim triggers the macOS "install developer tools" dialog (suspected; well-known shim behaviour; needs real Mac).
  The live UI does not even show python3 (BridgeEventEmitter.swift:293-296), and the standalone yt-dlp binary needs no Python. Pure downside.
- yt-dlp invocation (DownloadService.swift:320-332): `-f <quality> --merge-output-format mp4 --write-thumbnail --convert-thumbnails jpg -o <path> --no-playlist --newline --no-warnings <url>`.
  No `--ignore-config` (a parent's ~/.config/yt-dlp/config can change behaviour), no `--socket-timeout/--retries`, no sleeps, no `--ffmpeg-location`,
  no `--js-runtimes`. `--no-warnings` deletes the exact warning ("No supported JavaScript runtime could be found") that explains degraded results.
  The collector keeps only `ERROR` lines, last 3 (DownloadService.swift:546-564).
- A second yt-dlp process runs before every download just to print the title (DownloadService.swift:283, 521-537), even for synced videos whose title
  already came from the flat listing (ChannelSyncService.swift:171). That doubles YouTube extraction requests per video.
- Default format `bestvideo[vcodec^=avc1][height<=1080]+bestaudio[ext=m4a]/.../best[ext=mp4]/best` (AppSettings.swift:20). When the available clients do not
  expose AVC 1080p, it silently falls through to 360p progressive or non-AVC. No post-download check of codec/height.

### 2.2 What YouTube extraction needs today (web research; dates are source dates)
1. External JS runtime. yt-dlp 2025.11.12 (2025-11-12) added external JavaScript runtime support; without one "YouTube support is deprecated", formats go missing, and
   maintainers expect this to worsen (yt-dlp issue #15012). Supported: Deno (min 2.3.0 per EJS wiki and 2026.06.09 notes, enabled by default), Node >=22, QuickJS (>= 2023-12-9; <2025-4-26 can take minutes), Bun (deprecated, 1.2.11-1.3.14).
   Official yt-dlp executables (incl. `yt-dlp_macos`) bundle the EJS solver scripts; runtimes are NOT bundled. Homebrew/pip installs may not bundle EJS (EJS wiki). Point at a runtime with `--js-runtimes deno:/path`.
   Typical failure chain without it: `WARNING: [youtube] No supported JavaScript runtime...` then `n challenge solving failed` then `ERROR: Requested format is not available`.
2. Churn is monthly. 2026-08-17: many users saw 403 errors from the `android_vr` client; fixed by removing it from defaults in 2026.08.19 (release notes; corroborated by a vendor blog).
   2026-10-21: `tv_samsung` added as a default client. 2026-06-09: Deno min raised to 2.3, Bun limited. 2026-03: EJS 0.7.0/0.8.0 bumps; fixes often landed in nightly before stable
   (e.g. web_embedded fix for made-for-kids videos in nightly 2026.03.10 per a VRChat issue thread). Latest stable at time of research: 2026.10.26 (2026-10-26).
   A Homebrew yt-dlp that nobody upgrades would have been broken for the Aug 17-19 window and every later client change.
3. PO tokens. Per the yt-dlp PO Token Guide (last edited 2026-07-12): `web` needs tokens for subtitles+GVS, `mweb`/`tv_simply`/`web_creator`/`web_safari` need GVS tokens; `android_vr` and `web_embedded` need none
   but `android_vr` cannot fetch "made for kids" videos at all and `web_embedded` only works for embeddable videos. Manual tokens are no longer recommended (bound to video ID); use a provider plugin (bgutil-ytdlp-pot-provider).
   Relevance: a kids' app's content is disproportionately Made-for-Kids, the exact class where the no-token clients are weakest. Plugins require pip-style yt-dlp, not the frozen binary, so a token-provider strategy is expensive; prefer "stay current + runtime + cookies as last resort".
4. "Sign in to confirm you're not a bot": typically IP-reputation/rate driven; mitigations are slower request rate, current yt-dlp, JS runtime, and cookies from a logged-in browser (which risks the account; yt-dlp wiki warns).
5. Rate limits: yt-dlp wiki (mirror): ~300 videos/hour for guest sessions (~1000 webpage/player requests/hour), ~2000/hour with an account; recommended 5-10 s sleep between downloads (`--sleep-interval 5 --max-sleep-interval 15`, `--sleep-requests`).
   LocalTube runs 4 parallel downloads plus a duplicate extraction per video and zero sleeps (DownloadService.swift:35, 283, 313-332). A 300-video first sync is ~600 extractions in minutes.
6. Packaging facts: `yt-dlp_macos` is a universal standalone executable for macOS 10.15+ (README "Release files"); `-U` updates within its channel; `--update-to [CHANNEL]@[TAG]` switches channel or pins/downgrades
   (stable / nightly / master; README calls nightly the recommended channel for regular users); it warns when >90 days old (README). `yt-dlp_macos_legacy` is no longer offered. Python 3.11 is the minimum for pip/zipimport installs since 2026.10.26.

### 2.3 How a typical parent fails today (message they see)
| Situation | What the app shows | Where |
|---|---|---|
| Fresh Mac, no Homebrew | Settings: two red "Missing" pills, no instructions. Videos: "Failed to launch process: yt-dlp could not be launched (yt-dlp). Check Settings → Dependencies." | Settings.tsx:297-312; VideoCard.tsx:250-266 |
| Brew yt-dlp too old / no JS runtime | "Process exited 1: [youtube] <id>: Requested format is not available. Use --list-formats ..." (expected pattern, not reproduced) | ShellError.nonZeroExit (ShellRunner.swift:14) |
| Bot check | "Process exited 1: [youtube] <id>: Sign in to confirm you're not a bot. Use --cookies-from-browser or --cookies ..." clamped to 3 lines at 11px | same |
| Pasted a channel URL | Channel is created, auto-sync immediately fails: banner "Sync failed" + monospace one-liner of raw yt-dlp output (Channel.tsx:711-745) | ChannelSyncService.swift:205-213 |
| Premiere/deleted/private/members-only/age-gated | Raw error, then retried forever at each launch (see 3.4) | AppState.swift:540-543 |

### 2.4 Recommended strategy ("Downloader that fixes itself")
Goal: a parent never opens Terminal, and a YouTube change is fixed by an in-app update within a day without shipping a new app version.

Phase 0, quick wins, S (1-2 days), do now
1. Remove python3 from checks/status; drop the Homebrew-only wording. Show yt-dlp `--version` + age in Settings (amber at >45 days, red >90 days matching yt-dlp's own warning).
2. Replace `--no-warnings` with capturing WARNING lines to classify; add `--ignore-config --socket-timeout 30 --retries 5 --fragment-retries 5 --sleep-requests 1 --sleep-interval 2 --max-sleep-interval 6` for queue downloads; lower maxConcurrent 4 to 2.
3. Delete the pre-download title process: use `--print before_dl:LTMETA\t%(title)s\t%(duration)s\t%(channel_id)s\t%(tags)j` in the real download (also closes TODO L8/tags). Only needed for manually pasted videos.
4. Error taxonomy v1 (below) + friendly strings + a "Fix downloads" button that runs the repair flow.
5. Stop blind retries: add `retryCount`, `nextRetryAt`, `permanentFailure` to videos; only auto-retry transient classes with backoff.

Phase 1, managed yt-dlp with rollback, M (3-5 days)
- New `ToolManager` replaces DependencyService. Layout `~/Library/Application Support/LocalTube/tools/{bin/yt-dlp, bin/ffmpeg, bin/ffprobe, bin/deno, versions/<tag>/..., last-good.json}`.
- First run: download `yt-dlp_macos` from GitHub releases, verify against the release's SHA2-256SUMS, `chmod +x`. (URLSession downloads in a non-sandboxed app are not quarantined; confirm on Mac.)
- Update loop: at launch and every 24h (and immediately on classes `FORMAT_UNAVAILABLE`, `BOT_CHECK`, `HTTP_403`, `JS_RUNTIME`): copy current to `yt-dlp.prev`, `yt-dlp --update-to stable` (or `nightly` if stable fails the canary), run the canary, keep on pass, restore `.prev` on fail. Minimal version of this is ~1 day because yt-dlp already self-updates and supports `--update-to <channel>@<tag>` for pinning.
- Prepend `tools/bin` to PATH in ShellRunner.makeProcess and pass explicit `--ffmpeg-location` and `--js-runtimes deno:<abs>`.
- Canary self-test: `yt-dlp --simulate --print "%(id)s|%(height)s|%(vcodec)s" -f "bv*[vcodec^=avc1][height<=720]+ba[ext=m4a]"` against the most recently downloaded video in the user's own library (same content class, no hard-coded ID); fall back to a permanent public video if the library is empty. Pass = at least one AVC stream >=720p within 60 s; parse stderr into the taxonomy. Run at launch (debounced 12h), after every tool update, and from "Fix downloads".
- Stale banner for parents only in Editor mode; Viewer mode never sees tool state.

Phase 2, JS runtime, M (2-3 days + size trade-off)
- Download a pinned Deno >= 2.3 (single signed binary from denoland releases, hash verified) into tools/bin on first run (~100 MB unpacked). Alternatives: Node >= 22 (similar size), or a small QuickJS build (>= 2025-4-26) compiled in CI (~1-2 MB, requires `--js-runtimes quickjs:<path>`; slower). Speculative idea needing a spike: a tiny JavaScriptCore-based helper, since macOS ships JavaScriptCore. Unverified.
- Detection: look for the "No supported JavaScript runtime" warning (now captured) and verify with `deno --version`.

Phase 3, ffmpeg/ffprobe, M
- Do not bundle in the .app (would grow each Sparkle zip from 2.4 MB to 100+ MB). Download a pinned static LGPL (`--disable-gpl`) arm64 + x86_64 build from the project's own "tools" GitHub release with SHA-256s; the app only needs mux (`-c copy`), WebP-to-JPEG, and frame grab. Watch the GPL: a GPL (libx264) static build embedded or redistributed triggers source-offer obligations.
- Reduce reliance: duration via AVAsset and thumbnails via AVAssetImageGenerator (AV lane) so ffprobe can go away; yt-dlp still needs ffmpeg to merge.

Phase 4, hardening, M
- Opt-in "Sign-in help" (Editor-only, off by default): `--cookies-from-browser safari|firefox|chrome`. Privacy implications: gives yt-dlp the parent's Google session (account-ban risk per wiki; contradicts "no accounts"); Safari needs Full Disk Access; never default-on, never in Viewer mode, never stored beyond the browser.
- Global rate-limit governor: on 429/403/bot-check pause the whole queue 5m, 15m, 60m (exponential), reduce concurrency to 1, show "YouTube asked us to slow down; will resume at 14:30".
- Onboarding step "Setting up the downloader" with progress, replacing the missing dependency wizard; copy-able diagnostics report (versions, last 50 redacted stderr lines).

### 2.5 Error taxonomy (map to friendly text + action)
| Class | Match (stderr substring, maintain in a versioned table with fixtures) | Retry policy | Parent-facing message / action |
|---|---|---|---|
| TOOL_MISSING | launchFailed exit -1 | none | "Downloader isn't set up. [Set up now]" |
| JS_RUNTIME | "No supported JavaScript runtime", "n challenge solving failed" | after fix | "Needs a small helper component. [Fix downloads]" |
| FORMAT_UNAVAILABLE | "Requested format is not available" | once after tools update, then fallback format | "YouTube changed; updating the downloader." |
| BOT_CHECK | "Sign in to confirm you're not a bot" | exponential global pause | "YouTube is asking us to slow down. Will retry later." (+ cookies help, Editor) |
| AGE_GATE | "Sign in to confirm your age", "inappropriate for some users" | permanent | "Age-restricted: skipped." |
| UNAVAILABLE | "Video unavailable", "Private video", "members-only", "removed", "copyright", "not available in your country" | permanent (re-check weekly at most) | "No longer available on YouTube. [Remove]" |
| SCHEDULED | "Premieres in", "live event will begin" | at `release_timestamp` | "Not published yet." |
| RATE_LIMIT | "HTTP Error 429", "Too Many Requests" | global backoff | as BOT_CHECK |
| NETWORK | "Unable to download webpage", "timed out", "Temporary failure in name resolution", "getaddrinfo" | pause queue, resume on NWPath satisfied | "Offline. Will resume automatically." |
| DISK | "No space left on device" (errno 28) | pause until space | "Disk full." |
| FFMPEG | "ffmpeg not found", "Postprocessing" | after tool fix | as TOOL_MISSING |

---

## 3. Channel resolution and sync correctness

Key architectural finding: `ChannelResolverService.resolve`, `fetchVideoURLs` (200-cap, cancel) and `extractChannelId` (wrong-channel validation) are referenced only by the legacy Views
(NewChannelFlow.swift:295,546; AddVideosView.swift:249). The live bridge never calls them. The spec's "resolve channel, show video count, confirm, 200 cap, validate manual URL belongs to channel" is not implemented in the shipped UI.

### Sync bugs (evidence)
S1 (Critical, confirmed) Unbounded first sync. `ChannelSyncService.fetchVideoList` runs `yt-dlp --flat-playlist` with no `--playlist-end` (ChannelSyncService.swift:169-174, timeout 180 s). `AppState.syncChannel` then adds AND enqueues every id not already present (AppState.swift:476-491). The 200 cap (ChannelResolverService.swift:13) is dead code. Adding a channel with 3,000 videos queues 3,000 downloads (tens to hundreds of GB), with no confirmation, no size estimate, no disk-space preflight (no availableCapacity check anywhere, grep). Also 3,000 enqueue calls each persist to SQLite and mutate observable state. Runs again on every launch and midnight over the *full* list even when only the newest handful can be new (flat listing is newest-first), costing ~100+ paged requests per channel per run.
S2 (Major, confirmed) Channel input is a raw string. AddChannelModal.tsx:34-35 sends the trimmed text; handleAddChannel stores it verbatim (LocalTubeBridge.swift:546-557) and immediately syncs. `makeChannelURL` only understands bare `UC...`/`HC...` IDs and bare `@handle` (ChannelSyncService.swift:205-213). Anything else, including `https://www.youtube.com/@name`, `/channel/UC...`, `/c/Name`, `/user/Name`, playlist and video URLs, becomes `https://www.youtube.com/@https://www.youtube.com/@name/videos`. Same in ChannelBannerService.swift:110-117. A bare word starting with "UC" (e.g. "UCLAathletics") is misrouted as a channel ID. No display-name autofill, no preview, no duplicate-channel detection (the same YouTube channel can be added twice, each downloading its own copy).
S3 (Major, confirmed) Deleted videos resurrect. `removeVideo` deletes the row and files (AppState.swift:320-329) and records nothing; the next sync's `existingSet` no longer contains the id, so it re-adds and re-downloads it (AppState.swift:479-491). No tombstone/exclusion table exists (DatabaseMigrations tables list). A parent curating a source channel cannot permanently remove a video; it comes back at next launch or midnight. Fix: `excluded_videos(channel_id, youtube_video_id)` written by delete on source channels, consulted by sync. (S-M)
S4 (Major, confirmed) Failed downloads retry at every sync forever. `requeueMissingAndFailed` re-queues every `.error` video on every launch/midnight/manual sync (AppState.swift:540-543) with no counter or classification. Deleted/private/members-only/age-gated/premiere items re-hit YouTube twice each (title probe + download) indefinitely, wasting rate budget and flickering UI state.
S5 (Major, confirmed) Reliability under sleep/offline. No NWPathMonitor/reachability, no NSWorkspace wake observer, no `ProcessInfo.beginActivity` power assertion (grep). The inactivity watchdog compares wall-clock time (ShellRunner.swift:228-243): a Mac that sleeps mid-download wakes with `lastActivity` hours old and the watchdog kills a download that could have resumed; it surfaces as "Process produced no output for 600s and was stopped" and waits for the next sync to retry. Midnight auto-sync depends on `.NSCalendarDayChanged` (AppDelegate.swift:25-30, 125-141); the code comment says it fires on wake if the Mac slept through midnight (not independently verified, suspected). A Mac mini TV box that sleeps overnight likely syncs only on next launch. `applicationShouldTerminateAfterLastWindowClosed` is true (AppDelegate.swift:167-169) and `applicationWillTerminate` cancels all downloads (AppDelegate.swift:180-186), so closing the window stops background work.
S6 (Minor, confirmed) Sync coverage. The `/videos` tab excludes Shorts and past live streams (they live on /shorts and /streams tabs); manual add accepts shorts URLs (AddVideosModal.tsx:16-27) but Swift `youtubeVideoId` handles only `v=`, youtu.be, /shorts/ (StringExtensions.swift:29-47); `/live/ID` and `/embed/ID` unsupported (JS filter rejects them anyway). Channel sync has no setting to include Shorts/streams. Upcoming premieres have no duration (parsed as 0) and fail until published.
S7 (Minor, confirmed) Dedupe is app-level only: `idx_videos_youtube_id` is a plain index, no UNIQUE(channel_id, youtube_video_id) (DatabaseMigrations.swift:121-122). A manual add racing a sync can double-insert. Add a unique index in the next migration after a de-dupe pass.
S8 (Minor, confirmed) Manual URL ownership: AddVideosModal lets any YouTube URL be added to any channel including source channels (no channel-membership check); spec decision wanted validation. Low value for a curated family app; mention only.
S9 (Minor, confirmed) Titles/tags/thumbnails. Title comes from the flat listing for synced videos, but `fetchVideoTitle` re-probes anyway (DownloadService.swift:283). Tags are still not captured (TODO.md:73-77 open). Thumbnails come via `--write-thumbnail --convert-thumbnails jpg` (needs ffmpeg) with an ffmpeg frame fallback (DownloadService.swift:326-327, 395-399); `refreshThumbnails` runs yt-dlp per video serially with a 30 s timeout (DownloadService.swift:474-517) = more extraction traffic.
S10 (Minor, confirmed) `lastSyncError` is the raw `localizedDescription` ("Process exited 1: <entire stdout+stderr>", ShellRunner.swift:140-141): unbounded length persisted to SQLite and sent over the bridge; UI shows one monospace truncated line (Channel.tsx:711-745). Cap to ~300 chars and classify via the taxonomy.
S11 (Info) Auto-sync is sequential per channel (AppState.swift:566-568), good for politeness; each fetch is awaited up to 180 s; a stuck channel delays all others.

### URL forms matrix (live path today)
| Form | Works? |
|---|---|
| `@handle` bare | yes |
| `UCxxxxxxxxxxxxxxxxxxxxxx` bare | yes |
| `https://www.youtube.com/@handle` (any of /videos,/featured) | no |
| `/channel/UC...`, `/c/Name`, `/user/Name` | no |
| `youtube.com/playlist?list=PL...` (as source) | no (no playlist source concept) |
| video URL as channel | no |
| `youtu.be`, `m.youtube.com`, `music.youtube.com/watch?v=` as *video* | yes (manual add; `v=` or youtu.be path) |
| `/shorts/ID` as video | yes |
| `/live/ID`, `/embed/ID` as video | no |

Recommended fix (M): a Swift `YouTubeURL.parse` that handles all forms, then an "Add channel" step that calls `yt-dlp --flat-playlist -J --playlist-items 1` (resolver code already exists and is correct) to show channel name, avatar and *approximate video count* ("~1,240 videos"), with choices "Only new from now / Latest 25 / Latest 100 / Everything (~X GB est.)", disk-space preflight, and canonical storage of the `UC` channel ID (so handle renames do not break sync). Revive `ChannelResolverService.resolve/extractChannelId` rather than rewriting.

---

## 4. Feature opportunities (value / effort)

| Rank | Feature | Value | Effort | Notes |
|---|---|---|---|---|
| 1 | "How many to download" at channel add + "keep newest N" per channel | High | M | Fixes S1, controls disk; builds on resolver + preflight. Auto-delete watched needs `last_watched_at` (TODO.md:95). |
| 2 | Playlist as a source | High | S-M | yt-dlp lists playlists exactly like channel tabs; needs the URL parser; many kids' shows are playlists/seasons. |
| 3 | Self-updating yt-dlp + runtime + canary ("Fix downloads") | Highest for reliability | M-L | Section 2.4. |
| 4 | Tombstones for removed videos on source channels | High | S-M | S3. |
| 5 | Bandwidth limit (`--limit-rate`) + download window ("overnight only") | Med | S / M | Needs sleep-prevention for the overnight case. |
| 6 | Library manifest export/import (channels + YouTube IDs + quality) | Med | M | Matches the "drag the app to another Mac" workflow; re-downloads on target. |
| 7 | Subtitles (`--write-subs --sub-langs en.* --embed-subs`) | Med | M | Needs player track UI (AV lane); useful for early readers and accessibility. |
| 8 | Notification when a batch finishes | Low-Med | S | UNUserNotification works for ad-hoc apps typically; needs real Mac. In-app toast alternative. |
| 9 | SponsorBlock removal (`--sponsorblock-remove sponsor,selfpromo,...`) | Low-Med | M | yt-dlp downloads contain no YouTube-served ads; this only trims creator-embedded sponsor reads. Adds a third-party network call (hash-prefix lookups), re-mux with keyframe-cut glitches; make it per-channel opt-in. |
| 10 | `--age-limit` | Low | S | Only filters videos YouTube age-gates (which fail without cookies anyway); not a kid-safety filter. |
| 11 | `--download-archive` | Low | S | DB already dedupes; a second source of truth adds drift. Skip in favour of tombstones. |

---

## 5. Needs a real Mac to confirm
- A real Sparkle update 1.0.36 to 1.0.37 on an ad-hoc signed app: does it install, is quarantine stripped, does relaunch work from /Applications and from ~/Applications, what happens from a translocated Downloads copy.
- First launch of the zip from a browser download and via AirDrop/USB on macOS 14, 15 and 26 (Open Anyway flow).
- Intel Mac: confirm the arm64-only build refuses to launch.
- `/usr/bin/python3 --version` popup on a Mac with no Command Line Tools.
- Frozen `yt-dlp_macos` launched from the app: startup time (PyInstaller onefile unpack), signature acceptance on arm64, no quarantine on URLSession-downloaded files, Deno found via PATH from a Finder-launched app.
- Sparkle alert appearing over the player/idle TV; `.NSCalendarDayChanged` on wake; download watchdog behaviour after sleep.
- Non-admin account updating an app in /Applications.

## 6. Cross-lane notes
- AV: silent fall-through of the format string to 360p/non-AVC (AppSettings.swift:20); verify codec/height after download; VP9/AV1 in mp4 may not play in AVPlayer.
- SEC: `youtubeVideoId` returns any `v=` value unvalidated (StringExtensions.swift:29-41) and it is interpolated into `https://www.youtube.com/watch?v=\(id)` (DownloadService.swift:314): validate `^[A-Za-z0-9_-]{11}$`. Also Sparkle tools tarball unpinned (release.sh:67), private key handling.
- UX: Add-channel flow needs resolve/preview/choose-how-many; onboarding lacks a downloader-setup step; error copy.
- QA: zero tests (no Tests dir); sync URL parsing and stderr classification are ideal fixture-driven unit tests.
- ARC: ChannelResolverService.resolve/fetchVideoURLs/extractChannelId and Views/Onboarding/DependencyCheckView, Views/Editor/NewChannelFlow are the only users of logic worth porting; bulk enqueue of thousands of items does one DB write per item.

## 7. Sources (web research, queried generically)
- yt-dlp EJS announcement, issue #15012 (closed 2025-11-16): https://github.com/yt-dlp/yt-dlp/issues/15012
- yt-dlp wiki EJS: https://github.com/yt-dlp/yt-dlp/wiki/EJS
- yt-dlp PO Token Guide (edited 2026-07-12): https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide
- yt-dlp releases 2026.03.03 to 2026.10.26: https://github.com/yt-dlp/yt-dlp/releases ; 2026.08.19: https://github.com/yt-dlp/yt-dlp/releases/tag/2026.08.19
- yt-dlp README (release files, -U, --update-to, js-runtimes, sleep options): https://cdn.jsdelivr.net/gh/yt-dlp/yt-dlp@master/README.md
- android_vr 403 of 2026-08-17 (vendor blog, corroborated by release notes): https://www.videoproc.com/resource/yt-dlp-not-working.htm
- Sparkle docs: https://sparkle-project.org/documentation/ , /documentation/customization/ , /documentation/publishing/ , /documentation/gentle-reminders/
- Gatekeeper in Sequoia: https://eclecticlight.co/2024/08/10/gatekeeper-and-notarization-in-sequoia/ ; Apple developer news https://developer.apple.com/news/?id=saqachfa
- App translocation and updaters: https://eclecticlight.co/2022/09/06/dont-run-that-app-where-it-landed-how-translocation-can-cause-crashes/
- Apple Developer Program fee/notarization: https://developer.apple.com/forums/thread/746992
