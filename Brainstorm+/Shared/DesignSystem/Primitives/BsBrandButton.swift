import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsBrandButton —— 主 CTA，三色品牌渐变填色，一屏一个
//
// Phase 20 subtraction 的关键：把品牌色从"散落在 content"收敛到
// 一个"集中爆发点" —— 屏幕上最重要那个动作。
//
// 规则：
//   • **一屏最多 1 个** BsBrandButton。多了就稀释。
//   • 用在 "保存 / 提交 / 创建 / 打卡 / 发送" 等主 CTA。
//   • 次要动作用系统 Button / .bordered / .plain，不要都三色渐变。
//
// 对齐 Web `BsButton variant="primary"` 模式，iOS 版本用 iOS 26
// Liquid Glass + 三色渐变 overlay 的组合。
// ══════════════════════════════════════════════════════════════════

public struct BsBrandButton<Label: View>: View {
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
    let action: () -> Void
    let label: () -> Label
    @State private var isPressed: Bool = false

    public init(
        size: Size = .regular,
        isLoading: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.size = size
        self.isLoading = isLoading
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button {
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
            // Phase 21 校准：流体主导 → CTA 回玻璃半透材质（品牌 Azure tint）
            // 不再实色也不再渐变——iOS 26 用户肌肉记忆 CTA 应该是可折射玻璃物件
            .foregroundStyle(.white)
            .glassEffect(
                .regular
                    .tint(BsColor.brandAzure.opacity(0.55))
                    .interactive(),
                in: Capsule()
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .shadow(color: BsColor.brandAzure.opacity(0.30),
                    radius: 14, x: 0, y: 8)
            .animation(BsMotion.Anim.overshoot, value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
    }
}

// 纯文字签名的便捷构造器，避免调用方每次写 `{ Text("...") }`
public extension BsBrandButton where Label == Text {
    init(
        _ title: String,
        size: Size = .regular,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(size: size, isLoading: isLoading, action: action) {
            Text(title)
        }
    }
}

// 带 SF Symbol icon 前缀的便捷构造器
public struct BsBrandButtonWithIcon: View {
    let title: String
    let systemImage: String
    let size: BsBrandButton<AnyView>.Size
    let isLoading: Bool
    let action: () -> Void

    public init(
        _ title: String,
        systemImage: String,
        size: BsBrandButton<AnyView>.Size = .regular,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.size = size
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        BsBrandButton(size: size, isLoading: isLoading, action: action) {
            AnyView(
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                    Text(title)
                }
                .foregroundStyle(.white)
            )
        }
    }
}
