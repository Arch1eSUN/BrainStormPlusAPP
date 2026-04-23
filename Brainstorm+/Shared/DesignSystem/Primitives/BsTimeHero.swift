import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsTimeHero —— Dashboard 顶部时间驱动的品牌色弥散条
//
// 唯一允许强弥散的日常页位置：Dashboard 首屏 Large Title 正下方
// ~140pt 高的氛围条。色配随时间变：
//
//   • 早晨 5-11：偏 Mint 青 + Azure 淡 —— "清新"
//   • 正午 11-14：Coral 暖 + Mint 青 —— "阳光"
//   • 傍晚 14-18：Azure + 少量 Coral —— "日落"
//   • 夜晚 18-23：Azure 深 + Mint 冷 —— "暮色"
//   • 深夜 23-5：Azure 深 + Ink —— "夜深"
//
// 用 iOS 18+ 的 MeshGradient（可用时）或 Linear+Radial 叠加 fallback。
// 饱和度 40-60%（不是 5% 的假弥散，也不是 100% 的花）。
// 固定在 List Section 0 —— 滚动时跟着走，但 NavBar Large Title 覆盖会
// 自然过场。
// ══════════════════════════════════════════════════════════════════

public struct BsTimeHero: View {
    let height: CGFloat

    public init(height: CGFloat = 140) {
        self.height = height
    }

    private var moodColors: [Color] {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11:   // 早晨：青 + azure 淡
            return [
                BsColor.brandMint.opacity(0.55),
                BsColor.brandAzure.opacity(0.35),
                BsColor.brandMintLight.opacity(0.4)
            ]
        case 11..<14:  // 正午：橙 + 青
            return [
                BsColor.brandCoral.opacity(0.45),
                BsColor.brandMint.opacity(0.40),
                BsColor.brandAzureLight.opacity(0.35)
            ]
        case 14..<18:  // 下午：Azure + Coral
            return [
                BsColor.brandAzure.opacity(0.50),
                BsColor.brandCoral.opacity(0.35),
                BsColor.brandMint.opacity(0.30)
            ]
        case 18..<23:  // 傍晚：Azure 深 + Mint
            return [
                BsColor.brandAzureDark.opacity(0.45),
                BsColor.brandAzure.opacity(0.40),
                BsColor.brandMint.opacity(0.25)
            ]
        default:       // 深夜：Azure 深 + Ink
            return [
                BsColor.brandAzureDark.opacity(0.55),
                BsColor.brandAzure.opacity(0.30),
                BsColor.ink.opacity(0.20)
            ]
        }
    }

    public var body: some View {
        ZStack {
            // 底色：3 色径向渐变叠加（mesh 效果 fallback）
            GeometryReader { proxy in
                ZStack {
                    // 色 1 左上
                    Circle()
                        .fill(moodColors[0])
                        .frame(
                            width: proxy.size.width * 1.1,
                            height: proxy.size.width * 1.1
                        )
                        .blur(radius: 60)
                        .offset(
                            x: -proxy.size.width * 0.35,
                            y: -proxy.size.height * 0.4
                        )

                    // 色 2 右
                    Circle()
                        .fill(moodColors[1])
                        .frame(
                            width: proxy.size.width * 0.95,
                            height: proxy.size.width * 0.95
                        )
                        .blur(radius: 55)
                        .offset(
                            x: proxy.size.width * 0.3,
                            y: proxy.size.height * 0.1
                        )

                    // 色 3 中下
                    Circle()
                        .fill(moodColors[2])
                        .frame(
                            width: proxy.size.width * 0.85,
                            height: proxy.size.width * 0.85
                        )
                        .blur(radius: 50)
                        .offset(
                            x: 0,
                            y: proxy.size.height * 0.55
                        )
                }
            }

            // 底部柔淡渐变 —— 让 hero 条的下边沿自然过渡到 pageBackground
            LinearGradient(
                colors: [.clear, BsColor.pageBackground.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: height)
        .clipped()
        .allowsHitTesting(false)
    }
}
