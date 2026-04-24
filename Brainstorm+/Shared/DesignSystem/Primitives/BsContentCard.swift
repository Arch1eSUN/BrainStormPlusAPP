import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsContentCard —— v1.1 日常内容卡（matte surface + hairline + light shadow）
//
// 设计定位（plan docs/plans/2026-04-24-ios-full-redesign-plan.md §2.2/§3.1）：
//   • Dashboard widgets / list rows / 任何 "dense content" 容器
//   • 取代 content 区域里被滥用的 .glassEffect —— 玻璃拟态会干扰阅读
//   • 对齐 iOS 26 home-screen widget 视觉（radius 22pt）
//
// 与 BsCard 的区别：
//   • BsCard = 通用卡片（flat / elevated / glass variant-switch）
//   • BsContentCard = v1.1 默认 "内容卡"，matte 一种形态，
//     light mode 有极轻阴影，dark mode 靠 border + 色阶做层级
//
// 视觉规格：
//   • Fill:   BsColor.surfacePrimary（light=white / dark=#2C2C2E）
//   • Border: BsColor.borderSubtle @ 0.5pt hairline
//   • Radius: BsRadius.xl (22pt) —— iOS 26 widget 标准
//   • Shadow: light-only, BsShadow.contentCard (0 2 8 black@4%)
//   • Padding: 20pt default，支持 none/small/medium/large
//
// Interaction：
//   • 传 onTap → 变成 Button，scale 0.97 + Haptic.light() 按压反馈
//   • 弹性使用 BsMotion.Anim.overshoot
// ══════════════════════════════════════════════════════════════════

public struct BsContentCard<Content: View>: View {
    public enum Padding {
        case none, small, medium, large
        public var value: CGFloat {
            switch self {
            case .none:   return 0
            case .small:  return 12
            case .medium: return 20
            case .large:  return 28
            }
        }
    }

    private let padding: Padding
    private let isInteractive: Bool
    private let onTap: (() -> Void)?
    private let content: Content

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed: Bool = false

    public init(
        padding: Padding = .medium,
        isInteractive: Bool = false,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.isInteractive = isInteractive
        self.onTap = onTap
        self.content = content()
    }

    public var body: some View {
        if let onTap {
            Button(action: onTap) {
                cardBody
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            Haptic.light()
                        }
                    }
                    .onEnded { _ in isPressed = false }
            )
        } else {
            cardBody
        }
    }

    // MARK: - Card body

    private var cardBody: some View {
        content
            .padding(padding.value)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BsColor.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                    .stroke(BsColor.borderSubtle, lineWidth: 0.5)
            )
            .bsShadow(shadowValues)
            .scaleEffect(pressScale)
            .animation(BsMotion.Anim.overshoot, value: isPressed)
            .contentShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
    }

    // MARK: - Computed

    /// Light mode: 极轻阴影强化浮起感；Dark mode: 无阴影，靠 border 做层级
    private var shadowValues: BsShadow.Values {
        colorScheme == .dark ? BsShadow.none : BsShadow.contentCard
    }

    /// 按压 scale —— 只在 isInteractive 或 onTap 存在时生效
    private var pressScale: CGFloat {
        let canPress = isInteractive || onTap != nil
        return (canPress && isPressed) ? 0.97 : 1.0
    }
}

// MARK: - Preview

#Preview("BsContentCard") {
    ScrollView {
        VStack(spacing: BsSpacing.lg) {
            // Static card, default padding
            BsContentCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("今日简报")
                        .font(.custom("Inter-SemiBold", size: 17))
                        .foregroundStyle(BsColor.ink)
                    Text("共 3 条待办 · 2 条需在今天完成")
                        .font(.custom("Inter-Regular", size: 14))
                        .foregroundStyle(BsColor.inkMuted)
                }
            }

            // Interactive card with tap handler
            BsContentCard(onTap: { print("tapped") }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("审批中心")
                            .font(.custom("Inter-SemiBold", size: 16))
                            .foregroundStyle(BsColor.ink)
                        Text("3 条待处理")
                            .font(.custom("Inter-Regular", size: 13))
                            .foregroundStyle(BsColor.inkMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BsColor.inkMuted)
                }
            }

            // Large padding hero card
            BsContentCard(padding: .large) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("本月绩效")
                        .font(.custom("Inter-SemiBold", size: 20))
                        .foregroundStyle(BsColor.ink)
                    Text("92.4")
                        .font(.custom("Inter-Bold", size: 36))
                        .foregroundStyle(BsColor.ink)
                    Text("相较上月 +4.1")
                        .font(.custom("Inter-Regular", size: 13))
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
        }
        .padding(BsSpacing.lg)
    }
    .background(BsColor.pageBackground)
}
