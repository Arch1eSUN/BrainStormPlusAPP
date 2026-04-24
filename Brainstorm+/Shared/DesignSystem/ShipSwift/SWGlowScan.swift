import SwiftUI

// ══════════════════════════════════════════════════════════════════
// SWGlowScan —— 垂直扫过的品牌色光带
//
// 何时用：
//   • **主 CTA / 品牌签名元素**需要静态"注意引诱"—— 例如 Dashboard
//     hero 的 "开始打卡" 按钮、登录页的 wordmark、激活态的 brand
//     strip。一束品牌色光从上往下周期性扫过，语义是"这里是值得看的地方"。
//   • **成功 / 到账 / 达成**瞬间的一次性庆祝扫光（配合 .onAppear 触发）。
//
// 何时换成 SWShimmer：
//   • 占位 / loading skeleton —— 那是"白光对角线 + 数据未到"语义，
//     不要用 glowScan（品牌色会被误读成"这个组件坏了在报警"）。
//
// 何时都不要用：
//   • 静态内容（卡片 body / 列表 row 默认态）—— 过度动效会分散注意力。
//   • 一屏 > 1 个 glowScan —— 多个品牌色周期光会互相抢，选主焦点一个。
//
// 使用：
//   BsPrimaryButton("开始打卡") { ... }
//       .glowScan(color: BsColor.brandAzure)
//
// 或带周期控制：
//   myView.glowScan(color: BsColor.brandMint, duration: 2.5)
//
// 参数：
//   • color —— 扫光颜色。默认 .white（通用高光），品牌场景传
//     BsColor.brandAzure / brandMint / brandCoral。
//   • duration —— 一次扫光（上 → 下）的总时长（秒）。默认 2.5s，
//     配合 BsMotion.Duration.fluid (0.60s) × ~4 的节奏。
//   • bandHeightRatio —— 光带高度占 view 高度的比例，默认 0.4。
//     更小（0.2-0.3）更锐利；更大（0.5-0.7）更柔和。
// ══════════════════════════════════════════════════════════════════

public struct SWGlowScan: ViewModifier {
    @State private var hoverPoint: CGFloat = -0.5

    public let color: Color
    public let duration: Double
    public let bandHeightRatio: CGFloat

    public init(
        color: Color,
        duration: Double = 2.5,
        bandHeightRatio: CGFloat = 0.4
    ) {
        self.color = color
        self.duration = duration
        self.bandHeightRatio = bandHeightRatio
    }

    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { proxy in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, color.opacity(0.8), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: max(proxy.size.height * bandHeightRatio, 40))
                        .offset(y: proxy.size.height * hoverPoint)
                        .blendMode(.screen)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: duration)
                        .repeatForever(autoreverses: false)
                ) {
                    hoverPoint = 1.5
                }
            }
    }
}

public extension View {
    /// 垂直品牌色扫光 —— 主 CTA / 品牌签名 / 成功瞬间。
    ///
    /// - Parameters:
    ///   - color: 扫光颜色，默认 .white（通用高光）。
    ///   - duration: 一次扫光时长（秒），默认 2.5s。
    ///   - bandHeightRatio: 光带高度占 view 高度比例，默认 0.4。
    func glowScan(
        color: Color = .white,
        duration: Double = 2.5,
        bandHeightRatio: CGFloat = 0.4
    ) -> some View {
        self.modifier(SWGlowScan(
            color: color,
            duration: duration,
            bandHeightRatio: bandHeightRatio
        ))
    }
}
