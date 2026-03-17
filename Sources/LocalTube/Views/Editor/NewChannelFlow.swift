import SwiftUI

struct NewChannelFlow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .typeSelection
    @State private var channelType: ChannelType = .custom

    // Type A fields
    @State private var youtubeURL = ""
    @State private var isResolving = false
    @State private var resolvedChannel: ResolvedChannel?
    @State private var resolveError: String?

    // Type B fields
    @State private var channelName = ""
    @State private var selectedEmoji = ""

    enum Step: Int, CaseIterable {
        case typeSelection = 0
        case typeASetup    = 1
        case typeBSetup    = 3   // unique raw value; stepIndex returns 1 for visual parity
        case acquireMethod = 2

        /// Visual step index for the progress indicator (0-based).
        var stepIndex: Int {
            switch self {
            case .typeSelection: return 0
            case .typeASetup:    return 1
            case .typeBSetup:    return 1
            case .acquireMethod: return 2
            }
        }
    }

    /// Total number of visible progress steps for the current path.
    private var totalSteps: Int {
        switch step {
        case .typeSelection: return 3
        case .typeBSetup:    return 2
        default:             return 3
        }
    }

    var body: some View {
        ZStack {
            Color.ltBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ──────────────────────────────────────────────
                header
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                // ── Step progress dots ───────────────────────────────────
                LTStepIndicator(totalSteps: totalSteps, currentStep: step.stepIndex)
                    .padding(.bottom, 28)

                // ── Step content ─────────────────────────────────────────
                ScrollView {
                    VStack(spacing: 0) {
                        switch step {
                        case .typeSelection: typeSelectionStep
                        case .typeASetup:    typeAStep
                        case .typeBSetup:    typeBStep
                        case .acquireMethod: acquireMethodStep
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 520)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Channel")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ltText)
                Text(stepSubtitle)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.ltTextSecondary)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.ltTextTertiary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel("Close")
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .typeSelection: return "Choose a channel type"
        case .typeASetup:    return "Enter the YouTube channel URL"
        case .typeBSetup:    return "Name your custom collection"
        case .acquireMethod: return "How would you like to add videos?"
        }
    }

    // MARK: - Step 1: Type Selection

    private var typeSelectionStep: some View {
        HStack(spacing: 20) {
            typeCard(
                icon: "tv.fill",
                title: "Mirror a YouTube Channel",
                subtitle: "Link a real YouTube channel and sync all its videos",
                accent: Color.ltAccent,
                action: { channelType = .source; step = .typeASetup }
            )

            typeCard(
                icon: "rectangle.stack.fill",
                title: "Build a Custom Mix",
                subtitle: "Curate videos from any source into your own collection",
                accent: Color.ltBlue,
                action: { channelType = .custom; step = .typeBSetup }
            )
        }
        .padding(.top, 8)
    }

    private func typeCard(
        icon: String,
        title: String,
        subtitle: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(accent)

                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ltText)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.ltTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                HStack {
                    Text("Select")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 240)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.ltSurface)
                    .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.clear, lineWidth: 0)
            )
        }
        .buttonStyle(.plain)
        .buttonHoverEffect()
    }

    // MARK: - Step 2A: YouTube Channel URL

    private var typeAStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            // URL input
            VStack(alignment: .leading, spacing: 8) {
                Label("YouTube Channel URL", systemImage: "link")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ltTextSecondary)

                TextField("https://youtube.com/@ChannelName", text: $youtubeURL)
                    .font(.system(size: 15, design: .rounded))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .ltField()
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                    .onSubmit { if !youtubeURL.isEmpty && resolvedChannel == nil { resolveChannel() } }

                // Error — always in layout, opacity-toggled so nothing shifts
                Text(resolveError ?? "")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.ltDestructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 16)
                    .opacity(resolveError != nil ? 1 : 0)
            }

            // Resolved channel confirmation card — reserved height to prevent shift
            resolvedChannelArea

            // Action buttons
            HStack(spacing: 12) {
                Button("← Back") { step = .typeSelection }
                    .buttonStyle(LTEditorSecondaryButtonStyle())

                // Verify button — visible only when not yet resolved
                Button(action: resolveChannel) {
                    HStack(spacing: 6) {
                        if isResolving {
                            ProgressView().controlSize(.mini).tint(.black)
                        }
                        Text(isResolving ? "Verifying…" : "Verify Channel")
                    }
                }
                .buttonStyle(LTEditorButtonStyle())
                .disabled(youtubeURL.isEmpty || isResolving || resolvedChannel != nil)
                .opacity(resolvedChannel == nil ? 1 : 0)
                .allowsHitTesting(resolvedChannel == nil)

                // Continue button — visible only when resolved
                Button("Continue →") { step = .acquireMethod }
                    .buttonStyle(LTEditorButtonStyle(color: Color.ltSuccess))
                    .opacity(resolvedChannel != nil ? 1 : 0)
                    .allowsHitTesting(resolvedChannel != nil)
            }
        }
        .padding(.top, 8)
    }

    /// Always-present channel confirmation area — uses opacity to prevent layout shift.
    private var resolvedChannelArea: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.ltSuccess)

            VStack(alignment: .leading, spacing: 4) {
                Text(resolvedChannel?.displayName ?? "Channel verified")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ltText)
                Text(resolvedChannel?.channelId ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.ltTextSecondary)
            }

            Spacer()

            // Re-verify button
            Button("Change") {
                resolvedChannel = nil
                resolveError = nil
                youtubeURL = ""
            }
            .buttonStyle(LTEditorSecondaryButtonStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.ltSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.ltSuccess.opacity(0.6), lineWidth: 1.5)
                )
        )
        .opacity(resolvedChannel != nil ? 1 : 0)
        .allowsHitTesting(resolvedChannel != nil)
        // Reserve the space even when hidden so nothing shifts
        .frame(height: 70)
    }

    private func resolveChannel() {
        guard !youtubeURL.isEmpty else { return }
        isResolving = true
        resolveError = nil
        resolvedChannel = nil
        Task {
            do {
                let resolved = try await ChannelResolverService.resolve(youtubeURL: youtubeURL)
                await MainActor.run {
                    resolvedChannel = resolved
                    isResolving = false
                }
            } catch {
                await MainActor.run {
                    resolveError = error.localizedDescription
                    isResolving = false
                }
            }
        }
    }

    // MARK: - Step 2B: Custom Channel

    private let emojiOptions = ["🎵", "🌿", "🚂", "🦁", "🚀", "🎨", "🏖️", "⭐️", "🦋", "🌈",
                                 "🐳", "🎃", "🎄", "🌙", "🦊", "🐻", "🍎", "🎯", "🎡", "🎮"]

    private var typeBStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Name input
            VStack(alignment: .leading, spacing: 8) {
                Label("Channel Name", systemImage: "character.cursor.ibeam")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ltTextSecondary)

                TextField("e.g. Nature Videos, Bedtime Stories…", text: $channelName)
                    .font(.system(size: 15, design: .rounded))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .ltField()
            }

            // Emoji picker
            VStack(alignment: .leading, spacing: 10) {
                Text("Pick an icon (optional)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ltTextSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 50, maximum: 58))], spacing: 10) {
                    ForEach(emojiOptions, id: \.self) { emoji in
                        Button(emoji) { selectedEmoji = (selectedEmoji == emoji) ? "" : emoji }
                            .font(.system(size: 28))
                            .frame(width: 52, height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedEmoji == emoji
                                          ? Color.ltAccent.opacity(0.25)
                                          : Color.ltSurface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(
                                                selectedEmoji == emoji ? Color.ltAccent : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                            )
                            .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("← Back") { step = .typeSelection }
                    .buttonStyle(LTEditorSecondaryButtonStyle())

                Button("Create Channel") { createCustomChannel() }
                    .buttonStyle(LTEditorButtonStyle())
                    .disabled(channelName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Step 3: Acquire Method

    @State private var isAutoRetrieving = false
    @State private var discoveredCount: Int = 0
    @State private var retrieveProcess: Process?
    @State private var retrieveError: String?

    private var acquireMethodStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Persistent error — height-reserved
            Text(retrieveError ?? "")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color.ltDestructive)
                .frame(height: 16)
                .opacity(retrieveError != nil ? 1 : 0)

            if isAutoRetrieving {
                autoRetrieveProgress
            } else {
                acquireMethodCards
            }
        }
        .padding(.top, 8)
    }

    private var acquireMethodCards: some View {
        VStack(spacing: 16) {
            // Auto retrieve card
            Button(action: startAutoRetrieve) {
                HStack(spacing: 20) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.ltAccent)
                        .frame(width: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto Retrieve Videos")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.ltText)
                        Text("Fetch up to 200 videos from this channel automatically")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Color.ltTextSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ltTextTertiary)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.ltSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.ltAccent.opacity(0.4), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                )
            }
            .buttonStyle(.plain)

            // Add later card
            Button(action: { createTypeAChannel(withURLs: []); dismiss() }) {
                HStack(spacing: 20) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.ltBlue)
                        .frame(width: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add Videos Later")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.ltText)
                        Text("Create the channel now and add videos manually from the editor")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Color.ltTextSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ltTextTertiary)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.ltSurface)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                )
            }
            .buttonStyle(.plain)

            Button("← Back") { step = .typeASetup }
                .buttonStyle(LTEditorSecondaryButtonStyle())
        }
    }

    private var autoRetrieveProgress: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(Color.ltAccent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scanning channel…")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.ltText)
                    Text("Found \(discoveredCount) video\(discoveredCount == 1 ? "" : "s") so far")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.ltTextSecondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.ltSurface)
            )

            Button("Cancel") {
                retrieveProcess?.terminate()
                isAutoRetrieving = false
            }
            .buttonStyle(LTEditorSecondaryButtonStyle())
        }
    }

    // MARK: - Create Channels

    private func createCustomChannel() {
        let name = channelName.trimmingCharacters(in: .whitespaces)
        let channel = Channel(
            displayName: name,
            emoji: selectedEmoji.isEmpty ? nil : selectedEmoji,
            type: .custom,
            folderName: name.slugified(),
            sortOrder: appState.channels.count
        )
        appState.addChannel(channel)
        dismiss()
    }

    private func createTypeAChannel(withURLs urls: [String]) {
        guard let resolved = resolvedChannel else { return }
        let channel = Channel(
            displayName: resolved.displayName,
            type: .source,
            youtubeChannelId: resolved.channelId,
            folderName: resolved.displayName.slugified(),
            sortOrder: appState.channels.count
        )
        appState.addChannel(channel)

        for url in urls {
            guard let videoId = url.youtubeVideoId else { continue }
            let video = Video(
                channelId: channel.id,
                youtubeVideoId: videoId,
                title: "Video \(videoId)",
                downloadState: .queued
            )
            appState.addVideo(video)
            Task { await appState.downloadService.enqueue(video: video, channel: channel) }
        }
    }

    private func startAutoRetrieve() {
        isAutoRetrieving = true
        discoveredCount  = 0
        retrieveError    = nil

        let process = ChannelResolverService.fetchVideoURLs(
            channelURL: youtubeURL,
            onProgress: { count in
                Task { @MainActor in discoveredCount = count }
            }
        ) { result in
            Task { @MainActor in
                isAutoRetrieving = false
                switch result {
                case .success(let urls):
                    createTypeAChannel(withURLs: urls)
                    dismiss()
                case .failure(let err):
                    retrieveError = err.localizedDescription
                }
            }
        }
        retrieveProcess = process
    }
}

// MARK: - Hover effect helper
private extension View {
    func buttonHoverEffect() -> some View {
        self.onHover { _ in }   // SwiftUI handles cursor changes automatically
    }
}
