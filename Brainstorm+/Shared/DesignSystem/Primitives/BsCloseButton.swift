import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsCloseButton — 圆形 X 关闭按钮(iOS 26 原生 Liquid Glass)
//
// 用户反馈 (2026-04-25):
//   "右上角的叉用原生 liquidglass 做 你看看每个页面返回键的尺寸 来做这个叉
//    并且在该出现的时候出现 不该出现的时候不要出现 现在位置错设计错"
//
// 视觉规格(对齐系统返回键):
//   • SwiftUI NavigationStack 默认返回键: SF "chevron.backward"
//     17pt regular weight, 整个 hit target 44×44pt, iOS 26 Liquid Glass
//     视觉圆 ~36-40pt。
//   • 本组件 = 同字号(17pt regular)的 SF "xmark", 内圈 36pt 圆,
//     `.glassEffect(.regular.interactive(), in: Circle())` 真·Liquid Glass,
//     外加 4pt padding → 44pt hit target,跟系统 back button 完全一致。
//
// 使用边界(关键 — 用户原话"在该出现的时候出现"):
//   • 仅在 root sheet/modal/fullScreenCover 出现 —— 用户需要显式关闭整个
//     呈现的界面。
//   • Push 进 sub-view 后,系统左上 < back button 会自动接管 —— 此时
//     **不要渲染 BsCloseButton**。把 X overlay 挂在 NavigationStack 的
//     root content 上(而不是 NavStack 外层),push 时 root 自动 transition
//     out → X 跟随消失。
//   • 父容器有自己的关闭(form sheet swipe-down / .interactiveDismissDisabled
//     未禁)时,优先靠系统手势,X 仅做兜底。
//
// 实现细节:
//   • `.glassEffect(.regular.interactive(), in: Circle())` — interactive 给
//     SwiftUI 信号"这是可点击元素",系统会自动叠加按下/抬起的 glass 高光,
//     无需自己写 ButtonStyle 缩放动画。
//   • 不进 toolbar pipeline,因此不会被系统再 wrap 一层椭圆 capsule
//     (旧版 bug:"圆+椭圆"叠加)。
//   • 36pt 视觉 + 4pt padding = 44pt hit area, contentShape Circle 限定
//     圆心外的点击不算到本按钮上(避免遮挡相邻 toolbar)。
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
            // ── 视觉层 (36pt glass circle, 17pt SF xmark) ──────────
            // 系统 NavBar back button: SF chevron.backward 17pt regular,
            // hit target 44×44pt, iOS 26 Liquid Glass 视觉圆 ~36pt。
            // 本组件 1:1 对齐:同字号 + 同 glass 容器,只换 symbol。
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 36, height: 36)
                // iOS 26 原生 Liquid Glass — interactive 给 SwiftUI 信号
                // "这是可点击元素",系统自动叠加按下/抬起的 glass 高光反馈,
                // 无需自己写 ButtonStyle 缩放动画。
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        // ── 命中区扩到 44×44 (Apple HIG 最小可点) ───────────────
        // 视觉 36pt + 4pt padding × 2 = 44pt hit target,跟系统 back
        // button 完全一致;contentShape 圆形,圆心外的空白点击不算到本
        // 按钮上(避免遮挡相邻 toolbar / nav 项)。
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabelText)
    }
}

// MARK: - Conditional rendering helper
//
// 调用方约定:
//   • 只在 NavigationStack root view(也就是 sheet/cover 第一屏)上挂这个
//     overlay。push 进 destination 后,destination 自带系统返回键,X 自动
//     消失(因为 root 整体 transition out)。
//   • 如果父 view 不在 sheet 内 (比如 inline 嵌入 dashboard),
//     **不要**挂这个 overlay —— 系统返回键已足够。

public extension View {
    /// Attach a top-trailing iOS 26 Liquid Glass close button. Use on the
    /// root content of a sheet/modal/fullScreenCover NavigationStack so it
    /// disappears automatically when destinations are pushed.
    ///
    /// - Parameters:
    ///   - isVisible: When `false`, no overlay is rendered. Default `true`.
    ///   - dismiss: Closure invoked on tap (typically `{ dismiss() }`).
    func bsModalCloseButton(
        isVisible: Bool = true,
        dismiss: @escaping () -> Void
    ) -> some View {
        overlay(alignment: .topTrailing) {
            if isVisible {
                BsCloseButton(action: dismiss)
                    // 4pt top + BsSpacing.md(=12pt) trailing ≈ 系统 toolbar
                    // item insets,保证视觉位置对齐 NavBar trailing 真按钮。
                    .padding(.top, 4)
                    .padding(.trailing, BsSpacing.md)
            }
        }
    }
}

#Preview {
    ZStack {
        BsColor.pageBackground.ignoresSafeArea()
        BsCloseButton(action: {})
    }
}
