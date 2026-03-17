# LocalTube — App Parameters & Scope Document

> **Version:** 1.1  
> **Date:** 2026-03-16  
> **Status:** Draft — Pre-Development  
> **Platform:** macOS (native Swift / SwiftUI)  
> **Primary Audience:** Children (ages 3–12), operated by a parent or guardian

---

## 1. Project Overview

**LocalTube** is a locally-run macOS application that allows families to curate, download, and watch a personal offline video library sourced from YouTube. The app is designed exclusively for home or classroom use on a television or projector (the "ten-foot screen"), with no deployment for the general public and no cloud backend. All data is stored locally on the host Mac.

The design philosophy prioritizes safety, simplicity, and delight for young viewers, while giving parents and guardians full editorial control over the library.

---

## 2. Platform & Technical Foundation

| Property | Value |
|---|---|
| **Language** | Swift (latest stable) |
| **UI Framework** | SwiftUI + AppKit where necessary |
| **Target OS** | macOS 14 (Sonoma) and later |
| **Architecture** | Single-window, Library + Player app archetype |
| **Build System** | Xcode CLI Tools (`xcodebuild`) |
| **Output Artifact** | Signed `.app` bundle (clickable, drag-to-Applications) |
| **App Sandbox** | **Disabled** — local-only deployment, no public distribution |
| **Persistence** | Local SQLite database + local filesystem |
| **Download Tools** | `yt-dlp` (primary), `ffmpeg` (muxing/conversion), Python 3 |
| **Networking** | Download-only; no server, no accounts, no telemetry |

---

## 3. Ten-Foot Screen Design Rules

All UI decisions are governed by the constraint that the app is **exclusively viewed on a television or projector** at a distance of roughly 10 feet. Standard macOS close-up UI metrics are insufficient — every element must be legible and tappable from a couch.

### 3.1 Typography
- **Minimum body text:** 28pt
- **Minimum label text:** 24pt
- **Channel / video titles:** 36–48pt, bold weight
- **Font:** SF Rounded (friendly, legible, age-appropriate)
- **No small print, footnotes, or dense lists anywhere in the UI**

### 3.2 Touch / Pointer Targets
- Minimum interactive target size: **96 × 96pt** (buttons, cards)
- Generous hit-slop padding on all controls
- Focus rings must be large and high-contrast (tvOS-style ring, not macOS hairline)

### 3.3 Navigation
- Keyboard and Apple TV Remote (if applicable) navigable via focus system
- Arrow key navigation between all major elements
- No hover-dependent reveals — all controls visible at all times in the relevant mode
- Maximum navigation depth: **2 levels** (Library → Channel → Video). No deeper nesting.

### 3.4 Color & Contrast
- WCAG AA minimum contrast ratio across all text/background pairs
- Palette: warm, saturated, child-friendly (avoid clinical or muted tones)
- Dark background default (screen in a dim living room; avoids eye strain)
- Accent color: bright, distinct, single accent per state (no rainbow interfaces)

### 3.5 Imagery & Iconography
- SF Symbols at scale (minimum symbol size: 40pt)
- All icons paired with text labels — no icon-only navigation
- Thumbnails extracted from downloaded video (no network fetch at playback time)

---

## 4. App Launch Behavior

### 4.1 Single-Instance Enforcement
On every launch, the app:
1. Queries running processes for any other instance of itself (by bundle identifier).
2. If a prior instance is found, it sends a termination signal to that process.
3. Proceeds with its own initialization only after confirming the prior instance has exited.
4. Logs the termination event to a local debug log.

### 4.2 Dependency Check
On first launch (and on-demand from Settings), the app checks for the presence of:

| Tool | Required Version | Check Method |
|---|---|---|
| `python3` | 3.9+ | `python3 --version` |
| `yt-dlp` | Latest stable | `yt-dlp --version` |
| `ffmpeg` | 6.0+ | `ffmpeg -version` |

**If any dependency is missing:**
- A friendly, full-screen overlay appears (not a sheet or alert) with a large illustration, a plain-language explanation ("We need a few helpers to download videos!"), and a single large **"Install Now"** button.
- On confirmation, the app uses Homebrew (`brew`) to install missing tools, displaying a live progress view.
- If Homebrew itself is absent, the app installs Homebrew first, then the tools.
- Installation runs in the background with a visible progress indicator; the main UI is non-blocking.
- On completion, the overlay clears and the library is ready.

---

## 5. Library Architecture

### 5.1 Channels (Collections)

The library is organized into **Channels** — named collections of videos.

There are two channel types:

#### Type A — Source Channel (YouTube Channel Mirror)
- Linked to a specific YouTube channel URL.
- Accepts video URLs **only** from that channel (validated on input by comparing the channel ID extracted from the URL).
- Supports two acquisition modes:
  - **Auto Retrieval:** Attempts to fetch all public video URLs from the channel using `yt-dlp --flat-playlist`. The user is shown the count of discovered videos and confirms before downloading.
  - **Manual Input:** The user pastes individual YouTube video URLs one at a time (or in batch, one per line). The app validates that each URL belongs to the bound channel before accepting it.
- Channel identity is stored as `channelId` (YouTube's `@handle` or `UCxxxxxx` ID), not a mutable display name, ensuring consistency even if the YouTube channel renames itself.

#### Type B — Custom Channel (Curated Mix)
- Not bound to any single YouTube channel.
- Accepts YouTube video URLs from **any** channel.
- User provides a custom name and an optional emoji icon.
- Videos added exclusively via manual URL input (single or batch).
- Example use: "🌿 Nature Videos", "🚂 Train Rides", "🎵 Songs".

### 5.2 Channel Creation Flow
1. User taps **"+ New Channel"** (large button, always visible on the Library screen).
2. A large modal presents two choices: **"Mirror a YouTube Channel"** (Type A) or **"Build a Custom Mix"** (Type B) — displayed as large illustrated cards, not a dropdown.
3. For Type A: user pastes the YouTube channel URL; app resolves and displays the channel name and subscriber count for confirmation.
4. For Type B: user types a channel name and optionally selects an emoji.
5. Both flows present the download acquisition choice (Auto vs Manual) where applicable.
6. Channel is created and appears in the sidebar immediately.

### 5.3 Video Metadata (Minimal)
The app stores and displays **only:**

| Field | Source | Editable |
|---|---|---|
| `title` | Extracted from `yt-dlp` at download time | ✅ Yes |
| `localFilePath` | Set at download time | No |
| `channelId` | Extracted from URL | No |
| `thumbnailPath` | Extracted by `ffmpeg` at download time | No |
| `downloadedAt` | System timestamp | No |
| `durationSeconds` | Extracted by `ffmpeg` | No |

**No** description, view count, like count, comment data, or any other YouTube metadata is fetched or stored.

### 5.4 Local Storage Layout

The user selects a **root download folder** in Settings before any downloads can occur (e.g., `/Volumes/MyDrive/LocalTube`). This selection is required — downloading is blocked and a prompt is shown until a folder is chosen.

Within that root folder, LocalTube automatically creates one subfolder per channel, named after the channel's display name (slugified, filesystem-safe):

```
{UserSelectedRoot}/                  # e.g. /Volumes/MyDrive/LocalTube/
├── Cocomelon/
│   ├── videos/                      # .mp4 files
│   └── thumbnails/                  # .jpg files (one per video, ffmpeg-extracted)
├── Nature Videos/
│   ├── videos/
│   └── thumbnails/
└── ...
```

The app's SQLite database and logs live separately in the standard macOS app support directory and are never mixed into the download folder:

```
~/Library/Application Support/LocalTube/
├── library.sqlite                   # All channel + video metadata
└── logs/
    └── localtube.log
```

**Rules:**
- Download folder must be set before any download can begin. If the folder is unset or has been moved/deleted, the app shows a non-dismissible prompt to re-select it.
- Channel subfolder names are derived from the channel's display name at creation time. Renaming a channel in the app does **not** rename the folder on disk (avoids broken paths).
- The user may relocate the root folder at any time via Settings; the app updates all stored paths accordingly.

---

## 6. Viewer Mode

Viewer Mode is the **default and primary mode**. It is designed exclusively for children to use without parental supervision.

### 6.1 Library Screen (Home)
- Full-screen grid of Channel cards.
- Each card: large thumbnail (first video in channel), channel name in large bold text, video count.
- No delete, edit, or add buttons visible in Viewer Mode.
- A subtle, hard-to-accidentally-trigger access point for Editor Mode (e.g., a long-press or a hidden corner tap with a PIN confirmation — parent-only).

### 6.2 Channel Screen
- Full-screen horizontal scroll (or grid) of video cards.
- Each card: video thumbnail, video title.
- Large, obvious play button on hover/focus.
- Back button (upper left, large) to return to Library.

### 6.3 Video Player
- **Full-screen only** — no windowed player.
- Controls: Play/Pause (Space), Skip Back 10s (←), Skip Forward 10s (→), Volume (↑/↓), Back to Library (Escape or large back button).
- Controls auto-hide after 4 seconds of inactivity; reappear on any input.
- No ads, no related video suggestions, no comments, no external links.
- Looping: off by default, toggleable per-video.
- Playback position is remembered per video (resume on next open).
- Player is built using `AVPlayer` / `AVPlayerView` (native macOS, no third-party player).

---

## 7. Editor Mode

Editor Mode is **parent/guardian-only** and is accessed via PIN confirmation.

### 7.1 Access Control
- A 4–6 digit PIN is set on first launch (or via Settings).
- Entering Editor Mode requires PIN entry via a large, TV-friendly numpad overlay.
- PIN is stored in the macOS Keychain.
- An on-screen timer (configurable, default 10 minutes) of inactivity in Editor Mode returns the app to Viewer Mode automatically.

### 7.2 Editor Capabilities

| Action | Scope |
|---|---|
| **Create channel** | Library level |
| **Delete channel** | Library level (with confirmation) |
| **Reorder channels** | Library level (drag-and-drop) |
| **Edit channel name / emoji** | Channel level |
| **Add videos to channel** | Channel level |
| **Remove videos from channel** | Channel level (with confirmation) |
| **Reorder videos within channel** | Channel level (drag-and-drop) |
| **Edit video title** | Per video (inline tap-to-edit) |
| **Re-download a video** | Per video (if file is missing or corrupted) |
| **View download status** | Channel or library level |

### 7.3 Download Management
- Each video has a visible download state: Queued → Downloading (% progress) → Ready → Error.
- Downloads are queued and run sequentially (one at a time) to avoid bandwidth saturation.
- A persistent download queue tray is accessible from the Editor toolbar.
- Failed downloads surface a clear error with a **"Retry"** button.

---

## 8. Settings

Accessible from the macOS App menu (⌘,) — standard macOS convention.

| Setting | Default | Notes |
|---|---|---|
| **Download folder** | _(unset — must be chosen before first download)_ | Required. App blocks all downloads until set. User picks via folder picker. |
| **Editor Mode PIN** | Set on first launch | 4–6 digits; stored in Keychain |
| **Editor Mode auto-lock timeout** | 10 minutes | Configurable |
| **Download quality** | Best available (highest resolution, default frame rate) | No manual override — always maximum quality |
| **Auto-retrieve on channel creation** | Ask each time | For Type A channels |
| **Check for dependency updates** | On launch | `yt-dlp`, `ffmpeg` |

### 8.1 Download Folder Requirement
- On first launch, if no download folder is set, a full-screen **onboarding prompt** is shown before the library is accessible: "📁 First, choose where LocalTube should save your videos."
- A large **"Choose Folder"** button opens a standard macOS folder picker.
- Until a folder is chosen and confirmed, no other UI is accessible.
- If the previously chosen folder is later missing (drive unplugged, folder deleted), the app shows the same blocking prompt on next launch.

### 8.2 Download Quality
- Always downloads at the **highest available resolution** (e.g., 4K if available, otherwise 1080p, etc.) at the video's **native/default frame rate**.
- `yt-dlp` format selection string: `bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best`
- `ffmpeg` merges streams post-download when necessary.
- No quality setting is exposed to the user — this is always automatic.

---

## 9. macOS Design Conventions

The app adheres to macOS Human Interface Guidelines and the **Library + Editor archetype**.

- **Menu Bar:** Standard layout — App / File / View / Window / Help.
  - `App > Settings…` → ⌘,
  - `File > New Channel` → ⌘N
  - `View > Enter Editor Mode` → ⌘E
  - `View > Exit Editor Mode` → ⌘E (toggle)
- **Sidebar:** Channel list; content extends behind sidebar (material background).
- **Liquid Glass:** Applied to toolbar and sidebar navigation layer only — never to content (video cards, player).
- **SF Rounded** used throughout for child-friendliness.
- **Undo/Redo** supported for all Editor Mode operations (⌘Z / ⌘⇧Z).
- **Accessibility:** Full VoiceOver labeling, keyboard navigation, Reduce Motion support (no animations when enabled).

---

## 10. Out of Scope

The following are explicitly **not** in scope for v1.0:

- User accounts or cloud sync
- Multi-user profiles
- Parental controls beyond Editor Mode PIN
- Streaming (all content must be downloaded before playback)
- Non-YouTube sources (future consideration)
- iOS / iPadOS / tvOS versions
- In-app purchases or subscriptions
- Push notifications
- Any analytics or telemetry

---

## 11. Build & Delivery

| Step | Detail |
|---|---|
| **Build tool** | `xcodebuild` (Xcode CLI, no GUI required) |
| **Project type** | SwiftPM-based or `.xcodeproj` — TBD based on complexity |
| **Output** | `LocalTube.app` bundle in `build/Release/` |
| **Code signing** | Ad-hoc signing for local use (`-` identity) |
| **Notarization** | Not required (local use only) |
| **Minimum macOS** | 14.0 (Sonoma) |
| **Architecture** | Universal binary (Apple Silicon + Intel) |
| **Portability** | Built on development machine; deployed by dragging `LocalTube.app` to target machine's `/Applications`. No installer required. Dependencies (`yt-dlp`, `ffmpeg`) installed on the **target machine** by the app itself on first launch. |

---

## 12. Open Questions & Decisions Log

All questions resolved. This section is now a **decisions log**.

| # | Decision | Resolution |
|---|---|---|
| 1 | **Homebrew invocation** | Direct shell invocation via `Process` / `/bin/zsh -c brew install …`. No bundled script. |
| 2 | **Auto-retrieval cap** | Hard cap at **200 videos** per auto-fetch. User sees count before confirming. Auto-retrieval can be **cancelled cleanly at any point** — cancellation stops `yt-dlp`, discards the in-progress fetch result, and leaves previously downloaded videos untouched. |
| 3 | **PIN recovery** | At PIN creation time, the app generates a **recovery phrase** (4 random common English words, e.g. "maple river cloud seven"). Displayed once; user is prompted to write it down. Recovery phrase is stored in Keychain alongside the PIN. To reset: enter recovery phrase via on-screen keyboard; app prompts for a new PIN. |
| 4 | **App Sandbox** | **Disabled.** Local-only deployment, no public distribution. |
| 5 | **Thumbnail generation** | `ffmpeg` extracts a frame at t=5s post-download. No network access required at playback time. Keeps the app fully offline after initial download. |
| 6 | **Download quality** | Always highest available resolution at the video's native frame rate. No user-configurable quality setting. |
| 7 | **Download folder** | User-selected root folder required before any download. App creates per-channel subfolders automatically. Folder path stored in `UserDefaults`; re-prompted if folder goes missing. |
| 8 | **Dev → target deployment** | Build on development machine; drag `LocalTube.app` to target machine. Dependencies installed on target by the app at first launch. |

---

*Document maintained by the development team. All decisions are binding for v1.0 unless explicitly revised with a dated changelog entry.*
