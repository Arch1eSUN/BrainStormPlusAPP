import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsTagPill —— 统一状态 / 标签 pill
//
// 设计来源：audit 发现 12+ 处 raw capsule 散落：
//   Text(...)
//     .padding(.horizontal, 8).padding(.vertical, 2)
//     .background(Color.orange.opacity(0.12), in: Capsule())
//     .foregroundStyle(.orange)
//     .font(.caption2.weight(.semibold))
// 每处实现略不同（padding / 字号 / opacity）。统一成 BsTagPill，
// 按 tone 枚举走 token 配色 + 字体，外观一致。
//
// 用法：
//   BsTagPill("已通过", tone: .success)
//   BsTagPill("待审批", tone: .warning, icon: "clock.fill")
//   BsTagPill("紧急", tone: .danger)
//
// Tone → BsColor 映射：
//   • .brand      → brandAzure
//   • .success    → brandMint (= .success alias)
//   • .warning    → warning
//   • .danger     → danger
//   • .admin      → brandCoral（管理身份标识，v1.1）
//   • .neutral    → inkMuted
//
// 字体用 BsTypography.captionSmall (relativeTo .caption2)，自动 Dynamic Type。
// ══════════════════════════════════════════════════════════════════

public enum BsTagTone {
    case brand, success, warning, danger, admin, neutral

    /// 前景（文字 + icon）色
    public var foreground: Color {
        switch self {
        case .brand:   return BsColor.brandAzureDark
        case .success: return BsColor.brandMintText
        case .warning: return BsColor.warning
        case .danger:  return BsColor.danger
        case .admin:   return BsColor.brandCoralText
        case .neutral: return BsColor.inkMuted
        }
    }

    /// 背景 tint（自动 0.14 opacity）
    public var background: Color {
        switch self {
        case .brand:   return BsColor.brandAzure
        case .success: return BsColor.brandMint
        case .warning: return BsColor.warning
        case .danger:  return BsColor.danger
        case .admin:   return BsColor.brandCoral
        case .neutral: return BsColor.inkMuted
        }
    }
}

public struct BsTagPill: View {
    let text: String
    let tone: BsTagTone
    let icon: String?

    public init(_ text: String, tone: BsTagTone = .neutral, icon: String? = nil) {
        self.text = text
        self.tone = tone
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: BsSpacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(.caption2, weight: .semibold))
            }
            Text(text)
                .font(BsTypography.captionSmall.weight(.semibold))
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, BsSpacing.sm + 2)
        .padding(.vertical, BsSpacing.xxs + 1)
        .background(tone.background.opacity(0.14), in: Capsule())
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        BsTagPill("已通过", tone: .success, icon: "checkmark.seal.fill")
        BsTagPill("待审批", tone: .warning, icon: "clock.fill")
        BsTagPill("紧急", tone: .danger, icon: "exclamationmark.triangle.fill")
        BsTagPill("进行中", tone: .brand, icon: "play.fill")
        BsTagPill("管理员", tone: .admin, icon: "shield.lefthalf.filled")
        BsTagPill("草稿", tone: .neutral)
    }
    .padding()
    .background(BsColor.pageBackground)
}
