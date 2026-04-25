import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 4.1 — 用户管理列表
// Parity target: Web admin/page.tsx 'users' tab (L272-441) + 创建/编辑 modal.
// ══════════════════════════════════════════════════════════════════

public struct AdminUsersView: View {
    let canAssignPrivileges: Bool
    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool
    @StateObject private var viewModel = AdminUsersViewModel()
    @Environment(SessionManager.self) private var sessionManager

    @State private var showCreateSheet = false
    @State private var editTarget: AdminUserRow?
    /// Iter5 — 合并两个 confirmationDialog 为一个,通过 enum 区分意图。
    /// 之前两个 dialog 同时挂在 contentView 上,iOS 26 上后挂的会"吃掉"前一个,
    /// 表现为弹窗位置错乱、点击删除没反应。改用 presenting: 形态,弹窗按钮闭包
    /// 拿到的是 enum payload 的强引用,不依赖 @State 的 race。
    @State private var pendingAction: PendingAction?

    private enum PendingAction: Identifiable, Equatable {
        case deactivate(AdminUserRow)
        case delete(AdminUserRow)

        var id: String {
            switch self {
            case .deactivate(let u): return "deactivate-\(u.id.uuidString)"
            case .delete(let u): return "delete-\(u.id.uuidString)"
            }
        }

        var user: AdminUserRow {
            switch self {
            case .deactivate(let u), .delete(let u): return u
            }
        }
    }

    private var currentUserId: UUID? {
        sessionManager.currentProfile?.id
    }

    public init(canAssignPrivileges: Bool, isEmbedded: Bool = false) {
        self.canAssignPrivileges = canAssignPrivileges
        self.isEmbedded = isEmbedded
    }

    public var body: some View {
        if isEmbedded {
            coreContent
        } else {
            NavigationStack { coreContent }
        }
    }

    private var coreContent: some View {
        contentView
            .navigationTitle("用户管理")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Haptic removed: 用户反馈 toolbar 按钮过密震动
                        showCreateSheet = true
                    } label: {
                        Label("创建用户", systemImage: "person.badge.plus")
                    }
                    .disabled(!canAssignPrivileges)
                    .accessibilityLabel("创建用户")
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "搜索姓名、邮箱、部门…")
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
            .sheet(isPresented: $showCreateSheet) {
                AdminUserCreateSheet(
                    canAssignPrivileges: canAssignPrivileges,
                    departments: viewModel.departmentsList,
                    positions: viewModel.positionsList
                ) {
                    Task { await viewModel.load() }
                }
            }
            .sheet(item: $editTarget) { row in
                AdminUserEditSheet(
                    userId: row.id,
                    canAssignPrivileges: canAssignPrivileges,
                    departments: viewModel.departmentsList,
                    positions: viewModel.positionsList
                ) {
                    Task { await viewModel.load() }
                }
            }
            // Iter5 — 单一 confirmationDialog,以 enum payload 驱动两种危险操作。
            // presenting: 形态保证按钮闭包能拿到 strong-ref'd payload,即便
            // pendingAction 已被 dismiss 清空也不影响 await 内部逻辑。
            .confirmationDialog(
                dialogTitle(for: pendingAction),
                isPresented: Binding(
                    get: { pendingAction != nil },
                    set: { if !$0 { pendingAction = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingAction
            ) { action in
                switch action {
                case .deactivate(let user):
                    Button("禁用账号", role: .destructive) {
                        Task {
                            _ = await viewModel.deactivate(userId: user.id)
                            await viewModel.load()
                        }
                    }
                    Button("取消", role: .cancel) { }
                case .delete(let user):
                    Button("确认删除", role: .destructive) {
                        let name = user.fullName ?? "未命名"
                        Task {
                            _ = await viewModel.softDelete(userId: user.id, targetName: name)
                            await viewModel.load()
                        }
                    }
                    Button("取消", role: .cancel) { }
                }
            } message: { action in
                switch action {
                case .delete:
                    Text("iOS 端为软删除（标记为 deleted），物理清理 auth.users 仍需在 Web 超管后台完成。")
                case .deactivate:
                    Text("禁用后该用户将无法登录,可在编辑页恢复为活跃状态。")
                }
            }
            .zyErrorBanner($viewModel.errorMessage)
    }

    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: 0) {
            roleFilterStrip
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

            if viewModel.isLoading && viewModel.users.isEmpty {
                // Bug-fix(loading 一致性): full-screen loading 用 .large 圈。
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredUsers.isEmpty {
                BsEmptyState(
                    title: "暂无用户",
                    systemImage: "person.2.slash",
                    description: viewModel.searchText.isEmpty ? "没有找到用户数据" : "没有匹配的用户"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(viewModel.filteredUsers.enumerated()), id: \.element.id) { index, user in
                        AdminUserRowView(
                            user: user,
                            onEdit: { editTarget = user },
                            onDeactivate: { pendingAction = .deactivate(user) },
                            onDelete: { pendingAction = .delete(user) },
                            canManage: canAssignPrivileges,
                            isSelf: user.id == currentUserId
                        )
                        .listRowBackground(Color.clear)
                        .bsAppearStagger(index: index)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(BsColor.pageBackground.ignoresSafeArea())
    }

    private func dialogTitle(for action: PendingAction?) -> String {
        guard let action else { return "" }
        switch action {
        case .deactivate(let u): return "禁用用户 \(u.fullName ?? "未命名")?"
        case .delete(let u): return "确认删除账号 \(u.fullName ?? "未命名")?"
        }
    }

    private var roleFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "全部", value: "")
                filterChip(title: "超级管理员", value: "superadmin")
                filterChip(title: "管理员", value: "admin")
                filterChip(title: "员工", value: "employee")
            }
        }
    }

    private func filterChip(title: String, value: String) -> some View {
        let isSelected = viewModel.roleFilter == value
        return Button {
            // Haptic removed: 用户反馈 chip 切换过密震动
            viewModel.roleFilter = value
            Task { await viewModel.load() }
        } label: {
            Text(title)
                .font(BsTypography.captionSmall)
                .padding(.horizontal, BsSpacing.md)
                .padding(.vertical, BsSpacing.sm - 1)
                .background(
                    Capsule().fill(isSelected ? BsColor.brandAzure.opacity(0.15) : BsColor.inkMuted.opacity(0.08))
                )
                .foregroundStyle(isSelected ? BsColor.brandAzure : BsColor.ink)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row View

private struct AdminUserRowView: View {
    let user: AdminUserRow
    let onEdit: () -> Void
    let onDeactivate: () -> Void
    let onDelete: () -> Void
    let canManage: Bool
    let isSelf: Bool

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: BsSpacing.xs) {
                HStack(spacing: 6) {
                    Text(user.fullName?.isEmpty == false ? user.fullName! : "未命名")
                        .font(BsTypography.cardSubtitle)
                        .foregroundStyle(BsColor.ink)
                    if isSelf {
                        Text("本人")
                            .font(BsTypography.meta)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(BsColor.brandMint.opacity(0.2)))
                            .foregroundStyle(BsColor.brandAzureDark)
                    }
                }
                HStack(spacing: 6) {
                    Text(adminAppRoleLabel(adminDbRoleToAppRole(user.role)))
                        .font(BsTypography.meta)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(BsColor.brandAzure.opacity(0.12)))
                        .foregroundStyle(BsColor.brandAzure)
                    statusPill
                }
                if let dept = user.department, !dept.isEmpty {
                    Text(dept + (user.position.map { " · \($0)" } ?? ""))
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .bsSwipeActions(
            trailing: buildTrailingSwipeActions(),
            allowsFullSwipe: false
        )
        // Long-press v3:管理员行长按补全 —— 编辑/修改角色/复制 ID
        // + destructive (禁用 / 删除)。修改角色目前与编辑共享 sheet,
        // AdminUserEditSheet 内部含角色 picker;独立 surface 是 nice-to-have。
        .bsContextMenu(buildContextMenu())
        .onTapGesture {
            // Haptic removed: 用户反馈列表行点击过密震动
            onEdit()
        }
    }

    private func buildContextMenu() -> [BsContextMenuItem] {
        var items: [BsContextMenuItem] = []
        items.append(BsContextMenuItem(
            label: "编辑",
            systemImage: "square.and.pencil",
            action: { onEdit() }
        ))
        if canManage {
            items.append(BsContextMenuItem(
                label: "修改角色",
                systemImage: "person.badge.shield.checkmark",
                action: { onEdit() }   // sheet 内含角色 picker
            ))
        }
        items.append(BsContextMenuItem(
            label: "复制 ID",
            systemImage: "doc.on.doc",
            action: {
                UIPasteboard.general.string = user.id.uuidString
                Haptic.light()
            }
        ))
        if canManage && !isSelf {
            items.append(BsContextMenuItem(
                label: "禁用账号",
                systemImage: "nosign",
                role: .destructive,
                haptic: { Haptic.warning() },
                action: { onDeactivate() }
            ))
            items.append(BsContextMenuItem(
                label: "删除",
                systemImage: "trash",
                role: .destructive,
                haptic: { Haptic.warning() },
                action: { onDelete() }
            ))
        }
        return items
    }

    private func buildTrailingSwipeActions() -> [BsSwipeAction] {
        var actions: [BsSwipeAction] = [
            BsSwipeAction(
                label: "编辑",
                systemImage: "square.and.pencil",
                tint: BsColor.brandAzure,
                haptic: { /* Haptic removed: swipe action 系统自带反馈 */ },
                action: onEdit
            )
        ]
        if canManage {
            actions.insert(
                BsSwipeAction(
                    label: "禁用",
                    systemImage: "nosign",
                    tint: BsColor.warning,
                    haptic: { /* Haptic removed: swipe action 系统自带反馈 */ },
                    action: onDeactivate
                ),
                at: 0
            )
            actions.insert(.delete(action: onDelete), at: 0)
        }
        return actions
    }

    private var avatar: some View {
        let initial = String(user.fullName?.first ?? user.displayName?.first ?? "?")
        return ZStack {
            Circle()
                .fill(BsColor.brandAzure.opacity(0.15))
                .overlay(
                    Circle()
                        .stroke(BsColor.brandAzure.opacity(0.25), lineWidth: 0.5)
                )
            Text(initial)
                .font(BsTypography.cardTitle)
                .foregroundStyle(BsColor.brandAzure)
        }
        .frame(width: 40, height: 40)
        .accessibilityLabel(user.fullName ?? user.displayName ?? "用户")
    }

    @ViewBuilder
    private var statusPill: some View {
        let active = (user.status ?? "active") == "active"
        Text(active ? "活跃" : (user.status == "deleted" ? "已删除" : "已禁用"))
            .font(BsTypography.meta)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(active ? BsColor.success.opacity(0.15) : BsColor.danger.opacity(0.15))
            )
            .foregroundStyle(active ? BsColor.success : BsColor.danger)
    }
}
