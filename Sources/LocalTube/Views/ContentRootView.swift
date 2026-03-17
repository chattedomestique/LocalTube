import SwiftUI

/// Root view that gates the entire UI based on app state.
struct ContentRootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isOnboarding {
                // Gate 1: Must choose download folder
                DownloadFolderOnboardingView()

            } else if !appState.dependencyStatus.allSatisfied {
                // Gate 2: Missing tools (yt-dlp, ffmpeg, python3)
                DependencyCheckView()

            } else if appState.needsPINSetup {
                // Gate 3: First-run PIN setup
                PINSetupView {
                    appState.needsPINSetup = false
                }

            } else {
                // Main app
                switch appState.appMode {
                case .viewer:
                    ViewerRootView()
                case .editor:
                    EditorRootView()
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .preferredColorScheme(.dark)
    }
}
