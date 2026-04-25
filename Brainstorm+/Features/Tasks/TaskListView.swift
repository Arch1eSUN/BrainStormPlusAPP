import SwiftUI
import Combine

// ══════════════════════════════════════════════════════════════════
// TaskListView — iOS 26 原生重写 (Phase 11.x)
//
// 关键变化 vs. 旧版:
//   • 去掉 .navigationBarHidden(true) → NavigationStack 原生接管
//   • 去掉手搓 headerAndFilterSection (Text("任务管理") + 手搓 "+" 按钮)
//     → .navigationTitle("任务管理") + .navigationBarTitleDisplayMode(.large)
//     → toolbar ToolbarItem(.topBarTrailing) 放 + 按钮
//   • 手搓 segmented filter + matchedGeometryEffect
//     → 原生 Picker(.segmented) 放进 List Section header (随内容滚动)
//   • 手搓搜索 HStack + magnifier
//     → .searchable(placement: .navigationBarDrawer(.always))
//   • 列表模式 ScrollView + LazyVStack → List + ForEach,启用 .swipeActions
//   • 看板模式保持 ScrollView + HStack + columns (横向看板非原生 List 语义)
// ══════════════════════════════════════════════════════════════════

/// Tasks entry view. Supports two visual modes (list + kanban) toggled
/// in the toolbar, plus status segment filter, search, and project
/// filter — 1:1 port of `BrainStorm+-Web/src/app/dashboard/tasks/page.tsx`.
public struct TaskListView: View {
    @StateObject private var viewModel: TaskListViewModel
    @State private var selectedFilter: TaskFilter = .all
    @State private var isShowingCreateTask = false
    @State private var viewMode: ViewMode = .list
    /// 删除二次确认 —— 长按 / swipe 都打到这个 sheet（docs/longpress-system.md）。
    @State private var pendingDeleteTask: TaskModel? = nil

    /// Phase 3 isEmbedded：当父容器（例如 MainTabView tab / ActionItemHelper
    /// NavigationLink destination / Dashboard quick-action tile）已经持有
    /// NavigationStack 时，本 view 借用父 stack，避免双层嵌套导致 push 行为
    /// 异常 / nav-bar 双叠。
    public let isEmbedded: Bool

    // ── Status segment filter ───────────────────────────────────────
    // 4-state filter matches Web's `STATUS_COLUMNS` plus an "All" head.
    enum TaskFilter: String, CaseIterable {
        case all
        case todo
        case inProgress
        case review
        case done

        var cnLabel: String {
            switch self {
            case .all: return "全部"
            case .todo: return "待办"
            case .inProgress: return "进行中"
            case .review: return "审核中"
            case .done: return "已完成"
            }
        }

        var matchingStatus: TaskModel.TaskStatus? {
            switch self {
            case .all: return nil
            case .todo: return .todo
            case .inProgress: return .inProgress
            case .review: return .review
            case .done: return .done
            }
        }
    }

    enum ViewMode {
        case list
        case kanban
    }

    // MARK: - Derived lists

    /// Apply status segment filter on top of the vm-level search + project filter.
    private var visibleTasks: [TaskModel] {
        let base = viewModel.filteredTasks
        guard let status = selectedFilter.matchingStatus else { return base }
        return base.filter { $0.status == status }
    }

    public init(viewModel: TaskListViewModel, isEmbedded: Bool = false) {
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

    @ViewBuilder
    private var coreContent: some View {
        Group {
            if viewModel.isLoading && viewModel.tasks.isEmpty {
                loadingView
            } else if visibleTasks.isEmpty && viewMode == .list {
                emptyWrapper
            } else {
                switch viewMode {
                case .list:
                    listBody
                case .kanban:
                    kanbanBody
                }
            }
        }
        .background(BsColor.pageBackground.ignoresSafeArea())
        .navigationTitle("任务管理")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索任务..."
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                projectFilterMenu
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                viewModeToggleButton
                Button {
                    // Haptic removed: 用户反馈按钮过密震动
                    isShowingCreateTask = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(.headline, weight: .semibold))
                }
                .accessibilityLabel("新建任务")
            }
        }
        .refreshable {
            // Haptic removed: 用户反馈滑动场景不应震动
            await viewModel.fetchTasks()
            await viewModel.fetchProjects()
        }
        .task {
            await viewModel.fetchTasks()
            await viewModel.fetchProjects()
            await viewModel.fetchMembers()
        }
        .sheet(isPresented: $isShowingCreateTask) {
            CreateTaskView(viewModel: viewModel)
        }
        // 单一 destructive confirm —— 长按 / 横滑都打到这个 dialog。
        .confirmationDialog(
            "删除该任务？",
            isPresented: Binding(
                get: { pendingDeleteTask != nil },
                set: { if !$0 { pendingDeleteTask = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteTask
        ) { target in
            Button("删除", role: .destructive) {
                Haptic.warning() // destructive 真删确认完成
                Task { await viewModel.deleteTask(task: target) }
                pendingDeleteTask = nil
            }
            Button("取消", role: .cancel) { pendingDeleteTask = nil }
        } message: { target in
            Text("「\(target.title)」将被永久删除")
        }
    }

    // MARK: - Loading / Empty wrappers

    private var loadingView: some View {
        // Bug-fix(loading 一致性): 丢 scaleEffect(1.5),改 .controlSize(.large)。
        VStack {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(BsColor.brandAzure)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// List scroll container wrapping the empty state so that stats row + segmented
    /// filter remain visible (and pull-to-refresh still works) even when zero tasks.
    private var emptyWrapper: some View {
        List {
            Section {
                EmptyView()
            } header: {
                listHeaderContent
            }

            Section {
                emptyStateView
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: BsSpacing.xl, leading: BsSpacing.lg, bottom: BsSpacing.xl, trailing: BsSpacing.lg))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - List mode body

    private var listBody: some View {
        List {
            Section {
                ForEach(Array(visibleTasks.enumerated()), id: \.element.id) { index, task in
                    TaskCardView(task: task) {
                        // Quick-complete entry (Web's `toggleTaskCompletion`).
                        Task { await viewModel.toggleTaskCompletion(task.id) }
                    }
                    .bsAppearStagger(index: index)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: BsSpacing.lg, bottom: 4, trailing: BsSpacing.lg))
                    .listRowSeparator(.hidden)
                    // Trailing swipe —— delete 走二次确认；快速完成无确认。
                    // allowsFullSwipe 关掉避免误删（用户反馈过手滑）。
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeleteTask = task
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            // Haptic removed: swipe action 系统自带反馈
                            Task { await viewModel.toggleTaskCompletion(task.id) }
                        } label: {
                            Label(task.progress >= 100 ? "撤销完成" : "标记完成",
                                  systemImage: task.progress >= 100 ? "arrow.uturn.backward.circle" : "checkmark.circle")
                        }
                        .tint(BsColor.success)
                    }
                    // 长按系统设计 (docs/longpress-system.md)：
                    //   • 顶部：主要 mutation —— 标完成 / 撤销完成
                    //   • 中部：编辑（状态切换 submenu）
                    //   • 底部：destructive —— 删除（confirmationDialog 二次确认）
                    .contextMenu {
                        Button {
                            Haptic.success()
                            Task { await viewModel.toggleTaskCompletion(task.id) }
                        } label: {
                            Label(task.progress >= 100 ? "撤销完成" : "标完成",
                                  systemImage: task.progress >= 100 ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                        }

                        // 状态切换作为 "编辑" 的轻量入口 —— TaskEditSheet 待新
                        // sprint，状态是当前 ios 端唯一可改字段。
                        Menu {
                            ForEach([TaskModel.TaskStatus.todo, .inProgress, .review, .done], id: \.self) { s in
                                Button {
                                    Task { await viewModel.updateTaskStatus(task: task, newStatus: s) }
                                } label: {
                                    Label(s.cnLabel, systemImage: s == task.status ? "checkmark" : "circle")
                                }
                                .disabled(s == task.status)
                            }
                        } label: {
                            Label("修改状态", systemImage: "slider.horizontal.3")
                        }

                        Divider()

                        Button(role: .destructive) {
                            // Haptic removed: 仅打开 confirm dialog，真删确认时再震
                            pendingDeleteTask = task
                        } label: {
                            Label("删除任务", systemImage: "trash")
                        }
                    }
                }
            } header: {
                listHeaderContent
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    /// Stats row + segmented TaskFilter picker, lives inside the List Section header
    /// so it scrolls with content (rather than sticking above). Matches the DashboardView
    /// pattern of letting the List own the vertical composition.
    private var listHeaderContent: some View {
        VStack(spacing: BsSpacing.md) {
            statsRow
            filterSegmentedPicker
        }
        .padding(.top, BsSpacing.sm)
        .padding(.bottom, BsSpacing.sm)
        .listRowInsets(EdgeInsets(top: 0, leading: BsSpacing.lg, bottom: 0, trailing: BsSpacing.lg))
        .textCase(nil)
    }

    // MARK: - Segmented TaskFilter (native Picker)

    private var filterSegmentedPicker: some View {
        Picker("筛选", selection: $selectedFilter) {
            ForEach(TaskFilter.allCases, id: \.self) { filter in
                Text(filter.cnLabel).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        // Haptic removed: 用户反馈 picker 切换过密震动
    }

    // MARK: - Stats row (preserved)

    private var statsRow: some View {
        let s = viewModel.stats
        let cards: [(String, Int, Color)] = [
            ("待办", s.todo, BsColor.inkMuted),
            ("进行中", s.inProgress, BsColor.brandAzure),
            ("审核中", s.review, BsColor.warning),
            ("已完成", s.done, BsColor.success)
        ]
        return HStack(spacing: BsSpacing.sm) {
            ForEach(cards.indices, id: \.self) { idx in
                let (label, value, tint) = cards[idx]
                BsContentCard(padding: .none) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(value)")
                            .font(BsTypography.sectionTitle)
                            .foregroundColor(tint)
                            .contentTransition(.numericText())
                        Text(label)
                            .font(BsTypography.meta)
                            .foregroundColor(BsColor.inkMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, BsSpacing.md - 2)
                    .padding(.horizontal, BsSpacing.md)
                }
            }
        }
    }

    // MARK: - Toolbar items

    /// Project filter Menu — moved from inline search row into toolbar leading slot.
    private var projectFilterMenu: some View {
        Menu {
            Button {
                // Haptic removed: 用户反馈 menu 切换过密震动
                viewModel.projectFilter = nil
            } label: {
                Label("全部项目", systemImage: viewModel.projectFilter == nil ? "checkmark" : "folder")
            }
            Divider()
            ForEach(viewModel.projects) { project in
                Button {
                    // Haptic removed: 用户反馈 menu 切换过密震动
                    viewModel.projectFilter = project.id
                } label: {
                    Label(project.name, systemImage: viewModel.projectFilter == project.id ? "checkmark" : "folder")
                }
            }
        } label: {
            Image(systemName: viewModel.projectFilter == nil ? "folder" : "folder.fill")
                .font(.system(.headline, weight: .medium))
        }
        .accessibilityLabel("项目筛选")
    }

    /// List/Kanban toggle — single button that flips modes, uses SF symbol to convey state.
    private var viewModeToggleButton: some View {
        Button {
            // Haptic removed: 用户反馈 toolbar toggle 过密震动
            withAnimation(BsMotion.Anim.overshoot) {
                viewMode = (viewMode == .list) ? .kanban : .list
            }
        } label: {
            Image(systemName: viewMode == .list ? "rectangle.split.3x1" : "list.bullet")
                .font(.system(.headline, weight: .medium))
        }
        .accessibilityLabel(viewMode == .list ? "切换看板视图" : "切换列表视图")
    }

    // MARK: - Kanban mode body (Phase 12 重写)
    //
    // Bug-fix(Kanban 横向视图奇怪) v3:
    //
    // Root cause:
    //   1. 列宽固定 280pt → iPhone (393pt 屏) 一次只能看 1.4 列,半列被切边
    //      不舒服;小屏 (iPhone SE 320pt) 几乎看不全单列。
    //   2. 外横 ScrollView + 每列内部 vertical ScrollView 双层手势冲突 ——
    //      横向滑的时候经常被列内竖滚抢手,要先把手指放对位置才能横滑。
    //   3. 卡片用 TaskKanbanCardView 跟 list mode 视觉差异大,两个 mode 切换
    //      像换了个 app。
    //   4. 列 header 不 sticky,滚到底部看不到当前在哪列。
    //
    // 修法 v3 (按用户 spec):
    //   • 列宽 = 屏宽 / 1.5 → 一次能完整看一列 + 下一列预览 ~33%。
    //   • 外层 ScrollView(.horizontal) + LazyHStack —— 列 lazy 渲染,空列零代价。
    //   • 列内不再嵌 ScrollView ——> 改用 LazyVStack。如果某列卡片超过屏高,
    //     整个 kanban 一起垂直滚 (我们再加一层 vertical ScrollView 在外层
    //     嵌套时 gesture 会冲突 —— iOS 不允许两轴 ScrollView 嵌套同方向)。
    //   • 卡片用本文件下面定义的 KanbanCompactCard —— 一行标题 + 优先级
    //     小点 + due date,跟 list mode 视觉同源 (复用 BsContentCard token)。

    private var kanbanBody: some View {
        GeometryReader { proxy in
            let columnWidth = max(min(proxy.size.width / 1.5, 360), 240)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach([TaskModel.TaskStatus.todo, .inProgress, .review, .done], id: \.self) { column in
                        kanbanColumn(for: column, width: columnWidth)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, BsSpacing.md)
                .padding(.bottom, BsSpacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func kanbanColumn(for column: TaskModel.TaskStatus, width: CGFloat) -> some View {
        let tasks = viewModel.filteredTasks.filter { $0.status == column }

        VStack(alignment: .leading, spacing: 10) {
            // Column header — dot + label + count pill,跟 list mode statsRow 视觉同步。
            HStack(spacing: BsSpacing.sm) {
                Circle()
                    .fill(column.tint)
                    .frame(width: 8, height: 8)
                Text(column.cnLabel)
                    .font(BsTypography.cardSubtitle)
                    .foregroundColor(BsColor.ink)
                Spacer()
                Text("\(tasks.count)")
                    .font(BsTypography.captionSmall.weight(.semibold))
                    .foregroundColor(BsColor.inkMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(column.tint.opacity(0.15), in: Capsule())
            }
            .padding(.horizontal, BsSpacing.sm)
            .padding(.vertical, BsSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BsColor.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                    .stroke(BsColor.borderSubtle, lineWidth: 0.5)
            )

            // Body —— LazyVStack 不嵌 ScrollView。横/竖手势分离。
            LazyVStack(spacing: 10) {
                ForEach(tasks) { task in
                    KanbanCompactCard(task: task)
                        .draggable(task.id.uuidString) {
                            KanbanCompactCard(task: task)
                                .frame(width: width - 24)
                                .opacity(0.85)
                        }
                        .contextMenu {
                            ForEach([TaskModel.TaskStatus.todo, .inProgress, .review, .done], id: \.self) { s in
                                Button {
                                    Task { await viewModel.updateTaskStatus(task: task, newStatus: s) }
                                } label: {
                                    Label(s.cnLabel, systemImage: s == task.status ? "checkmark" : "")
                                }
                                .disabled(s == task.status)
                            }
                            Divider()
                            Button {
                                Task { await viewModel.toggleTaskCompletion(task.id) }
                            } label: {
                                Label(task.progress >= 100 ? "撤销完成" : "标记完成", systemImage: "checkmark.circle")
                            }
                            Divider()
                            Button(role: .destructive) {
                                pendingDeleteTask = task
                            } label: {
                                Label("删除任务", systemImage: "trash")
                            }
                        }
                }

                if tasks.isEmpty {
                    Text("暂无任务")
                        .font(BsTypography.caption)
                        .foregroundColor(BsColor.inkMuted.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BsSpacing.xxl)
                        .background(
                            RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                                .fill(BsColor.surfaceSecondary.opacity(0.4))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                                .stroke(BsColor.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                }
            }
            .dropDestination(for: String.self) { ids, _ in
                guard let first = ids.first, let uuid = UUID(uuidString: first) else { return false }
                guard let task = viewModel.tasks.first(where: { $0.id == uuid }) else { return false }
                guard task.status != column else { return false }
                Haptic.success()
                Task { await viewModel.updateTaskStatus(task: task, newStatus: column) }
                return true
            }
        }
        .frame(width: width, alignment: .top)
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        BsContentCard(padding: .none) {
            VStack(spacing: BsSpacing.lg) {
                ZStack {
                    Circle()
                        .fill(BsColor.brandMint.opacity(0.18))
                        .frame(width: 100, height: 100)
                    Image(systemName: "checklist")
                        .font(.system(.largeTitle))
                        .foregroundColor(BsColor.brandAzure)
                }
                Text("暂无\(selectedFilter.cnLabel)任务")
                    .font(BsTypography.sectionTitle)
                    .foregroundColor(BsColor.ink)
                Text("点击右上角的「+」按钮来创建第一个任务。")
                    .font(BsTypography.bodySmall)
                    .foregroundColor(BsColor.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BsSpacing.xxxl - 8)
            }
            .padding(.vertical, BsSpacing.xxxl - 8)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Create Task Sheet

public struct CreateTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TaskListViewModel

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var priority: TaskModel.TaskPriority = .medium
    @State private var projectId: UUID? = nil
    @State private var dueDate: Date = Date()
    @State private var includeDueDate: Bool = false
    @State private var selectedParticipants: Set<UUID> = []

    @State private var isSubmitting: Bool = false
    @State private var submissionError: String? = nil

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("任务详情").font(BsTypography.bodySmall).foregroundColor(BsColor.inkMuted)) {
                    TextField("任务标题", text: $title)
                        .font(Font.custom("Inter-Regular", size: 16, relativeTo: .body))

                    TextField("描述 (可选)", text: $description, axis: .vertical)
                        .font(Font.custom("Inter-Regular", size: 16, relativeTo: .body))
                        .lineLimit(3...6)
                }

                Section(header: Text("配置").font(BsTypography.bodySmall).foregroundColor(BsColor.inkMuted)) {
                    Picker("优先级", selection: $priority) {
                        Text(TaskModel.TaskPriority.low.cnLabel).tag(TaskModel.TaskPriority.low)
                        Text(TaskModel.TaskPriority.medium.cnLabel).tag(TaskModel.TaskPriority.medium)
                        Text(TaskModel.TaskPriority.high.cnLabel).tag(TaskModel.TaskPriority.high)
                        Text(TaskModel.TaskPriority.urgent.cnLabel).tag(TaskModel.TaskPriority.urgent)
                    }
                    .font(Font.custom("Inter-Regular", size: 16, relativeTo: .body))

                    Picker("所属项目 (可选)", selection: $projectId) {
                        Text("不关联项目").tag(nil as UUID?)
                        ForEach(viewModel.projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                    .font(Font.custom("Inter-Regular", size: 16, relativeTo: .body))

                    Toggle("设置截止日期", isOn: $includeDueDate)
                        .font(Font.custom("Inter-Regular", size: 16, relativeTo: .body))

                    if includeDueDate {
                        DatePicker("日期", selection: $dueDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                    }
                }

                // Participant picker mirrors Web's checkbox grid in
                // tasks/page.tsx:322-346. Owner (current user) is always
                // implicit — we exclude them from the list.
                Section(header: Text("协助者").font(BsTypography.bodySmall).foregroundColor(BsColor.inkMuted)) {
                    if viewModel.members.isEmpty {
                        Text("暂无可选协助者")
                            .font(BsTypography.bodySmall)
                            .foregroundColor(BsColor.inkMuted)
                    } else {
                        ForEach(viewModel.members.filter { $0.id != viewModel.currentUserId }) { member in
                            Button {
                                if selectedParticipants.contains(member.id) {
                                    selectedParticipants.remove(member.id)
                                } else {
                                    selectedParticipants.insert(member.id)
                                }
                                // Haptic removed: 用户反馈 chip 切换过密震动
                            } label: {
                                HStack {
                                    Image(systemName: selectedParticipants.contains(member.id) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(selectedParticipants.contains(member.id) ? BsColor.brandAzure : BsColor.inkMuted)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(member.displayName)
                                            .font(BsTypography.bodySmall)
                                            .foregroundColor(BsColor.ink)
                                        if let dept = member.department, !dept.isEmpty {
                                            Text(dept)
                                                .font(BsTypography.captionSmall)
                                                .foregroundColor(BsColor.inkMuted)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let error = submissionError {
                    Section {
                        Text(error)
                            .font(BsTypography.bodySmall)
                            .foregroundColor(BsColor.danger)
                    }
                }
            }
            .navigationTitle("新建任务")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Grab current user id so we can omit them from the
                // participant picker (they're the implicit owner).
                await viewModel.fetchCurrentUserId()
                if viewModel.members.isEmpty {
                    await viewModel.fetchMembers()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        // Haptic removed: 用户反馈辅助按钮过密震动
                        dismiss()
                    }
                    .font(Font.custom("Inter-Medium", size: 16, relativeTo: .body))
                    .foregroundColor(BsColor.inkMuted)
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("创建") {
                        // Haptic 由 submitTask() 内部统一触发
                        submitTask()
                    }
                    .font(Font.custom("Inter-SemiBold", size: 16, relativeTo: .body))
                    .foregroundColor(title.trimmingCharacters(in: .whitespaces).isEmpty ? BsColor.inkMuted : BsColor.brandAzure)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
            // Bug-fix(loading 一致性): 全屏提交 overlay 改用统一的 BsLoadingOverlay,
            // 和其他 submit sheet 对齐（同款 dim + ultraThinMaterial pill + .large 圈）。
            .bsLoadingOverlay(isLoading: isSubmitting, label: "提交中…")
        }
    }

    private func submitTask() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isSubmitting = true
        submissionError = nil
        Haptic.medium() // 关键 mutation：创建任务

        Task {
            do {
                try await viewModel.createTask(
                    title: title.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description.trimmingCharacters(in: .whitespaces),
                    priority: priority,
                    projectId: projectId,
                    dueDate: includeDueDate ? dueDate : nil,
                    participantIds: Array(selectedParticipants)
                )
                Haptic.success()
                dismiss()
            } catch {
                submissionError = ErrorLocalizer.localize(error)
                Haptic.error()
                isSubmitting = false
            }
        }
    }
}

// MARK: - Kanban Compact Card

/// 看板模式专用紧凑卡片 —— 一行能看清的最小信息密度:
///   • 优先级小圆点 (左侧 4pt 色条 + 顶部小点) —— 一眼颜色判断紧急程度
///   • 标题 (最多 2 行截断) —— 主要识别符
///   • 截止日期 + 是否逾期 (caption2) —— 时间感知
///
/// 跟 TaskCardView (list mode) 视觉同源:都用 BsContentCard token,
/// 都用 BsColor 调色板,但布局更紧凑 (适合横滑卡片)。
private struct KanbanCompactCard: View {
    let task: TaskModel

    private var isOverdue: Bool {
        guard let due = task.dueDate else { return false }
        return task.progress < 100 && due < Date()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // 左侧 3pt 优先级色条 —— 直观判断紧急程度
            Rectangle()
                .fill(task.priority.tint)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                // 标题 + 优先级小点
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(task.priority.tint)
                        .frame(width: 6, height: 6)
                        .padding(.top, 5)
                    Text(task.title)
                        .font(BsTypography.bodySmall.weight(.medium))
                        .foregroundColor(BsColor.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Due date 行 —— 没有 due 也不强行渲染,保持紧凑
                if let due = task.dueDate {
                    HStack(spacing: 4) {
                        Image(systemName: isOverdue ? "exclamationmark.circle.fill" : "calendar")
                            .font(.caption2)
                            .foregroundColor(isOverdue ? BsColor.danger : BsColor.inkMuted)
                        Text(due, format: .dateTime.month(.abbreviated).day())
                            .font(BsTypography.captionSmall)
                            .foregroundColor(isOverdue ? BsColor.danger : BsColor.inkMuted)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
