import SwiftUI

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

    // TODO(phase-12): 接 ApprovalCenterViewModel 汇总待我审的总 pending 数,
    // 目前留占位 — 不拖住这次 tab bar 重写的交付。
    @State private var approvalPendingBadge: Int = 0
    // TODO(phase-12): 接 ChatListViewModel.unreadCount(汇总频道未读),
    // 目前 ChatListViewModel 没有对外暴露汇总字段,先占位。
    @State private var chatUnreadBadge: Int = 0

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
                .badge(approvalPendingBadge > 0 ? approvalPendingBadge : 0)
                .tag(Tab.approvals)

            // ── 消息 ──
            // ChatListView 的 init 要求外部传入 VM,与 TaskListView 同构。
            LazyView(ChatListView(viewModel: ChatListViewModel(client: supabase)))
                .tabItem {
                    Label("消息", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .badge(chatUnreadBadge > 0 ? chatUnreadBadge : 0)
                .tag(Tab.chat)

            // ── 我的 (Profile + Settings) ──
            LazyView(SettingsView())
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle.fill")
                }
                .tag(Tab.me)
        }
        .tint(BsColor.brandAzure)
        .onChange(of: selectedTab) { _, _ in
            Haptic.selection()
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
