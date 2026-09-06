import Foundation

enum SettingsService {
    private static let key = "com.localtube.settings"
    private static let bookmarkKey = "com.localtube.folderBookmark"

    /// Loads persisted settings. The download folder path is kept even
    /// when the folder is currently unreachable (external drive unplugged,
    /// network share offline). Previously the path was cleared, which
    /// pushed the app back into onboarding and let the user pick a *new*
    /// folder — silently orphaning every video in the library. Callers use
    /// `isDownloadFolderAvailable(_:)` to decide what to show instead.
    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return settings
    }

    static func save(_ settings: AppSettings) {
        var toSave = settings
        if let root = toSave.downloadFolderPath, !root.isEmpty {
            toSave.rememberLibraryRoot(root)
        }
        guard let data = try? JSONEncoder().encode(toSave) else {
            AppLogger.error("SettingsService: failed to encode settings")
            return
        }
        UserDefaults.standard.set(data, forKey: key)

        // Save a security-scoped bookmark for the folder
        if let path = toSave.downloadFolderPath {
            let url = URL(fileURLWithPath: path)
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            }
        }
    }

    static func resolveBookmark() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    /// True when the configured download folder exists and is a directory.
    /// Returns false when no folder is configured at all.
    static func isDownloadFolderAvailable(_ settings: AppSettings) -> Bool {
        guard let path = settings.downloadFolderPath, !path.isEmpty else { return false }
        return isDirectory(atPath: path)
    }

    static func isDirectory(atPath path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
