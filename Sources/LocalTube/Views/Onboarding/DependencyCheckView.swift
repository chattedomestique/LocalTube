import SwiftUI

/// Full-screen blocking overlay shown when required tools are missing.
struct DependencyCheckView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Color.ltBackground.ignoresSafeArea()

            if appState.dependencyService.isInstalling {
                installProgressView
            } else {
                missingDepsView
            }
        }
    }

    // MARK: - Missing Deps View

    private var missingDepsView: some View {
        VStack(spacing: 48) {
            // Illustration
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 100))
                .foregroundStyle(Color.ltAccent)

            // Copy
            VStack(spacing: 16) {
                Text("A Few Helpers Needed")
                    .font(.ltHero)
                    .foregroundStyle(Color.ltText)

                Text("LocalTube needs these tools to download videos:")
                    .font(.ltBody)
                    .foregroundStyle(Color.ltTextSecondary)
            }

            // Missing tool list
            VStack(alignment: .leading, spacing: 16) {
                ForEach(missingToolInfo, id: \.name) { tool in
                    HStack(spacing: 16) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: LT.sfSymbolSize * 0.75))
                            .foregroundStyle(Color.ltDestructive)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tool.name)
                                .font(.ltHeadline)
                                .foregroundStyle(Color.ltText)
                            Text(tool.description)
                                .font(.ltCaption)
                                .foregroundStyle(Color.ltTextSecondary)
                        }
                    }
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: LT.cardCornerRadius)
                    .fill(Color.ltSurface)
            )
            .frame(maxWidth: 500)

            Button("Install Now") {
                Task { await appState.dependencyService.installMissing() }
            }
            .buttonStyle(LTButtonStyle())
            .accessibilityLabel("Install missing dependencies")
        }
        .padding(80)
    }

    // MARK: - Install Progress View

    private var installProgressView: some View {
        VStack(spacing: 36) {
            LTSpinner()

            Text("Installing…")
                .font(.ltHero)
                .foregroundStyle(Color.ltText)

            // Always present; opacity controls visibility so the spinner never shifts
            VStack(spacing: 16) {
                Text("Something went wrong:")
                    .font(.ltBody)
                    .foregroundStyle(Color.ltDestructive)
                Text(appState.dependencyService.installError ?? " ")
                    .font(.ltCaption)
                    .foregroundStyle(Color.ltTextSecondary)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    Task { await appState.dependencyService.installMissing() }
                }
                .buttonStyle(LTButtonStyle())
            }
            .opacity(appState.dependencyService.installError != nil ? 1 : 0)
            .allowsHitTesting(appState.dependencyService.installError != nil)

            // Live log
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(appState.dependencyService.installLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(Color.ltTextSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line)
                        }
                    }
                    .padding(16)
                }
                .frame(maxWidth: 600, maxHeight: 200)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.ltSurface)
                )
                .onChange(of: appState.dependencyService.installLog.count) { _, _ in
                    if let last = appState.dependencyService.installLog.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
        .padding(80)
        .onChange(of: appState.dependencyService.isInstalling) { _, installing in
            if !installing && appState.dependencyService.status.allSatisfied {
                appState.dependencyStatus = appState.dependencyService.status
            }
        }
    }

    // MARK: - Helpers

    private var missingToolInfo: [(name: String, description: String)] {
        let status = appState.dependencyStatus
        var tools: [(String, String)] = []
        if !status.python3 { tools.append(("Python 3", "Required by yt-dlp")) }
        if !status.ytDlp { tools.append(("yt-dlp", "Downloads videos from YouTube")) }
        if !status.ffmpeg { tools.append(("ffmpeg", "Merges audio/video and extracts thumbnails")) }
        return tools
    }
}
