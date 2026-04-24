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

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented picker — v1.1: 单色 Azure tint 选中态
                Picker("", selection: $selected) {
                    ForEach(MessagesSubTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, BsSpacing.lg)
                .padding(.top, BsSpacing.sm)
                .padding(.bottom, BsSpacing.sm)
                .tint(BsColor.brandAzure)

                Divider()
                    .opacity(0.4)

                // Content swap — 两个 view 都以 isEmbedded: true 借用外层 NavStack
                Group {
                    switch selected {
                    case .chat:
                        ChatListView(
                            viewModel: ChatListViewModel(client: supabase),
                            isEmbedded: true
                        )
                    case .notifications:
                        NotificationListView(
                            viewModel: NotificationListViewModel(client: supabase),
                            isEmbedded: true
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(BsColor.pageBackground.ignoresSafeArea())
            .navigationTitle("消息")
            .navigationBarTitleDisplayMode(.large)
            .onChange(of: selected) { _, _ in
                Haptic.light()
            }
        }
    }
}

#Preview {
    MessagesView()
}
