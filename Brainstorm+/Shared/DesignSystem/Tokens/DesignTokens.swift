import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// ══════════════════════════════════════════════════════════════════
// BrainStorm+ iOS Design Tokens  —— v1.1（2026-04-24 评审采纳版）
//
// 设计哲学：**飞书/钉钉 工作台骨架 + iOS 26 Liquid Glass 材质 +
//           Linear 排版纪律 + Web DNA 血脉**
//
// v1.1 评审采纳：
//   • Coral 单岗 —— 仅 admin 身份（不再背"警示"职责）
//   • 紧急/错误 走 iOS 系统 `.red`（不走品牌色）
//   • Mint 合并 success —— 所有"完成态"一律 Mint
//   • NavBar wordmark 16pt → 18pt（品牌瞬间更醒目）
//   • Dark mode 用深灰 #1C1C1E（不用纯黑）
//
// 参考：
//   docs/plans/2026-04-24-ios-full-redesign-plan.md §二·设计拍板
//   Web tokens: BrainStorm+-Web/src/design-system/brainstorm-plus/tokens/*
// ══════════════════════════════════════════════════════════════════

// MARK: - Color

public enum BsColor {
    // ── Brand accents（v1.1 三色一岗位）──────────────────────────
    //
    // Azure = 主交互 (CTA / link / selected / focus)
    // Mint  = 完成态 (成功 / 已打卡 / 已审批 / 已完成)
    // Coral = 管理身份 (admin tile / superadmin badge)
    //
    // 每个品牌色有 BG / Text 两个变种：
    //   • BG 色（品牌主色）—— 用于 tile 底、icon 背景、tint overlay
    //   • Text 色（深版）—— 用于白底/黑底 4.5:1 WCAG AA 文字对比度

    public static let brandAzure      = dynamic(light: "#0080FF", dark: "#3D9FFF")
    public static let brandAzureLight = Color(hex: "#E0F0FF")               // tile tint bg（静态）
    public static let brandAzureDark  = dynamic(light: "#0060CC", dark: "#0060CC") // 深版文字/icon

    public static let brandMint       = dynamic(light: "#2DB8D4", dark: "#5CCDE0")
    public static let brandMintLight  = Color(hex: "#D6F0F6")               // tile tint bg（静态）
    public static let brandMintDark   = dynamic(light: "#0E7A93", dark: "#7AD5E0") // 深版文字（= brandMintText）
    /// v1.1 alias —— 完成态文字/icon 白底黑底均 WCAG AA 读
    public static let brandMintText   = brandMintDark

    public static let brandCoral      = dynamic(light: "#FF6B42", dark: "#FF8660")
    public static let brandCoralDark  = dynamic(light: "#C24A26", dark: "#FF9D7A") // 深版文字（= brandCoralText）
    /// v1.1 alias —— 管理身份文字/icon 白底黑底均 WCAG AA 读
    public static let brandCoralText  = brandCoralDark

    // ── 语义文字 ────────────────────────────────────────────────
    public static let ink              = dynamic(light: "#1B1B18", dark: "#F5F5F7")
    public static let inkMuted         = dynamic(light: "#6B6B68", dark: "#A0A0A5")
    public static let inkFaint         = dynamic(light: "#A1A1AA", dark: "#6B6B70")

    // ── 页面 / 表面 ──────────────────────────────────────────────
    // v1.1: dark 用深灰 #1C1C1E（iOS systemGroupedBackground 深色等效），不是纯黑。
    public static let pageBackground   = dynamic(light: "#F2F2F7", dark: "#1C1C1E")
    public static let surfacePrimary   = dynamic(light: "#FFFFFF", dark: "#2C2C2E")
    public static let surfaceSecondary = dynamic(light: "#FAFAF7", dark: "#1A2332")
    public static let surfaceTertiary  = dynamic(light: "#FDFDFC", dark: "#1F2937")

    // ── Glass 材质 ───────────────────────────────────────────────
    // iOS 26 有原生 .glassEffect(.regular)；以下 token 用于手搓 overlay 场景（BsHeroCard inset top highlight）。
    public static let surfaceGlass     = Color.white.opacity(0.55)
    public static let surfaceGlassWarm = Color(hex: "#FFFCF8").opacity(0.60)
    public static let glassBorder      = Color.white.opacity(0.65)
    public static let glassHighlight   = Color.white.opacity(1.0)

    // ── 边框 ─────────────────────────────────────────────────────
    public static let borderSubtle     = dynamic(light: "#00000014", dark: "#FFFFFF14") // ~8%
    public static let borderDefault    = dynamic(light: "#E5E7EB",   dark: "#2A374B")
    public static let borderStrong     = dynamic(light: "#D4D4D8",   dark: "#3F3F46")

    // ── 反转按钮 ─────────────────────────────────────────────────
    public static let buttonInk        = dynamic(light: "#1B1B18", dark: "#F5F5F7")
    public static let buttonInkText    = dynamic(light: "#FFFFFF", dark: "#0A0E17")

    // ── 静态色 ───────────────────────────────────────────────────
    public static let paper     = Color(hex: "#FDFDFC")
    public static let inkStatic = Color(hex: "#1B1B18")

    // ── 语义状态（v1.1: 错误/警告走 iOS semantic，完成走 brandMint）───
    /// v1.1: 所有"成功/完成"合并到 brandMint，`success` 作为 alias 保留向后兼容
    public static let success = brandMint
    /// v1.1: 警告仍走 iOS 语义橙黄
    public static let warning = Color(hex: "#F59E0B")
    /// v1.1: 紧急/错误走 iOS 系统 red（而非品牌 Coral）
    public static let danger  = Color(hex: "#EF4444")
    public static let info    = brandAzure

    // ── Neutral 梯度（静态）──────────────────────────────────────
    public static let neutral50  = Color(hex: "#FAFAFA")
    public static let neutral100 = Color(hex: "#F4F4F5")
    public static let neutral200 = Color(hex: "#E4E4E7")
    public static let neutral300 = Color(hex: "#D4D4D8")
    public static let neutral400 = Color(hex: "#A1A1AA")
    public static let neutral500 = Color(hex: "#71717A")
    public static let neutral600 = Color(hex: "#52525B")
    public static let neutral700 = Color(hex: "#3F3F46")
    public static let neutral800 = Color(hex: "#27272A")
    public static let neutral900 = Color(hex: "#18181B")

    /// 同一语义 light/dark 两个 hex，UIColor 走 trait-based 自动切换。
    public static func dynamic(light: String, dark: String) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { trait in
            (UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light) ?? .black)
        })
        #else
        Color(hex: light)
        #endif
    }
}

// MARK: - Radius
// v1.1: xl = 22pt（iOS 26 widget 标准，对齐 Home Screen widget）
//        —— Web 用 24pt，iOS 26 widget 22pt，取 22 折中更贴原生手感。

public enum BsRadius {
    public static let none: CGFloat = 0
    public static let xs:   CGFloat = 4   // chip / 小 badge
    public static let sm:   CGFloat = 8   // tag / 细节
    public static let md:   CGFloat = 12  // input / small button / list row / app tile
    public static let lg:   CGFloat = 16  // card / large button
    public static let xl:   CGFloat = 22  // widget / signature glass card（iOS 26 widget 标准）
    public static let xxl:  CGFloat = 28  // 品牌 hero 极限
    public static let full: CGFloat = 9999
}

// MARK: - Spacing — 4px 基准

public enum BsSpacing {
    public static let xs: CGFloat  = 4
    public static let sm: CGFloat  = 8
    public static let md: CGFloat  = 12
    public static let lg: CGFloat  = 16
    public static let xl: CGFloat  = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

// MARK: - Shadow
// iOS 用得克制 —— 默认 card 不给阴影（靠 hairline border）
// 只有真正悬浮（sticky bar / sheet / toast）+ light mode content card 才上。
// Dark mode content card 不带 shadow（靠 border + 色阶）。

public enum BsShadow {
    public struct Values: Sendable {
        public let color: Color
        public let radius: CGFloat
        public let x: CGFloat
        public let y: CGFloat
    }

    public static let none  = Values(color: .clear, radius: 0, x: 0, y: 0)
    public static let xs    = Values(color: .black.opacity(0.02), radius: 1,  x: 0, y: 1)
    public static let sm    = Values(color: .black.opacity(0.04), radius: 4,  x: 0, y: 2)
    public static let md    = Values(color: .black.opacity(0.06), radius: 8,  x: 0, y: 4)
    public static let lg    = Values(color: .black.opacity(0.08), radius: 16, x: 0, y: 6)
    public static let xl    = Values(color: .black.opacity(0.12), radius: 30, x: 0, y: 20)
    public static let glow  = Values(color: BsColor.brandMint.opacity(0.20), radius: 40, x: 0, y: 0)

    /// v1.1 内容卡默认阴影（light mode 才上，dark mode 走 .none）
    public static let contentCard      = Values(color: .black.opacity(0.04), radius: 8,  x: 0, y: 2)
    /// 签名 hero glass card（Web 对齐：0 8px 32px -8px rgba(0,0,0,0.08)）
    public static let glassCard        = Values(color: .black.opacity(0.08), radius: 32, x: 0, y: 8)
    public static let glassCardHover   = Values(color: .black.opacity(0.12), radius: 48, x: 0, y: 16)
}

// MARK: - Motion
// v1.1: 只留 2 条曲线主线 —— `overshoot`（交互反馈）+ `smooth`（透明度过渡）
// 其他曲线保留为 deprecated alias，下个 refactor 清理。

public enum BsMotion {
    public enum Duration {
        public static let instant: Double = 0
        public static let fast: Double    = 0.16
        public static let normal: Double  = 0.26
        public static let slow: Double    = 0.42
        public static let fluid: Double   = 0.60
    }

    /// 旧名，保持兼容；新代码直接用 `Anim`
    public typealias Animations = Anim

    /// v1.1 只 2 条曲线：
    ///   • `overshoot` —— 所有交互反馈（press / focus / tap）
    ///   • `smooth`    —— 透明度 / 颜色过渡
    ///
    /// 其余曲线标 deprecated alias，behavior 指向 overshoot 或 smooth，
    /// 下一轮 refactor（Phase 6 打磨）集中清理 call-site。
    public enum Anim {
        /// v1.1 主线 · 交互反馈弹性
        /// Spring response 0.5 + dampingFraction 0.62 模拟 Web cubic-bezier(0.34, 1.56, 0.64, 1)
        public static let overshoot: Animation = .spring(response: 0.5, dampingFraction: 0.62)

        /// v1.1 主线 · 透明度 / 颜色过渡
        public static let smooth: Animation    = .easeInOut(duration: 0.3)

        /// Deprecated —— 指向 overshoot，下轮清理
        @available(*, deprecated, renamed: "overshoot")
        public static let standard: Animation  = overshoot
        @available(*, deprecated, renamed: "overshoot")
        public static let snappy: Animation    = overshoot
        @available(*, deprecated, renamed: "overshoot")
        public static let microBounce: Animation = overshoot
        @available(*, deprecated, renamed: "overshoot")
        public static let entrance: Animation  = overshoot

        /// Deprecated —— 指向 smooth，下轮清理
        @available(*, deprecated, renamed: "smooth")
        public static let gentle: Animation    = .easeInOut(duration: 0.5)
    }
}

// MARK: - Typography
// v1.1: 5 级 + wordmark(18pt) + heroNumber(Outfit 48pt) + 时间（SF Pro rounded）
//
// 3 字家各守其岗（不交叉）：
//   • Outfit     —— 品牌印章（Wordmark 18pt + HeroNumber 48pt 唯 2 处）
//   • Inter      —— Body + Caption（Web DNA 主力）
//   • SF Pro     —— Large Title / Section Title / 时间数字（.rounded）
//
// Phase 7 Dynamic Type：所有 Inter / Outfit 自定义字体都带 `relativeTo:`，
// 让用户系统字体放大（辅助功能 / 大型文本）时自动跟随缩放；SF Pro 的
// `Font.system` 和 `.rounded` 天然 scale。关键：Hero 数字 48pt 也应 scale，
// 但为避免 Attendance 卡布局被挤爆，在卡内部本地用 dynamicTypeSize clamp。

public enum BsTypography {
    // ── 品牌印章 (Outfit) —— v1.1 仅 2 处 ─────────────────────────
    /// NavBar wordmark "BrainStorm+" —— v1.1 16pt → 18pt 更醒目
    public static let brandWordmark = Font.custom("Outfit-Bold", size: 18, relativeTo: .headline)
    /// Hero 数字（Attendance 液体卡 / 签名瞬间 48pt）
    public static let heroNumber    = Font.custom("Outfit-Bold", size: 48, relativeTo: .largeTitle)

    // ── 页面结构 (SF Pro 原生) ──────────────────────────────────
    /// iOS 原生 Large Title —— 直接用 SwiftUI .largeTitle，完全 Dynamic Type
    public static let largeTitle    = Font.system(.largeTitle, design: .default, weight: .bold)
    /// 卡标题 / 分区 title 20pt SemiBold —— 挂 .title3 栅格（20pt）
    public static let sectionTitle  = Font.system(.title3, design: .default, weight: .semibold)

    // ── Body / Caption (Inter) —— Web DNA 主力 ───────────────────
    public static let body          = Font.custom("Inter-Regular",   size: 15, relativeTo: .body)
    public static let bodyMedium    = Font.custom("Inter-Medium",    size: 15, relativeTo: .body)
    public static let bodySmall     = Font.custom("Inter-Regular",   size: 14, relativeTo: .subheadline)
    public static let cardTitle     = Font.custom("Inter-SemiBold",  size: 17, relativeTo: .headline)
    public static let cardSubtitle  = Font.custom("Inter-Medium",    size: 15, relativeTo: .body)
    public static let caption       = Font.custom("Inter-Medium",    size: 12, relativeTo: .caption)
    public static let captionSmall  = Font.custom("Inter-Medium",    size: 11, relativeTo: .caption2)
    /// UPPERCASE label 场景（"WORKSPACE" style，Web DNA）
    public static let label         = Font.custom("Inter-SemiBold",  size: 11, relativeTo: .caption2)
    public static let meta          = Font.custom("Inter-Bold",      size: 10, relativeTo: .caption2)

    // ── 时间 / KPI 数字 (SF Pro .rounded + monospaced) ───────────
    public static let statLarge     = Font.system(.largeTitle, design: .rounded, weight: .bold)
    public static let statMedium    = Font.system(.title, design: .rounded, weight: .bold)
    public static let statSmall     = Font.system(.title3, design: .rounded, weight: .semibold)

    // ── 旧命名兼容（deprecated，指向新 token）────────────────────
    /// 登录 / 大 hero —— 指向 heroNumber（48pt）
    public static let brandDisplay  = heroNumber
    /// 旧页面 title —— 指向 largeTitle（34pt）
    public static let brandTitle    = Font.custom("Outfit-Bold", size: 26, relativeTo: .title)
    /// 旧页面 title —— 指向 SF Pro largeTitle
    public static let pageTitle     = largeTitle

    // ── 逃生舱 —— 必要时手指定 size + weight ────────────────────
    public static func outfit(_ size: CGFloat, weight: String = "Bold") -> Font {
        Font.custom("Outfit-\(weight)", size: size)
    }
    public static func inter(_ size: CGFloat, weight: String = "Regular") -> Font {
        Font.custom("Inter-\(weight)", size: size)
    }
}

// MARK: - Shadow helper

public extension View {
    /// 在 BsShadow 的 Values 上套一层 one-liner。
    func bsShadow(_ values: BsShadow.Values) -> some View {
        shadow(color: values.color, radius: values.radius, x: values.x, y: values.y)
    }
}

// UIColor(hex:) 已在 Shared/Theme/Color+Theme.swift 有定义（failable init?）
// 这里不再重复声明，dynamic() 里用 ?? .black 兜底 nil。
