# LocalTube — Code Review

Generated 2026-03-17. Full codebase review covering all Swift source files and WebUI TypeScript/React files.

---

## Severity Key

- 🔴 **CRITICAL** — Security hole or guaranteed crash in production
- 🟠 **HIGH** — Data loss, memory corruption, or severe functional bug
- 🟡 **MEDIUM** — Bad pattern, latent bug, or significant technical debt
- 🔵 **LOW** — Cleanup, modern idioms, accessibility, maintainability

---

## 🔴 CRITICAL

### C1 — Path Traversal in ThumbnailURLSchemeHandler
**File**: `Sources/LocalTube/Bridge/ThumbnailURLSchemeHandler.swift`

`resolveFilePath()` percent-decodes the URL path and uses it directly as a file path with no containment check. A crafted URL like `localtube-thumb://../../../../../../etc/passwd` will successfully read arbitrary files from the filesystem.

```swift
// No normalization or bounds check — can escape thumbnail directory
let decodedPath = url.path.removingPercentEncoding ?? url.absoluteString
```

**Fix**: After decoding, call `URL.standardized` and verify the resulting path has the expected thumbnail directory as a prefix before reading.

---

### C2 — XSS via Unescaped String Interpolation into JavaScript
**Files**: `Sources/LocalTube/Bridge/BridgeEventEmitter.swift`, `Sources/LocalTube/Bridge/PlayerOverlayController.swift`

User-controlled strings (video titles, error messages, file paths) are interpolated directly into `evaluateJavaScript()` calls without escaping. A video whose title contains `");alert(1);//` would break out of the JSON string literal.

```swift
// BridgeEventEmitter — jsonString could contain unescaped quotes/newlines
"window.LocalTubeBridge && window.LocalTubeBridge.dispatch(\(jsonString));"

// PlayerOverlayController — video title interpolated into JS
"window.LocalTubePlayer&&window.LocalTubePlayer.dispatch({type:'playerState',payload:\(json)});"
```

**Fix**: Always serialize via `JSONSerialization` into a `Data` blob and pass it as a base64 string, or use `WKScriptMessageHandler` for two-way communication instead of `evaluateJavaScript`.

---

### C3 — Homebrew Installed via `curl | bash`
**File**: `Sources/LocalTube/Services/DependencyService.swift` (~line 107)

The dependency installer downloads and executes an arbitrary shell script over the network with no integrity check. A compromised CDN or MITM attacker can execute arbitrary code as the user.

```swift
// Downloads and pipes to bash with no hash/signature verification
ShellRunner.stream(launchPath: "/bin/bash", args: ["-c", "curl -fsSL https://... | /bin/bash"])
```

**Fix**: Bundle yt-dlp and ffmpeg as app resources, or at minimum verify a SHA-256 checksum against a hardcoded expected value before executing.

---

### C4 — PIN Stored in Plaintext UserDefaults
**File**: `Sources/LocalTube/Services/PINService.swift`

The editor PIN is written to `UserDefaults` as a plain string. UserDefaults are stored unencrypted in `~/Library/Preferences/` and are world-readable by any process running as the same user.

**Fix**: Store the PIN hash in the Keychain (`kSecClassGenericPassword`), which the code elsewhere references as the intent. Never store the PIN value itself — store only a hash (e.g. SHA-256 with a random salt also stored in Keychain).

---

### C5 — PIN Stored in React Component State
**Files**: `WebUI/src/screens/PINEntry.tsx`, `WebUI/src/screens/PINSetup.tsx`, `Sources/LocalTube/Views/Shared/PINEntryOverlay.swift`, `Sources/LocalTube/Views/Onboarding/PINSetupView.swift`

The PIN digits live in `@State`/`useState` as plain strings throughout the UI layer — Swift views and React components alike. This makes the PIN value visible in memory dumps, React DevTools, and state snapshots.

**Fix**: In Swift views, use `SecureField` and never hold the combined PIN string longer than the single verification call. In React, send each digit to Swift immediately rather than accumulating in state, or clear state immediately after the bridge call.

---

### C6 — SQL Injection in DatabaseMigrations via String Interpolation
**File**: `Sources/LocalTube/Database/DatabaseMigrations.swift`

```swift
sqlite3_exec(db, "PRAGMA user_version = \(version);", nil, nil, nil)
```

`version` is currently an integer and safe in practice, but using string interpolation for SQL is the wrong pattern — it will fail a security audit and sets a dangerous precedent in a file that will receive future migrations.

**Fix**: Use a prepared statement with `sqlite3_bind_int`.

---

### C7 — WKWebView Script Message Handlers Never Removed
**File**: `Sources/LocalTube/Bridge/WebWindowController.swift`

`LocalTubeBridgeHandler` and `ConsoleMessageHandler` are added to `userContentController` but never removed. `WKUserContentController` holds a strong reference to its message handlers, preventing `WebWindowController` from ever being deallocated. On repeated window creation this leaks unboundedly.

**Fix**: Remove handlers in `deinit` (or in `windowWillClose`):
```swift
deinit {
    webView.configuration.userContentController.removeScriptMessageHandler(forName: "localTubeBridge")
    webView.configuration.userContentController.removeScriptMessageHandler(forName: "consoleRelay")
}
```

---

## 🟠 HIGH

### H1 — AVPlayer Time Observer and Notification Observer Never Removed
**File**: `Sources/LocalTube/Player/PlayerState.swift`

`addPeriodicTimeObserver` returns a token that must be passed back to `removeTimeObserver`. `NotificationCenter.addObserver` returns an opaque object that must be passed to `removeObserver`. Both are stored but `cleanup()` is never called automatically — there is no `deinit` and `VideoPlayerView.onDisappear` only calls `stop()`, not `cleanup()`. Observers fire on a deallocated object.

**Fix**:
1. Add `deinit { cleanup() }` to `PlayerState`.
2. In `VideoPlayerView`:
```swift
.onDisappear {
    playerState.stop()
    playerState.cleanup()  // currently missing
}
```

---

### H2 — `DownloadQueueItem` is `@unchecked Sendable` with Unguarded Mutable State
**File**: `Sources/LocalTube/Models/DownloadQueueItem.swift`

`@unchecked Sendable` tells the compiler to skip all thread-safety checking. The class has mutable `progress`, `state`, and `activeProcess` properties written from the download thread and read from the UI thread with no synchronization. This is a data race.

**Fix**: Add `@MainActor` to the class (matching the rest of the app's convention), or isolate it to a specific actor. Remove `@unchecked Sendable`.

---

### H3 — `AppDelegate` Uses Force-Unwrapped Implicitly Optional Properties
**File**: `Sources/LocalTube/App/AppDelegate.swift`

```swift
private var appState: AppState!
private var windowController: WebWindowController!
```

Both are used without nil checks in menu action handlers and event callbacks. Any menu item triggered before `applicationDidFinishLaunching` completes, or in a failure path, crashes the app.

**Fix**: Use true optionals with proper nil guards, or initialize as `let` constants in `applicationDidFinishLaunching`.

---

### H4 — `DatabaseService` Calls `String(cString:)` on Potentially NULL Pointers
**File**: `Sources/LocalTube/Database/DatabaseService.swift`

`sqlite3_column_text()` returns `UnsafePointer<UInt8>?` and will return `NULL` for SQL `NULL` values. `String(cString:)` does not accept an optional and will crash at runtime on a null column.

```swift
// Crashes if column is NULL
let displayName = String(cString: sqlite3_column_text(stmt, 1))
```

**Fix**: Check column type before converting:
```swift
let displayName = sqlite3_column_type(stmt, 1) != SQLITE_NULL
    ? String(cString: sqlite3_column_text(stmt, 1))
    : ""
```

---

### H5 — No Transactions for Multi-Step Database Writes
**File**: `Sources/LocalTube/Database/DatabaseService.swift`, `Sources/LocalTube/State/AppState.swift`

Channel insertion followed by batch video insertion runs as multiple independent `sqlite3_exec` calls. If the process is killed mid-sequence, the database is left with a channel that has no videos, or videos with no parent channel. Foreign key constraints are enabled but without transactions these checks run per-statement, not per-logical operation.

**Fix**: Wrap all multi-step writes in explicit `BEGIN IMMEDIATE; ... COMMIT;` / `ROLLBACK;` blocks.

---

### H6 — React App Has No Error Boundary
**File**: `WebUI/src/App.tsx`

Any uncaught exception during render (e.g., iterating a `null` array, accessing a missing property from a malformed bridge event) crashes the entire React tree. The WKWebView shows a blank white page with no recovery path.

**Fix**: Wrap the root component tree in a React `ErrorBoundary` that shows a recoverable error UI and reports the error to Swift via the bridge.

---

### H7 — `AppLogger` File Handle is Never Closed and Not Thread-Safe
**File**: `Sources/LocalTube/Utilities/AppLogger.swift`

`FileHandle` is opened at startup, never closed (no `deinit`), and `append()` is called from multiple threads without synchronization. Concurrent writes produce interleaved/corrupt log lines. File is never rotated or size-capped — will grow until disk is full.

**Fix**: Serialize all log writes through a dedicated actor or `DispatchQueue(label:)`, add a size check before each write, and close the handle in `deinit`.

---

### H8 — `PlayerOverlayController` Leaks `addPeriodicTimeObserver` Token
**File**: `Sources/LocalTube/Bridge/PlayerOverlayController.swift`

A periodic time observer is registered at line ~182 but the token is never passed back to `removeTimeObserver`. If the overlay is presented multiple times, observers accumulate and all fire simultaneously.

**Fix**: Store the token and remove it in a cleanup method called from `windowWillClose`.

---

### H9 — React `handleAddVideos` Resets Loading State Synchronously
**File**: `WebUI/src/screens/Channel.tsx`

```typescript
setAdding(true)
send({ type: 'addVideoURLs', payload: { ... } })  // fire-and-forget
setAdding(false)  // immediately reset — button never shows loading state
setShowAddVideos(false)
```

The bridge call is asynchronous but the loading guard is cleared immediately. The UI gives no feedback while Swift processes the URLs and the button can be pressed again before the operation completes.

**Fix**: Keep `adding = true` until a confirmation event arrives from Swift. Add a timeout fallback.

---

## 🟡 MEDIUM

### M1 — `Channel.folderName` Not Validated for Path Traversal
**File**: `Sources/LocalTube/Models/Channel.swift`

`folderName` is constructed from user-supplied `displayName` and used in `videosPath(rootFolder:)` to build file paths. A name containing `../` can navigate outside the download root.

**Fix**: Sanitize `folderName` to alphanumeric characters, hyphens, and underscores only. Reject or strip any `/`, `.`, or Unicode control characters.

---

### M2 — `Video.isPlayable` Has a TOCTOU Race
**File**: `Sources/LocalTube/Models/Video.swift`

```swift
var isPlayable: Bool {
    downloadState == .ready && FileManager.default.fileExists(atPath: localFilePath)
}
```

The file existence check and the subsequent `AVPlayerItem` creation happen in separate operations. The file can be deleted between the check and the play attempt, producing a confusing silent failure. The property is also a computed var called on every render tick, causing repeated filesystem I/O.

**Fix**: Cache `isPlayable` and invalidate only on download state transitions. Handle `AVPlayerItem` errors explicitly at playback time.

---

### M3 — `ShellRunner` Has No Timeout and No Process Validation
**File**: `Sources/LocalTube/Services/ShellRunner.swift`

`run()` blocks indefinitely (no timeout). `launchPath` is used without checking `fileExists(atPath:)` or `isExecutableFile(atPath:)` — a missing binary produces a cryptic `NSCocoaErrorDomain` exception rather than a human-readable message.

**Fix**: Accept an optional `timeout: TimeInterval` parameter. On expiry, call `process.terminate()` and throw. Validate `launchPath` before launch.

---

### M4 — Hardcoded Homebrew Paths Fragile on Non-Standard Installs
**Files**: `Sources/LocalTube/Services/DownloadService.swift`, `Sources/LocalTube/Services/DependencyService.swift`

```swift
let candidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
```

Homebrew can be installed to custom prefixes. On Apple Silicon machines with non-default installs, or machines using MacPorts or nix, all candidates miss.

**Fix**: Use `which yt-dlp` and `which ffmpeg` via `ShellRunner` as the primary resolution. Fall back to the candidate list only if `which` returns nothing.

---

### M5 — No Rate Limiting on PIN Entry
**Files**: `Sources/LocalTube/Views/Shared/PINEntryOverlay.swift`, `Sources/LocalTube/Views/Onboarding/PINSetupView.swift`, `WebUI/src/screens/PINEntry.tsx`

Failed PIN attempts have no delay, no lockout period, and no attempt counter. The 6-digit PIN space (10^6 = 1,000,000 combinations) can be brute-forced in minutes by automated input.

**Fix**: After 3 failures, enforce an exponential backoff (5s, 30s, 5min). After 10 failures, require the recovery phrase before allowing further attempts.

---

### M6 — Triple-Tap to Enter Editor Mode is Trivially Bypassable
**File**: `Sources/LocalTube/Views/Viewer/ViewerLibraryView.swift`

The corner tap count state and the timer that resets it are `@State` variables, but the tap counter appears to never be properly reset (the timer is referenced but may not fire correctly). More critically, any child who discovers the gesture gets unrestricted editor access — there is no second factor.

**Fix**: The triple-tap gesture should only *trigger the PIN prompt*, not directly enter Editor Mode. The gesture itself is fine as a discovery mechanism; the PIN is the actual security gate. Verify the reset timer is correctly attached.

---

### M7 — `BridgeMessage.BridgeMessageType` Enum Is Unused
**File**: `Sources/LocalTube/Bridge/BridgeMessage.swift`

`BridgeMessageType` is defined with 17 cases but `LocalTubeBridge` dispatches by comparing raw strings. There are two parallel sources of truth for valid message types that will inevitably diverge.

**Fix**: Either delete the enum and document the string protocol, or make `LocalTubeBridge` decode into `BridgeMessageType` and switch on the enum.

---

### M8 — `AnyCodable` Loses Type Information
**File**: `Sources/LocalTube/Bridge/BridgeMessage.swift`

`AnyCodable` erases type information. Payloads round-trip through `[String: Any]` and every handler casts blindly with `as? String`, `as? UUID`, etc. A Bool `true` is decoded as `Int 1` depending on codec pass order.

**Fix**: Define concrete `Codable` payload structs for each message type and decode directly into them in `LocalTubeBridge`.

---

### M9 — `WKWebView` Configured with Overly Permissive File Access
**File**: `Sources/LocalTube/Bridge/WebWindowController.swift`

```swift
config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
```

This allows the `file://` origin to make cross-origin file reads. Combined with a path traversal bug elsewhere, this widens the attack surface significantly.

**Fix**: Remove this setting. The custom `localtube-thumb://` URL scheme handler is the correct way to serve local assets.

---

### M10 — ISO8601DateFormatter Instantiated on Every Call
**Files**: `Sources/LocalTube/Bridge/BridgeEventEmitter.swift`, `Sources/LocalTube/Utilities/AppLogger.swift`

`DateFormatter` and `ISO8601DateFormatter` are expensive to construct (they parse locale/calendar data). Both files create a new instance on every log write or state emit.

**Fix**: Use a `static let` cached formatter.

---

### M11 — No Input Validation in Bridge Handlers
**File**: `Sources/LocalTube/Bridge/LocalTubeBridge.swift`

Bridge handlers trust all incoming payload values:
- PIN strings have no length or character set validation
- `displayName` for channels has no length limit
- `addVideoURLs` doesn't revalidate URL format server-side
- Channel ID lookup is done after optimistic operations

**Fix**: Validate all payload fields at the handler boundary before any state mutation. Return a typed error event to the JS layer on validation failure.

---

### M12 — Missing React Error Handling on Async Bridge Calls (No Timeout)
**File**: `WebUI/src/bridge.ts`

`sendBridge()` is fire-and-forget. If Swift crashes, hangs, or never responds to a message, the UI waits forever with no feedback and no way to recover.

**Fix**: Implement a request/response pattern with correlation IDs and a configurable timeout (e.g. 10s). On timeout, show an error toast and allow the user to retry.

---

### M13 — Download Progress Update Has Race Condition in React Store
**File**: `WebUI/src/store.ts`

The `downloadProgress` handler iterates all channels to find the target video. If a video is deleted from Swift state and a progress event arrives in the same event loop tick before the `stateUpdate` event processes, the update applies to a stale reference.

**Fix**: Process `stateUpdate` and `downloadProgress` events in a single batched reducer. If `videoId` is not found in current state, discard the progress event.

---

### M14 — Accessibility Gaps Throughout
**Files**: Multiple view files (Swift and React)

- Custom button styles have no `accessibilityLabel`
- PIN digit dot indicators are not hidden from VoiceOver (`accessibilityHidden(true)` missing on individual dots)
- Modal dialogs in React lack `role="dialog"` and `aria-modal="true"`
- Emoji picker is not keyboard navigable
- Delete confirmation buttons lack ARIA descriptions
- `<select>` elements in Settings.tsx have no `htmlFor` association with their labels

**Fix**: Audit all interactive elements with VoiceOver and keyboard-only navigation. Add missing labels, roles, and focus traps.

---

### M15 — `AppState` Silent Task Failures
**File**: `Sources/LocalTube/State/AppState.swift`

Database operations are wrapped in `Task { try? await ... }` throughout. Failures are silently discarded. A failed channel insertion looks identical to a successful one — the UI shows the channel, but the next app launch it is gone.

**Fix**: Replace `try?` with explicit error handling. At minimum log via `AppLogger`. For user-initiated operations (add channel, save settings) propagate the error to the UI as an alert.

---

### M16 — `Package.swift` on Swift 5.9 Tools Version
**File**: `Package.swift`

Swift 5.9 is from 2023. Swift 5.10 (2024) improves `@Observable` diagnostics and concurrency checking. Swift 6.0 enables strict concurrency mode which would catch the data races identified in this review at compile time.

**Fix**: Update to `swift-tools-version: 6.0` and resolve the resulting concurrency warnings. This will surface many of the race conditions identified above at compile time.

---

## 🔵 LOW

### L1 — `.onAppear` Used Instead of `.task {}`
**Files**: `ViewerRootView.swift`, `ViewerLibraryView.swift`, and others

`.onAppear` with an async `Task { }` inside does not benefit from structured concurrency — the task is not automatically cancelled when the view disappears. `.task {}` is the correct pattern since macOS 14.

**Fix**: Replace `onAppear { Task { await ... } }` with `.task { await ... }` throughout.

---

### L2 — Hardcoded Magic Numbers Throughout Views
**Files**: All view files

Pixel values like `280`, `240`, `160`, `380`, `520`, `800`, `900` appear directly in view bodies without named constants. Several already exist in `TenFootStyles.LT` but are not used consistently.

**Fix**: Add all repeated dimensions to `TenFootStyles.LT` as static constants. Search for bare `CGFloat` literals in view modifiers.

---

### L3 — `@MainActor` Annotations Missing on View Types
**Files**: Most view files

`@Observable` + `@MainActor` is the intended pattern for this codebase (per memory file). Most views do not declare `@MainActor` on the type itself, relying on SwiftUI's implicit main-thread rendering. This is usually safe but becomes dangerous in `.onAppear` / `.task` closures that access `appState`.

**Fix**: Add `@MainActor` to all `View` structs that mutate `@Observable` state directly.

---

### L4 — Recovery Phrase Has Low Entropy
**File**: `Sources/LocalTube/Services/PINService.swift`

4 words from a private wordlist provides roughly 2^16 entropy (assuming ~65,536 words, which is optimistic). This is far below the security bar for a recovery mechanism. If the wordlist is short (the fallback is only 16 words), entropy is catastrophic.

**Fix**: Use at least 6 words. If implementing recovery phrases seriously, adopt the BIP-39 standard wordlist (2048 words → 6 words = 66 bits of entropy). Fail loudly (don't silently fall back) if `wordlist.txt` cannot be loaded.

---

### L5 — `AppLogger` Has No Log Rotation
**File**: `Sources/LocalTube/Utilities/AppLogger.swift`

`localtube.log` grows without bound. On a machine used for months with active downloading, it will exhaust disk space.

**Fix**: Before each write, check file size. If it exceeds a threshold (e.g. 10 MB), rename to `localtube.log.1` (replacing any existing backup) and start fresh.

---

### L6 — Thumbnail Seek Hardcoded to 5 Seconds
**File**: `Sources/LocalTube/Services/ThumbnailService.swift`

Short videos (intros, trailers, clips under 5 seconds) produce a black thumbnail because ffmpeg seeks past EOF.

**Fix**: Use `-ss min(5, duration * 0.1)`. Alternatively, use `ffprobe` to get duration first, or seek to 1 second as a safer default.

---

### L7 — `DependencyCheckView` Scroll Proxy Has No Animation
**File**: `Sources/LocalTube/Views/Onboarding/DependencyCheckView.swift`

`proxy.scrollTo()` on log line appends has no `withAnimation {}` wrapper, causing jarring instant jumps.

**Fix**: Wrap in `withAnimation(.easeOut(duration: 0.15))`.

---

### L8 — yt-dlp Title Not Updated Post-Download
**Known gap from memory file** — after download completes, videos display `"Video XXXX"` as their title instead of the real title fetched from yt-dlp's JSON output.

**Fix**: Parse the `--write-info-json` output file that yt-dlp can produce alongside the video, or use `--print title` in a second pass. Update `DatabaseService.updateTitle(videoId:title:)` after the download task completes.

---

## Summary

| Severity | Count |
|----------|-------|
| 🔴 Critical | 7 |
| 🟠 High | 9 |
| 🟡 Medium | 16 |
| 🔵 Low | 8 |
| **Total** | **40** |

### Fix Priority Order

1. **C1** — Path traversal in thumbnail scheme handler (read arbitrary files)
2. **C2** — XSS via JS string interpolation in bridge emitter
3. **C4 / C5** — PIN stored plaintext (UserDefaults + React state)
4. **C6** — SQL injection pattern in migrations
5. **C7** — WKWebView message handler memory leak
6. **H1 / H8** — AVPlayer/time observer leaks (crash risk)
7. **H2** — `@unchecked Sendable` data race on DownloadQueueItem
8. **H4** — `String(cString:)` null crash in DatabaseService
9. **H5** — Missing transactions for multi-step DB writes
10. **H6** — No React error boundary
11. **C3 / M5** — Homebrew curl|bash + PIN brute force (before any public release)
