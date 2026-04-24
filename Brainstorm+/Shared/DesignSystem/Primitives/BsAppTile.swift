import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsAppTile —— "工作台" 模块入口图标
//
// 飞书/钉钉/企业微信 的工作台网格单元 的 iOS 版本。对齐结构：
//   • 顶部大 icon（SF Symbol palette 渲染，两色 tint 显品牌）
//   • 底部小字名称（Inter Medium 12pt ink）
//   • 可选 badge（右上角小红点或数字）
//   • Glass 底 + 轻微按压 scale
//
// 用法：
//   BsAppTile(
//       name: "审批",
//       systemImage: "checkmark.seal.fill",
//       tint: BsColor.brandAzure,
//       badge: 3,
//       destination: { AnyView(ApprovalCenterView()) }
//   )
// ══════════════════════════════════════════════════════════════════

public struct BsAppTile: View {
    let name: String
    let systemImage: String
    let tint: Color
    let badge: Int?
    let destination: () -> AnyView

    @State private var isPressed: Bool = false

    public init(
        name: String,
        systemImage: String,
        tint: Color = BsColor.brandAzure,
        badge: Int? = nil,
        @ViewBuilder destination: @escaping () -> AnyView
    ) {
        self.name = name
        self.systemImage = systemImage
        self.tint = tint
        self.badge = badge
        self.destination = destination
    }

    public var body: some View {
        NavigationLink(destination: destination()) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    // 5 人评审修正：iOS 2024+ app tile 是**圆角方**，不是圆形。
                    // 饱和度 0.18 让 icon 有精神（之前 0.14 奶乎乎）。
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.18))
                        .frame(width: 50, height: 50)

                    // icon 本身 —— palette 双色渲染
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(tint, tint.opacity(0.55))
                        .frame(width: 50, height: 50)

                    // badge —— 有数字显数字，否则小红点
                    if let badge, badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(BsColor.unreadBadge, in: Capsule())
                            .overlay(Capsule().stroke(BsColor.surfacePrimary, lineWidth: 1.5))
                            .offset(x: 4, y: -4)
                    }
                }

                Text(name)
                    .font(.custom("Inter-Medium", size: 12))
                    .foregroundStyle(BsColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 4)
            .scaleEffect(isPressed ? 0.94 : 1.0)
            .animation(BsMotion.Anim.overshoot, value: isPressed)
            .contentShape(Rectangle())
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
}

// MARK: - BsAppGrid —— 分组模块网格（纯灰底，无 glass 嵌套）
//
// Phase 25 校准：按飞书/钉钉工作台 pattern——icon 网格直接在 page 灰底上，
// 不再包 glass card（5 层卡堆叠视觉过载）。section label 走简单大字，
// 不做花哨。

public struct BsAppGrid<Content: View>: View {
    let title: String
    let content: () -> Content

    public init(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BsSpacing.md) {
            Text(title)
                .font(.custom("Inter-SemiBold", size: 15))
                .foregroundStyle(BsColor.ink)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: BsSpacing.sm), count: 4),
                spacing: BsSpacing.lg
            ) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
