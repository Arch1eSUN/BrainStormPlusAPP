import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsSectionTitle —— v1.2 统一 section 标题（带 Coral 尖端 underline）
//
// 设计来源：v1.2 配色重新平衡（40 Azure / 25 Mint / 35 Coral）。
// 要让 Coral 均匀分布在视线轨迹上，一个必要手段是：每个 section 标题
// 下方放一条短 Coral capsule underline（2pt × 24pt），像 logo 三角尖
// 端的视觉呼应。
//
// 用法：
//   BsSectionTitle("今日班次")                       // 默认 Coral underline
//   BsSectionTitle("完成任务", accent: .mint)        // 可按场景换 Mint/Azure
//
// 视觉规格：
//   • Text: BsTypography.label（UPPERCASE + tracking 0.8）
//   • Underline: 3pt × 24pt Capsule，位于 text 下方 6pt
//   • accent 默认 Coral；.azure / .mint 覆盖给"已完成/主任务"区 label
//
// v1.2 目标：每屏 section 标题 2-3 个 × Coral underline = 持续分布的
// 暖色视觉支点，让 Azure 大块不会显得孤冷。
// ══════════════════════════════════════════════════════════════════

public enum BsSectionAccent {
    case coral
    case azure
    case mint

    public var color: Color {
        switch self {
        case .coral: return BsColor.brandCoral
        case .azure: return BsColor.brandAzure
        case .mint:  return BsColor.brandMint
        }
    }
}

public struct BsSectionTitle: View {
    let text: String
    let accent: BsSectionAccent
    let uppercase: Bool

    public init(_ text: String, accent: BsSectionAccent = .coral, uppercase: Bool = true) {
        self.text = text
        self.accent = accent
        self.uppercase = uppercase
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs + 2) {
            Text(text)
                .font(BsTypography.label)
                .foregroundStyle(BsColor.inkMuted)
                .tracking(uppercase ? 0.8 : 0)
                .textCase(uppercase ? .uppercase : .none)

            Capsule()
                .fill(accent.color)
                .frame(width: 24, height: 3)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        BsSectionTitle("今日班次")
        BsSectionTitle("已完成任务", accent: .mint)
        BsSectionTitle("正在进行", accent: .azure)
        BsSectionTitle("活动概览", accent: .coral, uppercase: false)
    }
    .padding()
    .background(BsColor.pageBackground)
}
