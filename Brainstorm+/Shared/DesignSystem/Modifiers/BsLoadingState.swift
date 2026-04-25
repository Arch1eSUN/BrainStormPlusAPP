import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsLoadingState —— skeleton-first 加载状态语义
//
// 设计理念：
//   传统 ViewModel 用单一 `isLoading: Bool` 把"首次加载 / 后台刷新 /
//   错误 / 空"全部塞进同一条线，UI 表现常常退化成"loading 时整屏覆盖
//   ProgressView，刷新时屏幕闪烁"。BsLoadingState 把这四种状态显式
//   建模，并配套一个 view modifier `bsLoadingState(_:)` 帮助调用者
//   根据状态选择正确的 chrome：
//
//   • .idle      —— 数据已稳定，view 直接渲染，不附加任何覆盖层。
//   • .loading   —— 首次加载（无缓存）。content 用 .redacted 占位 +
//                   shimmering，给"骨架屏"语义。
//   • .stale     —— 已有缓存数据在屏，后台正在刷新。content 正常显示，
//                   右上角悬浮一颗"刷新中..." pill 提示用户后台在动。
//                   这条路径是无缓存阻塞 → 缓存优先 UX 的关键。
//   • .error     —— 后台请求失败。复用 zyErrorBanner 顶部红色横幅。
//   • .empty     —— 加载结束但数据为空。直接渲染 ContentUnavailableView，
//                   优先 iOS 17+ 原生 chrome（图标 + 标题 + 描述）。
//
// 何时用：
//   • 列表 / dashboard / detail 页面顶层包一层 .bsLoadingState(vm.state)，
//     就能把"是否显示骨架 / 是否盖错误条 / 是否换 empty"统一交给设计系统。
//   • ViewModel 暴露一个 `var loadingState: BsLoadingState`（计算属性），
//     根据 `isLoading / cache / error / items.isEmpty` 派生即可。
//
// 不要把它套到所有 view —— 这是"未来迁移"的入口，先发布 modifier，
// 让新写的 feature 直接走这条路；老 feature 可以在重构时再切。
// ══════════════════════════════════════════════════════════════════

public enum BsLoadingState {
    /// 数据稳定，无 chrome。
    case idle
    /// 首次加载，无缓存。content 上 redacted + shimmer。
    case loading
    /// 缓存数据已在屏，后台刷新中。右上角悬浮"刷新中..." pill。
    case stale
    /// 加载失败。错误信息会通过顶部 banner 呈现。
    case error(String)
    /// 数据为空。渲染 ContentUnavailableView 替代 content。
    case empty(systemImage: String, title: String, description: String?)
}

private struct BsLoadingStateModifier: ViewModifier {
    let state: BsLoadingState
    @State private var bannerMessage: String? = nil

    func body(content: Content) -> some View {
        Group {
            switch state {
            case .idle:
                content

            case .loading:
                content
                    .redacted(reason: .placeholder)
                    .shimmering()
                    .accessibilityLabel("正在加载")

            case .stale:
                content
                    .overlay(alignment: .topTrailing) {
                        StaleRefreshPill()
                            .padding(.top, BsSpacing.sm)
                            .padding(.trailing, BsSpacing.md)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

            case .error(let message):
                content
                    .zyErrorBanner($bannerMessage)
                    .task(id: message) {
                        bannerMessage = message
                    }

            case .empty(let systemImage, let title, let description):
                ContentUnavailableView(
                    title,
                    systemImage: systemImage,
                    description: description.map(Text.init)
                )
            }
        }
        .animation(BsMotion.Anim.gentle, value: stateKey)
    }

    /// Stable key for animation triggers — switching across cases re-renders.
    private var stateKey: String {
        switch state {
        case .idle: return "idle"
        case .loading: return "loading"
        case .stale: return "stale"
        case .error(let msg): return "error:\(msg)"
        case .empty(_, let title, _): return "empty:\(title)"
        }
    }
}

private struct StaleRefreshPill: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
                .tint(BsColor.brandAzure)
            Text("刷新中…")
                .font(.caption2.weight(.medium))
                .foregroundStyle(BsColor.brandAzureDark)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(BsColor.brandAzureLight.opacity(0.92))
        )
        .accessibilityLabel("正在后台刷新")
    }
}

public extension View {
    /// Apply skeleton / stale-pill / error-banner / empty chrome based on
    /// a `BsLoadingState`. Keeps the underlying view mounted so layout
    /// doesn't jump between transitions.
    ///
    /// - Parameter state: the current load state. Drive from a VM-computed
    ///   property — see header doc above for the recommended derivation.
    func bsLoadingState(_ state: BsLoadingState) -> some View {
        modifier(BsLoadingStateModifier(state: state))
    }
}

// ══════════════════════════════════════════════════════════════════
// MARK: - Iter 7 §C 推广 helpers
//
// 大多数 VM 已经持有 `isLoading: Bool`、`items: [T]`、`errorMessage: String?`
// 这套常见组合。`BsLoadingState.derive(...)` 把这些散字段折成一个 enum，
// VM 不必新增 `loadingState` published —— View 在调用站点里直接 derive。
//
// 不在 VM 里 cache `BsLoadingState` 是有意为之：enum 关联值 (.empty 的
// systemImage/title) 通常依赖 view 层的语境（"暂无任务" vs "暂无项目"），
// 放 VM 里反而要传 RawRepresentable，复杂度跳一档。
// ══════════════════════════════════════════════════════════════════

public extension BsLoadingState {
    /// VM-friendly derivation. Hand it the four typical published fields
    /// + an empty-state spec; it returns the right `BsLoadingState`:
    ///
    ///   • items 空 + isLoading + 无 error → .loading
    ///   • items 非空 + isLoading           → .stale
    ///   • errorMessage != nil              → .error(msg)
    ///   • items 空 + 已加载                → .empty(...)
    ///   • 其它                             → .idle
    ///
    /// 用法（典型 list view body 顶层）：
    /// ```
    /// List(items) { ... }
    ///   .bsLoadingState(BsLoadingState.derive(
    ///     isLoading: vm.isLoading,
    ///     hasItems: !vm.items.isEmpty,
    ///     errorMessage: vm.errorMessage,
    ///     emptySystemImage: "tray",
    ///     emptyTitle: "暂无任务",
    ///     emptyDescription: "下拉刷新或点击右上角新建"
    ///   ))
    /// ```
    static func derive(
        isLoading: Bool,
        hasItems: Bool,
        errorMessage: String?,
        emptySystemImage: String,
        emptyTitle: String,
        emptyDescription: String? = nil
    ) -> BsLoadingState {
        // error 优先级最高 —— 用户看到红色 banner 就知道要重试，不该被
        // skeleton/empty 把错误信息盖住。
        if let msg = errorMessage, !msg.isEmpty {
            return .error(msg)
        }
        if isLoading && !hasItems {
            return .loading
        }
        if isLoading && hasItems {
            return .stale
        }
        if !hasItems {
            return .empty(
                systemImage: emptySystemImage,
                title: emptyTitle,
                description: emptyDescription
            )
        }
        return .idle
    }
}
