import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Semantic components — 频繁复用的片段，封装成 BsXXX 而不是每处手搓
// ══════════════════════════════════════════════════════════════════

// MARK: - BsFormField
// 标签（上）+ 输入区（下），focus 时 border 变 Azure + 1.5px
// 用于 LoginView / 提交 Sheet 等表单场景。

public struct BsFormField<Input: View>: View {
    private let label: String
    private let trailingLabel: String?
    private let trailingAction: (() -> Void)?
    private let isFocused: Bool
    private let errorMessage: String?
    private let input: () -> Input

    public init(
        label: String,
        trailingLabel: String? = nil,
        trailingAction: (() -> Void)? = nil,
        isFocused: Bool = false,
        errorMessage: String? = nil,
        @ViewBuilder input: @escaping () -> Input
    ) {
        self.label = label
        self.trailingLabel = trailingLabel
        self.trailingAction = trailingAction
        self.isFocused = isFocused
        self.errorMessage = errorMessage
        self.input = input
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs + 2) {
            HStack {
                Text(label)
                    .font(BsTypography.label)
                    // label 色彩跟随 focus 联动 —— focus 时从 inkMuted → brandAzure
                    .foregroundStyle(isFocused ? BsColor.brandAzure : BsColor.inkMuted)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Spacer()
                if let trailingLabel, let trailingAction {
                    Button(action: trailingAction) {
                        Text(trailingLabel)
                            .font(BsTypography.label)
                            .foregroundStyle(BsColor.brandAzure)
                    }
                    .buttonStyle(.plain)
                }
            }

            input()
                .font(BsTypography.body)
                .foregroundStyle(BsColor.ink)
                .padding(.horizontal, BsSpacing.md + 2)
                .padding(.vertical, BsSpacing.md + 2)
                .background(
                    RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                        .fill(BsColor.surfacePrimary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
                // 多维 focus 叠加:
                //   1. soft glow ring - 外发光,focus 时展开(blur 模糊成柔光)
                //   2. scale 微幅 1.0 → 1.006 - "elevated" 感
                //   3. 整体 spring 动画,拟真感替代线性切换
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.md + 3, style: .continuous)
                        .strokeBorder(BsColor.brandAzure.opacity(isFocused && errorMessage == nil ? 0.35 : 0), lineWidth: 3)
                        .blur(radius: 4)
                        .allowsHitTesting(false)
                        .padding(-2)
                )
                .scaleEffect(isFocused ? 1.006 : 1.0)

            if let errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                    Text(errorMessage)
                        .font(BsTypography.captionSmall)
                }
                .foregroundStyle(BsColor.danger)
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // spring 曲线更有弹性,取代之前的 standard spring
        .animation(BsMotion.Anim.overshoot, value: isFocused)
        .animation(BsMotion.Anim.smooth, value: errorMessage)
    }

    private var borderColor: Color {
        if errorMessage != nil { return BsColor.danger }
        if isFocused { return BsColor.brandAzure }
        return BsColor.borderDefault
    }

    private var borderWidth: CGFloat {
        (isFocused || errorMessage != nil) ? 1.5 : 1
    }
}

// MARK: - BsPageHeader
// Large Title 风格：大字标题 + 可选副标题。贴在 ScrollView 顶部。

public struct BsPageHeader: View {
    private let title: String
    private let subtitle: String?

    public init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            Text(title)
                .font(BsTypography.pageTitle)
                .foregroundStyle(BsColor.ink)
            if let subtitle {
                Text(subtitle)
                    .font(BsTypography.body)
                    .foregroundStyle(BsColor.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - BsSectionHeader
// 大写字 + 字距，对应 Web 的 section label（WORKSPACE / REPORTING）

public struct BsSectionHeader: View {
    private let title: String
    private let trailing: String?
    private let trailingAction: (() -> Void)?

    public init(
        _ title: String,
        trailing: String? = nil,
        trailingAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.trailing = trailing
        self.trailingAction = trailingAction
    }

    public var body: some View {
        HStack {
            Text(title.uppercased())
                .font(BsTypography.label)
                .foregroundStyle(BsColor.inkMuted)
                .tracking(1.2)
            Spacer()
            if let trailing, let trailingAction {
                Button(action: trailingAction) {
                    Text(trailing)
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.brandAzure)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - BsBadge
// Pill 式大写字徽章。

public struct BsBadge: View {
    private let text: String
    private let tone: Tone
    private let size: BadgeSize

    public enum Tone {
        case azure, mint, coral, ink, success, warning, danger, neutral
        var background: Color {
            switch self {
            case .azure:   return BsColor.brandAzure
            case .mint:    return BsColor.brandMint
            case .coral:   return BsColor.brandCoral
            case .ink:     return BsColor.ink
            case .success: return BsColor.success
            case .warning: return BsColor.warning
            case .danger:  return BsColor.danger
            case .neutral: return BsColor.neutral400
            }
        }
        var foreground: Color {
            switch self {
            case .mint: return BsColor.ink  // mint 底上用深文字
            default:    return .white
            }
        }
    }

    public enum BadgeSize {
        case small, medium
        var font: Font {
            switch self {
            case .small:  return Font.custom("Inter-Bold", size: 9)
            case .medium: return Font.custom("Inter-Bold", size: 11)
            }
        }
        var padding: (h: CGFloat, v: CGFloat) {
            switch self {
            case .small:  return (6, 3)
            case .medium: return (10, 5)
            }
        }
    }

    public init(_ text: String, tone: Tone = .azure, size: BadgeSize = .medium) {
        self.text = text
        self.tone = tone
        self.size = size
    }

    public var body: some View {
        Text(text.uppercased())
            .font(size.font)
            .tracking(0.6)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, size.padding.h)
            .padding(.vertical, size.padding.v)
            .background(Capsule().fill(tone.background))
    }
}

// MARK: - BsEmptyState
// 用 iOS 17+ ContentUnavailableView 的包装，统一 tint + 文案层级

public struct BsEmptyState: View {
    private let title: String
    private let systemImage: String
    private let description: String?

    public init(title: String, systemImage: String, description: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .foregroundStyle(BsColor.inkMuted)
        } description: {
            if let description {
                Text(description)
                    .font(BsTypography.body)
                    .foregroundStyle(BsColor.inkFaint)
            }
        }
    }
}

// MARK: - BsStatCard
// 大号数字 + 小标签，用于 Dashboard KPI 格子

public struct BsStatCard: View {
    private let value: String
    private let label: String
    private let tone: Color
    private let systemImage: String?

    public init(value: String, label: String, tone: Color = BsColor.brandAzure, systemImage: String? = nil) {
        self.value = value
        self.label = label
        self.tone = tone
        self.systemImage = systemImage
    }

    public var body: some View {
        BsCard(variant: .flat, padding: .medium) {
            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                HStack {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(tone)
                    }
                    Text(label.uppercased())
                        .font(BsTypography.meta)
                        .foregroundStyle(BsColor.inkMuted)
                        .tracking(0.8)
                }
                Text(value)
                    .font(BsTypography.statMedium)
                    .foregroundStyle(tone)
            }
        }
    }
}

// ══════════════════════════════════════════════════════════════════
// Motion modifiers
// ══════════════════════════════════════════════════════════════════

/// 进场 stagger —— 配合 index + isVisible 驱动的淡入 + 上移。
public struct BsStaggeredAppear: ViewModifier {
    let index: Int
    let isVisible: Bool
    let baseDelay: Double

    public init(index: Int, isVisible: Bool, baseDelay: Double = 0.05) {
        self.index = index
        self.isVisible = isVisible
        self.baseDelay = baseDelay
    }

    public func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 12)
            .animation(
                BsMotion.Anim.overshoot.delay(Double(index) * baseDelay),
                value: isVisible
            )
    }
}

public extension View {
    /// 进场 stagger 动画 —— 按 index 分次淡入上移。
    func staggeredAppear(index: Int, isVisible: Bool, baseDelay: Double = 0.05) -> some View {
        modifier(BsStaggeredAppear(index: index, isVisible: isVisible, baseDelay: baseDelay))
    }
}

/// 错误时触发的水平 shake 效果（登录失败等场景）。
/// 调用方维护一个 trigger 值，每次改值就 shake 一次。
public struct BsShakeModifier: ViewModifier, Animatable {
    public var animatableData: CGFloat

    public init(trigger: CGFloat) {
        self.animatableData = trigger
    }

    public func body(content: Content) -> some View {
        content.offset(x: sin(animatableData * .pi * 6) * 8)
    }
}

public extension View {
    /// 每次把 trigger 改成一个新值，就触发一次 shake。
    func bsShake(trigger: CGFloat) -> some View {
        modifier(BsShakeModifier(trigger: trigger))
    }
}
