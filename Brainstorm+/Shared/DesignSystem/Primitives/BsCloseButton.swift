import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsCloseButton — 圆形 X 关闭按钮(iOS 26 原生 Liquid Glass)
//
// 用户反馈 (Iter 6 / 2026-04-25):
//   "所有应用的关闭按钮位置根本不正常 应该在右上角并且大小和其他页面的
//    返回键一样大"
//
// 实证发现 (实机截图对比 iOS 26 系统 NavBar back button):
//   • iOS 26 系统 back button 的 glass 圆视觉直径 ≈ **44pt** (整个 hit
//     target 也是 44pt,视觉 ≈ hit)。
//   • Iter 5 把 BsCloseButton 做成 36pt 视觉 + 44pt hit area,实机看明显
//     比系统 back 小一圈 → Iter 6 收敛到 44pt 视觉 = 44pt hit,1:1 对齐。
//
// 视觉规格 (Iter 6 终态):
//   • 视觉圆: 44×44pt `.glassEffect(.regular.interactive(), in: Circle())`
//   • SF Symbol: `xmark` 15pt regular weight (圆等比放大后,符号同步收 +2pt
//     避免视觉过满)
//   • Hit target: 44×44pt (= 视觉,本来就到 Apple HIG 下限)
//
// 使用约束 (用户原话"在该出现的时候出现"):
//   • 仅出现在 sheet / fullScreenCover root —— 用户需要显式关闭整个
//     呈现的界面。
//   • Push 进 sub-view 后由系统左上 < back button 接管,X 必须消失。
//     正确做法: 把 X overlay 挂在 NavigationStack 的 *root content* 上
//     (而不是 NavStack 外层),push destination 时 root transition out → X
//     自动跟随消失;或 (Iter 6 推荐) 用 `bsModalNavBar` 修饰符,X 走
//     toolbar pipeline,destination 自带 toolbar → 系统自动接管。
//
// 实现细节:
//   • `.glassEffect(.regular.interactive(), in: Circle())` — interactive 给
//     SwiftUI 信号 "这是可点击元素",系统自动叠加按下/抬起的 glass 高光,
//     无需自己写 ButtonStyle 缩放动画。
//   • 走 toolbar pipeline 时 (`bsModalNavBar`) 由 NavBar 自动处理 trailing
//     padding/spacing,我们不再手 padding overlay。
//   • 旧的 `bsModalCloseButton` overlay helper 保留兼容性,但新写代码请走
//     `bsModalNavBar` —— 视觉位置交给系统 NavBar trailing toolbar 槽,
//     完全不用手挪 padding。
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
            // ── 视觉层 (44pt glass circle, 15pt SF xmark) ──────────
            // Iter 6: 实机截图 vs iOS 26 NavBar back button 后,把视觉
            // 圆从 36 → 44pt,跟系统 back 1:1 (用户原话"大小和其他页面
            // 的返回键一样大")。symbol 同步 13→15pt regular (圆等比 +
            // 8pt,符号 +2pt 看着不会顶满边)。
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 44, height: 44)
                // iOS 26 原生 Liquid Glass — interactive 给 SwiftUI 信号
                // "这是可点击元素",系统自动叠加按下/抬起的 glass 高光反馈,
                // 无需自己写 ButtonStyle 缩放动画。
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        // ── Hit area = 视觉 (44×44pt) ──────────────────────────
        // 系统 back button 视觉 ≈ hit ≈ 44pt;此处不再额外 padding —
        // contentShape Circle 限定圆心外的空白点击不算到本按钮上
        // (避免遮挡相邻 toolbar / nav 项)。
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabelText)
    }
}

// MARK: - Conditional rendering helper (legacy overlay path)
//
// `bsModalCloseButton` overlay helper 是 Iter 5 的产物,新代码请改用
// `bsModalNavBar` (见 Modifiers/BsModalNavBar.swift),X 自动走 toolbar
// trailing 槽,不需要手挪 padding,push 时系统自动接管。本 helper 保留
// 仅为兼容旧 callsite (例如 BsCommandPalette 的 floating overlay),
// 但已在 Iter 6 内迁移到 bsModalNavBar。

public extension View {
    /// **Legacy** — prefer `bsModalNavBar` modifier.
    ///
    /// Attach a top-trailing iOS 26 Liquid Glass close button as an overlay
    /// (does NOT participate in NavigationStack push transitions when
    /// attached at the wrong level). New code should use `bsModalNavBar`.
    func bsModalCloseButton(
        isVisible: Bool = true,
        dismiss: @escaping () -> Void
    ) -> some View {
        overlay(alignment: .topTrailing) {
            if isVisible {
                BsCloseButton(action: dismiss)
                    // Iter 6: 视觉圆扩到 44pt 后,顶端不再需要 +4pt (圆
                    // 已经吃满 safe-area 内的视觉 baseline);trailing 仍
                    // 给 sm(=8pt) 让它跟 NavBar trailing item 视觉对齐。
                    .padding(.top, 0)
                    .padding(.trailing, BsSpacing.sm)
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
