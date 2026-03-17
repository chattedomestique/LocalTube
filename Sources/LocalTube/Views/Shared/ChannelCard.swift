import SwiftUI
import AppKit

struct ChannelCard: View {
    let channel: Channel
    var videoCount: Int
    var thumbnailPath: String?
    var isEditing: Bool = false
    var isSelected: Bool = false
    var onTap: (() -> Void)?
    var onEdit: (() -> Void)?

    private let cardWidth: CGFloat = 280
    private let cardHeight: CGFloat = 240
    private let thumbHeight: CGFloat = 160

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail
                ZStack(alignment: .topTrailing) {
                    thumbnailView
                        .frame(width: cardWidth, height: thumbHeight)
                        .clipped()

                    if isEditing {
                        editBadge
                    }
                }

                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(channel.displayLabel)
                        .font(.ltHeadline)
                        .foregroundStyle(Color.ltText)
                        .lineLimit(2)

                    Text(videoCountText)
                        .font(.ltCaption)
                        .foregroundStyle(Color.ltTextSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .frame(width: cardWidth, height: cardHeight)
        .ltCard(isSelected: isSelected)
        .accessibilityLabel("\(channel.displayLabel), \(videoCountText)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var thumbnailView: some View {
        if let path = thumbnailPath, !path.isEmpty,
           let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.ltSurfaceElevated
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: LT.sfSymbolSize))
                    .foregroundStyle(Color.ltTextTertiary)
            }
        }
    }

    private var editBadge: some View {
        Button(action: { onEdit?() }) {
            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.ltAccent)
                .background(Color.ltBackground.clipShape(Circle()))
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityLabel("Edit \(channel.displayName)")
    }

    private var videoCountText: String {
        videoCount == 1 ? "1 video" : "\(videoCount) videos"
    }
}
