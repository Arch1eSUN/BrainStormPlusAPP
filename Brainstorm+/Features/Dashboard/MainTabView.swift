import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// MainTabView — iOS 26 原生 TabView（v1.1 骨架）
//
// 5 tab 骨架（plan docs/plans/2026-04-24-ios-full-redesign-plan.md §三）:
//   1. 首页  —— Widget-card Dashboard（wordmark 代替 Large Title；Phase 4 重建）
//   2. 任务  —— Tasks list/kanban（高频每日）
//   3. 审批  —— Approvals 提交 + 我审 queue
//   4. 消息  —— 聊天 + 通知合并（Phase 6 顶部 sub-tab 切换）
//   5. 我的  —— Profile + 偏好 + 支持 + 退出（Phase 6 admin entry 移至 launcher）
//
// 实现要点:
//   • iOS 26 原生 Liquid Glass tab bar (Slack / Instagram / WeChat 规范)
//   • 每 tab 内部已自带 NavigationStack + .navigationTitle,这里不再套一层
//     （Phase 3 会给 destination 加 isEmbedded 参数进一步统一）
//   • LazyView 包装 —— 首次进入才构造,避免启动时同时初始化 5 个 Supabase 订阅
//   • .badge(...) 原生红点 badge
//   • .tint(BsColor.brandAzure) — v1.1 主交互色
//   • Haptic.selection() 切换反馈
//
// 已刻意裁掉的 tab (不是遗漏):
//   • AI Copilot tab — 用户要求 Phase 0/8 期间删除 Copilot 功能
//   • Schedule tab — 日程已作为 Dashboard 内 section,不再独立
//   • FloatingTabBar struct — 原生 tab bar 接管,手搓实现整块删除
//
// v1.1 后续微调（不在 Phase 2 范围）:
//   • Role-based tab 2 排序（员工=任务 / 经理=审批，根据 RBAC 动态）— Phase 6
//   • Messages = Chat + Notifications 合并 sub-tab — Phase 6
// ══════════════════════════════════════════════════════════════════

struct MainTabView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var selectedTab: Tab = .dashboard

    // v1.2 Phase 12 — tab badge 实时数据源:
    //   • 审批 = 所有可见 ApprovalQueueKind 的 pending head-count 汇总
    //     （RLS 已经过滤掉非审批人看不到的行,allCases 汇总是安全的)
    //   • 消息 = 通知未读数（chat 未实现 last_read 追踪,暂不计入;
    //     MessagesView 合并了通知,语义仍然闭合)
    // 初次拉取在 .task {},切 tab 时再刷新一次,无需 realtime 订阅。
    @StateObject private var badgeCoordinator = TabBadgeCoordinator(client: supabase)

    enum Tab: Hashable {
        case dashboard, tasks, approvals, chat, me
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // ── 首页 ──
            // v1.1: 名字从"工作台"改"首页"（plan §三）；视觉 Phase 4 重建
            // 为 widget-card Dashboard + wordmark NavBar + liquid fill hero。
            LazyView(DashboardView())
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
                .tag(Tab.dashboard)

            // ── 任务 ──
            // TaskListView 的 init 需要显式 VM,VM 需要 supabase client。
            // 用 LazyView 包住 → 首次切到该 tab 才构造 VM,不在启动时拉一次任务列表。
            LazyView(TaskListView(viewModel: TaskListViewModel(client: supabase)))
                .tabItem {
                    Label("任务", systemImage: "checklist")
                }
                .tag(Tab.tasks)

            // ── 审批 ──
            // ApprovalCenterView 默认 init 会用 module-level `supabase`,
            // 内部 @StateObject 自行持有 MySubmissionsViewModel。
            LazyView(ApprovalCenterView())
                .tabItem {
                    Label("审批", systemImage: "checkmark.seal.fill")
                }
                .badge(badgeCoordinator.approvalBadgeText)
                .tag(Tab.approvals)

            // ── 消息 ──
            // v1.1: 消息 = 聊天 + 通知 合并（plan §六 Phase 6.3）
            // 顶部 segmented picker 切换两个 sub-tab，外层 NavStack 由 MessagesView 接管
            LazyView(MessagesView())
                .tabItem {
                    Label("消息", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .badge(badgeCoordinator.messagesBadgeText)
                .tag(Tab.chat)

            // ── 我的 (Profile + Settings) ──
            LazyView(SettingsView())
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle.fill")
                }
                .tag(Tab.me)
        }
        .tint(BsColor.brandAzure)
        .onChange(of: selectedTab) { _, newTab in
            Haptic.selection()
            // 切到对应 tab 时触发该 badge 的轻量刷新 —— 进入 tab 内部各自
            // VM 会 fetch 更完整的数据，这里只保证 badge 值紧跟离开 tab
            // 后的状态（例如在 ApprovalCenterView 审批完一条，切回主 tab
            // bar 时 badge 立即回落)。
            Task { await badgeCoordinator.refresh(for: newTab) }
        }
        .task {
            await badgeCoordinator.refreshAll()
        }
    }
}

// MARK: - TabBadgeCoordinator
//
// v1.2 Phase 12 — MainTabView 轻量 badge 数据源。
//
// 为什么不复用 ApprovalQueueViewModel / ChatListViewModel:
//   • ApprovalCenterView 内部按 `ApprovalQueueKind` 分片,自己已经用
//     `fetchPendingCount` head-count;MainTabView 外层要的是"汇总",
//     所以在这里再跑一次 TaskGroup 汇总 —— 共享的是静态方法,不是 VM
//     实例。
//   • ChatListViewModel 只在消息 tab 挂载时存在,MainTabView 无法持有;
//     并且 chat 目前没有 last_read_at 这类成员级已读列,真正的"未读汇总"
//     拿不到 —— 改由 `notifications.is_read = false` 的 COUNT 驱动消息
//     tab badge,语义上 MessagesView 也合并了通知这一 sub-tab。
//
// 刷新节奏:
//   • 启动 .task {} 一次拉全量
//   • 切 tab 时 onChange 触发该 tab 的 badge 单独 refresh
//   • 不订阅 realtime —— tab 内部 VM 有自己的 refresh / pull-to-refresh,
//     badge 只需要反映"上次离开应用以来"的状态。
@MainActor
final class TabBadgeCoordinator: ObservableObject {
    @Published private(set) var approvalPending: Int = 0
    @Published private(set) var messagesUnread: Int = 0

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// `.badge(_: Text?)` 接受 Optional<Text>。count<=0 时返回 nil,让 SwiftUI
    /// 不渲染红点;>99 封顶显示 "99+" 对齐 ApprovalCenterView 内部 pill。
    var approvalBadgeText: Text? {
        badgeText(for: approvalPending)
    }

    var messagesBadgeText: Text? {
        badgeText(for: messagesUnread)
    }

    private func badgeText(for count: Int) -> Text? {
        guard count > 0 else { return nil }
        return Text(count > 99 ? "99+" : "\(count)")
    }

    // MARK: - Refresh

    func refreshAll() async {
        async let approvals: Void = refreshApprovalPending()
        async let messages: Void = refreshMessagesUnread()
        _ = await (approvals, messages)
    }

    func refresh(for tab: MainTabView.Tab) async {
        switch tab {
        case .approvals: await refreshApprovalPending()
        case .chat: await refreshMessagesUnread()
        default: break
        }
    }

    /// 并行跑所有 ApprovalQueueKind 的 head-count,汇总为总 pending。
    /// RLS 已经在 DB 层面过滤非审批人看不到的行,即便普通员工触发也是 0。
    private func refreshApprovalPending() async {
        let kinds = ApprovalQueueKind.allCases
        let total: Int = await withTaskGroup(of: Int.self) { group in
            for kind in kinds {
                group.addTask { [client] in
                    await ApprovalQueueViewModel.fetchPendingCount(kind: kind, client: client)
                }
            }
            var sum = 0
            for await n in group { sum += n }
            return sum
        }
        self.approvalPending = total
    }

    /// notifications.is_read = false + user_id = self 的 head-count。
    /// chat 没有 last_read 列,暂不计入 —— 消息 tab 在 MessagesView 合并了
    /// 通知,用通知未读作代理语义闭合。
    private func refreshMessagesUnread() async {
        do {
            let currentUserId = try await client.auth.session.user.id
            let response = try await client
                .from("notifications")
                .select("*", head: true, count: .exact)
                .eq("user_id", value: currentUserId.uuidString)
                .eq("is_read", value: false)
                .execute()
            self.messagesUnread = response.count ?? 0
        } catch {
            // 悄悄失败 —— badge 是辅助信息,不值得弹 banner。
            self.messagesUnread = 0
        }
    }
}

// MARK: - LazyView
// 经典 iOS 懒加载包装:TabView 默认会立即实例化所有 tab 的 root view,
// 对于带 Supabase 订阅 / realtime 的 VM 会在启动时一次性起 N 条连接。
// LazyView 把 view body 的构造推迟到真正访问时 —— 切到该 tab 才会
// 调用 build()。
struct LazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    var body: Content { build() }
}

#Preview {
    MainTabView()
}
