import SwiftUI

public struct NotificationCardView: View {
    public let notification: AppNotification

    public init(notification: AppNotification) {
        self.notification = notification
    }

    public var body: some View {
        HStack(alignment: .top, spacing: BsSpacing.lg) {
            // Icon
            ZStack {
                Circle()
                    .fill(typeColor(notification.type).opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: typeIcon(notification.type))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(typeColor(notification.type))
            }

            VStack(alignment: .leading, spacing: BsSpacing.xs + 2) {
                HStack {
                    Text(notification.title)
                        .font(BsTypography.cardTitle)
                        .foregroundStyle(notification.isEffectivelyRead ? BsColor.inkMuted : BsColor.ink)
                        .lineLimit(1)

                    Spacer()

                    if let date = notification.createdAt {
                        Text(date, style: .time)
                            .font(BsTypography.captionSmall)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                }

                let msg = notification.displayMessage
                if !msg.isEmpty {
                    Text(msg)
                        .font(BsTypography.bodySmall)
                        .foregroundStyle(BsColor.inkMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            // Unread Indicator —— Fusion coral glass dot
            if !notification.isEffectivelyRead {
                Color.clear
                    .frame(width: 8, height: 8)
                    .glassEffect(
                        .regular.tint(BsColor.brandCoral.opacity(0.85)),
                        in: Circle()
                    )
                    .padding(.top, BsSpacing.xs + 2)
            }
        }
        .padding(BsSpacing.lg)
        // Fusion glass envelope —— 替换 solid surfacePrimary + hairline border
        .bsGlassCard(cornerRadius: BsRadius.lg)
    }

    private func typeColor(_ type: AppNotification.NotificationType) -> Color {
        switch type {
        case .info:    return BsColor.brandAzure
        case .success: return BsColor.success
        case .warning: return BsColor.warning
        case .error:   return BsColor.danger
        }
    }

    private func typeIcon(_ type: AppNotification.NotificationType) -> String {
        switch type {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.seal.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}
