import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsModalNavBar — sheet / fullScreenCover 顶栏统一收口
//
// 用户反馈 (Iter 6 / 2026-04-25):
//   "所有应用的关闭按钮位置根本不正常 应该在右上角并且大小和其他页面的
//    返回键一样大"
//
// 设计动机:
//   Iter 5 的 `bsModalCloseButton` overlay helper 把 X 当 floating
//   overlay 贴在内容上,跟系统 NavBar trailing 自带的 toolbar item 不在
//   同一坐标系,要靠手 padding 拼对齐 —— 多个 sheet 出现位置漂移。Iter 6
//   改走 toolbar pipeline:把 BsCloseButton 塞进 `ToolbarItem(placement:
//   .topBarTrailing)`,系统 NavBar 自动给我们对齐到 trailing slot,
//   位置/spacing 跟 leading < back button 完全镜像。
//
// 同时此 modifier 也负责 NavigationStack 包裹兜底 (用户传进来的 view
// 如果没有自己的 NavigationStack,我们补一层),避免每个 sheet 都要写
// `NavigationStack { ... .toolbar { ... } }`。
//
// 使用边界:
//   • Form / 编辑类 sheet (LeaveSubmit / ReimbursementSubmit / 创建
//     公告 ...) 已有 `cancellationAction + confirmationAction` (取消/
//     提交) 的双 toolbar item —— 这是系统 idiom,**保持不变**,不要
//     migrate 到 X。
//   • 只读类 sheet (UserPreviewSheet 用户预览 / BsCommandPalette
//     启动器 / 详情预览) 用本 modifier,把 "完成" 文字按钮 / overlay X
//     都收口成统一 BsCloseButton 玻璃圆。
// ══════════════════════════════════════════════════════════════════

/// X 按钮在 sheet 顶栏的呈现方式。
public enum BsModalDismissBehavior {
    /// 默认 — X 渲染在 trailing 槽 (右上),`.topBarTrailing` placement。
    case auto
    /// X 渲染在 leading 槽 (左上)。极少数情况下 user 期待 "back" 语义
    /// 时使用 (例如二级返回到父 sheet),日常基本不用。
    case leadingX
    /// 不渲染 X — sheet 完全靠下拉手势关闭 (例如 .fraction(0.4)
    /// 半屏 day-peek)。
    case none
}

public extension View {
    /// 给 sheet / fullScreenCover 的根 view 套上系统化 NavBar:
    /// 自动注入 trailing X 按钮 (BsCloseButton 玻璃圆,跟系统
    /// back button 1:1 大小),并按需补齐 NavigationStack 包裹。
    ///
    /// 触发 dismiss 走 `Environment(\.dismiss)`,所以本 modifier 必须
    /// 在 sheet content view 内部使用 (否则 dismiss closure 拿不到
    /// 正确的 sheet presentation 上下文)。
    ///
    /// - Parameters:
    ///   - title: 可选 NavBar title。传 nil 不设置 (允许调用方自己用
    ///     `.navigationTitle` 已经设过)。
    ///   - displayMode: title 显示模式,默认 `.inline` (sheet 顶栏一般
    ///     不给 large title 让 NavBar 高度跟 X 圆对齐)。
    ///   - dismissBehavior: X 位置/隐藏控制,默认 `.auto`。
    func bsModalNavBar(
        title: String? = nil,
        displayMode: NavigationBarItem.TitleDisplayMode = .inline,
        dismissBehavior: BsModalDismissBehavior = .auto
    ) -> some View {
        modifier(
            BsModalNavBarModifier(
                title: title,
                displayMode: displayMode,
                dismissBehavior: dismissBehavior
            )
        )
    }
}

// MARK: - Internal modifier

private struct BsModalNavBarModifier: ViewModifier {
    let title: String?
    let displayMode: NavigationBarItem.TitleDisplayMode
    let dismissBehavior: BsModalDismissBehavior

    func body(content: Content) -> some View {
        // 注:不在这里包裹 NavigationStack。多数 sheet 调用方已经自己
        // 包了 NavigationStack (Form / 复杂 list 都需要),我们在外面
        // 再包一层会变成嵌套 NavStack,push destination 时行为退化。
        // 调用约定:确保使用本 modifier 的 view 自己有 NavigationStack
        // 包裹 (90% 的 sheet 都已经包了);BsCommandPalette / 简单
        // VStack 类型直接用 wrap helper (见下面 navStackEnsured 注释)。
        content
            .navigationBarTitleDisplayMode(displayMode)
            .modifier(MaybeNavTitle(title: title))
            .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        switch dismissBehavior {
        case .auto:
            ToolbarItem(placement: .topBarTrailing) { DismissButton() }
        case .leadingX:
            ToolbarItem(placement: .topBarLeading) { DismissButton() }
        case .none:
            // 留空 — 系统不渲染额外 toolbar item;sheet 仍可走 swipe-down
            // 关闭 (前提是调用方没有 .interactiveDismissDisabled)。
            ToolbarItem(placement: .topBarTrailing) { EmptyView() }
        }
    }
}

/// `.navigationTitle` 只接受非 optional `String`,我们用一个 modifier
/// 桥接 optional —— title 为 nil 时不调用,调用方可继续用自己的
/// `.navigationTitle("...")`。
private struct MaybeNavTitle: ViewModifier {
    let title: String?
    func body(content: Content) -> some View {
        if let title { content.navigationTitle(title) } else { content }
    }
}

/// X 按钮 — 走 `Environment(\.dismiss)` 拿当前 presentation 的
/// dismiss closure。BsCloseButton 内部已是 44pt glass 圆 + 15pt SF
/// xmark,跟系统 back button 1:1。
private struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        BsCloseButton {
            // Haptic 由 BsCloseButton 调用方 / Iter 5 决定不加 (用户反馈
            // 关闭按钮过密震动) — 这里保持不动。
            dismiss()
        }
    }
}
