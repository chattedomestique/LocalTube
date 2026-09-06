import Foundation

// MARK: - Library Maintenance
//
// Everything that reconciles the database with what is actually on disk:
//
//   • verify()   — "Rescan": confirm every ready video's file still exists,
//                  heal paths after a folder move, regenerate lost
//                  thumbnails, re-queue videos whose files vanished, and
//                  report orphaned / partial files.
//   • relocate() — move the library to a new folder (physically moving the
//                  files), adopt a folder the user already moved by hand,
//                  or simply switch the download target for new videos.
//   • delete helpers — remove a video's or a channel's files from disk when
//                  the user deletes them in the app (previously nothing was
//                  deleted and the UI merely claimed it was).
//
// Filesystem walking runs off the main actor; state mutation is applied
// back on the main actor through AppState / LibraryStore.

struct LibraryScanResult: Sendable {
    var scannedAt = Date()
    var folderAvailable = true
    var totalVideos = 0
    var readyVideos = 0
    /// Ready videos whose stored path was stale but whose file was found
    /// under the current root (folder moved) — paths rewritten.
    var healedPaths = 0
    /// Ready videos whose file could not be found anywhere.
    var missingFiles = 0
    /// Missing videos put back into the download queue.
    var requeued = 0
    var thumbnailsQueuedForRegeneration = 0
    /// Files inside channel folders that no video/channel references.
    var orphanFiles = 0
    var orphanBytes: Int64 = 0
    /// yt-dlp leftovers (.part / .ytdl) not belonging to a live download.
    var partialFiles = 0
    var bannersHealed = 0
    var errors: [String] = []

    func bridgePayload() -> [String: Any] {
        [
            "scannedAt": ISO8601DateFormatter().string(from: scannedAt),
            "folderAvailable": folderAvailable,
            "totalVideos": totalVideos,
            "readyVideos": readyVideos,
            "healedPaths": healedPaths,
            "missingFiles": missingFiles,
            "requeued": requeued,
            "thumbnailsQueuedForRegeneration": thumbnailsQueuedForRegeneration,
            "orphanFiles": orphanFiles,
            "orphanBytes": orphanBytes,
            "partialFiles": partialFiles,
            "bannersHealed": bannersHealed,
            "errors": errors,
        ]
    }
}

enum LibraryRelocationMode: String, Sendable {
    /// Physically move every channel folder into the new root.
    case move
    /// The files are already in the new root (user moved them in Finder).
    /// Re-point the database at them.
    case adopt
    /// Keep existing files where they are; only new downloads go to the
    /// new root. The old root stays a "known root" so its thumbnails keep
    /// serving.
    case switchOnly = "switch"
}

struct LibraryFolderAnalysis: Sendable {
    var path: String
    var exists = false
    var writable = false
    var isCurrentRoot = false
    var isInsideCurrentRoot = false
    var containsCurrentRoot = false
    /// Channel folders from this library already present in the folder.
    var matchingChannelFolders = 0
    var totalChannels = 0
    var libraryVideoCount = 0
    var libraryReadyCount = 0
    var freeBytes: Int64 = 0
    var libraryBytes: Int64 = 0

    var canMove: Bool { exists && writable && !isCurrentRoot && !isInsideCurrentRoot && !containsCurrentRoot }
    var canAdopt: Bool { exists && matchingChannelFolders > 0 && !isCurrentRoot }

    func bridgePayload() -> [String: Any] {
        [
            "path": path,
            "exists": exists,
            "writable": writable,
            "isCurrentRoot": isCurrentRoot,
            "isInsideCurrentRoot": isInsideCurrentRoot,
            "containsCurrentRoot": containsCurrentRoot,
            "matchingChannelFolders": matchingChannelFolders,
            "totalChannels": totalChannels,
            "libraryVideoCount": libraryVideoCount,
            "libraryReadyCount": libraryReadyCount,
            "freeBytes": freeBytes,
            "libraryBytes": libraryBytes,
            "canMove": canMove,
            "canAdopt": canAdopt,
        ]
    }
}

struct LibraryRelocationResult: Sendable {
    var ok = false
    var mode: LibraryRelocationMode
    var newRoot: String
    var movedChannels = 0
    var rewrittenPaths = 0
    var failedChannels: [String] = []
    var message = ""

    func bridgePayload() -> [String: Any] {
        [
            "ok": ok,
            "mode": mode.rawValue,
            "newRoot": newRoot,
            "movedChannels": movedChannels,
            "rewrittenPaths": rewrittenPaths,
            "failedChannels": failedChannels,
            "message": message,
        ]
    }
}

enum LibraryMaintenanceError: Error, LocalizedError {
    case noLibraryFolder
    case folderUnavailable(String)
    case invalidTarget(String)
    case busy

    var errorDescription: String? {
        switch self {
        case .noLibraryFolder:            return "No library folder is configured."
        case .folderUnavailable(let p):   return "The library folder is not reachable: \(p)"
        case .invalidTarget(let why):     return why
        case .busy:                       return "Another library operation is still running."
        }
    }
}

// File-scope constants so the nonisolated filesystem scan can read them
// without touching main-actor state.
private let libraryVideoExtensions: Set<String> = ["mp4", "m4v", "mov", "mkv", "webm", "m4a"]
private let libraryPartialExtensions: Set<String> = ["part", "ytdl", "tmp"]

@MainActor
final class LibraryMaintenanceService {
    weak var appState: AppState?

    /// Emits updated videos to interested parties (the bridge) as
    /// background thumbnail regeneration completes.
    var onVideosUpdated: (@MainActor ([Video]) -> Void)?
    /// Relocation progress: (done, total, current channel name).
    var onRelocationProgress: (@MainActor (Int, Int, String) -> Void)?

    private(set) var isScanning = false
    private(set) var isRelocating = false
    private(set) var lastScanResult: LibraryScanResult?
    private var thumbnailRegenTask: Task<Void, Never>?

    init(appState: AppState? = nil) {
        self.appState = appState
    }

    // MARK: - Verify / Rescan

    /// Reconciles the database with the files on disk.
    ///
    /// - `requeueMissing`: put ready videos whose file is gone back in the
    ///   download queue (the TODO's "refresh channel for missing videos").
    /// - `preferCurrentRoot`: when a file exists both at its stored path
    ///   and at the same relative path under the current root, prefer the
    ///   current root (used right after "adopt").
    @discardableResult
    func verify(requeueMissing: Bool = true, preferCurrentRoot: Bool = false) async -> LibraryScanResult {
        guard let appState else { return LibraryScanResult() }
        guard !isScanning else {
            return lastScanResult ?? LibraryScanResult()
        }
        isScanning = true
        defer { isScanning = false }

        var result = LibraryScanResult()
        guard let root = appState.settings.downloadFolderPath, !root.isEmpty else {
            result.folderAvailable = false
            result.errors.append("No library folder configured")
            lastScanResult = result
            return result
        }
        guard SettingsService.isDirectory(atPath: root) else {
            result.folderAvailable = false
            result.errors.append("Library folder is not reachable: \(root)")
            lastScanResult = result
            return result
        }

        let channels = appState.channels
        let videosByChannel = appState.videos
        let knownRoots = appState.settings.knownLibraryRoots
        let liveDownloadIds = Set(appState.downloadQueue.filter { $0.isLive }.map { $0.videoId })

        // ── Filesystem pass (off the main actor) ─────────────────────────
        let scan = await Task.detached(priority: .utility) { () -> ScanOutcome in
            Self.scanFilesystem(
                root: root,
                knownRoots: knownRoots,
                channels: channels,
                videosByChannel: videosByChannel,
                liveDownloadIds: liveDownloadIds,
                preferCurrentRoot: preferCurrentRoot
            )
        }.value

        result.totalVideos = scan.totalVideos
        result.readyVideos = scan.readyVideos
        result.orphanFiles = scan.orphanFiles
        result.orphanBytes = scan.orphanBytes
        result.partialFiles = scan.partialFiles
        result.errors.append(contentsOf: scan.errors)

        // ── Apply healed paths ───────────────────────────────────────────
        var healedVideos: [Video] = []
        for heal in scan.healed {
            guard var v = appState.videoById(heal.videoId) else { continue }
            v.localFilePath = heal.localFilePath
            v.thumbnailPath = heal.thumbnailPath
            appState.updateVideo(v)
            healedVideos.append(v)
        }
        if !healedVideos.isEmpty {
            let snapshot = healedVideos
            await appState.persist("verify heal paths") {
                for v in snapshot {
                    try await DatabaseService.shared.updateVideoPaths(
                        id: v.id, localFilePath: v.localFilePath, thumbnailPath: v.thumbnailPath
                    )
                }
            }
            result.healedPaths = healedVideos.count
            AppLogger.info("Verify: healed \(healedVideos.count) stale video path(s)")
        }

        // ── Banners ──────────────────────────────────────────────────────
        for heal in scan.healedBanners {
            guard let idx = appState.channels.firstIndex(where: { $0.id == heal.channelId }) else { continue }
            appState.channels[idx].bannerPath = heal.bannerPath
            let cid = heal.channelId
            let path = heal.bannerPath
            await appState.persist("verify heal banner") {
                try await DatabaseService.shared.updateChannelBanner(id: cid, bannerPath: path)
            }
            result.bannersHealed += 1
        }

        // ── Missing files ────────────────────────────────────────────────
        result.missingFiles = scan.missing.count
        if !scan.missing.isEmpty {
            var toPersist: [Video] = []
            for videoId in scan.missing {
                guard var v = appState.videoById(videoId) else { continue }
                if requeueMissing {
                    v.downloadState = .queued
                    v.downloadError = nil
                } else {
                    v.downloadState = .error
                    v.downloadError = "Video file is missing from the library folder."
                }
                v.downloadProgress = 0
                appState.updateVideo(v)
                toPersist.append(v)
            }
            let snapshot = toPersist
            await appState.persist("verify missing files") {
                try await DatabaseService.shared.persistVideos(snapshot)
            }
            if requeueMissing {
                for v in toPersist {
                    guard let channel = appState.channelById(v.channelId) else { continue }
                    await appState.downloadService.enqueue(video: v, channel: channel)
                    result.requeued += 1
                }
            }
            AppLogger.info("Verify: \(scan.missing.count) video file(s) missing, \(result.requeued) re-queued")
        }

        // ── Thumbnails ───────────────────────────────────────────────────
        result.thumbnailsQueuedForRegeneration = scan.needsThumbnail.count
        if !scan.needsThumbnail.isEmpty {
            scheduleThumbnailRegeneration(videoIds: scan.needsThumbnail, root: root)
        }

        lastScanResult = result
        AppLogger.info("Verify complete: \(result.readyVideos)/\(result.totalVideos) ready, \(result.missingFiles) missing, \(result.orphanFiles) orphan file(s), \(result.partialFiles) partial file(s)")
        return result
    }

    private func scheduleThumbnailRegeneration(videoIds: [UUID], root: String) {
        thumbnailRegenTask?.cancel()
        thumbnailRegenTask = Task { [weak self] in
            guard let self, let appState = self.appState else { return }
            var updatedBatch: [Video] = []
            for id in videoIds {
                if Task.isCancelled { break }
                guard var v = appState.videoById(id),
                      v.downloadState == .ready,
                      let channel = appState.channelById(v.channelId) else { continue }
                let thumbsDir = channel.thumbnailsPath(rootFolder: root)
                try? FileManager.default.createDirectory(atPath: thumbsDir, withIntermediateDirectories: true)
                let dest = ThumbnailService.thumbnailPath(for: v, channel: channel, rootFolder: root)
                do {
                    try await ThumbnailService.extract(videoPath: v.localFilePath, outputPath: dest)
                } catch {
                    AppLogger.error("Thumbnail regeneration failed for \(v.title): \(error.localizedDescription)")
                    continue
                }
                guard FileManager.default.fileExists(atPath: dest),
                      var latest = appState.videoById(id) else { continue }
                latest.thumbnailPath = dest
                latest.thumbnailVersion += 1
                v = latest
                appState.updateVideoAndPersist(v, context: "regen thumbnail")
                updatedBatch.append(v)
                if updatedBatch.count >= 10 {
                    self.onVideosUpdated?(updatedBatch)
                    updatedBatch.removeAll()
                }
            }
            if !updatedBatch.isEmpty {
                self.onVideosUpdated?(updatedBatch)
            }
        }
    }

    // MARK: - Filesystem scan (nonisolated)

    private struct HealedVideo: Sendable {
        let videoId: UUID
        let localFilePath: String
        let thumbnailPath: String
    }

    private struct HealedBanner: Sendable {
        let channelId: UUID
        let bannerPath: String
    }

    private struct ScanOutcome: Sendable {
        var totalVideos = 0
        var readyVideos = 0
        var healed: [HealedVideo] = []
        var healedBanners: [HealedBanner] = []
        var missing: [UUID] = []
        var needsThumbnail: [UUID] = []
        var orphanFiles = 0
        var orphanBytes: Int64 = 0
        var partialFiles = 0
        var errors: [String] = []
    }

    private nonisolated static func scanFilesystem(
        root: String,
        knownRoots: [String],
        channels: [Channel],
        videosByChannel: [UUID: [Video]],
        liveDownloadIds: Set<UUID>,
        preferCurrentRoot: Bool
    ) -> ScanOutcome {
        let fm = FileManager.default
        var outcome = ScanOutcome()
        var referenced = Set<String>()
        let channelsById = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })

        func firstExisting(_ candidates: [String]) -> String? {
            candidates.first { !$0.isEmpty && fm.fileExists(atPath: $0) }
        }

        func resolve(_ stored: String) -> String? {
            guard !stored.isEmpty else { return nil }
            var candidates = LibraryPaths.candidateLocations(for: stored, currentRoot: root, knownRoots: knownRoots)
            if preferCurrentRoot, candidates.count > 1 {
                // Put the current-root candidates first so an adopted copy
                // wins over the original location.
                let underRoot = candidates.filter { LibraryPaths.isPath($0, under: root) }
                let others = candidates.filter { !LibraryPaths.isPath($0, under: root) }
                candidates = underRoot + others
            }
            return firstExisting(candidates)
        }

        for (channelId, videos) in videosByChannel {
            let channel = channelsById[channelId]
            for video in videos {
                outcome.totalVideos += 1
                guard video.downloadState == .ready else {
                    // Queued/downloading/error videos may have a .part on
                    // disk; those belong to them, don't count as orphans.
                    if !video.localFilePath.isEmpty {
                        referenced.insert(LibraryPaths.normalize(video.localFilePath))
                    }
                    continue
                }
                outcome.readyVideos += 1

                var resolvedVideo = resolve(video.localFilePath)
                if resolvedVideo == nil, let channel {
                    // Title changed between attempts → different slug, same
                    // 8-char id suffix. Look for "*-<prefix>.mp4" in the folder.
                    let dir = channel.videosPath(rootFolder: root)
                    let suffix = "-" + String(video.id.uuidString.prefix(8))
                    if let names = try? fm.contentsOfDirectory(atPath: dir) {
                        if let match = names.first(where: { name in
                            let base = (name as NSString).deletingPathExtension
                            let ext = (name as NSString).pathExtension.lowercased()
                            return base.hasSuffix(suffix) && libraryVideoExtensions.contains(ext)
                        }) {
                            resolvedVideo = (dir as NSString).appendingPathComponent(match)
                        }
                    }
                }

                guard let videoPath = resolvedVideo else {
                    outcome.missing.append(video.id)
                    continue
                }
                referenced.insert(LibraryPaths.normalize(videoPath))

                var thumbPath = resolve(video.thumbnailPath) ?? ""
                if thumbPath.isEmpty, let channel {
                    // Standard location for this video's thumbnail.
                    let standard = ThumbnailService.thumbnailPath(for: video, channel: channel, rootFolder: root)
                    if fm.fileExists(atPath: standard) { thumbPath = standard }
                }
                if thumbPath.isEmpty {
                    outcome.needsThumbnail.append(video.id)
                } else {
                    referenced.insert(LibraryPaths.normalize(thumbPath))
                }

                let normalizedVideo = LibraryPaths.normalize(videoPath)
                let normalizedThumb = LibraryPaths.normalize(thumbPath)
                if normalizedVideo != LibraryPaths.normalize(video.localFilePath)
                    || (!thumbPath.isEmpty && normalizedThumb != LibraryPaths.normalize(video.thumbnailPath)) {
                    outcome.healed.append(HealedVideo(
                        videoId: video.id,
                        localFilePath: normalizedVideo,
                        thumbnailPath: thumbPath.isEmpty ? video.thumbnailPath : normalizedThumb
                    ))
                }
            }
        }

        // Banners
        for channel in channels {
            let standard = channel.bannerFilePath(rootFolder: root)
            var resolved = resolve(channel.bannerPath)
            if resolved == nil, fm.fileExists(atPath: standard) { resolved = standard }
            if let resolved {
                referenced.insert(LibraryPaths.normalize(resolved))
                if LibraryPaths.normalize(resolved) != LibraryPaths.normalize(channel.bannerPath) {
                    outcome.healedBanners.append(HealedBanner(channelId: channel.id, bannerPath: LibraryPaths.normalize(resolved)))
                }
            }
        }

        // Orphans + partial files inside each channel folder.
        let livePrefixes = Set(liveDownloadIds.map { "-" + String($0.uuidString.prefix(8)) })
        for channel in channels {
            for dir in [channel.videosPath(rootFolder: root), channel.thumbnailsPath(rootFolder: root)] {
                guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for name in names where !name.hasPrefix(".") {
                    let full = (dir as NSString).appendingPathComponent(name)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { continue }
                    let normalized = LibraryPaths.normalize(full)
                    if referenced.contains(normalized) { continue }
                    let ext = (name as NSString).pathExtension.lowercased()
                    let isPartial = libraryPartialExtensions.contains(ext) || name.contains(".part")
                    if isPartial {
                        // A .part belonging to a download that's running right now is expected.
                        let base = (name as NSString).deletingPathExtension
                        if livePrefixes.contains(where: { base.contains($0) }) { continue }
                        outcome.partialFiles += 1
                    } else {
                        // Files for queued/error videos are referenced above; anything
                        // else nobody knows about.
                        outcome.orphanFiles += 1
                        let size = (try? fm.attributesOfItem(atPath: full)[.size] as? Int64) ?? 0
                        outcome.orphanBytes += size
                    }
                }
            }
        }

        return outcome
    }

    // MARK: - Relocation

    /// Inspects a candidate folder so the UI can offer Move / Adopt / Switch.
    func analyzeFolder(_ path: String) async -> LibraryFolderAnalysis {
        let normalized = LibraryPaths.normalize(path)
        var analysis = LibraryFolderAnalysis(path: normalized)
        guard let appState else { return analysis }
        let current = appState.settings.downloadFolderPath.map(LibraryPaths.normalize) ?? ""
        let channels = appState.channels
        let allVideos = appState.videos.values.flatMap { $0 }
        analysis.totalChannels = channels.count
        analysis.libraryVideoCount = allVideos.count
        analysis.libraryReadyCount = allVideos.filter { $0.downloadState == .ready }.count
        analysis.isCurrentRoot = !current.isEmpty && normalized == current
        analysis.isInsideCurrentRoot = !current.isEmpty && normalized != current && LibraryPaths.isPath(normalized, under: current)
        analysis.containsCurrentRoot = !current.isEmpty && normalized != current && LibraryPaths.isPath(current, under: normalized)

        let readyPaths = allVideos.filter { $0.downloadState == .ready }.map { $0.localFilePath }
        let folderNames = channels.map { $0.sanitizedFolderName }

        let (exists, writable, matching, free, libraryBytes) = await Task.detached(priority: .utility) {
            () -> (Bool, Bool, Int, Int64, Int64) in
            let fm = FileManager.default
            let exists = SettingsService.isDirectory(atPath: normalized)
            var writable = false
            if exists {
                let probe = (normalized as NSString).appendingPathComponent(".localtube-write-test-\(UUID().uuidString.prefix(8))")
                writable = fm.createFile(atPath: probe, contents: Data())
                if writable { try? fm.removeItem(atPath: probe) }
            }
            var matching = 0
            if exists {
                for name in folderNames {
                    let candidate = (normalized as NSString).appendingPathComponent(name)
                    if SettingsService.isDirectory(atPath: candidate) { matching += 1 }
                }
            }
            var free: Int64 = 0
            if exists,
               let attrs = try? fm.attributesOfFileSystem(forPath: normalized),
               let n = attrs[.systemFreeSize] as? NSNumber {
                free = n.int64Value
            }
            var bytes: Int64 = 0
            for p in readyPaths where !p.isEmpty {
                if let size = (try? fm.attributesOfItem(atPath: p)[.size] as? Int64) { bytes += size }
            }
            return (exists, writable, matching, free, bytes)
        }.value

        analysis.exists = exists
        analysis.writable = writable
        analysis.matchingChannelFolders = matching
        analysis.freeBytes = free
        analysis.libraryBytes = libraryBytes
        return analysis
    }

    /// Performs the relocation. Always snapshots the database first.
    func relocate(to newRootRaw: String, mode: LibraryRelocationMode) async -> LibraryRelocationResult {
        let newRoot = LibraryPaths.normalize(newRootRaw)
        var result = LibraryRelocationResult(mode: mode, newRoot: newRoot)
        guard let appState else { result.message = "App state unavailable"; return result }
        guard !isRelocating else {
            result.message = LibraryMaintenanceError.busy.localizedDescription
            return result
        }
        isRelocating = true
        defer { isRelocating = false }

        let analysis = await analyzeFolder(newRoot)
        guard analysis.exists else {
            result.message = "The chosen folder does not exist."
            return result
        }
        let oldRoot = appState.settings.downloadFolderPath.map(LibraryPaths.normalize) ?? ""

        switch mode {
        case .move:
            guard analysis.canMove else {
                if analysis.isCurrentRoot { result.message = "That is already the library folder." }
                else if analysis.isInsideCurrentRoot { result.message = "The new folder cannot be inside the current library folder." }
                else if analysis.containsCurrentRoot { result.message = "The new folder cannot contain the current library folder." }
                else if !analysis.writable { result.message = "LocalTube cannot write to that folder." }
                else { result.message = "That folder cannot be used." }
                return result
            }
            if analysis.freeBytes > 0, analysis.libraryBytes > 0,
               analysis.freeBytes < analysis.libraryBytes,
               !Self.sameVolume(oldRoot, newRoot) {
                result.message = "Not enough free space in the new folder (\(Self.formatBytes(analysis.libraryBytes)) needed, \(Self.formatBytes(analysis.freeBytes)) free)."
                return result
            }
        case .adopt:
            guard !analysis.isCurrentRoot else {
                result.message = "That is already the library folder."
                return result
            }
        case .switchOnly:
            guard analysis.writable else {
                result.message = "LocalTube cannot write to that folder."
                return result
            }
        }

        // Stop in-flight downloads; they resume against the new root below.
        appState.downloadService.cancelAll()

        do {
            try await DatabaseService.shared.backupDatabase(label: "pre-relocate-\(mode.rawValue)")
        } catch {
            AppLogger.error("Relocation: database backup failed — \(error.localizedDescription)")
            result.message = "Could not back up the library database: \(error.localizedDescription)"
            return result
        }

        if mode == .move, !oldRoot.isEmpty {
            let channels = appState.channels
            let total = channels.count
            var done = 0
            for channel in channels {
                let name = channel.displayName
                onRelocationProgress?(done, total, name)
                let src = channel.folderPath(rootFolder: oldRoot)
                let dst = channel.folderPath(rootFolder: newRoot)
                let moveError = await Task.detached(priority: .userInitiated) { () -> String? in
                    Self.moveChannelFolder(from: src, to: dst)
                }.value
                if let moveError {
                    AppLogger.error("Relocation: failed to move \(name): \(moveError)")
                    result.failedChannels.append(name)
                } else {
                    result.movedChannels += 1
                    do {
                        let n = try await DatabaseService.shared.rewritePathPrefix(from: src + "/", to: dst + "/")
                        result.rewrittenPaths += n
                    } catch {
                        AppLogger.error("Relocation: path rewrite failed for \(name): \(error.localizedDescription)")
                        result.failedChannels.append(name)
                    }
                }
                done += 1
                onRelocationProgress?(done, total, name)
            }
        }

        // Point the app at the new root, remembering the old one.
        var settings = appState.settings
        if !oldRoot.isEmpty { settings.rememberLibraryRoot(oldRoot) }
        settings.downloadFolderPath = newRoot
        settings.rememberLibraryRoot(newRoot)
        appState.settings = settings
        SettingsService.save(settings)
        appState.refreshLibraryFolderAvailability()

        // Reload paths from the database so memory matches what was rewritten.
        await appState.library.reloadFromDatabase()

        // Adopt / post-move: heal any path the prefix rewrite didn't cover
        // and pick up the copies under the new root.
        if mode == .adopt || mode == .move {
            let scan = await verify(requeueMissing: false, preferCurrentRoot: true)
            result.rewrittenPaths += scan.healedPaths
        }

        await appState.downloadService.resumePendingDownloads()

        switch mode {
        case .move:
            result.ok = result.failedChannels.isEmpty
            result.message = result.ok
                ? "Moved \(result.movedChannels) channel folder(s) to \(newRoot)."
                : "Moved \(result.movedChannels) channel folder(s); \(result.failedChannels.count) could not be moved and still live in the previous folder."
        case .adopt:
            result.ok = true
            result.message = "Library now points at \(newRoot). \(result.rewrittenPaths) file path(s) updated."
        case .switchOnly:
            result.ok = true
            result.message = "New downloads will be saved to \(newRoot). Existing videos stay where they are."
        }
        AppLogger.info("Relocation (\(mode.rawValue)) finished: \(result.message)")
        return result
    }

    /// Moves `src` → `dst`, merging into `dst` if it already exists.
    /// Returns an error description, or nil on success.
    private nonisolated static func moveChannelFolder(from src: String, to dst: String) -> String? {
        let fm = FileManager.default
        guard SettingsService.isDirectory(atPath: src) else { return nil }   // nothing to move
        do {
            if !fm.fileExists(atPath: dst) {
                try fm.createDirectory(atPath: (dst as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try fm.moveItem(atPath: src, toPath: dst)
                return nil
            }
            // Merge: walk src recursively, move each file that isn't already present.
            guard let enumerator = fm.enumerator(atPath: src) else { return "Cannot enumerate \(src)" }
            var failures: [String] = []
            while let rel = enumerator.nextObject() as? String {
                let from = (src as NSString).appendingPathComponent(rel)
                let to = (dst as NSString).appendingPathComponent(rel)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: from, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    try? fm.createDirectory(atPath: to, withIntermediateDirectories: true)
                    continue
                }
                if fm.fileExists(atPath: to) {
                    // Same file already there — drop the duplicate source.
                    try? fm.removeItem(atPath: from)
                    continue
                }
                do {
                    try fm.createDirectory(atPath: (to as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                    try fm.moveItem(atPath: from, toPath: to)
                } catch {
                    failures.append("\(rel): \(error.localizedDescription)")
                }
            }
            if failures.isEmpty {
                // Remove the now-empty source tree (ignore failure — leftovers are harmless).
                try? fm.removeItem(atPath: src)
                return nil
            }
            return failures.prefix(3).joined(separator: "; ")
        } catch {
            return error.localizedDescription
        }
    }

    private nonisolated static func sameVolume(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        let fm = FileManager.default
        let idA = (try? fm.attributesOfItem(atPath: a)[.systemNumber] as? NSNumber)?.intValue
        let idB = (try? fm.attributesOfItem(atPath: b)[.systemNumber] as? NSNumber)?.intValue
        guard let idA, let idB else { return false }
        return idA == idB
    }

    private nonisolated static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Existence checks

    /// True when the stored path — or its equivalent under the current
    /// root after a folder move — exists on disk. Cheap enough to call
    /// per-video from a channel sync.
    nonisolated static func fileExists(forStored path: String, currentRoot: String?, knownRoots: [String]) -> Bool {
        guard !path.isEmpty else { return false }
        let fm = FileManager.default
        if fm.fileExists(atPath: path) { return true }
        guard let root = currentRoot, !root.isEmpty else { return false }
        return LibraryPaths.candidateLocations(for: path, currentRoot: root, knownRoots: knownRoots)
            .contains { fm.fileExists(atPath: $0) }
    }

    // MARK: - Deletion helpers

    /// Removes a video's file, thumbnail and any yt-dlp leftovers (.part,
    /// .ytdl, sibling thumbnails) from disk. Runs off the main actor.
    nonisolated static func deleteFiles(for video: Video, channel: Channel?, rootFolder: String?) async {
        let paths = [video.localFilePath, video.thumbnailPath].filter { !$0.isEmpty }
        let suffix = "-" + String(video.id.uuidString.prefix(8))
        let videosDir: String? = {
            guard let channel, let root = rootFolder, !root.isEmpty else { return nil }
            return channel.videosPath(rootFolder: root)
        }()
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            for p in paths where fm.fileExists(atPath: p) {
                Self.remove(p)
            }
            guard let dir = videosDir, let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for name in names {
                let base = (name as NSString).deletingPathExtension
                // Matches "<slug>-<prefix>.mp4", "<slug>-<prefix>.mp4.part",
                // "<slug>-<prefix>.webp", … but never another video's files.
                guard base.contains(suffix) || name.contains(suffix + ".") else { continue }
                Self.remove((dir as NSString).appendingPathComponent(name))
            }
        }.value
        AppLogger.info("Deleted files for video \(video.title)")
    }

    /// Moves a channel's whole folder to the Trash (falling back to a
    /// permanent delete on volumes without a Trash). Refuses when another
    /// channel shares the same folder name.
    nonisolated static func deleteFolder(for channel: Channel, rootFolder: String, otherChannels: [Channel]) async -> Bool {
        let name = channel.sanitizedFolderName
        guard LibraryPaths.isSafeComponent(name) else { return false }
        if otherChannels.contains(where: { $0.id != channel.id && $0.sanitizedFolderName == name }) {
            AppLogger.error("Not deleting folder \(name): shared with another channel")
            return false
        }
        let folder = channel.folderPath(rootFolder: rootFolder)
        guard LibraryPaths.isPath(folder, under: rootFolder), LibraryPaths.normalize(folder) != LibraryPaths.normalize(rootFolder) else {
            return false
        }
        let removed = await Task.detached(priority: .utility) { () -> Bool in
            guard SettingsService.isDirectory(atPath: folder) else { return true }
            return Self.trashOrRemove(folder)
        }.value
        if removed {
            AppLogger.info("Deleted channel folder \(folder)")
        } else {
            AppLogger.error("Failed to delete channel folder \(folder)")
        }
        return removed
    }

    private nonisolated static func remove(_ path: String) {
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            AppLogger.error("Failed to delete \(path): \(error.localizedDescription)")
        }
    }

    private nonisolated static func trashOrRemove(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            do {
                try FileManager.default.removeItem(at: url)
                return true
            } catch {
                AppLogger.error("Failed to delete \(path): \(error.localizedDescription)")
                return false
            }
        }
    }
}
