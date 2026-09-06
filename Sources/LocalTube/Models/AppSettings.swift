import Foundation

// MARK: - Download Quality
//
// Maps the Settings "Download Quality" picker to a yt-dlp format selector.
// H.264 (avc1) + AAC (m4a) is preferred everywhere because AVPlayer decodes
// it in hardware on every supported Mac; AV1/VP9 can stall on first frame.
enum DownloadQuality: String, CaseIterable, Codable, Sendable {
    case best
    case p1080 = "1080p"
    case p720  = "720p"
    case p480  = "480p"
    case p360  = "360p"
    case audio

    /// The `-f` selector passed to yt-dlp.
    var ytDlpFormat: String {
        switch self {
        case .best:
            return "bestvideo[vcodec^=avc1][height<=1080]+bestaudio[ext=m4a]/bestvideo[vcodec^=avc1]+bestaudio/bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
        case .p1080: return Self.capped(1080)
        case .p720:  return Self.capped(720)
        case .p480:  return Self.capped(480)
        case .p360:  return Self.capped(360)
        case .audio:
            // Audio-only is still muxed into an .mp4 container (AAC in mp4)
            // so the player + thumbnail pipeline stay unchanged.
            return "bestaudio[ext=m4a]/bestaudio"
        }
    }

    private static func capped(_ height: Int) -> String {
        "bestvideo[vcodec^=avc1][height<=\(height)]+bestaudio[ext=m4a]/bestvideo[height<=\(height)][ext=mp4]+bestaudio[ext=m4a]/best[height<=\(height)][ext=mp4]/best[height<=\(height)]/best"
    }
}

// MARK: - App Settings
//
// Persisted as JSON in UserDefaults (see SettingsService). Decoding is
// deliberately tolerant: every field falls back to its default when the
// key is missing or malformed. Before this, adding *any* new property
// made `JSONDecoder` fail on older saved blobs, which reset settings to
// `AppSettings()` — i.e. `downloadFolderPath == nil` — and dropped users
// straight back into onboarding with an orphaned library. Older builds
// reading newer blobs simply ignore unknown keys, so rollback is safe.

struct AppSettings: Codable, Sendable {
    var downloadFolderPath: String?
    var editorAutoLockMinutes: Int
    var checkDepsOnLaunch: Bool
    /// yt-dlp quality preset for new downloads.
    var downloadQuality: DownloadQuality
    /// Every root folder the library has ever lived in (current one
    /// included). Used to (a) let the thumbnail scheme handler serve
    /// images from a previous root after a "keep files where they are"
    /// switch, and (b) heal stale absolute paths when the folder moves.
    var knownLibraryRoots: [String]

    init(
        downloadFolderPath: String? = nil,
        editorAutoLockMinutes: Int = 10,
        checkDepsOnLaunch: Bool = true,
        downloadQuality: DownloadQuality = .best,
        knownLibraryRoots: [String] = []
    ) {
        self.downloadFolderPath = downloadFolderPath
        self.editorAutoLockMinutes = editorAutoLockMinutes
        self.checkDepsOnLaunch = checkDepsOnLaunch
        self.downloadQuality = downloadQuality
        self.knownLibraryRoots = knownLibraryRoots
    }

    private enum CodingKeys: String, CodingKey {
        case downloadFolderPath
        case editorAutoLockMinutes
        case checkDepsOnLaunch
        case downloadQuality
        case knownLibraryRoots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        downloadFolderPath    = try? c.decodeIfPresent(String.self, forKey: .downloadFolderPath)
        editorAutoLockMinutes = (try? c.decodeIfPresent(Int.self, forKey: .editorAutoLockMinutes)) ?? 10
        checkDepsOnLaunch     = (try? c.decodeIfPresent(Bool.self, forKey: .checkDepsOnLaunch)) ?? true
        let qualityRaw        = (try? c.decodeIfPresent(String.self, forKey: .downloadQuality)) ?? nil
        downloadQuality       = qualityRaw.flatMap(DownloadQuality.init(rawValue:)) ?? .best
        knownLibraryRoots     = (try? c.decodeIfPresent([String].self, forKey: .knownLibraryRoots)) ?? []
        // The current root is always a known root.
        if let root = downloadFolderPath, !root.isEmpty, !knownLibraryRoots.contains(root) {
            knownLibraryRoots.append(root)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(downloadFolderPath, forKey: .downloadFolderPath)
        try c.encode(editorAutoLockMinutes, forKey: .editorAutoLockMinutes)
        try c.encode(checkDepsOnLaunch, forKey: .checkDepsOnLaunch)
        try c.encode(downloadQuality.rawValue, forKey: .downloadQuality)
        try c.encode(knownLibraryRoots, forKey: .knownLibraryRoots)
    }

    /// Records `root` as a library location (current or historical).
    mutating func rememberLibraryRoot(_ root: String) {
        let normalized = LibraryPaths.normalize(root)
        guard !normalized.isEmpty else { return }
        if !knownLibraryRoots.contains(normalized) {
            knownLibraryRoots.append(normalized)
        }
    }
}
