import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsPrimaryButton —— 主 CTA，实色 Azure 印章，一屏一个
//
// v1.1 redesign 的关键取舍：把主 CTA 从"三色液态玻璃 tint"收敛到
// "实色 Azure 印章" —— 一块平整的蓝色色块读起来比带折射的玻璃
// 物件更果断，适合"保存 / 提交 / 创建 / 打卡 / 发送"这类一次性
// 决定动作。
//
// 规则：
//   • **一屏最多 1 个** BsPrimaryButton。多了就稀释。
//   • 用在 "保存 / 提交 / 创建 / 打卡 / 发送" 等主 CTA。
//   • 次要动作用系统 Button / .bordered / .plain，不要都 Azure 实色。
//
// 视觉规格：
//   • 填充：实色 BsColor.brandAzure（不是 .glassEffect(.tint:)）
//   • Dark mode 不投影，Azure 在深色背景上自带"发光"感
//   • 尺寸 / 按压反馈 / loading / API 与其他一级按钮一致，便于 muscle memory
// ══════════════════════════════════════════════════════════════════

public struct BsPrimaryButton<Label: View>: View {
    public enum Size {
        case regular  // 44pt 高度
        case large    // 52pt 高度

        var height: CGFloat {
            switch self {
            case .regular: return 44
            case .large: return 52
            }
        }
        var hPadding: CGFloat {
            switch self {
            case .regular: return 16
            case .large: return 20
            }
        }
        var font: Font {
            switch self {
            case .regular: return .custom("Inter-SemiBold", size: 15)
            case .large: return .custom("Inter-SemiBold", size: 17)
            }
        }
    }

    let size: Size
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void
    let label: () -> Label
    @State private var isPressed: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    public init(
        size: Size = .regular,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.size = size
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
        self.label = label
    }

    private var isInteractionBlocked: Bool {
        isLoading || isDisabled
    }

    private var fillColor: Color {
        isDisabled ? BsColor.brandAzure.opacity(0.35) : BsColor.brandAzure
    }

    public var body: some View {
        Button {
            guard !isInteractionBlocked else { return }
            Haptic.medium()
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                }
                label()
                    .font(size.font)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: size.height)
            .padding(.horizontal, size.hPadding)
            // v1.1 关键：实色 Azure 印章 —— 不是玻璃，不是渐变
            .foregroundStyle(.white)
            .background(fillColor, in: Capsule())
            .scaleEffect(isPressed && !isInteractionBlocked ? 0.97 : 1.0)
            // 浅色模式下柔和 Azure 投影；深色模式不投影（Azure 自发光）
            .shadow(
                color: colorScheme == .dark
                    ? .clear
                    : BsColor.brandAzure.opacity(0.25),
                radius: colorScheme == .dark ? 0 : 14,
                x: 0,
                y: colorScheme == .dark ? 0 : 8
            )
            .animation(BsMotion.Anim.overshoot, value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(isInteractionBlocked)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isInteractionBlocked else { return }
                    if !isPressed { isPressed = true }
                }
                .onEnded { _ in isPressed = false }
        )
    }
}

// 纯文字签名的便捷构造器，避免调用方每次写 `{ Text("...") }`
public extension BsPrimaryButton where Label == Text {
    init(
        _ title: String,
        size: Size = .regular,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            size: size,
            isLoading: isLoading,
            isDisabled: isDisabled,
            action: action
        ) {
            Text(title)
        }
    }
}

// 带 SF Symbol icon 前缀的便捷构造器（v1.1 Batch 7 合并到 BsPrimaryButton 本体）
//
// 过去 BsPrimaryButtonWithIcon 是独立 struct（内部包 AnyView + 再度 wrap 一次
// BsPrimaryButton）。Batch 7 清理把"icon + title"直接下放到 BsPrimaryButton
// 的 @ViewBuilder label —— 调用方可以写：
//
//     BsPrimaryButton(size: .large, action: { ... }) {
//         HStack(spacing: 8) {
//             Image(systemName: "plus.circle.fill")
//                 .font(.system(size: 14, weight: .semibold))
//             Text("创建")
//         }
//     }
//
// 或者用下面的 `systemImage:` 便捷构造器（内部走 BsPrimaryIconLabel，
// 固定 8pt 间距 + 14pt semibold icon，对齐 Web primary button 节奏）。

/// 内部使用：BsPrimaryButton `systemImage:` 便捷构造器的 label 容器。
/// 命名显式成独立 View 避免 generic `Label` 泛型签名引入内部 SwiftUI 类型。
public struct BsPrimaryIconLabel: View {
    let systemImage: String
    let title: String

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
        }
    }
}

public extension BsPrimaryButton where Label == BsPrimaryIconLabel {
    /// 带前置 SF Symbol 的便捷构造器。
    ///
    /// 替代旧的 `BsPrimaryButtonWithIcon(...)`（已移除）。
    init(
        _ title: String,
        systemImage: String,
        size: Size = .regular,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            size: size,
            isLoading: isLoading,
            isDisabled: isDisabled,
            action: action
        ) {
            BsPrimaryIconLabel(systemImage: systemImage, title: title)
        }
    }
}

#Preview("BsPrimaryButton states") {
    VStack(spacing: 20) {
        BsPrimaryButton("保存", size: .regular) {}
        BsPrimaryButton("提交打卡", size: .large) {}
        BsPrimaryButton("发送中", size: .regular, isLoading: true) {}
        BsPrimaryButton("不可用", size: .regular, isDisabled: true) {}
        BsPrimaryButton("创建", systemImage: "plus.circle.fill", size: .large) {}
    }
    .padding()
}
