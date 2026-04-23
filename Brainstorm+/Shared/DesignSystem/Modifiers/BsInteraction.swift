import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsInteraction —— iOS 原生交互 primitives
//
// 统一封装：按压 scale 反馈 + haptic 分级 + 长按 + 滑动快捷操作
// + 入场 stagger。业务代码用一行 modifier 替代自己搓 gesture。
//
// 分级规范：
//   • Haptic.soft     —— 最轻，卡片预览/悬停（iOS 没鼠标，这里留着）
//   • Haptic.light    —— 普通 tap（行 / 链接 / 次要按钮）
//   • Haptic.medium   —— 主操作（提交 / 确认 / 主 CTA）
//   • Haptic.rigid    —— 硬派瞬态（segmented 切换 / 重要选择）
//   • Haptic.selection—— picker 切换
//   • Haptic.success  —— 通知成功（提交通过 / clock in 等）
//   • Haptic.warning  —— 通知警告
//   • Haptic.error    —— 通知失败
// ══════════════════════════════════════════════════════════════════

// MARK: - BsPressable —— 按压反馈（scale + haptic + tap）

/// 可按压反馈的"行为"分类 —— 驱动 haptic 强度 + scale 幅度。
public enum BsPressIntent {
    case row        // 列表行 / 次要链接 ← Haptic.light + scale 0.98
    case card       // 卡片级 tap ← Haptic.light + scale 0.97
    case action     // 主操作 / 提交 ← Haptic.medium + scale 0.96
    case destructive// 删除 / 撤销 ← Haptic.rigid + scale 0.96
    case segment    // segmented / picker ← Haptic.rigid + scale 1.0（无 scale）

    var scale: CGFloat {
        switch self {
        case .row: return 0.98
        case .card: return 0.97
        case .action, .destructive: return 0.96
        case .segment: return 1.0
        }
    }

    fileprivate func fireHaptic() {
        switch self {
        case .row: Haptic.light()
        case .card: Haptic.light()
        case .action: Haptic.medium()
        case .destructive: Haptic.rigid()
        case .segment: Haptic.rigid()
        }
    }
}

public struct BsPressableModifier: ViewModifier {
    let intent: BsPressIntent
    let action: () -> Void
    @State private var isPressed: Bool = false

    public func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? intent.scale : 1.0)
            .animation(BsMotion.Anim.overshoot, value: isPressed)
            .onTapGesture { action() }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            intent.fireHaptic()
                        }
                    }
                    .onEnded { _ in isPressed = false }
            )
    }
}

public extension View {
    /// 按压反馈 —— scale + haptic，按 intent 分级。
    /// 用于 NavigationLink 里不好加 ButtonStyle 的行 / 卡。
    ///
    ///     VStack { ... }
    ///         .bsPressable(.card) { navigate() }
    func bsPressable(
        _ intent: BsPressIntent = .row,
        action: @escaping () -> Void
    ) -> some View {
        modifier(BsPressableModifier(intent: intent, action: action))
    }
}

// MARK: - BsInteractiveFeel —— 纯视觉按压反馈（不绑 tap）

/// 只给视觉 press 感，action 由外层（如 NavigationLink / Button）处理。
public struct BsInteractiveFeelModifier: ViewModifier {
    let intent: BsPressIntent
    @State private var isPressed: Bool = false

    public func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? intent.scale : 1.0)
            .animation(BsMotion.Anim.overshoot, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            intent.fireHaptic()
                        }
                    }
                    .onEnded { _ in isPressed = false }
            )
    }
}

public extension View {
    /// 按压视觉反馈（无 tap 回调）—— 外层 NavigationLink / Button 负责动作。
    /// 用于：`NavigationLink { ... } label: { card.bsInteractiveFeel(.card) }`
    func bsInteractiveFeel(_ intent: BsPressIntent = .card) -> some View {
        modifier(BsInteractiveFeelModifier(intent: intent))
    }
}

// MARK: - Swipe Action 快捷组合（iOS 原生 List swipeActions 语义糖）

/// 一个滑动动作的语义 + 视觉约定。
public struct BsSwipeAction {
    public let label: String
    public let systemImage: String
    public let tint: Color
    public let role: ButtonRole?
    public let haptic: () -> Void
    public let action: () -> Void

    public init(
        label: String,
        systemImage: String,
        tint: Color,
        role: ButtonRole? = nil,
        haptic: @escaping () -> Void = { Haptic.medium() },
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.tint = tint
        self.role = role
        self.haptic = haptic
        self.action = action
    }

    // MARK: Factory presets

    /// 删除（trailing，destructive red）
    public static func delete(action: @escaping () -> Void) -> Self {
        BsSwipeAction(
            label: "删除",
            systemImage: "trash",
            tint: BsColor.danger,
            role: .destructive,
            haptic: { Haptic.rigid() },
            action: action
        )
    }

    /// 归档（trailing，neutral）
    public static func archive(action: @escaping () -> Void) -> Self {
        BsSwipeAction(
            label: "归档",
            systemImage: "archivebox.fill",
            tint: BsColor.inkMuted,
            haptic: { Haptic.medium() },
            action: action
        )
    }

    /// 标记完成（leading 或 trailing，success green）
    public static func complete(isDone: Bool, action: @escaping () -> Void) -> Self {
        BsSwipeAction(
            label: isDone ? "撤销完成" : "标记完成",
            systemImage: isDone ? "arrow.uturn.backward.circle" : "checkmark.circle",
            tint: BsColor.success,
            haptic: { Haptic.success() },
            action: action
        )
    }

    /// 撤销（leading 或 trailing，warning）
    public static func withdraw(action: @escaping () -> Void) -> Self {
        BsSwipeAction(
            label: "撤回",
            systemImage: "arrow.uturn.backward",
            tint: BsColor.warning,
            haptic: { Haptic.rigid() },
            action: action
        )
    }

    /// 标记已读（leading，azure）
    public static func markRead(action: @escaping () -> Void) -> Self {
        BsSwipeAction(
            label: "已读",
            systemImage: "envelope.open.fill",
            tint: BsColor.brandAzure,
            haptic: { Haptic.light() },
            action: action
        )
    }

    /// 批准（trailing，success）
    public static func approve(action: @escaping () -> Void) -> Self {
        BsSwipeAction(
            label: "通过",
            systemImage: "checkmark.circle.fill",
            tint: BsColor.success,
            haptic: { Haptic.success() },
            action: action
        )
    }

    /// 拒绝（trailing，danger）
    public static func reject(action: @escaping () -> Void) -> Self {
        BsSwipeAction(
            label: "驳回",
            systemImage: "xmark.circle.fill",
            tint: BsColor.danger,
            role: .destructive,
            haptic: { Haptic.warning() },
            action: action
        )
    }
}

public extension View {
    /// 应用一组 trailing 边 swipe actions（允许 full swipe 触发第一项）。
    ///
    /// 用法：
    ///     row.bsSwipeActions(trailing: [.delete { ... }, .complete(isDone: false) { ... }])
    @ViewBuilder
    func bsSwipeActions(
        leading: [BsSwipeAction] = [],
        trailing: [BsSwipeAction] = [],
        allowsFullSwipe: Bool = true
    ) -> some View {
        self
            .swipeActions(edge: .leading, allowsFullSwipe: allowsFullSwipe) {
                ForEach(leading.indices, id: \.self) { i in
                    let item = leading[i]
                    Button(role: item.role) {
                        item.haptic()
                        item.action()
                    } label: {
                        Label(item.label, systemImage: item.systemImage)
                    }
                    .tint(item.tint)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: allowsFullSwipe) {
                ForEach(trailing.indices, id: \.self) { i in
                    let item = trailing[i]
                    Button(role: item.role) {
                        item.haptic()
                        item.action()
                    } label: {
                        Label(item.label, systemImage: item.systemImage)
                    }
                    .tint(item.tint)
                }
            }
    }
}

// MARK: - BsContextMenuItem —— 长按菜单项（带 haptic）

public struct BsContextMenuItem {
    public let label: String
    public let systemImage: String
    public let role: ButtonRole?
    public let haptic: () -> Void
    public let action: () -> Void

    public init(
        label: String,
        systemImage: String,
        role: ButtonRole? = nil,
        haptic: @escaping () -> Void = { Haptic.light() },
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.role = role
        self.haptic = haptic
        self.action = action
    }
}

public extension View {
    /// 长按菜单 —— 带每项独立 haptic。
    /// iOS 自动给长按激活本身一个默认 .rigid haptic，我们不覆写；
    /// 各菜单项点击时单独触发自己的 haptic。
    ///
    ///     row.bsContextMenu([
    ///         .init(label: "详情", systemImage: "arrow.up.forward.square") { push() },
    ///         .init(label: "删除", systemImage: "trash", role: .destructive,
    ///               haptic: { Haptic.error() }) { delete() }
    ///     ])
    func bsContextMenu(_ items: [BsContextMenuItem]) -> some View {
        contextMenu {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                Button(role: item.role) {
                    item.haptic()
                    item.action()
                } label: {
                    Label(item.label, systemImage: item.systemImage)
                }
            }
        }
    }
}

// MARK: - Stagger appear（已有 staggeredAppear，再加一个按序自动版方便用）

public struct BsSequentialAppear: ViewModifier {
    let index: Int
    let baseDelay: Double
    @State private var didAppear: Bool = false

    public func body(content: Content) -> some View {
        content
            .opacity(didAppear ? 1 : 0)
            .offset(y: didAppear ? 0 : 14)
            .animation(
                BsMotion.Anim.overshoot.delay(Double(index) * baseDelay),
                value: didAppear
            )
            .onAppear { didAppear = true }
    }
}

public extension View {
    /// 按序入场 —— 不用外部 @State，onAppear 自行触发。
    /// 比老的 `.staggeredAppear(index:isVisible:)` 少一个参数，
    /// 适合纯声明性列表（ForEach + BsSequentialAppear）。
    func bsAppearStagger(index: Int, baseDelay: Double = 0.05) -> some View {
        modifier(BsSequentialAppear(index: index, baseDelay: baseDelay))
    }
}
