import Foundation

enum SettingsService {
    private static let key = "com.localtube.settings"
    private static let bookmarkKey = "com.localtube.folderBookmark"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              var settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        // Validate the folder still exists
        if let path = settings.downloadFolderPath,
           !FileManager.default.fileExists(atPath: path) {
            settings.downloadFolderPath = nil
        }
        return settings
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)

        // Save a security-scoped bookmark for the folder
        if let path = settings.downloadFolderPath {
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
}
