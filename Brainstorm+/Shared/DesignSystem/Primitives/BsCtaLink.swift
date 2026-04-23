import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsCtaLink —— 全 app 统一的 Azure 链接 + chevron CTA
//
// 镜像 Web "查看全部 →" 的 `group-hover:translate-x-1` chevron 滑动。
// iOS 版把 hover → press：按下时 chevron 向右滑 4pt，松手回弹。
//
// 用法：
//   BsCtaLink("查看全部") { NavigationLink(...) }
//   BsCtaLink("详情", systemImage: "chevron.right", destination: SomeView())
//
// 所有卡片底部的 "查看更多 / 详情 / 更多" 都走它。
// ══════════════════════════════════════════════════════════════════

public struct BsCtaLink<Destination: View>: View {
    let label: String
    let systemImage: String
    let destination: Destination

    @State private var isPressed: Bool = false

    public init(
        _ label: String,
        systemImage: String = "chevron.right",
        @ViewBuilder destination: () -> Destination
    ) {
        self.label = label
        self.systemImage = systemImage
        self.destination = destination()
    }

    public var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 4) {
                Text(label)
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.brandAzure)

                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BsColor.brandAzure)
                    .offset(x: isPressed ? 4 : 0)
            }
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
        .animation(BsMotion.Anim.overshoot, value: isPressed)
    }
}

/// 轻量 "action" 版 —— 不是 NavigationLink，是 Button 点击回调。
public struct BsCtaButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    @State private var isPressed: Bool = false

    public init(_ label: String, systemImage: String = "chevron.right", action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: {
            Haptic.light()
            action()
        }) {
            HStack(spacing: 4) {
                Text(label)
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.brandAzure)

                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BsColor.brandAzure)
                    .offset(x: isPressed ? 4 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
        .animation(BsMotion.Anim.overshoot, value: isPressed)
    }
}
