import SwiftUI

/// Root container for Viewer Mode. Full-screen NavigationStack.
struct ViewerRootView: View {
    @Environment(AppState.self) private var appState
    @State private var playerState = PlayerState()

    var body: some View {
        @Bindable var state = appState

        ZStack {
            NavigationStack(path: $state.viewerPath) {
                ViewerLibraryView()
                    .navigationDestination(for: ViewerDestination.self) { destination in
                        switch destination {
                        case .channel(let id):
                            ViewerChannelView(channelId: id)
                        case .player(let videoId):
                            VideoPlayerView(videoId: videoId)
                        }
                    }
            }
            .environment(playerState)

            // PIN entry overlay — always in hierarchy so the NavigationStack never
            // shifts; opacity + allowsHitTesting control visibility and interaction.
            PINEntryOverlay(onCancel: { appState.showPINEntry = false })
                .opacity(appState.showPINEntry ? 1 : 0)
                .allowsHitTesting(appState.showPINEntry)
                .animation(.easeInOut(duration: 0.2), value: appState.showPINEntry)
        }
        .onAppear {
            // Wire appState into the existing PlayerState rather than creating a new
            // instance — recreating would orphan the already-configured AVPlayer.
            playerState.appState = appState
        }
    }
}
