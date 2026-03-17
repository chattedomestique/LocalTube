import SwiftUI

struct EditorChannelDetailView: View {
    let channelId: UUID
    @Environment(AppState.self) private var appState

    @State private var selectedTab: Tab = .videos
    @State private var editingVideoId: UUID?
    @State private var editingTitle = ""
    @State private var showDeleteVideoAlert = false
    @State private var videoToDelete: Video?
    @State private var isEditingChannelName = false
    @State private var editingChannelName = ""

    // Multi-select state
    @State private var isSelecting = false
    @State private var selectedVideoIds = Set<UUID>()
    @State private var showBulkDeleteAlert = false

    enum Tab: String, CaseIterable { case videos = "Videos", add = "Add Videos" }

    private var channel: Channel? { appState.channelById(channelId) }
    private var videos: [Video] { appState.videosForChannel(channelId) }
    private var failedVideos: [Video] { videos.filter { $0.downloadState == .error } }
    private var notDownloadedVideos: [Video] { videos.filter { $0.downloadState != .ready } }

    var body: some View {
        VStack(spacing: 0) {
            if let channel = channel {
                channelHeader(channel)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)

                Divider()

                // Tab picker — always visible so layout never shifts
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .onChange(of: selectedTab) { _, _ in
                    // Exit selection mode when switching tabs
                    isSelecting = false
                    selectedVideoIds.removeAll()
                }

                switch selectedTab {
                case .videos:
                    videosTab(channel)
                case .add:
                    AddVideosView(channel: channel, onDone: { selectedTab = .videos })
                }
            } else {
                emptyState
            }
        }
        .background(Color.ltBackground)
    }

    // MARK: - Channel Header

    private func channelHeader(_ channel: Channel) -> some View {
        HStack(spacing: 16) {
            if isEditingChannelName {
                HStack(spacing: 12) {
                    TextField("Channel Name", text: $editingChannelName)
                        .font(.ltTitle)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Color.ltText)

                    Button("Save") {
                        var updated = channel
                        updated.displayName = editingChannelName
                        appState.updateChannel(updated)
                        isEditingChannelName = false
                    }
                    .buttonStyle(LTButtonStyle())

                    Button("Cancel") { isEditingChannelName = false }
                        .buttonStyle(LTSecondaryButtonStyle())
                }
            } else {
                Text(channel.displayLabel)
                    .font(.ltTitle)
                    .foregroundStyle(Color.ltText)
                    .lineLimit(1)

                Button(action: {
                    editingChannelName = channel.displayName
                    isEditingChannelName = true
                }) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.ltAccent.opacity(0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit channel name")
            }

            Spacer()

            Text("\(videos.count) video\(videos.count == 1 ? "" : "s")")
                .font(.ltCaption)
                .foregroundStyle(Color.ltTextSecondary)
        }
    }

    // MARK: - Videos Tab

    @ViewBuilder
    private func videosTab(_ channel: Channel) -> some View {
        if videos.isEmpty {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "film.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.ltTextTertiary)
                Text("No videos yet")
                    .font(.ltHeadline)
                    .foregroundStyle(Color.ltTextSecondary)
                Button("Add Videos") { selectedTab = .add }
                    .buttonStyle(LTButtonStyle())
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 0) {
                // ── Selection toolbar — fixed height, always in layout ────────
                selectionToolbar
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Color.ltSurface.opacity(isSelecting ? 1 : 0))
                    .opacity(isSelecting ? 1 : 1)  // always in layout, never shifts

                Divider().opacity(isSelecting ? 1 : 0)

                // ── Video grid ───────────────────────────────────────────────
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: LT.gridSpacing) {
                        ForEach(videos) { video in
                            videoCardRow(video: video, channel: channel)
                        }
                        .onMove { source, dest in
                            appState.moveVideos(in: channelId, from: source, to: dest)
                        }
                    }
                    .padding(24)
                    // Extra bottom padding so the action bar doesn't cover last row
                    .padding(.bottom, isSelecting ? 80 : 0)
                }

                // ── Bottom action bar — fixed height, opacity-toggled ────────
                bottomActionBar(channel: channel)
                    .opacity(isSelecting ? 1 : 0)
                    .allowsHitTesting(isSelecting)
            }
        }
    }

    // MARK: - Selection Toolbar

    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            // Left: toggle select mode
            Button(isSelecting ? "Cancel" : "Select") {
                isSelecting.toggle()
                if !isSelecting { selectedVideoIds.removeAll() }
            }
            .buttonStyle(LTSecondaryButtonStyle())

            if isSelecting {
                Divider().frame(height: 20)

                // Quick-select buttons
                Button("All") {
                    selectedVideoIds = Set(videos.map(\.id))
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.ltAccent)

                Button("Not Downloaded") {
                    selectedVideoIds = Set(notDownloadedVideos.map(\.id))
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.ltAccent)

                if !failedVideos.isEmpty {
                    Button("Failed (\(failedVideos.count))") {
                        selectedVideoIds = Set(failedVideos.map(\.id))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ltDestructive)
                }

                Button("None") {
                    selectedVideoIds.removeAll()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.ltTextSecondary)
            }

            Spacer()

            // Right: quick "Retry All Failed" outside selection mode
            if !isSelecting && !failedVideos.isEmpty {
                Button("Retry All Failed (\(failedVideos.count))") {
                    retryVideos(failedVideos, channel: appState.channelById(channelId))
                }
                .buttonStyle(LTSecondaryButtonStyle())
            }

            if isSelecting {
                Text("\(selectedVideoIds.count) selected")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.ltTextSecondary)
            }
        }
    }

    // MARK: - Bottom Action Bar

    private func bottomActionBar(channel: Channel) -> some View {
        HStack(spacing: 16) {
            Spacer()

            // Retry selected (only shows if any selected have errors)
            let retryable = videos.filter { selectedVideoIds.contains($0.id) && $0.downloadState == .error }
            if !retryable.isEmpty {
                Button("Retry \(retryable.count) Failed") {
                    retryVideos(retryable, channel: channel)
                    isSelecting = false
                    selectedVideoIds.removeAll()
                }
                .buttonStyle(LTSecondaryButtonStyle())
            }

            // Re-download selected (not yet downloaded)
            let redownloadable = videos.filter { selectedVideoIds.contains($0.id) && $0.downloadState != .ready && $0.downloadState != .downloading }
            if !redownloadable.isEmpty && retryable.isEmpty {
                Button("Download \(redownloadable.count)") {
                    retryVideos(redownloadable, channel: channel)
                    isSelecting = false
                    selectedVideoIds.removeAll()
                }
                .buttonStyle(LTSecondaryButtonStyle())
            }

            // Delete selected
            if !selectedVideoIds.isEmpty {
                Button("Delete \(selectedVideoIds.count)") {
                    showBulkDeleteAlert = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.ltDestructive)
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 24)
        .background(.ultraThinMaterial)
        .alert("Delete \(selectedVideoIds.count) Video\(selectedVideoIds.count == 1 ? "" : "s")?",
               isPresented: $showBulkDeleteAlert) {
            Button("Delete", role: .destructive) {
                let ids = selectedVideoIds
                for id in ids { appState.removeVideo(id: id) }
                selectedVideoIds.removeAll()
                isSelecting = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Selected videos will be removed from this channel. Downloaded files on disk are not deleted.")
        }
    }

    // MARK: - Individual Video Card Row

    private let gridColumns = [
        GridItem(.adaptive(minimum: 240, maximum: 300), spacing: LT.gridSpacing)
    ]

    private func videoCardRow(video: Video, channel: Channel) -> some View {
        VStack(spacing: 8) {
            VideoCard(
                video: video,
                isEditing: true,
                isSelected: selectedVideoIds.contains(video.id),
                onTap: isSelecting ? { toggleSelection(video.id) } : nil,
                onDelete: isSelecting ? nil : {
                    videoToDelete = video
                    showDeleteVideoAlert = true
                },
                onRetry: isSelecting ? nil : {
                    Task { await appState.downloadService.retryDownload(video: video, channel: channel) }
                }
            )
            .onTapGesture {
                if isSelecting { toggleSelection(video.id) }
            }

            // Inline title editing — only when not selecting
            if !isSelecting {
                if editingVideoId == video.id {
                    HStack(spacing: 8) {
                        TextField("Title", text: $editingTitle)
                            .font(.system(size: 14, design: .rounded))
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.ltSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button("Save") {
                            var updated = video
                            updated.title = editingTitle
                            appState.updateVideo(updated)
                            Task { try? await DatabaseService.shared.updateVideo(updated) }
                            editingVideoId = nil
                        }
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.ltAccent)
                        .buttonStyle(.plain)
                    }
                } else {
                    Button(action: {
                        editingVideoId = video.id
                        editingTitle = video.title
                    }) {
                        Text(video.title)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Color.ltTextSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                }
            }
        }
        .alert("Remove Video?", isPresented: $showDeleteVideoAlert, presenting: videoToDelete) { v in
            Button("Remove", role: .destructive) { appState.removeVideo(id: v.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This video will be removed from this channel. The downloaded file will remain on disk.")
        }
    }

    // MARK: - Helpers

    private func toggleSelection(_ id: UUID) {
        if selectedVideoIds.contains(id) {
            selectedVideoIds.remove(id)
        } else {
            selectedVideoIds.insert(id)
        }
    }

    private func retryVideos(_ videos: [Video], channel: Channel?) {
        guard let channel = channel else { return }
        for video in videos {
            Task { await appState.downloadService.retryDownload(video: video, channel: channel) }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sidebar.right")
                .font(.system(size: 64))
                .foregroundStyle(Color.ltTextTertiary)
            Text("Select a channel")
                .font(.ltHeadline)
                .foregroundStyle(Color.ltTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
