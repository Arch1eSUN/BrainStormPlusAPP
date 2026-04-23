import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsGlassCard —— BrainStorm+ 招牌玻璃卡
//
// 对齐 Web `.card-zy` / BsCard variant="glass"：
//   • rounded 24 (BsRadius.xl)
//   • iOS 26 Liquid Glass 材质 (.glassEffect) 等价 Web
//     backdrop-blur-64 + backdrop-saturate-200
//   • 顶部 1px 白高光（inset）—— Web 招牌 bevel 感
//   • 白 0.5 alpha 半透 stroke 边 —— Web glass border
//   • 0 8 32 -8 black/0.08 软阴影 —— 让卡"漂在" warm bg 上
//   • interactive 变体：按压 scale 0.98 + shadow grow + overshoot spring
//
// 用法：
//     VStack { ... }.bsGlassCard()                              // 静态卡
//     Button(...) { ... }.bsGlassCard(.interactive)             // 带按压反馈
//     .bsGlassCard(.tinted(BsColor.brandAzure.opacity(0.12)))   // 带品牌色 tint
//
// 不要再自己 .background(surfacePrimary).overlay(stroke) —— 走这个 modifier。
// ══════════════════════════════════════════════════════════════════

public enum BsGlassVariant {
    case plain
    case interactive
    case tinted(Color)
}

public struct BsGlassCardModifier: ViewModifier {
    let variant: BsGlassVariant
    let cornerRadius: CGFloat

    @State private var isPressed: Bool = false

    public init(variant: BsGlassVariant = .plain, cornerRadius: CGFloat = BsRadius.xl) {
        self.variant = variant
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        glassEffectApplied(content: content, shape: shape)
            // Inset 1px 白顶高光 —— Web `shadow-[inset_0_1px_0_rgba(255,255,255,1)]` 的 iOS 近似
            .overlay(topHighlight(shape: shape))
            // 白 0.5 alpha 半透 stroke 边 —— Web glass border
            .overlay(shape.stroke(BsColor.glassBorder, lineWidth: 0.5))
            // 软下沉阴影 —— Web `0 8 32 -8 black/0.08`
            .bsShadow(isPressed ? BsShadow.glassCardHover : BsShadow.glassCard)
            // interactive：press scale + overshoot spring
            .scaleEffect(pressScale)
            .animation(BsMotion.Anim.overshoot, value: isPressed)
            .simultaneousGesture(pressGesture)
    }

    // MARK: - Variants

    @ViewBuilder
    private func glassEffectApplied<V: View>(content: V, shape: RoundedRectangle) -> some View {
        switch variant {
        case .plain:
            content.glassEffect(.regular, in: shape)
        case .interactive:
            content.glassEffect(.regular.interactive(), in: shape)
        case .tinted(let color):
            content.glassEffect(.regular.tint(color).interactive(), in: shape)
        }
    }

    @ViewBuilder
    private func topHighlight(shape: RoundedRectangle) -> some View {
        // 顶部 1px 白高光 —— 模拟 Web 的 inset-1px-white bevel
        // 用 LinearGradient mask 只保留顶部 12% 区域
        shape
            .stroke(BsColor.glassHighlight, lineWidth: 1)
            .mask(
                LinearGradient(
                    colors: [.white, .white.opacity(0)],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.12)
                )
            )
            .allowsHitTesting(false)
    }

    private var pressScale: CGFloat {
        guard case .interactive = variant else { return 1.0 }
        guard case .interactive = variant else { return 1.0 }
        return isPressed ? 0.98 : 1.0
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if isInteractive, !isPressed { isPressed = true }
            }
            .onEnded { _ in
                if isInteractive { isPressed = false }
            }
    }

    private var isInteractive: Bool {
        if case .interactive = variant { return true }
        return false
    }
}

public extension View {
    /// 招牌玻璃卡 —— 24 圆角 + Liquid Glass + inset 顶光 + 软阴影。
    /// 默认 plain；传 .interactive 开按压反馈；传 .tinted(color) 加品牌色 tint。
    func bsGlassCard(
        _ variant: BsGlassVariant = .plain,
        cornerRadius: CGFloat = BsRadius.xl
    ) -> some View {
        modifier(BsGlassCardModifier(variant: variant, cornerRadius: cornerRadius))
    }
}
