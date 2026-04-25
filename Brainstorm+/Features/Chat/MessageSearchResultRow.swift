import SwiftUI

/// Iter 7 Phase 1.2 — standalone search result row for the global FTS path.
/// Currently `ChatListView` renders search results inline (see
/// `searchResultRow(_:)`); this file is staged so future UX (per-channel
/// search drawer, mention search, etc.) can share the same row visual.
///
/// Visual: channel name (or DM peer) + sender label + snippet (highlighted)
/// + relative time. Tap → caller navigates into channel + scrolls to message.
struct MessageSearchResultRow: View {
    let channelName: String
    let channelType: ChatChannel.ChannelType
    let senderLabel: String?
    let message: ChatMessage
    let searchTerm: String
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            Haptic.light()
            onTap()
        }) {
            VStack(alignment: .leading, spacing: BsSpacing.xs) {
                HStack(spacing: BsSpacing.xs) {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                    Text(channelName)
                        .font(BsTypography.cardSubtitle)
                        .foregroundStyle(BsColor.ink)
                    if let s = senderLabel, !s.isEmpty {
                        Text("· \(s)")
                            .font(BsTypography.captionSmall)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                    Spacer()
                    Text(ChatDateFormatter.format(message.createdAt))
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
                if message.content.isEmpty {
                    Text("[附件]")
                        .font(BsTypography.body)
                        .foregroundStyle(BsColor.inkMuted)
                        .lineLimit(2)
                } else {
                    Text(ChatContentHighlighter.attributed(
                        message.content,
                        searchTerm: searchTerm
                    ))
                        .font(BsTypography.body)
                        .foregroundStyle(BsColor.inkMuted)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, BsSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        switch channelType {
        case .direct:        return "person.fill"
        case .group:         return "person.3.fill"
        case .announcement:  return "megaphone.fill"
        }
    }
    private var tint: Color {
        switch channelType {
        case .direct:        return BsColor.brandAzure
        case .group:         return BsColor.success
        case .announcement:  return BsColor.brandCoral
        }
    }
}
