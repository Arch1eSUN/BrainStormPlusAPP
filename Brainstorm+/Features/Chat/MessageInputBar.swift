import SwiftUI
import PhotosUI

/// Phase 1.1 — 升级版输入栏
///
/// Slack 等级体验:
///   • TextEditor 多行自动撑高(最高 6 行,~140pt @ 17pt body line-height),
///     超过后内部滚动而不挤压上方消息流。
///   • Send 按钮 enabled-state: 空 → 灰 inkFaint glass tint; 有内容 → brandAzure
///     glass tint 全饱和。
///   • Quick action row(底部):📎 附件 / 📷 截图 / 😀 表情 / @ 提及触发器。
///   • `.glassEffect(.regular)` 跟 iOS 26 系统输入栏一致的材质,顶部 hairline
///     保留分隔感。
///   • 软键盘 inset 由 safeAreaInset 统一处理(在 caller 一侧),input bar 永远
///     悬浮在键盘上方,不被覆盖。
///
/// 视觉风格 = 我们的流体设计,不是 Slack 默认的灰底白角输入框。
struct MessageInputBar: View {
    @Binding var text: String
    let isSending: Bool
    let canSend: Bool
    let placeholder: String
    let onSend: () -> Void
    let onAttachmentTap: () -> Void
    let onPhotoTap: () -> Void
    let onEmojiTap: () -> Void
    let onMentionTap: () -> Void

    @FocusState private var focused: Bool
    @State private var dynamicHeight: CGFloat = 38

    /// 6 行上限 ≈ 17pt body × 1.2 line-height × 6 ≈ 122pt + 16 padding
    private let minHeight: CGFloat = 38
    private let maxHeight: CGFloat = 138

    var body: some View {
        VStack(spacing: 0) {
            // 顶部 hairline 分隔
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(BsColor.borderSubtle)

            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                // 文本编辑区 —— ZStack 把 placeholder 叠在 TextEditor 之上
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(BsTypography.body)
                            .foregroundStyle(BsColor.inkFaint)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $text)
                        .font(BsTypography.body)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .foregroundStyle(BsColor.ink)
                        .frame(minHeight: minHeight, maxHeight: dynamicHeight)
                        .focused($focused)
                        .background(
                            // 不可见 measure layer —— 同样的 text + font,GeometryReader
                            // 报回真实高度供我们 clamp。Apple 没给 TextEditor 的"内容
                            // 高度" public API,只能这么测。
                            Text(text.isEmpty ? " " : text)
                                .font(BsTypography.body)
                                .lineLimit(nil)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .background(GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: InputHeightKey.self,
                                        value: proxy.size.height
                                    )
                                })
                                .hidden()
                        )
                }
                .onPreferenceChange(InputHeightKey.self) { newHeight in
                    let clamped = min(max(newHeight, minHeight), maxHeight)
                    if abs(clamped - dynamicHeight) > 1 {
                        withAnimation(BsMotion.Anim.smooth) {
                            dynamicHeight = clamped
                        }
                    }
                }

                // 底部快捷行 + Send
                HStack(spacing: BsSpacing.lg) {
                    quickActionButton(systemName: "paperclip", label: "附件", action: onAttachmentTap)
                    quickActionButton(systemName: "camera.fill", label: "图片", action: onPhotoTap)
                    quickActionButton(systemName: "face.smiling", label: "表情", action: onEmojiTap)
                    quickActionButton(systemName: "at", label: "提及", action: onMentionTap)
                    Spacer()
                    sendButton
                }
            }
            .padding(.horizontal, BsSpacing.lg)
            .padding(.vertical, BsSpacing.sm + 2)
        }
        .glassEffect(
            .regular,
            in: Rectangle()
        )
    }

    @ViewBuilder
    private func quickActionButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var sendButton: some View {
        Button(action: {
            guard canSend && !isSending else { return }
            Haptic.medium()
            onSend()
        }) {
            Group {
                if isSending {
                    ProgressView()
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canSend ? BsColor.brandAzure : BsColor.inkFaint)
                        .rotationEffect(.degrees(45))
                        .offset(x: -1)
                }
            }
            .frame(width: 36, height: 36)
            .glassEffect(
                .regular
                    .tint(
                        canSend
                            ? BsColor.brandAzure.opacity(0.35)
                            : BsColor.inkFaint.opacity(0.10)
                    )
                    .interactive(),
                in: Circle()
            )
        }
        .disabled(!canSend || isSending)
        .accessibilityLabel("发送")
        .animation(BsMotion.Anim.smooth, value: canSend)
    }
}

private struct InputHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 38
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
