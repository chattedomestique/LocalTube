import Foundation
import Observation

// MARK: - Download Queue State
enum DownloadQueueState: Equatable, Sendable {
    case waiting
    case active
    case completed
    case failed(error: String)
    case cancelled
}

// MARK: - Download Queue Item
// H2 fix: Added @MainActor to eliminate @unchecked Sendable data race.
// All mutable state (progress, state, activeProcess) is now confined
// to the main actor, matching the rest of the app's convention.
@Observable
@MainActor
final class DownloadQueueItem: Identifiable {
    let id: UUID
    let videoId: UUID
    var videoTitle: String
    var channelName: String
    var progress: Double   // 0.0 – 1.0
    var state: DownloadQueueState

    /// Live process handle — used for cancellation.
    var activeProcess: Process?

    init(
        videoId: UUID,
        videoTitle: String,
        channelName: String
    ) {
        self.id = UUID()
        self.videoId = videoId
        self.videoTitle = videoTitle
        self.channelName = channelName
        self.progress = 0
        self.state = .waiting
        self.activeProcess = nil
    }
}
