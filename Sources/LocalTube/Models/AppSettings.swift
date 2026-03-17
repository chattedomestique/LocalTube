import Foundation

struct AppSettings: Codable, Sendable {
    var downloadFolderPath: String?
    var editorAutoLockMinutes: Int
    var checkDepsOnLaunch: Bool

    init(
        downloadFolderPath: String? = nil,
        editorAutoLockMinutes: Int = 10,
        checkDepsOnLaunch: Bool = true
    ) {
        self.downloadFolderPath = downloadFolderPath
        self.editorAutoLockMinutes = editorAutoLockMinutes
        self.checkDepsOnLaunch = checkDepsOnLaunch
    }
}
