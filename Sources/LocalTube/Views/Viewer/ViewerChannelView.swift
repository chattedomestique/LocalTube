import SwiftUI

struct ViewerChannelView: View {
    let channelId: UUID
    @Environment(AppState.self) private var appState

    // Persisted across sessions — survives app restart
    @AppStorage("viewerGridScale") private var gridScale: Double = 1.0

    @State private var searchQuery: String = ""

    private let baseCardWidth: CGFloat = 260

    private var gridColumns: [GridItem] {
        let min = baseCardWidth * gridScale
        // max = 2× min keeps the grid from ever showing a single sprawling card
        return [GridItem(.adaptive(minimum: min, maximum: min * 2), spacing: LT.gridSpacing)]
    }

    private var channel: Channel? { appState.channelById(channelId) }

    private var allVideos: [Video] {
        appState.videosForChannel(channelId).filter { $0.downloadState == .ready }
    }

    private var filteredVideos: [Video] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return allVideos }
        return allVideos.filter { $0.title.localizedCaseInsensitiveContains(q) }
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
                            Text("\(allVideos.count) video\(allVideos.count == 1 ? "" : "s")")
                                .font(.ltCaption)
                                .foregroundStyle(Color.ltTextSecondary)
                        }

                        Spacer()

                        // Search bar — hidden when no videos (stable layout)
                        if !allVideos.isEmpty {
                            searchBar
                        }

                        // Tile-size slider — opacity-hidden when no videos (stable layout)
                        tileScaleControl
                            .opacity(allVideos.isEmpty ? 0 : 1)
                            .allowsHitTesting(!allVideos.isEmpty)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 36)
                    .padding(.bottom, 24)

                    if allVideos.isEmpty {
                        emptyState
                    } else if filteredVideos.isEmpty {
                        noResultsState
                    } else {
                        ScrollView {
                            LazyVGrid(columns: gridColumns, spacing: LT.gridSpacing) {
                                ForEach(filteredVideos) { video in
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

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(searchQuery.isEmpty ? Color.ltTextTertiary : Color.ltAccent)

            TextField("Search videos…", text: $searchQuery)
                .font(.ltHeadline)
                .foregroundStyle(Color.ltText)
                .textFieldStyle(.plain)
                .frame(minWidth: 200, maxWidth: 360)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.ltTextTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: LT.buttonCornerRadius)
                .fill(Color.ltSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: LT.buttonCornerRadius)
                        .strokeBorder(
                            searchQuery.isEmpty ? Color.clear : Color.ltAccent.opacity(0.6),
                            lineWidth: 2
                        )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: searchQuery.isEmpty)
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

    // MARK: - Empty States

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

    private var noResultsState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 80))
                .foregroundStyle(Color.ltTextTertiary)

            Text("No videos found")
                .font(.ltHero)
                .foregroundStyle(Color.ltText)

            Text("Nothing matches \"\(searchQuery)\"")
                .font(.ltBody)
                .foregroundStyle(Color.ltTextSecondary)

            Button {
                searchQuery = ""
            } label: {
                Text("Clear Search")
            }
            .buttonStyle(LTSecondaryButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Rounding helper (one decimal place)

private extension Double {
    var ltRounded: Double { (self * 10).rounded() / 10 }
}
