import SwiftUI

public struct NotificationCardView: View {
    public let notification: AppNotification
    
    public init(notification: AppNotification) {
        self.notification = notification
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(typeColor(notification.type).opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: typeIcon(notification.type))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(typeColor(notification.type))
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(notification.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(notification.isEffectivelyRead ? .primary.opacity(0.7) : .primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let date = notification.createdAt {
                        Text(date, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                let msg = notification.displayMessage
                if !msg.isEmpty {
                    Text(msg)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            
            // Unread Indicator
            if !notification.isEffectivelyRead {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private func typeColor(_ type: AppNotification.NotificationType) -> Color {
        switch type {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
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
