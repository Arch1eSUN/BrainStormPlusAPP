import SwiftUI

// ══════════════════════════════════════════════════════════════════
// SWShimmer —— loading skeleton 上的对角线扫光
//
// 何时用：
//   • **Loading / skeleton 占位** —— 列表 row / card 在数据到达前
//     先放一个 tint 0.06~0.12 的 RoundedRectangle 占位块，套 .shimmering()
//     让"正在加载"被肉眼感知。
//   • 静态内容**不要**加 shimmer —— 会读成"这块在一直刷新 / 没加载完"，
//     违反"运动必须有意义"原则。
//
// 何时换成 SWGlowScan：
//   • 要对**主 CTA / 品牌签名**吸引注意 —— 用 glowScan（垂直品牌色扫过）
//     而非 shimmer（对角白光）。两者色调 / 运动方向 / 语义完全不同。
//
// 使用：
//   RoundedRectangle(cornerRadius: 12)
//       .fill(BsColor.borderSubtle)
//       .frame(height: 60)
//       .shimmering()
//
// 可调参数：
//   • duration —— 默认 1.5s。如果列表密集（> 8 row），可缩到 1.2s 让
//     整屏节奏更统一；hero 大占位块可拉到 2.0s 显质感。
//   • highlightOpacity —— 默认 0.3（白光透明度）。dark mode 下
//     不透明度感知会下降，必要时在 dark 传 0.45 补偿。
//
// 性能：
//   • GeometryReader + withAnimation repeatForever —— 每块 skeleton
//     独立渲染，iPhone 12 以上一屏 20 块 shimmer 仍 60fps；
//     老机器（iPhone X 及以下）建议 skeleton 数 ≤ 8。
// ══════════════════════════════════════════════════════════════════

public struct SWShimmer: ViewModifier {
    @State private var phase: CGFloat = 0

    /// 一个扫光循环的总时长（秒）。默认 1.5s，对应"平静的 loading 心跳"。
    public let duration: Double
    /// 扫光高亮的白光不透明度。默认 0.3，dark mode 建议 0.45。
    public let highlightOpacity: Double

    public init(duration: Double = 1.5, highlightOpacity: Double = 0.3) {
        self.duration = duration
        self.highlightOpacity = highlightOpacity
    }

    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            .white.opacity(highlightOpacity),
                            .clear,
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + (geometry.size.width * 2 * phase))
                }
            )
            .mask(content)
            .onAppear {
                withAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

public extension View {
    /// Loading skeleton 对角线扫光。
    ///
    /// - Parameters:
    ///   - duration: 一次扫光的总时长，默认 1.5s。
    ///   - highlightOpacity: 扫光白光透明度，默认 0.3（dark mode 建议 0.45）。
    func shimmering(
        duration: Double = 1.5,
        highlightOpacity: Double = 0.3
    ) -> some View {
        self.modifier(SWShimmer(duration: duration, highlightOpacity: highlightOpacity))
    }
}
