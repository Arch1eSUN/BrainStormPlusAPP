import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsCard — 平铺白卡（iOS 原生惯例）
//
// 默认 variant = .flat：
//   • surfacePrimary 底 + hairline border + radius 16
//   • 无 shadow（iOS 不靠 elevation 制造层次，靠 List/Section 留白）
//
// Glass variant 仅用于真正的"悬浮 UI"：
//   • 贴底 sticky bar / 顶部 material nav bar / context menu
//   • LoginView / 正常内容 请用 .flat
//
// Subcomponents: BsCardHeader / BsCardTitle / BsCardBody
// ══════════════════════════════════════════════════════════════════

/// v1.1 legacy —— 优先使用专用 primitive：
///   • `BsContentCard` 替代 `.flat` / `.elevated`
///   • `BsHeroCard` 替代 `.glass`（签名瞬间）
/// 本 variant-switch API 保留至 call-sites 全部迁移完毕后删除。
@available(*, deprecated, message: "Use BsContentCard for matte; BsHeroCard for Liquid Glass signature. Migration tracked in docs/plans/2026-04-24-ios-polish-audit.md Batch 1.")
public struct BsCard<Content: View>: View {
    public enum Variant {
        /// Flat white 卡片（iOS 默认）—— hairline border，无阴影
        case flat
        /// 需要轻微浮起的卡片（例如底部 pinned CTA 区域），带 sm 阴影
        case elevated
        /// 玻璃拟态 —— ultraThinMaterial + hairline，只给真·悬浮 UI
        case glass
    }

    public enum Padding {
        case none, small, medium, large
        public var value: CGFloat {
            switch self {
            case .none:   return 0
            case .small:  return BsSpacing.md
            case .medium: return BsSpacing.lg + 4  // 20
            case .large:  return BsSpacing.xl + 4  // 28
            }
        }
    }

    private let variant: Variant
    private let padding: Padding
    private let content: Content

    public init(
        variant: Variant = .flat,
        padding: Padding = .medium,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        switch variant {
        case .flat, .elevated:
            content
                .padding(padding.value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BsColor.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
                .bsShadow(shadowValues)
        case .glass:
            // iOS 26 真·Liquid Glass 材质 — 不再是手搓 ultraThinMaterial
            content
                .padding(padding.value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        }
    }

    private var cornerRadius: CGFloat {
        variant == .glass ? BsRadius.xl : BsRadius.lg
    }

    private var borderColor: Color {
        variant == .glass ? Color.white.opacity(0.5) : BsColor.borderSubtle
    }

    private var borderWidth: CGFloat {
        variant == .glass ? 1 : 0.5
    }

    private var shadowValues: BsShadow.Values {
        switch variant {
        case .flat:     return BsShadow.none
        case .elevated: return BsShadow.sm
        case .glass:    return BsShadow.md
        }
    }
}

// MARK: - Subcomponents

public struct BsCardHeader<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        HStack(spacing: BsSpacing.md) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, BsSpacing.md)
    }
}

public struct BsCardTitle: View {
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(BsTypography.cardTitle)
            .foregroundStyle(BsColor.ink)
    }
}

public struct BsCardBody<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content
            .font(BsTypography.body)
            .foregroundStyle(BsColor.inkMuted)
    }
}
