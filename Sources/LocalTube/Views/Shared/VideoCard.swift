import SwiftUI
import AppKit

struct VideoCard: View {
    let video: Video
    var scale: CGFloat = 1.0
    var isEditing: Bool = false
    var isSelected: Bool = false
    var onTap:    (() -> Void)?
    var onDelete: (() -> Void)?
    var onRetry:  (() -> Void)?

    @State private var isHovering = false

    private let baseWidth:  CGFloat = 260
    private let baseHeight: CGFloat = 200

    private var cardWidth:  CGFloat { baseWidth  * scale }
    private var cardHeight: CGFloat { baseHeight * scale }

    var body: some View {
        Button(action: { if video.isPlayable { onTap?() } }) {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail
                thumbnailView
                    .frame(width: cardWidth, height: cardHeight * 0.72)
                    .clipped()
                    .overlay(alignment: .topTrailing) { durationBadge }
                    .overlay(alignment: .topLeading)  { if isEditing { selectionBadge } }
                    .overlay(alignment: .topTrailing)  { if isEditing { downloadBadge } }

                // Info row
                HStack(alignment: .top, spacing: 8) {
                    Text(video.title)
                        .font(.system(size: max(11, 13 * scale), weight: .medium, design: .rounded))
                        .foregroundStyle(Color.ltText)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isEditing {
                        editorControls
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(width: cardWidth)
                .background(Color.ltSurface)
            }
        }
        .buttonStyle(.plain)
        .frame(width: cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: LT.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: LT.cardCornerRadius)
                .strokeBorder(
                    isSelected ? Color.ltAccent : (isHovering ? Color.white.opacity(0.2) : Color.white.opacity(0.07)),
                    lineWidth: isSelected ? 2.5 : 1
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: LT.shadowRadius, x: 0, y: 4)
        .scaleEffect(isHovering && !isEditing ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .opacity(video.isPlayable || isEditing ? 1.0 : 0.5)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        if !video.thumbnailPath.isEmpty,
           let nsImage = NSImage(contentsOfFile: video.thumbnailPath) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.ltSurfaceElevated
                Image(systemName: "film.fill")
                    .font(.system(size: LT.sfSymbolSize * scale * 0.8))
                    .foregroundStyle(Color.ltTextTertiary)
            }
        }
    }

    // MARK: - Duration badge

    @ViewBuilder
    private var durationBadge: some View {
        if video.durationSeconds > 0 {
            Text(video.formattedDuration)
                .font(.system(size: max(10, 11 * scale), weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(6)
        }
    }

    // MARK: - Editor overlays

    @ViewBuilder
    private var selectionBadge: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: max(18, 22 * scale), weight: .semibold))
            .foregroundStyle(isSelected ? Color.ltAccent : Color.white.opacity(0.75))
            .shadow(color: .black.opacity(0.5), radius: 2)
            .padding(6)
    }

    @ViewBuilder
    private var downloadBadge: some View {
        DownloadStateBadge(video: video)
            .padding(.top, video.durationSeconds > 0 ? 30 : 6)
            .padding(.trailing, 6)
    }

    private var editorControls: some View {
        HStack(spacing: 4) {
            if video.downloadState == .error {
                Button(action: { onRetry?() }) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.ltAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry download")
            }
            Button(action: { onDelete?() }) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.ltDestructive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove video")
        }
        .padding(.top, 1)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts = [video.title]
        if video.durationSeconds > 0 { parts.append(video.formattedDuration) }
        parts.append(video.downloadState.rawValue)
        return parts.joined(separator: ", ")
    }
}
