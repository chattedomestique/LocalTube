import SwiftUI

struct DownloadStateBadge: View {
    let video: Video

    var body: some View {
        switch video.downloadState {
        case .queued:
            badgeView(icon: "clock.fill", color: .ltTextSecondary, label: "Queued")

        case .downloading:
            ZStack {
                Circle()
                    .stroke(Color.ltSurface, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: video.downloadProgress)
                    .stroke(Color.ltBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(video.downloadProgress * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            .background(Color.ltBackground.opacity(0.85))
            .clipShape(Circle())
            .accessibilityLabel("Downloading \(Int(video.downloadProgress * 100))%")

        case .ready:
            badgeView(icon: "checkmark.circle.fill", color: .ltSuccess, label: "Ready")

        case .error:
            badgeView(icon: "exclamationmark.circle.fill", color: .ltDestructive, label: "Error")
        }
    }

    private func badgeView(icon: String, color: Color, label: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: LT.sfSymbolSize * 0.7))
            .foregroundStyle(color)
            .background(Color.ltBackground.opacity(0.85).clipShape(Circle()))
            .accessibilityLabel(label)
    }
}
