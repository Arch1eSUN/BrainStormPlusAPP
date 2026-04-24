import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsAllAppsTile —— Dashboard "所有应用" 入口磁贴
//
// 参考：docs/plans/2026-04-24-ios-full-redesign-plan.md
//   §2.6 Signature B —— Dashboard widget 堆叠 matte 卡片家族
//   §4.5 Phase 4 —— macOS Launchpad 风格命令面板（Phase 5 构建 palette；
//                   本 tile 仅负责触发打开）
//
// 结构（HStack 3 列）：
//   • Leading: 28×28 brandAzure 底 + "square.grid.3x3.fill" 图标
//   • Middle : "所有应用" 标题 + 最多 5 个预览小图标（重叠 6pt）
//               超出 5 个时尾巴挂 "+N"
//   • Trailing: chevron.right 暗示可展开
//
// 视觉规格：
//   • matte 自渲染（不嵌套 BsContentCard，保持自包含）
//   • 填充 BsColor.surfacePrimary；圆角 BsRadius.xl(22pt)
//   • 边框 BsColor.borderSubtle stroke 0.5
//   • Shadow：light-mode 才走 BsShadow.contentCard（@Environment colorScheme 门控）
//   • Padding 16pt；按压 0.97 scale + overshoot spring + Haptic.light()
//
// 用法：
//   BsAllAppsTile(previewIcons: iconsFromPermissions) {
//       presentCommandPalette()
//   }
// ══════════════════════════════════════════════════════════════════

public struct AppIconPreview: Identifiable, Hashable, Sendable {
    public let id: String          // stable key（去重 / diff 用）
    public let systemImage: String
    public let tint: Color

    public init(id: String, systemImage: String, tint: Color) {
        self.id = id
        self.systemImage = systemImage
        self.tint = tint
    }
}

public struct BsAllAppsTile: View {
    let previewIcons: [AppIconPreview]
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed: Bool = false

    // MARK: 最多 5 个图标进入预览，其余走 "+N" label
    private static let maxPreview: Int = 5

    private var visibleIcons: [AppIconPreview] {
        Array(previewIcons.prefix(Self.maxPreview))
    }

    private var remainingCount: Int {
        max(0, previewIcons.count - Self.maxPreview)
    }

    public init(previewIcons: [AppIconPreview], onTap: @escaping () -> Void) {
        self.previewIcons = previewIcons
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                // Leading: 品牌色方形 + 九宫格图标
                leadingBadge

                // Middle: 标题 + 预览小图标
                VStack(alignment: .leading, spacing: 8) {
                    Text("所有应用")
                        .font(.custom("Inter-SemiBold", size: 15))
                        .foregroundStyle(BsColor.ink)

                    previewRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Trailing: chevron 暗示 tap-to-expand
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BsColor.inkFaint)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                    .fill(BsColor.surfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                    .stroke(BsColor.borderSubtle, lineWidth: 0.5)
            )
            .bsShadow(colorScheme == .light ? BsShadow.contentCard : BsShadow.none)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(BsMotion.Anim.overshoot, value: isPressed)
            .contentShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
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
    }

    // MARK: - Leading badge（28×28 brandAzure 底）

    private var leadingBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BsColor.brandAzure.opacity(0.14))
                .frame(width: 28, height: 28)

            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BsColor.brandAzure)
        }
    }

    // MARK: - Preview row（重叠小图标 + 可选 +N）

    private var previewRow: some View {
        HStack(spacing: -6) {
            ForEach(Array(visibleIcons.enumerated()), id: \.element.id) { index, icon in
                miniIcon(icon)
                    .zIndex(Double(Self.maxPreview - index))
            }

            if remainingCount > 0 {
                Text("+\(remainingCount)")
                    .font(.custom("Inter-SemiBold", size: 11))
                    .foregroundStyle(BsColor.inkFaint)
                    .padding(.leading, 10) // 把 spacing: -6 的负偏移吃掉一点，避免和最后 icon 贴死
            }
        }
    }

    private func miniIcon(_ icon: AppIconPreview) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(icon.tint.opacity(0.14))
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(BsColor.surfacePrimary, lineWidth: 1.5) // 重叠分层描边
                )

            Image(systemName: icon.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(icon.tint)
        }
    }

    // MARK: - Preview sample（documentable）

    public static let sampleIcons: [AppIconPreview] = [
        .init(id: "attendance",    systemImage: "clock.fill",            tint: BsColor.brandAzure),
        .init(id: "schedule",      systemImage: "calendar",              tint: BsColor.brandAzure),
        .init(id: "leaves",        systemImage: "calendar.badge.minus",  tint: BsColor.brandMint),
        .init(id: "reporting",     systemImage: "doc.text.fill",         tint: BsColor.brandMint),
        .init(id: "announcements", systemImage: "megaphone.fill",        tint: BsColor.brandCoral),
    ]
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            BsAllAppsTile(previewIcons: BsAllAppsTile.sampleIcons) {
                print("tapped 所有应用")
            }
        }
        .padding()
    }
    .background(BsColor.pageBackground)
}
