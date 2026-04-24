import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsBrand —— 品牌浓度 primitives
//
// 对齐 Web sidebar / section accent / hero 数字的品牌渐变习惯，
// 把 BrainStorm+ 的 Azure→Mint "签名"散布到每张卡、每个 hero、每个
// Large Title 的名字处。单独一个文件方便全局统一调调。
// ══════════════════════════════════════════════════════════════════

// MARK: - Brand gradient —— 按 logo 实际配比
//
// Logo 真实配比（量过）：
//   • Azure 蓝 ~55%   —— 主体
//   • Mint 青  ~30%   —— 中段高光
//   • Coral 橙 ~10-15% —— 只在两个角小三角尖
//
// 之前 stops 0.0/0.55/1.0 让 Coral 占到 45% —— 读起来"彩虹按钮"。
// 现在把 Azure 撑到 0.40（前 40% 都是蓝），Mint 占 0.40-0.85，
// Coral 只留最后 15% —— 视觉是"蓝身，带一抹橙尖"，跟 logo 配比一致。

public extension LinearGradient {
    /// BrainStorm+ 三色签名渐变 —— 按 logo 配比 Azure 主导、Mint 中段、Coral 收尾。
    static let bsBrand = LinearGradient(
        stops: [
            .init(color: BsColor.brandAzure, location: 0.00),
            .init(color: BsColor.brandAzure, location: 0.40),  // 蓝撑住前 40%
            .init(color: BsColor.brandMint,  location: 0.75),  // 青占中段
            .init(color: BsColor.brandCoral, location: 1.00),  // 橙只在末尾一抹
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// 垂直向三色 —— 用在 accent bar / 按钮侧光等竖向场景。
    static let bsBrandVertical = LinearGradient(
        stops: [
            .init(color: BsColor.brandAzure, location: 0.00),
            .init(color: BsColor.brandAzure, location: 0.40),
            .init(color: BsColor.brandMint,  location: 0.75),
            .init(color: BsColor.brandCoral, location: 1.00),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - BsBrandText —— 品牌渐变文字

/// 一段品牌色渐变填充的 Text。
///
///     BsBrandText("孙奕骁", font: .system(size: 34, weight: .bold))
///     BsBrandText("26", font: .custom("Outfit-Bold", size: 48))
///
/// 用于：Large Title 名字、卡 hero 数字、品牌强调瞬间。
/// **克制使用** —— 一个页面 1~2 处，多了就成彩虹贴纸。
public struct BsBrandText: View {
    let text: String
    let font: Font
    let tracking: CGFloat

    public init(_ text: String, font: Font, tracking: CGFloat = 0) {
        self.text = text
        self.font = font
        self.tracking = tracking
    }

    public var body: some View {
        Text(text)
            .font(font)
            .tracking(tracking)
            .foregroundStyle(LinearGradient.bsBrand)
    }
}

// MARK: - .bsBrandWash() —— 卡内品牌弥散氛围（v2）
//
// 替代 v1 的"左侧 4pt 硬条"—— 那个方案贴上去不融。
// 新方案：卡内部两道柔焦品牌色斑 —— Azure 从 topLeading 渗、
// Mint 从 bottomTrailing 渗，都走 opacity ≤ 0.16 + 大 blur。
// 放在卡壳下层，matte surface 再把它压一层 ——
// 品牌色"从卡底里渗出来"，而不是"贴在卡表面上"。

public struct BsBrandWashModifier: ViewModifier {
    let enabled: Bool
    let intensity: CGFloat

    public init(enabled: Bool = true, intensity: CGFloat = 1.0) {
        self.enabled = enabled
        self.intensity = intensity
    }

    public func body(content: Content) -> some View {
        content.background {
            if enabled {
                GeometryReader { geo in
                    ZStack {
                        // Azure 左上渗色 —— 主品牌色
                        Circle()
                            .fill(BsColor.brandAzure)
                            .frame(width: geo.size.width * 0.75,
                                   height: geo.size.width * 0.75)
                            .blur(radius: 50)
                            .opacity(0.16 * intensity)
                            .offset(x: -geo.size.width * 0.35,
                                    y: -geo.size.width * 0.25)

                        // Mint 右下渗色 —— 辅品牌色
                        Circle()
                            .fill(BsColor.brandMint)
                            .frame(width: geo.size.width * 0.65,
                                   height: geo.size.width * 0.65)
                            .blur(radius: 45)
                            .opacity(0.13 * intensity)
                            .offset(x: geo.size.width * 0.3,
                                    y: geo.size.height * 0.5)

                        // Coral 右上渗色 —— logo 第三色，最淡最高，点亮品牌
                        Circle()
                            .fill(BsColor.brandCoral)
                            .frame(width: geo.size.width * 0.45,
                                   height: geo.size.width * 0.45)
                            .blur(radius: 40)
                            .opacity(0.10 * intensity)
                            .offset(x: geo.size.width * 0.4,
                                    y: -geo.size.width * 0.1)
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }
}

public extension View {
    /// 卡内品牌弥散氛围 —— 柔焦 Azure 左上 + Mint 右下渗色，
    /// 放在卡壳 (`BsContentCard` / matte fill) 之前作为背景层，没有硬边。
    ///
    ///     BsContentCard {
    ///         VStack { ... }.bsBrandWash()
    ///     }
    ///
    /// intensity 参数可调浓度：1.0 标准，0.6 弱化（次要卡），1.4 强化（hero）。
    func bsBrandWash(enabled: Bool = true, intensity: CGFloat = 1.0) -> some View {
        modifier(BsBrandWashModifier(enabled: enabled, intensity: intensity))
    }

    /// v1 别名保留，避免调用方需要批量改名 —— 内部指向 v2 bsBrandWash。
    @available(*, deprecated, renamed: "bsBrandWash")
    func bsBrandAccent(enabled: Bool = true, width: CGFloat = 4) -> some View {
        bsBrandWash(enabled: enabled)
    }
}

// MARK: - BsBrandHero —— Dashboard 顶部品牌 hero

/// Dashboard / 主 tab 顶部的 hero 区块：greeting ink + 名字品牌渐变 +
/// 副标（日期 / 副信息）。取代 iOS 原生 Large Title —— 拉满品牌感，
/// 但同时保持 Large Title 的视觉体量。
///
///     BsBrandHero(greeting: "夜深了", accent: "孙奕骁", subtitle: "4月23日 周四")
///
/// 放在 List / ScrollView 最顶端的 Section 里。NavigationStack 用
/// `.navigationBarTitleDisplayMode(.inline)` + toolbar .principal 继续放
/// 压缩 wordmark。
public struct BsBrandHero: View {
    let greeting: String
    let accent: String?
    let subtitle: String?

    public init(greeting: String, accent: String? = nil, subtitle: String? = nil) {
        self.greeting = greeting
        self.accent = accent
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(greeting)
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .foregroundStyle(BsColor.ink)
                    .tracking(-0.5)

                if let accent, !accent.isEmpty {
                    Text("，")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(BsColor.ink)
                        .tracking(-0.5)

                    Text(accent)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(LinearGradient.bsBrand)  // 三色：Azure→Mint→Coral
                        .tracking(-0.5)
                }

                Spacer(minLength: 0)
            }

            if let subtitle {
                Text(subtitle)
                    .font(BsTypography.bodyMedium)
                    .foregroundStyle(BsColor.inkMuted)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BsSpacing.lg)
        .padding(.top, BsSpacing.sm)
        .padding(.bottom, BsSpacing.md)
    }
}
