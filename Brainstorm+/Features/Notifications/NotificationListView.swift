import SwiftUI
import Combine

public struct NotificationListView: View {
    @StateObject private var viewModel: NotificationListViewModel
    @State private var filter: Filter = .all

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
                    ProgressView()
                        .scaleEffect(1.2)
                } else if filteredNotifications.isEmpty {
                    VStack(spacing: BsSpacing.md) {
                        filterChipRow
                            .padding(.horizontal, BsSpacing.lg)
                            .padding(.top, BsSpacing.xs)

                        BsEmptyState(
                            title: filter == .unread ? "没有未读通知" : "暂无通知",
                            systemImage: "bell.slash",
                            description: "一切安好"
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
        .navigationTitle("通知")
        .toolbar {
            if unreadCount > 0 {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.markAllAsRead() }
                    } label: {
                        Image(systemName: "checkmark.circle.badge.xmark")
                            .foregroundStyle(BsColor.brandCoral)
                    }
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
    }

    @ViewBuilder
    private var filterChipRow: some View {
        HStack(spacing: BsSpacing.sm) {
            ForEach(Filter.allCases) { f in
                chip(
                    label: f == .unread && unreadCount > 0 ? "未读 (\(unreadCount))" : f.displayLabel,
                    isSelected: filter == f
                ) {
                    Haptic.rigid()
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

    /// 一个通知行 —— glass envelope + swipe "已读" + bsContextMenu + stagger。
    /// 删除动作缺服务端接口（VM 没 delete 方法），所以 trailing swipe 留空
    /// —— 不通过客户端 optimistic 删行，避免与 supabase 状态不一致。
    @ViewBuilder
    private func notificationRow(_ notification: AppNotification, index: Int) -> some View {
        Button {
            Haptic.light()
            Task { await viewModel.markAsRead(notification) }
        } label: {
            NotificationCardView(notification: notification)
        }
        .buttonStyle(.plain)
        .bsAppearStagger(index: index)
        // Leading swipe 只在未读时有意义 —— 已读再 mark 无动作。
        .bsSwipeActions(
            leading: notification.isEffectivelyRead
                ? []
                : [
                    BsSwipeAction.markRead {
                        Task { await viewModel.markAsRead(notification) }
                    }
                  ]
        )
        .bsContextMenu(
            notification.isEffectivelyRead
                ? []
                : [
                    BsContextMenuItem(
                        label: "标记已读",
                        systemImage: "envelope.open.fill",
                        haptic: { Haptic.light() }
                    ) {
                        Task { await viewModel.markAsRead(notification) }
                    }
                  ]
        )
    }
}
