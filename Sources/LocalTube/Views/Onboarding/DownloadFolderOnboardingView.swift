import SwiftUI
import AppKit

/// Full-screen blocking view shown when no download folder has been configured.
struct DownloadFolderOnboardingView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Color.ltBackground.ignoresSafeArea()

            VStack(spacing: 48) {
                // Illustration
                Image(systemName: "folder.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(Color.ltAccent)
                    .shadow(color: Color.ltAccent.opacity(0.4), radius: 20)

                // Copy
                VStack(spacing: 16) {
                    Text("Choose a Video Folder")
                        .font(.ltHero)
                        .foregroundStyle(Color.ltText)
                        .multilineTextAlignment(.center)

                    Text("Pick where LocalTube should save downloaded videos.\nThis folder will hold all your channels and videos.")
                        .font(.ltBody)
                        .foregroundStyle(Color.ltTextSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 600)
                }

                // Action
                Button("Choose Folder") {
                    pickFolder()
                }
                .buttonStyle(LTButtonStyle())
                .accessibilityLabel("Choose download folder")
            }
            .padding(80)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.message = "Select where LocalTube will save your videos"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var settings = appState.settings
        settings.downloadFolderPath = url.path
        appState.settings = settings
        SettingsService.save(settings)
        appState.isOnboarding = false
        AppLogger.info("Download folder set: \(url.path)")
    }
}
