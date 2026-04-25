import SwiftUI

// ══════════════════════════════════════════════════════════════════
// MessagesView —— v1.1 Tab 4「消息」合并容器
//
// 设计来源：docs/plans/2026-04-24-ios-full-redesign-plan.md §三 + §六 Phase 6.3
//
// 聊天 + 通知两个原来相互独立的模块合并进单一 tab。顶部 segmented
// picker 切换：
//   • 聊天   —— 嵌 ChatListView(isEmbedded: true)
//   • 通知   —— 嵌 NotificationListView(isEmbedded: true)
//
// 共享单一 NavigationStack（本 view 外层），二者借用这个 stack 做
// push detail（Phase 3 isEmbedded 基建）。
//
// Picker 选择状态 @AppStorage 持久化——切 tab/后台回来保留用户偏好。
// ══════════════════════════════════════════════════════════════════

public enum MessagesSubTab: String, CaseIterable, Identifiable, Hashable {
    case chat
    case notifications

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .chat:          return "聊天"
        case .notifications: return "通知"
        }
    }
}

public struct MessagesView: View {
    @AppStorage("messagesSubTab") private var selected: MessagesSubTab = .chat

    // VM hoist 到 MessagesView 持有 —— 之前在 body switch 里 `ChatListViewModel(client:)`
    // 每次 picker 切换 / view 重建都新建 VM，channels 列表清零、realtime 订阅断
    // 重连、fetch 重跑 —— 用户感觉"切换 tab 数据消失 / 闪烁不可用"。
    // 用 @StateObject 把 VM 生命周期挂到 MessagesView 本身，segment 切换不重建。
    @StateObject private var chatVM: ChatListViewModel
    @StateObject private var notifVM: NotificationListViewModel

    public init() {
        _chatVM = StateObject(wrappedValue: ChatListViewModel(client: supabase))
        _notifVM = StateObject(wrappedValue: NotificationListViewModel(client: supabase))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented picker — v1.1: 单色 Azure tint 选中态
                Picker("切换聊天或通知", selection: $selected) {
                    ForEach(MessagesSubTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, BsSpacing.lg)
                .padding(.top, BsSpacing.sm)
                .padding(.bottom, BsSpacing.sm)
                .tint(BsColor.brandAzure)
                .accessibilityLabel("消息分类")
                .accessibilityHint("聊天或通知")
                // Haptic removed: 用户反馈 picker 切换过密震动

                Divider()
                    .opacity(0.4)

                // Content swap — 两个 view 都以 isEmbedded: true 借用外层 NavStack。
                // VM 由 MessagesView @StateObject 持有，segment 切换不会重建。
                Group {
                    switch selected {
                    case .chat:
                        ChatListView(viewModel: chatVM, isEmbedded: true)
                    case .notifications:
                        NotificationListView(viewModel: notifVM, isEmbedded: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(BsColor.pageBackground.ignoresSafeArea())
            .navigationTitle("消息")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    MessagesView()
}
