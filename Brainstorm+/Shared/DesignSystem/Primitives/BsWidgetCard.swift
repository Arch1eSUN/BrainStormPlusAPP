import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsWidgetCard —— Dashboard widget 统一模板
//
// 对齐 Web my-tasks-card.tsx / monthly-snapshot-card.tsx 的"卡片微词汇"：
//
//   ┌─────────────────────────────────────┐
//   │ LABEL                       accessory │  ← uppercase tracking inkMuted
//   │                                       │
//   │          HeroNumber                   │  ← 可选大数字居中
//   │         heroSublabel                  │
//   │                                       │
//   │  [ 自定义 body 内容 ]                  │  ← 3 tile row / 列表 / 图 / 等
//   │                                       │
//   │                      查看全部 →       │  ← 可选 Azure CTA
//   └─────────────────────────────────────┘
//
// 整壳走 BsContentCard 材质 —— 和 Dashboard 其他卡统一 matte 内容卡。
//
// 用法：
//   BsWidgetCard(
//       label: "我的任务",
//       hero: .number("26", sublabel: "活跃任务"),
//       cta: .link("查看全部") { AnyView(TaskListView(viewModel: ...)) }
//   ) {
//       BsStatTileRow([...])
//   }
// ══════════════════════════════════════════════════════════════════

public struct BsWidgetCard<Accessory: View, Body: View>: View {
    public enum Hero {
        case number(String, sublabel: String)
        case none
    }

    public enum Cta {
        case link(String, destination: () -> AnyView)
        case button(String, action: () -> Void)
        case none
    }

    let label: String
    let hero: Hero
    let cta: Cta
    let accessory: () -> Accessory
    let content: () -> Body

    public init(
        label: String,
        hero: Hero = .none,
        cta: Cta = .none,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Body
    ) {
        self.label = label
        self.hero = hero
        self.cta = cta
        self.accessory = accessory
        self.content = content
    }

    public var body: some View {
        BsContentCard(padding: .none) {
            VStack(alignment: .leading, spacing: BsSpacing.md) {
                // 1. Header — uppercase tracking label + optional accessory
                HStack(alignment: .center) {
                    Text(label)
                        .font(BsTypography.label)
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(BsColor.inkMuted)
                    Spacer()
                    accessory()
                }

                // 2. Optional hero number block (giant Outfit number centered)
                heroBlock

                // 3. Custom body content
                content()

                // 4. Optional CTA link at bottom (Azure + chevron)
                ctaBlock
            }
            // Phase 20 subtraction: 卡内部不再渗品牌色。克制 = 高级。
            // 品牌只活在 chrome (NavBar wordmark / TabBar tint) + primary CTA，
            // content 是 Ink 黑为主、一个 semantic tone 点缀。
            .padding(BsSpacing.lg + 4)  // 留白 30% 提升：16 → 20
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var heroBlock: some View {
        switch hero {
        case .number(let value, let sublabel):
            VStack(spacing: 2) {
                // Hero 数字 —— Ink 黑。让 content 干净，品牌走 chrome + CTA。
                Text(value)
                    .font(.custom("Outfit-Bold", size: 48))
                    .monospacedDigit()
                    .tracking(-1)
                    .foregroundStyle(BsColor.ink)
                    .contentTransition(.numericText())
                Text(sublabel)
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BsSpacing.xs)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var ctaBlock: some View {
        switch cta {
        case .link(let label, let destinationFactory):
            HStack {
                Spacer()
                BsCtaLink(label) { destinationFactory() }
            }
            .padding(.top, BsSpacing.xs)
        case .button(let label, let action):
            HStack {
                Spacer()
                BsCtaButton(label, action: action)
            }
            .padding(.top, BsSpacing.xs)
        case .none:
            EmptyView()
        }
    }
}
