import SwiftUI
import AppKit

struct SettingsView: View {
    private enum Tab: String, CaseIterable {
        case general = "General"
        case security = "Security"
        case storage = "Storage"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .security: return "lock.shield"
            case .storage: return "externaldrive"
            }
        }
    }

    var body: some View {
        TabView {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabContent(tab)
                    .tabItem {
                        Label(tab.rawValue, systemImage: tab.icon)
                    }
            }
        }
        .frame(width: 520, height: 440)
    }

    @ViewBuilder
    private func tabContent(_ tab: Tab) -> some View {
        switch tab {
        case .general: GeneralSettingsView()
        case .security: SecuritySettingsView()
        case .storage: StorageSettingsView()
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isCheckingDeps = false

    var body: some View {
        @Bindable var state = appState

        Form {
            // Download folder
            Section("Download Folder") {
                LabeledContent("Location") {
                    HStack {
                        Text(appState.settings.downloadFolderPath ?? "Not set")
                            .foregroundStyle(appState.settings.downloadFolderPath != nil
                                ? .primary : Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Change…") { changeFolder() }
                    }
                }
            }

            // Auto-lock
            Section("Editor Mode") {
                LabeledContent("Auto-lock after") {
                    HStack {
                        Stepper(
                            "\(appState.settings.editorAutoLockMinutes) minutes",
                            value: Binding(
                                get: { appState.settings.editorAutoLockMinutes },
                                set: { val in
                                    var s = appState.settings
                                    s.editorAutoLockMinutes = max(1, min(60, val))
                                    appState.settings = s
                                    SettingsService.save(s)
                                }
                            ),
                            in: 1...60
                        )
                    }
                }
            }

            // Dependencies
            Section("Tools") {
                LabeledContent("python3") {
                    statusBadge(appState.dependencyStatus.python3)
                }
                LabeledContent("yt-dlp") {
                    statusBadge(appState.dependencyStatus.ytDlp)
                }
                LabeledContent("ffmpeg") {
                    statusBadge(appState.dependencyStatus.ffmpeg)
                }
                Button(isCheckingDeps ? "Checking…" : "Check for Updates") {
                    checkDeps()
                }
                .disabled(isCheckingDeps)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func statusBadge(_ ok: Bool) -> some View {
        Label(ok ? "Installed" : "Missing", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(ok ? Color.ltSuccess : Color.ltDestructive)
            .font(.system(size: 13))
    }

    private func changeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var s = appState.settings
        s.downloadFolderPath = url.path
        appState.settings = s
        SettingsService.save(s)
    }

    private func checkDeps() {
        isCheckingDeps = true
        Task {
            await appState.dependencyService.checkAll()
            appState.dependencyStatus = appState.dependencyService.status
            await MainActor.run { isCheckingDeps = false }
        }
    }
}

// MARK: - Security Settings

struct SecuritySettingsView: View {
    @State private var showPINSetup = false
    @State private var showRecoveryPhrase = false
    @State private var verifyPINForPhrase = false
    @State private var pinEntry = ""
    @State private var revealedPhrase: String?
    @State private var pinError = false

    var body: some View {
        Form {
            Section("PIN") {
                Button("Change PIN…") { showPINSetup = true }
            }

            Section("Recovery Phrase") {
                if let phrase = revealedPhrase {
                    LabeledContent("Your phrase") {
                        Text(phrase)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Button("Hide") { revealedPhrase = nil }
                } else {
                    Button("View Recovery Phrase…") {
                        verifyPINForPhrase = true
                        pinEntry = ""
                        pinError = false
                    }
                }

                if pinError {
                    Text("Incorrect PIN")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showPINSetup) {
            PINSetupView(isReset: true)
        }
        .sheet(isPresented: $verifyPINForPhrase) {
            pinVerifyForPhraseSheet
        }
    }

    private var pinVerifyForPhraseSheet: some View {
        VStack(spacing: 24) {
            Text("Enter PIN to reveal recovery phrase")
                .font(.headline)
            NumpadView(digits: $pinEntry, maxDigits: 6) { entered in
                if PINService.verify(entered) {
                    revealedPhrase = PINService.loadRecoveryPhrase()
                    verifyPINForPhrase = false
                } else {
                    pinError = true
                    pinEntry = ""
                }
            }
            Button("Cancel") { verifyPINForPhrase = false }
                .buttonStyle(.bordered)
        }
        .padding(32)
    }
}

// MARK: - Storage Settings

struct StorageSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var totalSize: String = "…"
    @State private var channelSizes: [(name: String, size: String)] = []

    var body: some View {
        Form {
            Section("Download Folder") {
                if let path = appState.settings.downloadFolderPath {
                    LabeledContent("Path") {
                        Text(path).lineLimit(2).truncationMode(.middle)
                    }
                    LabeledContent("Total Size") { Text(totalSize) }

                    Button("Open in Finder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }

                    Button("Change Folder…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.canCreateDirectories = true
                        panel.prompt = "Choose"
                        guard panel.runModal() == .OK, let url = panel.url else { return }
                        var s = appState.settings
                        s.downloadFolderPath = url.path
                        appState.settings = s
                        SettingsService.save(s)
                    }
                } else {
                    Text("No folder selected").foregroundStyle(.secondary)
                }
            }

            if !channelSizes.isEmpty {
                Section("By Channel") {
                    ForEach(channelSizes, id: \.name) { item in
                        LabeledContent(item.name) { Text(item.size) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await computeSizes() }
    }

    private func computeSizes() async {
        guard let root = appState.settings.downloadFolderPath else { return }
        let fm = FileManager.default
        var total: Int64 = 0
        var sizes: [(String, String)] = []

        for channel in appState.channels {
            let channelDir = URL(fileURLWithPath: root).appendingPathComponent(channel.folderName)
            let size = directorySize(url: channelDir, fm: fm)
            total += size
            sizes.append((channel.displayName, formatBytes(size)))
        }
        await MainActor.run {
            totalSize = formatBytes(total)
            channelSizes = sizes
        }
    }

    private func directorySize(url: URL, fm: FileManager) -> Int64 {
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
