import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsStatTile —— Web `bg-{tone}-50 + text-{tone}-600` 语义色 tile 对
//
// 镜像 Web my-tasks-card.tsx 的 3-tile 布局：
//   • bg-{tone}.opacity(0.10) + fg 全饱和文字
//   • 上 text-lg bold 数字 + 下 text-[10px] uppercase tracking-widest 标签
//   • rounded-xl (BsRadius.md)
//
// 用法：
//     BsStatTile(value: "26", label: "进行中", tone: .azure)
//
// 不要再自己 VStack { Text(value).font(.xxx) ... bg(...) } —— 走这个。
// ══════════════════════════════════════════════════════════════════

public struct BsStatTile: View {
    public enum Tone: Hashable {
        case azure, mint, coral, success, warning, danger, neutral

        /// tile 上文字颜色 —— 需在白底/pale 底上保持 WCAG AA 对比度，
        /// 因此 mint / coral 用 Dark 变体（详见 DesignTokens.swift）。
        var foreground: Color {
            switch self {
            case .azure:   return BsColor.brandAzure
            case .mint:    return BsColor.brandMintDark    // 蓝偏青深色，白底可读
            case .coral:   return BsColor.brandCoralDark   // 橙深色，白底可读
            case .success: return BsColor.success
            case .warning: return BsColor.warning
            case .danger:  return BsColor.danger
            case .neutral: return BsColor.inkMuted
            }
        }

        /// tile 背景 —— 用亮色原色 0.12 透明，既有品牌感又淡不抢字。
        var background: Color {
            switch self {
            case .azure:   return BsColor.brandAzure.opacity(0.12)
            case .mint:    return BsColor.brandMint.opacity(0.14)   // 浅版品牌青
            case .coral:   return BsColor.brandCoral.opacity(0.12)
            case .success: return BsColor.success.opacity(0.12)
            case .warning: return BsColor.warning.opacity(0.12)
            case .danger:  return BsColor.danger.opacity(0.12)
            case .neutral: return BsColor.inkMuted.opacity(0.10)
            }
        }
    }

    let value: String
    let label: String
    let tone: Tone

    public init(value: String, label: String, tone: Tone = .neutral) {
        self.value = value
        self.label = label
        self.tone = tone
    }

    public var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tone.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(label)
                .font(BsTypography.meta)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(tone.foreground.opacity(0.85))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BsSpacing.sm)
        .padding(.vertical, BsSpacing.sm + 2)
        .background(tone.background)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
    }
}

/// 横向 Tile 行 —— 自动等分。最多 4 个 tile 一行（再多视觉压得太紧）。
public struct BsStatTileRow: View {
    public struct Item: Identifiable {
        public let id = UUID()
        public let value: String
        public let label: String
        public let tone: BsStatTile.Tone
        public init(value: String, label: String, tone: BsStatTile.Tone = .neutral) {
            self.value = value
            self.label = label
            self.tone = tone
        }
    }

    let items: [Item]

    public init(_ items: [Item]) {
        self.items = items
    }

    public var body: some View {
        HStack(spacing: BsSpacing.sm) {
            ForEach(items) { item in
                BsStatTile(value: item.value, label: item.label, tone: item.tone)
            }
        }
    }
}
