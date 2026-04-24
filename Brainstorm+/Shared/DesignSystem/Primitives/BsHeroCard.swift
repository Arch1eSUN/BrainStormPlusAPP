import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsHeroCard — Signature 玻璃 Hero 卡（1 张/屏 的 signature moment）
//
// 用途：仅用于每屏最多一张的 signature moment（e.g. Dashboard 的
// 出勤 liquid-fill hero）。这是 v1.1 的 signature material。
//
// 与 BsCard(.glass) 的区别：
//   • BsCard(.glass)：常规 glass，stroke 是纯白 0.5 opacity
//   • BsHeroCard：顶部 1pt inset highlight（中心 1.0 → 边缘 0）
//     模拟光线扫过玻璃顶边 —— 这是 hero 的差异化 signature 元素
//
// Spec（docs/plans/2026-04-24-ios-full-redesign-plan.md §2.2 / §2.6）：
//   • Fill: iOS 26 原生 .glassEffect(.regular, in:)
//   • Radius: BsRadius.xl (22pt，iOS 26 widget 标准)
//   • Padding: 24 (hero 比 content card 更宽松 — §2.4)
//   • Shadow: BsShadow.glassCard，dark mode drop
//   • Top inset highlight: gradient 1.0 → 0 linearly
// ══════════════════════════════════════════════════════════════════

public struct BsHeroCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let content: Content

    @Environment(\.colorScheme) private var colorScheme

    public init(
        cornerRadius: CGFloat = BsRadius.xl,
        padding: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: shape)
            .overlay(
                // Signature inset top highlight — 1pt 光线扫过玻璃顶边
                shape
                    .inset(by: 0.5)
                    .stroke(
                        LinearGradient(
                            colors: [
                                BsColor.glassHighlight.opacity(0.95),
                                BsColor.glassHighlight.opacity(0.35),
                                BsColor.glassHighlight.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
            )
            .bsShadow(colorScheme == .dark ? BsShadow.none : BsShadow.glassCard)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        BsColor.pageBackground
            .ignoresSafeArea()

        BsHeroCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(BsColor.brandAzure)
                    Text("本月出勤")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BsColor.ink)
                    Spacer()
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("18")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(BsColor.ink)
                    Text("/ 22 天")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(BsColor.inkMuted)
                }

                Text("已完成 82%，继续保持")
                    .font(.system(size: 14))
                    .foregroundStyle(BsColor.inkMuted)
            }
        }
        .padding(20)
    }
}
