import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsProgressBar —— 内联水平进度条
//
// 用在卡 footer 展示比例数据：日报覆盖 X% / 完成率 X% / 使用率 X% 等。
// 补 5 人评审的"有 % 没 bar" 缺口。
//
// 轻量：6pt 高 + rounded + 品牌 tint，不抢主内容视线。
// ══════════════════════════════════════════════════════════════════

public struct BsProgressBar: View {
    /// 进度 0.0 - 1.0
    let progress: Double
    let tint: Color
    let height: CGFloat

    public init(progress: Double, tint: Color = BsColor.brandAzure, height: CGFloat = 6) {
        self.progress = max(0, min(1, progress))
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // 背景槽 —— 淡品牌色
                Capsule()
                    .fill(tint.opacity(0.12))

                // 进度条 —— 实品牌色
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: height)
        .animation(BsMotion.Anim.overshoot, value: progress)
    }
}
