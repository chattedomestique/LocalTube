import SwiftUI

struct DownloadQueuePanel: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Download Queue", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ltText)
                Spacer()
                Button("Cancel All") {
                    appState.downloadService.cancelAll()
                }
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Color.ltDestructive)
                .buttonStyle(.plain)

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.ltTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().overlay(Color.ltSurfaceElevated)

            if appState.downloadQueue.isEmpty {
                emptyState
            } else {
                List(appState.downloadQueue) { item in
                    DownloadQueueRow(item: item)
                        .listRowBackground(Color.ltSurface)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.ltSurface)
        .frame(width: 380)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.ltSuccess)
            Text("No downloads")
                .font(.system(size: 18, design: .rounded))
                .foregroundStyle(Color.ltTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct DownloadQueueRow: View {
    @Environment(AppState.self) private var appState
    let item: DownloadQueueItem

    var body: some View {
        HStack(spacing: 12) {
            // State icon
            stateIcon

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.videoTitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ltText)
                    .lineLimit(1)
                Text(item.channelName)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.ltTextSecondary)

                if case .active = item.state {
                    ProgressView(value: item.progress)
                        .tint(Color.ltBlue)
                }

                if case .failed(let error) = item.state {
                    Text(error)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color.ltDestructive)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Cancel button
            if item.state == .waiting || item.state == .active {
                Button(action: {
                    appState.downloadService.cancelDownload(itemId: item.id)
                }) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(Color.ltTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch item.state {
        case .waiting:
            Image(systemName: "clock")
                .foregroundStyle(Color.ltTextSecondary)
                .frame(width: 20)
        case .active:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(Color.ltBlue)
                .frame(width: 20)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.ltSuccess)
                .frame(width: 20)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.ltDestructive)
                .frame(width: 20)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(Color.ltTextTertiary)
                .frame(width: 20)
        }
    }
}
