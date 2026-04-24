import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsPressFeedback —— 统一 press 反馈 modifier
//
// 设计来源：audit 发现 5 个 primitives 里同款 `DragGesture(minimumDistance: 0) +
// @State isPressed + .scaleEffect + Haptic.light()` 模式复制（BsAppTile /
// BsAllAppsTile / BsContentCard / BsPrimaryButton / BsCommandPalette 内联 tile）。
// 抽成单一 modifier，未来所有 interactive primitive 只挂一行即可。
//
// 用法：
//   MyTile()
//     .bsPressFeedback()                    // 默认 scale 0.97 + light haptic
//     .bsPressFeedback(scale: 0.94, haptic: .medium)
//
// 关键实现：
//   • 用 simultaneousGesture 包住，不抢外层 NavigationLink / Button 的 tap
//   • `minimumDistance: 0` 让按下立刻触发 press state（非滑动后）
//   • Haptic 只在 "未按压 → 按压" 边沿触发一次（isPressed false→true 沿）
//   • 释放立即回弹（onEnded）—— iOS 原生按压节奏
//   • BsMotion.Anim.overshoot spring 作 scale 动画
// ══════════════════════════════════════════════════════════════════

public enum BsPressHaptic {
    case none
    case light
    case medium
    case rigid
}

public struct BsPressFeedback: ViewModifier {
    let scale: CGFloat
    let haptic: BsPressHaptic

    @State private var isPressed: Bool = false

    public init(scale: CGFloat = 0.97, haptic: BsPressHaptic = .light) {
        self.scale = scale
        self.haptic = haptic
    }

    public func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1.0)
            .animation(BsMotion.Anim.overshoot, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            fireHaptic()
                        }
                    }
                    .onEnded { _ in isPressed = false }
            )
    }

    private func fireHaptic() {
        switch haptic {
        case .none: break
        case .light: Haptic.light()
        case .medium: Haptic.medium()
        case .rigid: Haptic.rigid()
        }
    }
}

public extension View {
    /// 给可点击 view 加统一的 scale-on-press + haptic 反馈。
    /// 默认 scale 0.97 + light haptic，符合 iOS HIG press feedback。
    func bsPressFeedback(
        scale: CGFloat = 0.97,
        haptic: BsPressHaptic = .light
    ) -> some View {
        modifier(BsPressFeedback(scale: scale, haptic: haptic))
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Tap me")
            .padding()
            .background(BsColor.brandAzure.opacity(0.2), in: Capsule())
            .bsPressFeedback()

        Text("Medium haptic")
            .padding()
            .background(BsColor.brandMint.opacity(0.2), in: Capsule())
            .bsPressFeedback(scale: 0.94, haptic: .medium)
    }
}
