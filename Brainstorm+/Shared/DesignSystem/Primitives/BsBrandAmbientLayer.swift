import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsBrandAmbientLayer —— 品牌签名 ambient 背景层
//
// 设计来源：audit 发现 SplashView + LoginView 两处复制了完全相同的
// azure + mint radial blob 背景 layer（~30 LOC 重复）。抽成单独
// primitive，两处共用。
//
// 用法：
//   ZStack {
//     BsBrandAmbientLayer()     // 铺底 azure/mint 氛围光
//     VStack { ... }            // 前景内容
//   }
//
// 视觉：
//   • BsColor.pageBackground 底
//   • 左上角 azure radial (opacity 0.22, radius 420)
//   • 右下角 mint radial (opacity 0.18, radius 420)
//   • 两团色晕 blur + 无 hit-testing
//
// 这只用在"品牌签名瞬间"（Splash / Login / 其他入场页），不用在
// 日常 tab 页（v1.1 弥散彻底退出日常页 per §2.1）。
// ══════════════════════════════════════════════════════════════════

public struct BsBrandAmbientLayer: View {
    /// azure blob 的 opacity（0-1）。默认 0.22。
    let azureOpacity: CGFloat
    /// mint blob 的 opacity。默认 0.18。
    let mintOpacity: CGFloat

    public init(azureOpacity: CGFloat = 0.22, mintOpacity: CGFloat = 0.18) {
        self.azureOpacity = azureOpacity
        self.mintOpacity = mintOpacity
    }

    public var body: some View {
        ZStack {
            BsColor.pageBackground.ignoresSafeArea()

            RadialGradient(
                colors: [BsColor.brandAzure.opacity(azureOpacity), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [BsColor.brandMint.opacity(mintOpacity), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        BsBrandAmbientLayer()
        VStack {
            Text("品牌签名氛围层")
                .font(BsTypography.largeTitle)
                .foregroundStyle(BsColor.ink)
        }
    }
}
