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

    public init(viewModel: TaskListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
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
                        Haptic.light()
                        isShowingCreateTask = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(.headline, weight: .semibold))
                    }
                    .accessibilityLabel("新建任务")
                }
            }
            .refreshable {
                Haptic.soft()
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
        }
    }

    // MARK: - Loading / Empty wrappers

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteTask(task: task) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            Task { await viewModel.toggleTaskCompletion(task.id) }
                        } label: {
                            Label(task.progress >= 100 ? "撤销完成" : "标记完成",
                                  systemImage: task.progress >= 100 ? "arrow.uturn.backward.circle" : "checkmark.circle")
                        }
                        .tint(BsColor.success)
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
                            Task { await viewModel.deleteTask(task: task) }
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
        .onChange(of: selectedFilter) { _, _ in
            Haptic.rigid()
        }
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
                Haptic.selection()
                viewModel.projectFilter = nil
            } label: {
                Label("全部项目", systemImage: viewModel.projectFilter == nil ? "checkmark" : "folder")
            }
            Divider()
            ForEach(viewModel.projects) { project in
                Button {
                    Haptic.selection()
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
            Haptic.rigid()
            withAnimation(BsMotion.Anim.overshoot) {
                viewMode = (viewMode == .list) ? .kanban : .list
            }
        } label: {
            Image(systemName: viewMode == .list ? "rectangle.split.3x1" : "list.bullet")
                .font(.system(.headline, weight: .medium))
        }
        .accessibilityLabel(viewMode == .list ? "切换看板视图" : "切换列表视图")
    }

    // MARK: - Kanban mode body (UNCHANGED logic, only dropped the old header wrapper)

    private var kanbanBody: some View {
        // Horizontal swipeable columns — each card is .draggable, each
        // column is .dropDestination. Reordering across columns fires
        // the status update via the view model (which owns the done→*
        // revert guard).
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach([TaskModel.TaskStatus.todo, .inProgress, .review, .done], id: \.self) { column in
                        kanbanColumn(for: column)
                            .frame(width: 280)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, BsSpacing.md)
                .padding(.bottom, 100)
            }
        }
    }

    @ViewBuilder
    private func kanbanColumn(for column: TaskModel.TaskStatus) -> some View {
        let tasks = viewModel.filteredTasks.filter { $0.status == column }

        VStack(alignment: .leading, spacing: 10) {
            // Column header: dot + label + count pill.
            HStack(spacing: BsSpacing.sm) {
                Circle()
                    .fill(column.tint)
                    .frame(width: 8, height: 8)
                Text(column.cnLabel)
                    .font(Font.custom("Inter-SemiBold", size: 14, relativeTo: .subheadline))
                    .foregroundColor(BsColor.ink)
                Spacer()
                Text("\(tasks.count)")
                    .font(BsTypography.captionSmall)
                    .foregroundColor(BsColor.inkMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(BsColor.inkFaint.opacity(0.2))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, BsSpacing.xs)

            // Droppable body — iOS 16+ `.dropDestination` receives the
            // task id (String). Body keeps a minimum height so empty
            // columns can still accept drops.
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(tasks) { task in
                        TaskKanbanCardView(
                            task: task,
                            onChangeStatus: { newStatus in
                                Task { await viewModel.updateTaskStatus(task: task, newStatus: newStatus) }
                            },
                            onToggleComplete: {
                                Task { await viewModel.toggleTaskCompletion(task.id) }
                            },
                            onDelete: {
                                Task { await viewModel.deleteTask(task: task) }
                            }
                        )
                        .draggable(task.id.uuidString) {
                            // Lightweight drag preview.
                            TaskKanbanCardView(
                                task: task,
                                onChangeStatus: { _ in },
                                onToggleComplete: {},
                                onDelete: {}
                            )
                            .frame(width: 260)
                            .opacity(0.85)
                        }
                    }
                    if tasks.isEmpty {
                        Text("暂无任务")
                            .font(BsTypography.caption)
                            .foregroundColor(BsColor.inkMuted.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, BsSpacing.xxxl - 8)
                    }
                }
                .padding(BsSpacing.sm)
            }
            .frame(minHeight: 200)
            .background(BsColor.surfaceSecondary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                    .stroke(BsColor.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
            .dropDestination(for: String.self) { ids, _ in
                guard let first = ids.first, let uuid = UUID(uuidString: first) else { return false }
                guard let task = viewModel.tasks.first(where: { $0.id == uuid }) else { return false }
                guard task.status != column else { return false }
                Haptic.success()
                Task { await viewModel.updateTaskStatus(task: task, newStatus: column) }
                return true
            }
        }
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
                                Haptic.rigid()
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
                        Haptic.light()
                        dismiss()
                    }
                    .font(Font.custom("Inter-Medium", size: 16, relativeTo: .body))
                    .foregroundColor(BsColor.inkMuted)
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("创建") {
                        Haptic.medium()
                        submitTask()
                    }
                    .font(Font.custom("Inter-SemiBold", size: 16, relativeTo: .body))
                    .foregroundColor(title.trimmingCharacters(in: .whitespaces).isEmpty ? BsColor.inkMuted : BsColor.brandAzure)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        ProgressView()
                            .padding()
                            .background(BsColor.surfacePrimary)
                            .cornerRadius(BsRadius.md)
                            .shadow(radius: 10)
                    }
                }
            }
        }
    }

    private func submitTask() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isSubmitting = true
        submissionError = nil
        Haptic.rigid()

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
