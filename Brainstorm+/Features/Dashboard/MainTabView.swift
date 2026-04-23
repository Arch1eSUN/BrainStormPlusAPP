import SwiftUI

// ══════════════════════════════════════════════════════════════════
// MainTabView — iOS 26 原生 TabView 重写 (Phase 11.x)
//
// 替换掉旧实现的两个反模式:
//   1. .tabViewStyle(.page(indexDisplayMode: .never)) + 手搓 FloatingTabBar
//      → 用户会误触横滑在 Dashboard/Tasks 之间切换 (两者无语义顺序关系)
//   2. 每个 tab 内 .navigationBarHidden(true) + 全局 UINavigationBarAppearance
//      hack → 会把 Phase 11 的 Large Title 吃掉
//
// 新实现 = iOS 26 原生 Liquid Glass tab bar (Slack / Instagram / WeChat 规范):
//   • 5 个 tab: 工作台 / 任务 / 审批 / 消息 / 我的
//   • 每个 tab 内部已自带 NavigationStack + .navigationTitle,这里不再套一层
//   • LazyView 包装 —— 首次进入才构造,避免启动时同时初始化 5 个 Supabase 订阅
//   • .badge(...) 原生红点 badge
//   • Haptic.selection() 保持切换反馈
//
// 已刻意裁掉的内容 (不是遗漏):
//   • Copilot tab — 移到 Dashboard toolbar trailing 按钮触发 sheet (后续 phase)
//   • Schedule tab — 日程已经作为 Dashboard schedule section 呈现,不再独立 tab
//   • FloatingTabBar struct — 整块删除,原生 tab bar 接管
//   • UINavigationBarAppearance .onAppear hack — Phase 11 各视图已走
//     .navigationTitle + .navigationBarTitleDisplayMode(.large) 原生链路
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
            // ── 工作台 ──
            LazyView(DashboardView())
                .tabItem {
                    Label("工作台", systemImage: "square.grid.2x2.fill")
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
