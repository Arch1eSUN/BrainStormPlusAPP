import SwiftUI
import PhotosUI

/// Iter 7 Fix 3 — 流体设计输入栏(替代 Phase 1.1 矩形版)。
///
/// 设计语言:
///   • 整个 composer = 一颗悬浮的 glass capsule(BsRadius.xl 圆角),不再是
///     "上 hairline + 矩形底"那种 Slack web 风格。读起来像 iMessage iOS 26 +
///     我们 Fusion tokens 的混合 —— glass.regular 材质 + brandAzure 半透明 stroke,
///     底色透到下方消息流的 page background。
///   • 顶部分隔线改成柔和 LinearGradient hairline(中间 borderSubtle.opacity(0.5),
///     左右淡出),不抢视觉。
///   • 快捷动作行:每个图标 32pt glass 圆,跟 nav toolbar 那颗 "新建" 圆按钮
///     同语言。
///   • Send button: 36pt glass 圆 + brandAzure tint + drop-shadow,enabled 时
///     带轻微浮起感。
///   • Send 按下:scale 0.92 → 1.0 spring + Haptic medium,跟 BsMotion 对齐。
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
    @State private var sendPressed: Bool = false

    /// 6 行上限 ≈ 17pt body × 1.2 line-height × 6 ≈ 122pt + 16 padding
    private let minHeight: CGFloat = 38
    private let maxHeight: CGFloat = 138

    var body: some View {
        VStack(spacing: 0) {
            // 顶部柔和 hairline —— 中央 8% 透明 borderSubtle, 两端淡出
            // 视觉上是"呼吸"的而不是死板分隔。
            LinearGradient(
                colors: [
                    .clear,
                    BsColor.borderSubtle.opacity(0.5),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 0.5)

            // 输入栏主体 capsule
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
                            // Hidden measure layer for dynamic height.
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
                HStack(spacing: BsSpacing.sm + 2) {
                    quickActionButton(systemName: "paperclip", label: "附件", action: onAttachmentTap)
                    quickActionButton(systemName: "camera.fill", label: "图片", action: onPhotoTap)
                    quickActionButton(systemName: "face.smiling", label: "表情", action: onEmojiTap)
                    quickActionButton(systemName: "at", label: "提及", action: onMentionTap)
                    Spacer()
                    sendButton
                }
            }
            .padding(.horizontal, BsSpacing.md + 2)
            .padding(.vertical, BsSpacing.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                    .fill(BsColor.surfacePrimary.opacity(0.001))   // capture taps
            )
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                BsColor.brandAzure.opacity(focused ? 0.22 : 0.15),
                                BsColor.brandAzure.opacity(focused ? 0.10 : 0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(
                color: BsColor.brandAzure.opacity(focused ? 0.10 : 0.04),
                radius: focused ? 12 : 6,
                x: 0,
                y: 2
            )
            .padding(.horizontal, BsSpacing.md)
            .padding(.bottom, BsSpacing.sm)
            .padding(.top, BsSpacing.sm)
            .animation(BsMotion.Anim.smooth, value: focused)
        }
    }

    @ViewBuilder
    private func quickActionButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            Haptic.light()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 32, height: 32)
                .glassEffect(
                    .regular.interactive(),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var sendButton: some View {
        Button(action: {
            guard canSend && !isSending else { return }
            Haptic.medium()
            // 微小的 press → release 弹动,跟 SwiftUI scale spring 一起做
            // "按下 → 弹出" 的体感。
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                sendPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.65)) {
                    sendPressed = false
                }
            }
            onSend()
        }) {
            Group {
                if isSending {
                    ProgressView()
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canSend ? .white : BsColor.inkFaint)
                        .rotationEffect(.degrees(45))
                        .offset(x: -1)
                }
            }
            .frame(width: 36, height: 36)
            .glassEffect(
                .regular
                    .tint(
                        canSend
                            ? BsColor.brandAzure.opacity(0.85)
                            : BsColor.inkFaint.opacity(0.10)
                    )
                    .interactive(),
                in: Circle()
            )
            .shadow(
                color: canSend ? BsColor.brandAzure.opacity(0.35) : .clear,
                radius: canSend ? 8 : 0,
                x: 0,
                y: 2
            )
            .scaleEffect(sendPressed ? 0.92 : 1.0)
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
