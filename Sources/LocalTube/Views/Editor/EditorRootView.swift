import SwiftUI

struct EditorRootView: View {
    @Environment(AppState.self) private var appState
    @State private var showNewChannel = false
    @State private var showDownloadQueue = false
    @State private var showDeleteChannelAlert = false
    @State private var channelToDelete: Channel?

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            sidebarContent
                .navigationTitle("Library")
                .toolbar { sidebarToolbar }
        } detail: {
            if let selectedId = appState.editorSelectedChannelId {
                EditorChannelDetailView(channelId: selectedId)
            } else {
                emptyDetail
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar { mainToolbar }
        .inspector(isPresented: $showDownloadQueue) {
            DownloadQueuePanel(isPresented: $showDownloadQueue)
                .inspectorColumnWidth(min: 300, ideal: 380, max: 480)
        }
        .sheet(isPresented: $showNewChannel) {
            NewChannelFlow()
                .environment(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChannelRequested)) { _ in
            showNewChannel = true
        }
        .onTapGesture { appState.resetEditorLockTimer() }
        .alert("Delete Channel?", isPresented: $showDeleteChannelAlert, presenting: channelToDelete) { ch in
            Button("Delete", role: .destructive) { appState.removeChannel(id: ch.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This channel and all its entries will be removed. Downloaded video files on disk are not deleted.")
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Channel list
            List(selection: Binding(
                get: { appState.editorSelectedChannelId },
                set: {
                    appState.editorSelectedChannelId = $0
                    appState.resetEditorLockTimer()
                }
            )) {
                if appState.channels.isEmpty {
                    // Empty sidebar guidance
                    VStack(spacing: 10) {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.ltTextTertiary)
                        Text("No channels yet")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.ltTextSecondary)
                        Text("Tap the button below to create one")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Color.ltTextTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(appState.channels) { channel in
                        editorChannelRow(channel)
                            .tag(channel.id)
                    }
                    .onMove { source, dest in appState.moveChannels(from: source, to: dest) }
                }
            }
            .listStyle(.sidebar)

            // ─── Permanent, prominent "New Channel" footer ───────────────
            Divider()
            Button(action: { showNewChannel = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("New Channel")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Color.ltAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .background(Color(NSColor.windowBackgroundColor))
            .accessibilityLabel("Create new channel")
        }
    }

    private func editorChannelRow(_ channel: Channel) -> some View {
        HStack(spacing: 12) {
            if let thumb = appState.firstThumbnail(for: channel),
               let img = NSImage(contentsOfFile: thumb) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.ltSurface)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(channel.emoji ?? "▶")
                            .font(.system(size: channel.emoji != nil ? 22 : 14))
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(channel.displayLabel)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ltText)
                    .lineLimit(1)
                let count = appState.videosForChannel(channel.id).count
                let ready = appState.videosForChannel(channel.id).filter { $0.downloadState == .ready }.count
                Text(count == 0 ? "No videos" : "\(ready)/\(count) ready")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(ready == count && count > 0 ? Color.ltSuccess : Color.ltTextSecondary)
            }
        }
        .contextMenu {
            Button("Delete Channel", role: .destructive) {
                channelToDelete = channel
                showDeleteChannelAlert = true
            }
        }
    }

    // MARK: - Toolbars

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        // Intentionally empty — New Channel lives in the sidebar footer
        ToolbarItem(placement: .automatic) { EmptyView() }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            AutoLockTimerView()
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: { showDownloadQueue.toggle() }) {
                Label("Downloads", systemImage: "arrow.down.circle\(appState.pendingDownloadCount > 0 ? ".fill" : "")")
            }
            .overlay(alignment: .topTrailing) {
                if appState.pendingDownloadCount > 0 {
                    Text("\(appState.pendingDownloadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.ltDestructive)
                        .clipShape(Circle())
                        .offset(x: 6, y: -6)
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Exit Editor") { appState.exitEditorMode() }
                .buttonStyle(LTEditorSecondaryButtonStyle())
        }
    }

    // MARK: - Empty Detail

    private var emptyDetail: some View {
        VStack(spacing: 20) {
            if appState.channels.isEmpty {
                // No channels at all — give them a clear call to action
                Spacer()
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.ltAccent.opacity(0.85))

                VStack(spacing: 8) {
                    Text("Start Building Your Library")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ltText)
                    Text("Create a channel to add and download videos for kids to watch offline.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color.ltTextSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }

                Button(action: { showNewChannel = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text("Create First Channel")
                    }
                }
                .buttonStyle(LTEditorButtonStyle())
                Spacer()
            } else {
                // Channels exist, none selected
                Spacer()
                Image(systemName: "sidebar.left")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.ltTextTertiary)
                Text("Select a channel from the sidebar")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ltTextSecondary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ltBackground)
    }
}
