import SwiftUI

struct AddVideosView: View {
    let channel: Channel
    var onDone: () -> Void
    @Environment(AppState.self) private var appState

    @State private var urlText = ""
    @State private var validationResults: [(url: String, valid: Bool, error: String?)] = []
    @State private var isAutoRetrieving = false
    @State private var autoRetrieveCount = 0
    @State private var autoRetrieveProcess: Process?
    @State private var autoRetrieveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // Auto-retrieve section (only for channel-mirrored sources)
                if channel.type == .source {
                    autoRetrieveSection
                }

                // Manual URL section — always shown
                manualInputSection
            }
            .padding(28)
        }
        .background(Color.ltBackground)
    }

    // MARK: - Auto Retrieve Section

    @ViewBuilder
    private var autoRetrieveSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.ltAccent)
                Text("Auto Retrieve All Videos")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ltText)
            }

            Text("Automatically fetch all public videos from this channel (up to 200).")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color.ltTextSecondary)

            // Error — stable layout
            Text(autoRetrieveError ?? "")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color.ltDestructive)
                .frame(height: 16)
                .opacity(autoRetrieveError != nil ? 1 : 0)

            if isAutoRetrieving {
                HStack(spacing: 14) {
                    ProgressView().controlSize(.small).tint(Color.ltAccent)
                    Text("Found \(autoRetrieveCount) video\(autoRetrieveCount == 1 ? "" : "s")…")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color.ltText)
                    Spacer()
                    Button("Cancel") {
                        autoRetrieveProcess?.terminate()
                        isAutoRetrieving = false
                    }
                    .buttonStyle(LTEditorSecondaryButtonStyle())
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.ltSurface)
                )
            } else {
                Button("Auto Retrieve") { startAutoRetrieve() }
                    .buttonStyle(LTEditorButtonStyle())
                    .disabled(channel.youtubeChannelId == nil)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.ltSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.ltAccent.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
        )
    }

    // MARK: - Manual URL Input Section

    private var manualInputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.ltBlue)
                Text("Add Videos by URL")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ltText)
            }

            Text("Paste one YouTube video URL per line.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color.ltTextSecondary)

            // ─── Text area with placeholder ─────────────────────────────
            ZStack(alignment: .topLeading) {
                // Placeholder — hidden once user types
                if urlText.isEmpty {
                    // Use template-style text (not real URLs) so macOS link
                    // detection doesn't override the foreground colour with blue.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("youtube.com/watch?v=VIDEO_ID")
                            .foregroundStyle(Color.white.opacity(0.5))
                        Text("youtube.com/watch?v=VIDEO_ID")
                            .foregroundStyle(Color.white.opacity(0.5))
                        Text("youtu.be/VIDEO_ID")
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
                }

                TextEditor(text: $urlText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.ltText)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 130)
                    .onChange(of: urlText) { _, _ in validateURLs() }
            }
            .background(Color.ltSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        urlText.isEmpty ? Color(white: 0.35) : Color.ltAccent.opacity(0.6),
                        lineWidth: urlText.isEmpty ? 1 : 1.5
                    )
            )

            // ─── Validation results ─────────────────────────────────────
            if !validationResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(validationResults.prefix(10), id: \.url) { result in
                        HStack(spacing: 8) {
                            Image(systemName: result.valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.valid ? Color.ltSuccess : Color.ltDestructive)
                                .font(.system(size: 14))

                            Text(result.url.count > 55 ? String(result.url.prefix(52)) + "…" : result.url)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(result.valid ? Color.ltText : Color.ltTextTertiary)
                                .lineLimit(1)

                            if let err = result.error {
                                Text("— \(err)")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(Color.ltDestructive)
                            }
                        }
                    }
                    if validationResults.count > 10 {
                        Text("…and \(validationResults.count - 10) more")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color.ltTextSecondary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.ltSurface)
                )
            }

            // ─── Action button ──────────────────────────────────────────
            let validCount = validationResults.filter { $0.valid }.count
            Button(validCount > 0
                   ? "Add \(validCount) Video\(validCount == 1 ? "" : "s") to Queue"
                   : "Add Videos to Queue") {
                queueValidURLs()
            }
            .buttonStyle(LTEditorButtonStyle())
            .disabled(validCount == 0)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.ltSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.ltBlue.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
        )
    }

    // MARK: - Validation

    private func validateURLs() {
        let lines = urlText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        validationResults = lines.map { url in
            if !url.isYouTubeVideoURL {
                return (url: url, valid: false, error: "Not a YouTube video URL")
            }
            return (url: url, valid: true, error: nil)
        }
    }

    private func queueValidURLs() {
        let validURLs = validationResults.filter { $0.valid }.map { $0.url }
        for url in validURLs {
            guard let videoId = url.youtubeVideoId else { continue }
            let alreadyAdded = appState.videosForChannel(channel.id).contains { $0.youtubeVideoId == videoId }
            if alreadyAdded { continue }
            let video = Video(
                channelId: channel.id,
                youtubeVideoId: videoId,
                title: "Video \(videoId)",
                downloadState: .queued,
                sortOrder: appState.videosForChannel(channel.id).count
            )
            appState.addVideo(video)
            Task { await appState.downloadService.enqueue(video: video, channel: channel) }
        }
        onDone()
    }

    // MARK: - Auto Retrieve

    private func startAutoRetrieve() {
        guard let channelId = channel.youtubeChannelId else { return }
        isAutoRetrieving = true
        autoRetrieveCount = 0
        autoRetrieveError = nil

        let channelURL = "https://www.youtube.com/channel/\(channelId)"
        let process = ChannelResolverService.fetchVideoURLs(
            channelURL: channelURL,
            onProgress: { count in
                Task { @MainActor in autoRetrieveCount = count }
            }
        ) { result in
            Task { @MainActor in
                isAutoRetrieving = false
                switch result {
                case .success(let urls):
                    for url in urls {
                        guard let videoId = url.youtubeVideoId else { continue }
                        let alreadyAdded = appState.videosForChannel(channel.id).contains { $0.youtubeVideoId == videoId }
                        if alreadyAdded { continue }
                        let video = Video(
                            channelId: channel.id,
                            youtubeVideoId: videoId,
                            title: "Video \(videoId)",
                            downloadState: .queued,
                            sortOrder: appState.videosForChannel(channel.id).count
                        )
                        appState.addVideo(video)
                        Task { await appState.downloadService.enqueue(video: video, channel: channel) }
                    }
                    onDone()
                case .failure(let err):
                    autoRetrieveError = err.localizedDescription
                }
            }
        }
        autoRetrieveProcess = process
    }
}
