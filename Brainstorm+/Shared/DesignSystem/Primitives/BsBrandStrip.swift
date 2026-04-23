import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsBrandStrip —— 品牌锚点，Dashboard 顶部常驻
//
// 像 Apple Fitness 的"活动"页顶部那条"活动 / 历史"+日期条，BrainStorm+ 版：
//   • Logo 32pt + BrainStorm+ wordmark（Outfit Bold Azure→Mint 线性渐变）
//   • 右侧可选副信息（如当前用户/日期）
//
// 在 Dashboard Large Title 之上，告诉用户"你在 BrainStorm+"。
// 5 个 tab 的工作台永远有这条；切 tab 到 Tasks/Approvals/Chat 会消失，
// 回到 Dashboard 就显回——品牌锚点专属工作台。
// ══════════════════════════════════════════════════════════════════

public struct BsBrandStrip: View {
    let subtitle: String?

    public init(subtitle: String? = nil) {
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(spacing: BsSpacing.sm) {
            // Logo
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)

            // Wordmark with Azure→Mint gradient
            Text("BrainStorm+")
                .font(.custom("Outfit-Bold", size: 18))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BsColor.brandAzure, BsColor.brandMint],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .tracking(-0.3)

            Spacer()

            if let subtitle {
                Text(subtitle)
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkMuted)
            }
        }
        .padding(.horizontal, BsSpacing.lg)
        .padding(.vertical, BsSpacing.sm)
    }
}
