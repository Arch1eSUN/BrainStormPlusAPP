import SwiftUI

/// Phase 1.1 — 未读分隔线
///
/// 在第一条 created_at > member.last_read_at 的消息上方渲染。视觉走我们的
/// flow design (BsColor.brandCoral 渐变 hairline + Inter SemiBold count pill),
/// 不抄 Slack 的红色字号。
///
/// Slack 视觉:水平红线 + "New" badge 居中。
/// 我们视觉:水平 hairline 走 Coral→Coral.opacity(0) 渐变(从左到 pill 处),
///         pill 居中(brandCoral.opacity(0.18) glass tint + Inter SemiBold 11pt
///         "X 条新消息"),右侧 hairline 镜像渐变。
///
/// Coral 是 v1.2 token 的"注意 / 未读"语义岗位(unreadBadge alias 也指向它),
/// 所以未读 divider 用 Coral 而非 brandAzure。
struct UnreadDividerView: View {
    let unreadCount: Int

    var body: some View {
        HStack(spacing: BsSpacing.smd) {
            LinearGradient(
                colors: [BsColor.brandCoral.opacity(0), BsColor.brandCoral.opacity(0.55)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)

            Text("\(unreadCount) 条新消息")
                .font(BsTypography.label)
                .foregroundStyle(BsColor.brandCoralText)
                .padding(.horizontal, BsSpacing.smd)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(BsColor.brandCoral.opacity(0.14))
                )
                .overlay(
                    Capsule().stroke(BsColor.brandCoral.opacity(0.30), lineWidth: 0.5)
                )

            LinearGradient(
                colors: [BsColor.brandCoral.opacity(0.55), BsColor.brandCoral.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
        }
        .padding(.horizontal, BsSpacing.lg)
        .padding(.vertical, BsSpacing.xs)
        .accessibilityLabel("\(unreadCount) 条新消息")
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(spacing: 20) {
        UnreadDividerView(unreadCount: 1)
        UnreadDividerView(unreadCount: 12)
        UnreadDividerView(unreadCount: 99)
    }
    .padding()
    .background(BsColor.pageBackground)
}
