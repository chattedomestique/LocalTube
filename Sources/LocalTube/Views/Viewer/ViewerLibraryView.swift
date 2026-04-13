import SwiftUI

struct ViewerLibraryView: View {
    @Environment(AppState.self) private var appState

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 340), spacing: LT.gridSpacing)
    ]

    var body: some View {
        ZStack {
            Color.ltBackground.ignoresSafeArea()

            if appState.channels.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
                        HStack {
                            Text("LocalTube")
                                .font(.ltHero)
                                .foregroundStyle(Color.ltText)
                            Spacer()
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 48)
                        .padding(.bottom, 32)

                        // Channel grid
                        LazyVGrid(columns: columns, spacing: LT.gridSpacing) {
                            ForEach(appState.channels) { channel in
                                // ChannelCard already contains a Button — don't double-wrap
                                // in NavigationLink. Drive navigation by appending to the path.
                                ChannelCard(
                                    channel: channel,
                                    videoCount: appState.videosForChannel(channel.id).count,
                                    thumbnailPath: appState.firstThumbnail(for: channel),
                                    onTap: {
                                        appState.viewerPath.append(ViewerDestination.channel(channel.id))
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 48)
                    }
                }
            }

            // Hidden editor mode trigger — triple-tap bottom-right corner
            editorAccessTrigger
        }
        .navigationTitle("")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 100))
                .foregroundStyle(Color.ltTextTertiary)

            Text("No Videos Yet")
                .font(.ltHero)
                .foregroundStyle(Color.ltText)

            Text("Ask a grown-up to add some channels!")
                .font(.ltBody)
                .foregroundStyle(Color.ltTextSecondary)
        }
    }

    // MARK: - Hidden Editor Trigger

    private var editorAccessTrigger: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                // Invisible 96×96pt tap target in the bottom-right corner
                Color.clear
                    .frame(width: LT.minTargetSize, height: LT.minTargetSize)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 3) {
                        appState.requestEditorMode()
                    }
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }
}
