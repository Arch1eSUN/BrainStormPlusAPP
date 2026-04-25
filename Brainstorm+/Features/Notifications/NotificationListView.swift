import SwiftUI
import Combine

public struct NotificationListView: View {
    @StateObject private var viewModel: NotificationListViewModel
    @State private var filter: Filter = .all
    /// 删除二次确认 —— destructive 动作走 confirmationDialog（iOS 26 习惯）。
    @State private var pendingDelete: AppNotification? = nil

    public enum Filter: String, CaseIterable, Identifiable {
        case all
        case unread

        public var id: String { rawValue }

        public var displayLabel: String {
            switch self {
            case .all:    return "全部"
            case .unread: return "未读"
            }
        }
    }

    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    public init(viewModel: NotificationListViewModel, isEmbedded: Bool = false) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.isEmbedded = isEmbedded
    }

    private var filteredNotifications: [AppNotification] {
        switch filter {
        case .all:    return viewModel.notifications
        case .unread: return viewModel.notifications.filter { !$0.isEffectivelyRead }
        }
    }

    private var unreadCount: Int {
        viewModel.notifications.filter { !$0.isEffectivelyRead }.count
    }

    public var body: some View {
        if isEmbedded {
            coreContent
        } else {
            NavigationStack { coreContent }
        }
    }

    private var coreContent: some View {
        ZStack {
            // Fusion ambient 底层 —— 通知列表需要"airy"感，不是白底。
            BsColor.pageBackground.ignoresSafeArea()

            Group {
                if viewModel.isLoading && viewModel.notifications.isEmpty {
                    notificationSkeleton
                } else if filteredNotifications.isEmpty {
                    VStack(spacing: BsSpacing.md) {
                        filterChipRow
                            .padding(.horizontal, BsSpacing.lg)
                            .padding(.top, BsSpacing.xs)

                        BsEmptyState(
                            title: filter == .unread ? "全部已读" : "暂无通知",
                            systemImage: filter == .unread ? "envelope.open" : "bell.slash",
                            description: filter == .unread
                                ? "最近没有新的提醒"
                                : "新任务、审批与消息会在此汇总"
                        )
                        .padding(.top, BsSpacing.xxl + 8)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, BsSpacing.lg)
                } else {
                    // 用 List 才能走 native swipeActions —— Mail.app-style
                    // leading "已读" / trailing "删除"。List 自带 scroll，
                    // 顶部 filterChipRow 放 safeAreaInset 贴着导航栏。
                    List {
                        Section {
                            ForEach(Array(filteredNotifications.enumerated()), id: \.element.id) { idx, notification in
                                notificationRow(notification, index: idx)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(
                                        top: BsSpacing.xs,
                                        leading: BsSpacing.lg,
                                        bottom: BsSpacing.xs,
                                        trailing: BsSpacing.lg
                                    ))
                            }
                        } header: {
                            filterChipRow
                                .padding(.vertical, BsSpacing.xs)
                                .listRowInsets(EdgeInsets(
                                    top: 0,
                                    leading: BsSpacing.lg,
                                    bottom: BsSpacing.xs,
                                    trailing: BsSpacing.lg
                                ))
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        // embedded（MessagesView 通知 sub-tab）时,外层 NavStack 的标题由
        // MessagesView 控制（"消息"）,child 再 set title 会导致 iOS 26 nav
        // bar 出现 replay / layout 塌陷。用 modifier 条件应用,而不是 set ""
        // —— set "" 会把外层 title 覆盖成空,出现"消息"title 突然消失的闪烁。
        .modifier(ConditionalNavTitleN(isEmbedded: isEmbedded, title: "通知"))
        .toolbar {
            if unreadCount > 0 {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Haptic.medium()
                        Task { await viewModel.markAllAsRead() }
                    } label: {
                        Label("全部已读", systemImage: "envelope.open.fill")
                            .font(BsTypography.captionSmall.weight(.semibold))
                            .foregroundStyle(BsColor.brandAzure)
                    }
                    .accessibilityLabel("全部标记为已读")
                }
            }
        }
        .refreshable {
            await viewModel.fetchNotifications()
        }
        .task {
            await viewModel.fetchNotifications()
        }
        .zyErrorBanner($viewModel.errorMessage)
        // Single source of truth for the destructive delete dialog —— hoisted
        // here (vs. attached per-row) so SwiftUI doesn't render N dialog
        // bindings, and dismissal is unambiguous (set pendingDelete = nil).
        .confirmationDialog(
            "删除该通知？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { target in
            Button("删除", role: .destructive) {
                Haptic.warning() // destructive 真删确认完成
                Task { await viewModel.delete(target) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("此操作不可撤销")
        }
    }

    /// Loading skeleton —— 行高对齐 NotificationCardView 视觉密度
    @ViewBuilder
    private var notificationSkeleton: some View {
        VStack(spacing: BsSpacing.md) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(alignment: .top, spacing: BsSpacing.md) {
                    Circle()
                        .fill(BsColor.inkFaint.opacity(0.18))
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(BsColor.inkFaint.opacity(0.18))
                            .frame(height: 13)
                            .frame(maxWidth: 210, alignment: .leading)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(BsColor.inkFaint.opacity(0.12))
                            .frame(height: 11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, BsSpacing.lg)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, BsSpacing.lg)
        .shimmer()
        .accessibilityLabel("正在加载通知")
    }

    @ViewBuilder
    private var filterChipRow: some View {
        HStack(spacing: BsSpacing.sm) {
            ForEach(Filter.allCases) { f in
                chip(
                    label: f == .unread && unreadCount > 0 ? "未读 · \(unreadCount)" : f.displayLabel,
                    isSelected: filter == f
                ) {
                    // Haptic removed: 用户反馈 chip filter 切换过密震动
                    filter = f
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(BsTypography.caption)
                .padding(.horizontal, BsSpacing.md)
                .padding(.vertical, BsSpacing.xs + 2)
                // Fusion glass chip：selected → azure glass tint；rest → neutral glass
                .glassEffect(
                    isSelected
                        ? .regular.tint(BsColor.brandAzure.opacity(0.35)).interactive()
                        : .regular.interactive(),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? BsColor.brandAzure : BsColor.ink)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notification row

    /// 一个通知行 —— glass envelope + swipe "已读" + 长按 contextMenu + stagger。
    ///
    /// 长按菜单（docs/longpress-system.md）：
    ///   • 标已读 / 标未读（互斥，按当前 read 状态显示）
    ///   • 打开来源（如 link 非空）
    ///   • 删除（destructive，confirmationDialog 二次确认）
    @ViewBuilder
    private func notificationRow(_ notification: AppNotification, index: Int) -> some View {
        Button {
            // Haptic removed: 用户反馈列表行点击期待静默
            Task { await viewModel.markAsRead(notification) }
        } label: {
            NotificationCardView(notification: notification)
        }
        .buttonStyle(.plain)
        .bsAppearStagger(index: index)
        // Leading swipe：未读 → 标已读。Mail.app 镜像。
        // Trailing swipe：删除（走 pendingDelete confirmation，避免 fullSwipe 误触）。
        // contextMenu 与 swipe 共享同一 destructive state —— 双入口同终点。
        .bsSwipeActions(
            leading: notification.isEffectivelyRead
                ? []
                : [
                    BsSwipeAction.markRead {
                        Task { await viewModel.markAsRead(notification) }
                    }
                  ],
            trailing: [
                BsSwipeAction.delete {
                    pendingDelete = notification
                }
            ],
            allowsFullSwipe: false
        )
        .contextMenu {
            // —— 顶部：read-state toggle（按当前状态选择 mark）
            if notification.isEffectivelyRead {
                Button {
                    // Haptic removed: contextMenu 选项过密震动
                    Task { await viewModel.markAsUnread(notification) }
                } label: {
                    Label("标为未读", systemImage: "envelope.badge")
                }
            } else {
                Button {
                    // Haptic removed: contextMenu 选项过密震动
                    Task { await viewModel.markAsRead(notification) }
                } label: {
                    Label("标为已读", systemImage: "envelope.open.fill")
                }
            }

            // —— 中部：跳转到来源（link 非空时）
            // notification.link 通常是 web 路径（"/dashboard/tasks/..."）；
            // 这里用 UIApplication.open 让系统自动决定（universal link 走 in-app，
            // 否则 fallback Safari）。
            if let link = notification.link, !link.isEmpty,
               let url = URL(string: link)
            {
                Button {
                    // Haptic removed: contextMenu 选项过密震动
                    #if canImport(UIKit)
                    UIApplication.shared.open(url)
                    #endif
                } label: {
                    Label("打开来源", systemImage: "arrow.up.forward.app")
                }
            }

            // —— 底部：destructive
            Button(role: .destructive) {
                // Haptic removed: 仅打开 confirm dialog，真删确认时再震
                pendingDelete = notification
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

// MARK: - ConditionalNavTitleN
// embedded 时完全跳过 `.navigationTitle`,让外层容器独占 nav bar 标题。
// 命名带 N 后缀避免与 ChatListView 的同名 helper 冲突（同一 target 下
// private 名字作用域按文件隔离,但显式区分便于 grep）。
private struct ConditionalNavTitleN: ViewModifier {
    let isEmbedded: Bool
    let title: String

    func body(content: Content) -> some View {
        if isEmbedded {
            content
        } else {
            content.navigationTitle(title)
        }
    }
}
