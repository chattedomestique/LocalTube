import SwiftUI

struct ViewerChannelView: View {
    let channelId: UUID
    @Environment(AppState.self) private var appState

    // Persisted across sessions — survives app restart
    @AppStorage("viewerGridScale") private var gridScale: Double = 1.0

    private let baseCardWidth: CGFloat = 260

    private var gridColumns: [GridItem] {
        let min = baseCardWidth * gridScale
        // max = 2× min keeps the grid from ever showing a single sprawling card
        return [GridItem(.adaptive(minimum: min, maximum: min * 2), spacing: LT.gridSpacing)]
    }

    private var channel: Channel? { appState.channelById(channelId) }
    private var videos: [Video] {
        appState.videosForChannel(channelId).filter { $0.downloadState == .ready }
    }

    var body: some View {
        ZStack {
            Color.ltBackground.ignoresSafeArea()

            if let channel = channel {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Header ───────────────────────────────────────────────
                    HStack(alignment: .center, spacing: 20) {
                        // Channel name with back context
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.displayLabel)
                                .font(.ltHero)
                                .foregroundStyle(Color.ltText)
                                .lineLimit(1)
                            Text("\(videos.count) video\(videos.count == 1 ? "" : "s")")
                                .font(.ltCaption)
                                .foregroundStyle(Color.ltTextSecondary)
                        }

                        Spacer()

                        // Tile-size slider — opacity-hidden when no videos (stable layout)
                        tileScaleControl
                            .opacity(videos.isEmpty ? 0 : 1)
                            .allowsHitTesting(!videos.isEmpty)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 36)
                    .padding(.bottom, 24)

                    if videos.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVGrid(columns: gridColumns, spacing: LT.gridSpacing) {
                                ForEach(videos) { video in
                                    VideoCard(
                                        video: video,
                                        scale: gridScale,
                                        onTap: {
                                            appState.viewerPath.append(
                                                ViewerDestination.player(video.id)
                                            )
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 40)
                            .padding(.top, 8)
                            .padding(.bottom, 48)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                backButton
            }
        }
    }

    // MARK: - Tile Scale Control

    private var tileScaleControl: some View {
        HStack(spacing: 10) {
            // Smaller-grid icon — step down
            Button {
                gridScale = max(0.6, (gridScale - 0.1).ltRounded)
            } label: {
                Image(systemName: "rectangle.grid.3x2")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.ltTextSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Smaller tiles")

            Slider(value: $gridScale, in: 0.6...2.2, step: 0.05)
                .tint(Color.ltAccent)
                .frame(width: 140)
                .accessibilityLabel("Tile size")

            // Larger-grid icon — step up
            Button {
                gridScale = min(2.2, (gridScale + 0.1).ltRounded)
            } label: {
                Image(systemName: "rectangle.grid.1x2")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.ltTextSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Larger tiles")
        }
    }

    // MARK: - Back Button

    private var backButton: some View {
        Button(action: {
            if !appState.viewerPath.isEmpty {
                appState.viewerPath.removeLast()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                Text("Back")
                    .font(.ltHeadline)
            }
            .foregroundStyle(Color.ltAccent)
        }
        .buttonStyle(.plain)
        .frame(minWidth: LT.minTargetSize, minHeight: LT.minTargetSize)
        .accessibilityLabel("Back to library")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "film.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.ltTextTertiary)

            Text("No videos ready yet")
                .font(.ltHero)
                .foregroundStyle(Color.ltText)

            Text("Videos are still downloading. Check back soon!")
                .font(.ltBody)
                .foregroundStyle(Color.ltTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Rounding helper (one decimal place)

private extension Double {
    var ltRounded: Double { (self * 10).rounded() / 10 }
}
