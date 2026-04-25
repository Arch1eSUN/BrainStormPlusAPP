import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsCloseButton — 圆形 X 关闭按钮(iOS 26 原生 Liquid Glass)
//
// 用户反馈 (2026-04-25):
//   "右上角的叉没用容器了 但是 liquid glass 特性也没有了
//    所有的这种 button 都要有原生 liquid glass 特性"
//
// 上一次修复(BsCommandPalette closeButtonOverlay)为了避开 toolbar 自动
// 套椭圆 capsule 的问题,把按钮做成了手搓 ZStack(Circle.fill +
// Circle.stroke) —— 失掉了原生 Liquid Glass 材质。本组件:
//
//   • 视觉本体 = 32pt 内圈 Circle,材质 = `.glassEffect(.regular.interactive(),
//     in: Circle())` —— iOS 26 原生 Liquid Glass(高斯+折射+触感反馈),
//     不再用 fill+stroke 仿造。
//   • 不套 Capsule 也不进 toolbar pipeline,因此不会被系统再 wrap 一层椭圆
//     glass 容器(原 bug:"圆+椭圆"叠加)。
//   • 44pt 命中区(+6 padding 扩 hit area, contentShape Circle)
//   • SF Symbol "xmark" 14pt semibold + ink-muted tint
//   • 调用方负责放置位置 + 可见性绑定(必须 conditional 渲染,不要常驻)
//
// 用法:
//   .overlay(alignment: .topTrailing) {
//       BsCloseButton { dismiss() }
//           .padding(.top, 6)
//           .padding(.trailing, BsSpacing.md)
//   }
// ══════════════════════════════════════════════════════════════════

public struct BsCloseButton: View {
    private let action: () -> Void
    private let accessibilityLabelText: String

    public init(
        accessibilityLabel: String = "关闭",
        action: @escaping () -> Void
    ) {
        self.action = action
        self.accessibilityLabelText = accessibilityLabel
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 32, height: 32)
                // iOS 26 原生 Liquid Glass —— interactive 给 SwiftUI 信号
                // 这是一个可点击元素,系统会自动叠加按下/抬起的 glass 高光
                // 反馈,无需自己写 ButtonStyle 缩放动画。
                .glassEffect(.regular.interactive(), in: Circle())
                // 44pt hit area(32 + 6*2)。contentShape 限定为 Circle 让
                // 圆心外的点击不算到本按钮上(避免遮挡相邻 toolbar 元素)。
                .padding(6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabelText)
    }
}

#Preview {
    ZStack {
        BsColor.pageBackground.ignoresSafeArea()
        BsCloseButton(action: {})
    }
}
