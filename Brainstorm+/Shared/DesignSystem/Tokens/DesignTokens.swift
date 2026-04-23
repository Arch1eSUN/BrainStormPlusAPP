import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// ══════════════════════════════════════════════════════════════════
// BrainStorm+ iOS Design Tokens
//
// • 色彩 light/dark 双值（Color.dynamic），全站自动 respect colorScheme
// • 几何 + 间距 + 阴影走统一 token，业务代码不写 raw 数字
// • Outfit 字体留"品牌印章"场景（大标题、Dashboard 欢迎）
//   正文 UI 默认用 Inter；极细处（tab bar / segmented 等系统组件）走 .system
//
// 参考：
//   Web tokens: BrainStorm+-Web/src/design-system/brainstorm-plus/tokens/*
//   iOS 原生 HIG 模式 + Slack/Claude/Samurai+ 的语言
// ══════════════════════════════════════════════════════════════════

// MARK: - Color

public enum BsColor {
    // Brand accents — 按 logo 实际像素采样值（PIL 量化）：
    //   Azure  #0080F0（主色约 55%）—— 保留 #0080FF
    //   Cyan   #30C0D0（蓝偏青，约 30%）—— 旧 #00E5CC 是绿偏青，跟 logo 不符
    //   Coral  #F07050（小三角尖约 15%）—— 保留 #FF6B42
    //
    // brandMint (light) 读起来浅、蓝偏、可视；
    // brandMintDark 用于必须在白底上有可读对比度的文字/图标场景（WCAG AA）。
    public static let brandAzure      = Color(hex: "#0080FF")
    public static let brandAzureLight = Color(hex: "#E0F0FF")
    public static let brandAzureDark  = Color(hex: "#0060CC")
    public static let brandMint       = Color(hex: "#2DB8D4")  // 蓝偏青，对齐 logo
    public static let brandMintLight  = Color(hex: "#D6F0F6")  // 浅版，tile bg 用
    public static let brandMintDark   = Color(hex: "#0E7A93")  // 深版，白底文字/icon 可读
    public static let brandCoral      = Color(hex: "#FF6B42")
    public static let brandCoralDark  = Color(hex: "#C24A26")  // 深版，白底文字可读

    // 语义色 — 全部 light/dark 双值，自动适配 Dark Mode
    public static let ink              = dynamic(light: "#1B1B18", dark: "#F8FAFC")
    public static let inkMuted         = dynamic(light: "#6B6B68", dark: "#94A3B8")
    public static let inkFaint         = dynamic(light: "#A1A1AA", dark: "#64748B")

    // Phase 21 校准：弥散退出日常页，主导切流体。pageBackground 回 iOS 原生
    // systemGroupedBackground 的等效值 —— 神经色干净灰，玻璃卡在灰底上显形。
    // 弥散只保留给签名瞬间（Login / Dashboard hero / 成功 ripple），不做全页弥散。
    public static let pageBackground   = dynamic(light: "#F2F2F7", dark: "#000000")
    public static let surfacePrimary   = dynamic(light: "#FFFFFF", dark: "#141B26")
    public static let surfaceSecondary = dynamic(light: "#FAFAF7", dark: "#1A2332")
    public static let surfaceTertiary  = dynamic(light: "#FDFDFC", dark: "#1F2937")

    // Web glass tokens —— 半透材质，配合 .glassEffect(.regular) 或手搓 overlay
    // 镜像 Web --color-surface-card / --color-surface-warm / --color-glass-border。
    public static let surfaceGlass     = Color.white.opacity(0.55)
    public static let surfaceGlassWarm = Color(hex: "#FFFCF8").opacity(0.60)
    public static let glassBorder      = Color.white.opacity(0.65)
    public static let glassHighlight   = Color.white.opacity(1.0)   // 用于 inset 顶部 1px 高光

    public static let borderSubtle     = dynamic(light: "#00000014", dark: "#FFFFFF14") // 约 0.08
    public static let borderDefault    = dynamic(light: "#E5E7EB",   dark: "#2A374B")
    public static let borderStrong     = dynamic(light: "#D4D4D8",   dark: "#3F3F46")

    // 品牌反转按钮的背景：light 下是近黑 ink，dark 下反转为近白
    public static let buttonInk        = dynamic(light: "#1B1B18", dark: "#F8FAFC")
    public static let buttonInkText    = dynamic(light: "#FFFFFF", dark: "#0A0E17")

    // 静态（不随 dark mode 变）
    public static let paper     = Color(hex: "#FDFDFC")
    public static let inkStatic = Color(hex: "#1B1B18")

    // 语义状态
    public static let success = Color(hex: "#10B981")
    public static let warning = Color(hex: "#F59E0B")
    public static let danger  = Color(hex: "#EF4444")
    public static let info    = Color(hex: "#06B6D4")

    // Neutral 梯度（跨 light/dark，直接用原值）
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

    /// 同一个语义，light / dark 两个 hex，自动切换。
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
// impeccable.md §Aesthetic: 禁用直角 cornerRadius(0)。`none=0` 留 token 表完整性但不用。

public enum BsRadius {
    public static let none: CGFloat = 0
    public static let xs:   CGFloat = 4   // chip / 小 badge
    public static let sm:   CGFloat = 8   // tag / 细节
    public static let md:   CGFloat = 12  // input / small button / list row
    public static let lg:   CGFloat = 16  // card / large button
    public static let xl:   CGFloat = 24  // sheet / modal / signature glass card (Web: --radius-xl)
    public static let xxl:  CGFloat = 28  // 品牌 hero
    public static let full: CGFloat = 9999
}

// MARK: - Spacing — 4px 基准

public enum BsSpacing {
    public static let px: CGFloat  = 1
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat  = 4
    public static let sm: CGFloat  = 8
    public static let md: CGFloat  = 12
    public static let lg: CGFloat  = 16
    public static let xl: CGFloat  = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
    public static let xxxxl: CGFloat = 64
}

// MARK: - Shadow
// iOS 用得克制 — 默认 card 不给阴影（靠 hairline border）
// 只有真正悬浮的（sticky bar / sheet / toast）才上。

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

    // Web card signature shadow：0 8px 32px -8px rgba(0,0,0,0.08) — 偏柔的下沉感
    public static let glassCard       = Values(color: .black.opacity(0.08), radius: 32, x: 0, y: 8)
    public static let glassCardHover  = Values(color: .black.opacity(0.12), radius: 48, x: 0, y: 16)
}

// MARK: - Motion

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

    /// 标准动画曲线 —— 大部分场景直接用这几个
    public enum Anim {
        /// 默认反馈 / focus / press —— 弹性克制
        public static let standard: Animation = .spring(response: 0.35, dampingFraction: 0.85)
        /// 微反馈 —— 按键、segmented 切换
        public static let snappy: Animation   = .snappy(duration: 0.25)
        /// Press 效果 —— 短促 bounce
        public static let microBounce: Animation = .interpolatingSpring(stiffness: 300, damping: 20)
        /// 透明度 / 颜色过渡
        public static let smooth: Animation   = .easeInOut(duration: 0.3)
        /// 背景慢淡入
        public static let gentle: Animation   = .easeInOut(duration: 0.5)
        /// 入场弹出
        public static let entrance: Animation = .spring(response: 0.4, dampingFraction: 0.8)
        /// Overshoot 弹性 —— 对齐 Web cubic-bezier(0.34, 1.56, 0.64, 1)
        /// dampingFraction < 0.7 会有回弹；0.62 模拟 Web 的 1.56 overshoot
        public static let overshoot: Animation = .spring(response: 0.5, dampingFraction: 0.62)
    }
}

// MARK: - Typography
// Outfit 是品牌印章（Large Title / 品牌瞬间），Inter 是工作字体（UI 95% 场景）
// 超小 meta / stat number 可选 .system(.rounded) 以对齐 iOS 数字风

public enum BsTypography {
    // 品牌瞬间（登录 / Dashboard 欢迎 / hero title）
    public static let brandDisplay  = Font.custom("Outfit-Bold",     size: 32)
    public static let brandTitle    = Font.custom("Outfit-Bold",     size: 26)
    public static let brandWordmark = Font.custom("Outfit-Bold",     size: 22)

    // 页面结构
    public static let pageTitle     = Font.custom("Outfit-Bold",     size: 28)
    public static let sectionTitle  = Font.custom("Outfit-SemiBold", size: 20)

    // 卡片 / 正文（Inter 主力）
    public static let cardTitle     = Font.custom("Inter-SemiBold",  size: 17)
    public static let cardSubtitle  = Font.custom("Inter-Medium",    size: 15)
    public static let body          = Font.custom("Inter-Regular",   size: 15)
    public static let bodyMedium    = Font.custom("Inter-Medium",    size: 15)
    public static let bodySmall     = Font.custom("Inter-Regular",   size: 14)

    // Caption / Label / Meta
    public static let caption       = Font.custom("Inter-Medium",    size: 13)
    public static let captionSmall  = Font.custom("Inter-Medium",    size: 12)
    public static let label         = Font.custom("Inter-SemiBold",  size: 11) // UPPER 用
    public static let meta          = Font.custom("Inter-Bold",      size: 10) // UPPER 用

    // 数字（KPI / 金额）— 圆体更顺，iOS 惯例
    public static let statLarge     = Font.system(size: 34, weight: .bold, design: .rounded)
    public static let statMedium    = Font.system(size: 26, weight: .bold, design: .rounded)
    public static let statSmall     = Font.system(size: 18, weight: .semibold, design: .rounded)

    // 逃生舱 —— 必要时手指定 size + weight
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
