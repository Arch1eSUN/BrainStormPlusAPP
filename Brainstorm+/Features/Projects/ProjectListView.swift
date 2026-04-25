import SwiftUI
import Combine
import Supabase

public struct ProjectListView: View {
    @StateObject private var viewModel: ProjectListViewModel

    /// Identity source for server-side membership scoping — mirrors `guard.role` /
    /// `guard.userId` in `BrainStorm+-Web/src/lib/actions/projects.ts`.
    @Environment(SessionManager.self) private var sessionManager

    /// 1.9: secondary edit entry on list rows. Holds the project whose edit sheet is
    /// currently being presented; `nil` hides the sheet. Using an identifiable binding
    /// (rather than a bool) so SwiftUI re-creates the sheet when a different row is edited
    /// in quick succession.
    @State private var projectBeingEdited: Project? = nil

    /// 2.0: row-level delete entry. Same identifiable-binding pattern as
    /// `projectBeingEdited` so rapid row-switching creates a fresh confirmation dialog
    /// targeting the correct project.
    @State private var projectPendingDelete: Project? = nil

    /// D.2a: presentation state for the create-project sheet. Mirrors Web's `showCreate`
    /// dialog (`BrainStorm+-Web/src/app/dashboard/projects/page.tsx` line 31).
    @State private var isShowingCreateSheet: Bool = false

    /// Bug-fix(滑动判定为点击 + 震动): NavigationLink in LazyVStack inside ScrollView
    /// 在 iOS 26 触发太敏感 —— 手指放上去稍微停留就触发 tap (NavigationLink push +
    /// contextMenu preview haptic),用户想滑动反馈成"点击"。
    /// 改用 Button + .navigationDestination(item:) 的程序化导航:Button 在
    /// ScrollView 里有正确的 tap-vs-drag 判定 (drag 超过阈值会自动 cancel tap)。
    @State private var pushTarget: Project? = nil

    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    public init(viewModel: ProjectListViewModel, isEmbedded: Bool = false) {
        _viewModel = StateObject(wrappedValue: viewModel)
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
        ZStack {
            BsColor.surfaceSecondary
                .ignoresSafeArea()

            Group {
                if viewModel.isLoading && viewModel.projects.isEmpty {
                    ProgressView()
                        .scaleEffect(1.3)
                        .tint(BsColor.brandAzure)
                } else if let error = viewModel.errorMessage, viewModel.projects.isEmpty {
                    errorStateView(message: error)
                } else if viewModel.scopeOutcome == .noMembership {
                    noMembershipStateView
                } else if viewModel.projects.isEmpty {
                    if hasActiveFilter {
                        filteredEmptyStateView
                    } else {
                        emptyStateView
                    }
                } else {
                    contentList
                }
            }
        }
        .navigationTitle("项目管理")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                statusFilterMenu
            }
            // D.2a: create entry. Any authenticated user can create a project (Web
            // `createProject` gates on `serverGuard` only, no admin check).
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Haptic removed: 用户反馈 toolbar 按钮过密震动
                    isShowingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(BsColor.brandAzure)
                }
                .accessibilityLabel("新建项目")
            }
        }
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索项目"
        )
        .onSubmit(of: .search) {
            // User pressed the Search key on the keyboard — push the server-side `ilike`.
            Task { await reload() }
        }
        .onChange(of: viewModel.searchText) { _, newValue in
            // Handles the `.searchable` clear (X) affordance — when the user empties the
            // field we must re-fetch without the `ilike` filter so the list isn't frozen
            // at the last server-side filtered result set.
            if newValue.isEmpty {
                Task { await reload() }
            }
        }
        .onChange(of: viewModel.statusFilter) { _, _ in
            // Haptic removed: 用户反馈 filter onChange 过密震动
            // Discrete choice — safe to trigger server-side `eq('status', s)` immediately.
            Task { await reload() }
        }
        .refreshable {
            await reload()
        }
        .task {
            await reload()
        }
        // 1.9: secondary edit entry. Long-press on a row surfaces a context-menu "Edit"
        // action which sets `projectBeingEdited`, triggering this identifiable sheet.
        .sheet(item: $projectBeingEdited) { project in
            ProjectEditSheet(
                client: supabase,
                project: project,
                onSaved: { _ in
                    Task { await reload() }
                }
            )
        }
        // D.2a: create sheet. Presents when the "+" toolbar button is tapped. The sheet
        // calls `onCreated` with the fresh row; we reload the list so membership-scoped
        // non-admin users see the new project they just became the owner of.
        .sheet(isPresented: $isShowingCreateSheet) {
            ProjectCreateSheet(
                client: supabase,
                currentUserId: userId,
                onCreated: { _ in
                    Task { await reload() }
                }
            )
        }
        // Bug-fix(滑动判定为点击 + 震动): 程序化导航 destination,配合 list 内
        // Button + pushTarget binding,替代旧 NavigationLink 的过敏感 tap 触发。
        .navigationDestination(item: $pushTarget) { project in
            ProjectDetailView(
                viewModel: ProjectDetailViewModel(
                    client: supabase,
                    initialProject: project
                ),
                onProjectUpdated: { _ in
                    Task { await reload() }
                },
                onProjectDeleted: { id in
                    viewModel.removeProjectLocally(id: id)
                }
            )
        }
        // 2.0: row-level delete confirmation. Mirrors Web `confirm('确定删除这个项目吗？')`
        // semantics via the native `.confirmationDialog` + `Button(role: .destructive)`
        // pattern. The destructive action is gated behind `isDeleting` to prevent double-taps.
        .confirmationDialog(
            "确定删除这个项目吗？",
            isPresented: Binding(
                get: { projectPendingDelete != nil },
                set: { newValue in if !newValue { projectPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: projectPendingDelete
        ) { project in
            Button("删除 “\(project.name)”", role: .destructive) {
                Task {
                    let succeeded = await viewModel.deleteProject(id: project.id)
                    projectPendingDelete = nil
                    if !succeeded {
                        // Error surfaces via the `.alert` below; list rows stay intact.
                    }
                }
            }
            Button("取消", role: .cancel) {
                projectPendingDelete = nil
            }
        } message: { project in
            Text("将永久删除 “\(project.name)” 及其全部成员，此操作不可撤销。")
        }
        .alert(
            "删除失败",
            isPresented: Binding(
                get: { viewModel.deleteErrorMessage != nil },
                set: { newValue in if !newValue { viewModel.deleteErrorMessage = nil } }
            ),
            actions: {
                Button("好的", role: .cancel) { viewModel.deleteErrorMessage = nil }
            },
            message: {
                Text(viewModel.deleteErrorMessage ?? "")
            }
        )
    }

    // MARK: - Identity / reload

    private var primaryRole: PrimaryRole? {
        // SessionManager exposes the raw `profile.role` string; RBACManager is the single
        // normalization surface used across iOS for mapping legacy strings onto PrimaryRole.
        RBACManager.shared.migrateLegacyRole(sessionManager.currentProfile?.role).primaryRole
    }

    private var userId: UUID? {
        sessionManager.currentProfile?.id
    }

    private func reload() async {
        await viewModel.fetchProjects(role: primaryRole, userId: userId)
    }

    private var hasActiveFilter: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || viewModel.statusFilter != nil
    }

    // MARK: - Subviews

    private var contentList: some View {
        // Server is authoritative; `filteredProjects` is a thin client smoothing layer.
        let rows = viewModel.filteredProjects
        return Group {
            if rows.isEmpty {
                filteredEmptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: BsSpacing.lg) {
                        ForEach(rows) { project in
                            // Bug-fix(滑动判定为点击 + 震动): 用 Button + pushTarget 替代
                                // NavigationLink。Button 在 ScrollView 里正确处理 tap-vs-drag。
                            Button {
                                pushTarget = project
                            } label: {
                                ProjectCardView(
                                    project: project,
                                    // 1.7: feed the batched owner lookup into the card so it can
                                    // show `full_name` when available (mirrors Web's nested
                                    // `profiles:owner_id(full_name, avatar_url)` join).
                                    owner: project.ownerId.flatMap { viewModel.ownersById[$0] },
                                    // 2.1: feed the batched task count aggregate into the card.
                                    // `nil` when the count isn't yet fetched or failed; card
                                    // hides the count label rather than showing a stale value.
                                    taskCount: viewModel.taskCountsByProject[project.id]
                                )
                                    .padding(.horizontal, BsSpacing.lg + 4)
                            }
                            .buttonStyle(.plain)
                            // 1.9: secondary edit entry. Long-press the row to surface the
                            // same edit sheet used from the detail toolbar.
                            // 2.0: secondary delete entry with destructive role + its own
                            // confirmation dialog (see `.confirmationDialog` above).
                            .contextMenu {
                                Button {
                                    // Haptic removed: contextMenu 选项过密震动
                                    projectBeingEdited = project
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    // Haptic removed: 菜单选项；真删确认时由 confirmationDialog 处理
                                    projectPendingDelete = project
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                        Spacer().frame(height: 24)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var statusFilterMenu: some View {
        Menu {
            Button {
                // Haptic removed: 用户反馈 filter menu 过密震动
                viewModel.statusFilter = nil
            } label: {
                Label("全部状态", systemImage: viewModel.statusFilter == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(Self.statusOptions, id: \.0) { option in
                Button {
                    // Haptic removed: 用户反馈 filter menu 过密震动
                    viewModel.statusFilter = option.0
                } label: {
                    Label(option.1, systemImage: viewModel.statusFilter == option.0 ? "checkmark" : "")
                }
            }
        } label: {
            Image(systemName: viewModel.statusFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .foregroundColor(BsColor.brandAzure)
        }
        .accessibilityLabel("筛选状态")
    }

    // D.2a: Chinese labels to match Web STATUS_CFG in
    // `BrainStorm+-Web/src/app/dashboard/projects/page.tsx` lines 18-24.
    private static let statusOptions: [(Project.ProjectStatus, String)] = [
        (.planning, "规划中"),
        (.active, "进行中"),
        (.onHold, "暂停"),
        (.completed, "已完成"),
        (.archived, "归档"),
    ]

    private var emptyStateView: some View {
        VStack(spacing: BsSpacing.lg) {
            ZStack {
                Circle()
                    .fill(BsColor.brandMint.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "folder")
                    .font(.system(.largeTitle))
                    .foregroundColor(BsColor.brandAzure)
            }
            Text("暂无项目")
                .font(BsTypography.sectionTitle)
                .foregroundColor(BsColor.ink)
            Text("点击右上角创建第一个项目。")
                .font(BsTypography.bodySmall)
                .foregroundColor(BsColor.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BsSpacing.xxxl - 8)
        }
        .padding(.vertical, BsSpacing.xxxl - 8)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xxl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
        .padding(.horizontal, BsSpacing.xl)
    }

    /// Rendered when the server returns no rows because the current user is a non-admin
    /// with zero `project_members` rows — mirrors Web's early-return empty path.
    private var noMembershipStateView: some View {
        VStack(spacing: BsSpacing.lg) {
            ZStack {
                Circle()
                    .fill(BsColor.brandMint.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "person.2.slash")
                    .font(.system(.largeTitle))
                    .foregroundColor(BsColor.brandAzure)
            }
            Text("暂无可访问的项目")
                .font(BsTypography.sectionTitle)
                .foregroundColor(BsColor.ink)
            Text("你还不是任何项目的成员。可请管理员在 Web 端将你加入项目，或点击右上角“+”新建项目。")
                .font(BsTypography.bodySmall)
                .foregroundColor(BsColor.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BsSpacing.xxl)
        }
        .padding(.vertical, BsSpacing.xxxl - 8)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xxl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
        .padding(.horizontal, BsSpacing.xl)
    }

    private var filteredEmptyStateView: some View {
        VStack(spacing: BsSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(.largeTitle))
                .foregroundColor(BsColor.inkMuted)
            Text("未找到匹配的项目")
                .font(BsTypography.sectionTitle)
                .foregroundColor(BsColor.ink)
            Text("尝试修改搜索关键词或清除状态筛选。")
                .font(BsTypography.bodySmall)
                .foregroundColor(BsColor.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BsSpacing.xxl)
        }
        .padding(.vertical, BsSpacing.xxl)
        .padding(.horizontal, BsSpacing.xl)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
        .padding(.horizontal, BsSpacing.xl)
        .padding(.top, BsSpacing.xl)
    }

    private func errorStateView(message: String) -> some View {
        VStack(spacing: BsSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(.largeTitle))
                .foregroundColor(BsColor.warning)
            Text("项目加载失败")
                .font(BsTypography.sectionTitle)
                .foregroundColor(BsColor.ink)
            Text(message)
                .font(BsTypography.bodySmall)
                .foregroundColor(BsColor.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BsSpacing.xxl)
            Button {
                Task { await reload() }
            } label: {
                Text("重试")
                    .font(.system(.subheadline, weight: .semibold))
                    .padding(.horizontal, BsSpacing.lg + 4)
                    .padding(.vertical, BsSpacing.md - 2)
                    .background(BsColor.brandAzure)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, BsSpacing.xxl)
        .padding(.horizontal, BsSpacing.xl)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
        .padding(.horizontal, BsSpacing.xl)
    }
}
