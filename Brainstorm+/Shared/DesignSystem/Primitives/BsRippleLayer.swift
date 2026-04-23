import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsRippleLayer —— 触发扩散 ripple，iOS 流体签名动效
//
// 放在 ZStack 内某个圆形元素（如 progress ring）上方作为 overlay。
// 外部 `trigger: Int` 值每变一次（递增或递减都行），触发一次从中心
// 向外扩散的品牌色波纹，0.8s 后自然消散。
//
// 用法：
//   @State var ripple: Int = 0
//   ZStack {
//       Circle().stroke(...)
//       BsRippleLayer(trigger: ripple, color: BsColor.brandAzure)
//   }
//   Button("打卡") { ripple += 1 }
// ══════════════════════════════════════════════════════════════════

public struct BsRippleLayer: View {
    let trigger: Int
    let color: Color
    let maxScale: CGFloat

    /// 内部状态：当前扩散进度 (0 → 1)，opacity (1 → 0)
    @State private var scale: CGFloat = 0.5
    @State private var opacity: CGFloat = 0.0

    public init(trigger: Int, color: Color, maxScale: CGFloat = 1.8) {
        self.trigger = trigger
        self.color = color
        self.maxScale = maxScale
    }

    public var body: some View {
        Circle()
            .stroke(color, lineWidth: 3)
            .scaleEffect(scale)
            .opacity(opacity)
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, _ in
                fire()
            }
    }

    private func fire() {
        // 重置到起点
        scale = 0.5
        opacity = 0.9

        // 扩散动画：0.8s 内放大到 maxScale + 淡出
        withAnimation(.easeOut(duration: 0.8)) {
            scale = maxScale
            opacity = 0
        }
    }
}
