import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 4.1 — 用户管理列表
// Parity target: Web admin/page.tsx 'users' tab (L272-441) + 创建/编辑 modal.
// ══════════════════════════════════════════════════════════════════

public struct AdminUsersView: View {
    let canAssignPrivileges: Bool
    @StateObject private var viewModel = AdminUsersViewModel()
    @Environment(SessionManager.self) private var sessionManager

    @State private var showCreateSheet = false
    @State private var editTarget: AdminUserRow?
    @State private var pendingDeactivate: AdminUserRow?
    @State private var pendingDelete: AdminUserRow?

    private var currentUserId: UUID? {
        sessionManager.currentProfile?.id
    }

    public init(canAssignPrivileges: Bool) {
        self.canAssignPrivileges = canAssignPrivileges
    }

    public var body: some View {
        contentView
            .navigationTitle("用户管理")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("创建用户", systemImage: "person.badge.plus")
                    }
                    .disabled(!canAssignPrivileges)
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
            .confirmationDialog(
                pendingDeactivate.map { "禁用用户 \($0.fullName ?? "")？禁用后该用户将无法登录。" } ?? "",
                isPresented: Binding(
                    get: { pendingDeactivate != nil },
                    set: { if !$0 { pendingDeactivate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("禁用账号", role: .destructive) {
                    if let u = pendingDeactivate {
                        Task {
                            _ = await viewModel.deactivate(userId: u.id)
                            await viewModel.load()
                            pendingDeactivate = nil
                        }
                    }
                }
                Button("取消", role: .cancel) { pendingDeactivate = nil }
            }
            .confirmationDialog(
                pendingDelete.map { "确认删除账号 \($0.fullName ?? "")？" } ?? "",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("确认删除", role: .destructive) {
                    if let u = pendingDelete {
                        Task {
                            _ = await viewModel.softDelete(userId: u.id, targetName: u.fullName ?? "未命名")
                            await viewModel.load()
                            pendingDelete = nil
                        }
                    }
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("iOS 端为软删除（标记为 deleted），物理清理 auth.users 仍需在 Web 超管后台完成。")
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
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredUsers.isEmpty {
                ContentUnavailableView(
                    "暂无用户",
                    systemImage: "person.2.slash",
                    description: Text(viewModel.searchText.isEmpty ? "没有找到用户数据" : "没有匹配的用户")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(viewModel.filteredUsers.enumerated()), id: \.element.id) { index, user in
                        AdminUserRowView(
                            user: user,
                            onEdit: { editTarget = user },
                            onDeactivate: { pendingDeactivate = user },
                            onDelete: { pendingDelete = user },
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
        .background(BsAmbientBackground(includeCoral: true))
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
        .bsContextMenu([
            BsContextMenuItem(
                label: "编辑",
                systemImage: "square.and.pencil",
                action: { onEdit() }
            ),
            BsContextMenuItem(
                label: "复制 ID",
                systemImage: "doc.on.doc",
                action: {
                    UIPasteboard.general.string = user.id.uuidString
                    Haptic.success()
                }
            )
        ])
        .onTapGesture {
            Haptic.light()
            onEdit()
        }
    }

    private func buildTrailingSwipeActions() -> [BsSwipeAction] {
        var actions: [BsSwipeAction] = [
            BsSwipeAction(
                label: "编辑",
                systemImage: "square.and.pencil",
                tint: BsColor.brandAzure,
                haptic: { Haptic.light() },
                action: onEdit
            )
        ]
        if canManage {
            actions.insert(
                BsSwipeAction(
                    label: "禁用",
                    systemImage: "nosign",
                    tint: BsColor.warning,
                    haptic: { Haptic.warning() },
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
