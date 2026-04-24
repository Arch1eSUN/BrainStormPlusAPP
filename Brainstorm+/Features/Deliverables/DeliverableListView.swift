import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 2.1 — Deliverables list view.
//
// 1:1 surface port of
// `BrainStorm+-Web/src/app/dashboard/deliverables/page.tsx` minus the
// create/edit dialogs (scope is list + detail this pass — see batch
// brief). iOS-specific deviations:
//   • The Web page mixes filters + search + stats on a single scroll
//     container. On iOS we fold the stats into a compact row and put
//     the filter controls inside a collapsible section to keep the
//     nav bar usable on iPhone SE-class widths.
//   • Platform detection for the external link chip reuses the same
//     regexes Web uses (page.tsx:23-36) so the UX — "Google Drive /
//     百度网盘 / 夸克网盘" — reads identically to Web.
//   • Create is shipped via `DeliverableCreateSheet` (see Phase 2.1
//     follow-up — the sheet mirrors Web's "新建交付物" dialog at
//     page.tsx:199-254). Edit + delete stay out of scope for this
//     pass.
// ══════════════════════════════════════════════════════════════════

public struct DeliverableListView: View {
    @StateObject private var viewModel: DeliverableListViewModel
    @State private var showFilters: Bool = false
    @State private var showCreateSheet: Bool = false
    @State private var editTarget: Deliverable? = nil
    @State private var deleteTarget: Deliverable? = nil
    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    public init(viewModel: DeliverableListViewModel, isEmbedded: Bool = false) {
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
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView()
            } else {
                content
            }
        }
        .navigationTitle("交付物")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Haptic.light()
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建交付物")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Haptic.light()
                    withAnimation(BsMotion.Anim.smooth) {
                        showFilters.toggle()
                    }
                } label: {
                    Image(systemName: showFilters
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("筛选")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            DeliverableCreateSheet(viewModel: viewModel)
        }
        .sheet(item: $editTarget) { target in
            DeliverableEditSheet(viewModel: viewModel, deliverable: target)
        }
        .confirmationDialog(
            "删除后该交付物记录无法恢复，确认？",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { target in
            Button("删除", role: .destructive) {
                Task {
                    _ = await viewModel.deleteDeliverable(id: target.id)
                    deleteTarget = nil
                }
            }
            Button("取消", role: .cancel) {
                deleteTarget = nil
            }
        }
        .modifier(DeliverableListFiltersModifier(viewModel: viewModel))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                statsRow
                statusChipRow
                if showFilters {
                    advancedFilters
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if viewModel.filteredItems.isEmpty {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "暂无交付物",
                            systemImage: "shippingbox",
                            description: Text(emptyDescription)
                        )
                        // Mirrors Web's gradient CTA at page.tsx:202 — the
                        // empty state gives users a direct entry into the
                        // create flow without hunting for the toolbar.
                        Button {
                            Haptic.light()
                            showCreateSheet = true
                        } label: {
                            Label("新建交付物", systemImage: "plus")
                                .font(BsTypography.inter(15, weight: "SemiBold"))
                                .padding(.horizontal, BsSpacing.lg)
                                .padding(.vertical, BsSpacing.md - 2)
                                .background(BsColor.brandAzure)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 40)
                } else {
                    list
                }
            }
            .padding(.vertical)
        }
    }

    @ViewBuilder
    private var statsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Deliverable.DeliverableStatus.primaryCases, id: \.self) { s in
                    BsContentCard(padding: .small) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(viewModel.statusCounts[s] ?? 0)")
                                .font(.title3.weight(.bold))
                                .contentTransition(.numericText())
                            Text(s.displayName)
                                .font(.caption2)
                                .foregroundStyle(BsColor.inkMuted)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var statusChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "全部", isSelected: viewModel.statusFilter == nil) {
                    viewModel.statusFilter = nil
                }
                ForEach(Deliverable.DeliverableStatus.primaryCases, id: \.self) { s in
                    chip(label: s.displayName, isSelected: viewModel.statusFilter == s) {
                        viewModel.statusFilter = s
                    }
                }
                Divider().frame(height: 16)
                chip(label: "仅我负责", isSelected: viewModel.onlyMine) {
                    viewModel.onlyMine.toggle()
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var advancedFilters: some View {
        VStack(spacing: 10) {
            HStack {
                Text("项目")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BsColor.inkMuted)
                Spacer()
                Menu {
                    Button("所有项目") { Haptic.selection(); viewModel.projectFilter = nil }
                    ForEach(viewModel.projects, id: \.id) { p in
                        if let pid = p.id {
                            Button(p.name ?? "(未命名)") { Haptic.selection(); viewModel.projectFilter = pid }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(projectFilterLabel)
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.caption)
                }
            }
            HStack {
                Text("负责人")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BsColor.inkMuted)
                Spacer()
                Menu {
                    Button("所有人") { Haptic.selection(); viewModel.assigneeFilter = nil }
                    ForEach(viewModel.members, id: \.id) { m in
                        if let mid = m.id {
                            Button(m.fullName ?? "未命名") { Haptic.selection(); viewModel.assigneeFilter = mid }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(assigneeFilterLabel)
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.caption)
                }
            }
            HStack {
                DatePicker(
                    "开始",
                    selection: Binding(
                        get: { viewModel.dateFrom ?? Date() },
                        set: { viewModel.dateFrom = $0 }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .font(.caption)
                Text("—")
                    .foregroundStyle(BsColor.inkFaint)
                DatePicker(
                    "结束",
                    selection: Binding(
                        get: { viewModel.dateTo ?? Date() },
                        set: { viewModel.dateTo = $0 }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .font(.caption)
                Spacer()
                if viewModel.dateFrom != nil || viewModel.dateTo != nil
                    || viewModel.projectFilter != nil || viewModel.assigneeFilter != nil {
                    Button("清除") {
                        Haptic.light()
                        viewModel.dateFrom = nil
                        viewModel.dateTo = nil
                        viewModel.projectFilter = nil
                        viewModel.assigneeFilter = nil
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BsColor.danger)
                }
            }
        }
        .padding(.horizontal)
    }

    private var projectFilterLabel: String {
        guard let pid = viewModel.projectFilter else { return "所有项目" }
        return viewModel.projects.first(where: { $0.id == pid })?.name ?? "所有项目"
    }

    private var assigneeFilterLabel: String {
        guard let aid = viewModel.assigneeFilter else { return "所有人" }
        return viewModel.members.first(where: { $0.id == aid })?.fullName ?? "所有人"
    }

    private var emptyDescription: String {
        let hasFilter = !viewModel.searchText.isEmpty
            || viewModel.statusFilter != nil
            || viewModel.projectFilter != nil
            || viewModel.assigneeFilter != nil
            || viewModel.dateFrom != nil
            || viewModel.dateTo != nil
            || viewModel.onlyMine
        return hasFilter ? "没有匹配的交付物，尝试调整筛选条件" : "提交你的第一个交付物"
    }

    // MARK: - Row list

    @ViewBuilder
    private var list: some View {
        LazyVStack(spacing: 10) {
            ForEach(viewModel.filteredItems) { d in
                NavigationLink {
                    DeliverableDetailView(
                        viewModel: DeliverableDetailViewModel(
                            deliverable: d,
                            client: supabase,
                            listViewModel: viewModel
                        )
                    )
                } label: {
                    DeliverableRow(item: d)
                        .padding(.horizontal)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        Haptic.light()
                        editTarget = d
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        Haptic.light()
                        deleteTarget = d
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                // NOTE: Swipe actions require a parent `List` — the list
                // here is a LazyVStack (matches the Web list's grid
                // layout), so we ship the same two entry points via
                // context-menu long-press instead. If the list is later
                // migrated to `List`, re-add .swipeActions here.
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.selection()
            action()
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? BsColor.brandAzure.opacity(0.15) : BsColor.inkMuted.opacity(0.08))
                .foregroundStyle(isSelected ? BsColor.brandAzure : BsColor.ink)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

private struct DeliverableRow: View {
    let item: Deliverable

    var body: some View {
        BsContentCard(padding: .small) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let project = item.project?.name, !project.isEmpty {
                            Label(project, systemImage: "folder")
                                .labelStyle(.titleAndIcon)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(BsColor.brandAzure)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(BsColor.brandAzure.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    if let desc = item.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(BsColor.inkMuted)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        DeliverableStatusChip(status: item.status)
                        if let urlStr = item.url ?? item.fileUrl,
                           !urlStr.isEmpty,
                           let platform = DeliverablePlatform.detect(urlStr) {
                            Label(platform.label, systemImage: "link")
                                .labelStyle(.titleAndIcon)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(platform.color.opacity(0.12))
                                .foregroundStyle(platform.color)
                                .clipShape(Capsule())
                        }
                        if let submittedAt = item.submittedAt {
                            Text(submittedAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(BsColor.inkFaint)
                        } else if let createdAt = item.createdAt {
                            Text(createdAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(BsColor.inkFaint)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BsColor.inkFaint)
            }
        }
    }
}

// MARK: - ViewModifier · 搜索/onChange/refresh 打包
// Swift 单 body 里 toolbar + 2 sheet + confirmationDialog + searchable +
// onSubmit + 7 个 onChange + refreshable + task + zyErrorBanner 一起串联会
// 触发类型推断超时（xcodebuild 真超时，非 SourceKit 虚警）。抽出筛选/搜索
// /刷新这一段到独立 ViewModifier 让编译器分块推断即可。
private struct DeliverableListFiltersModifier: ViewModifier {
    @ObservedObject var viewModel: DeliverableListViewModel

    func body(content: Content) -> some View {
        content
            .searchable(text: $viewModel.searchText, prompt: "搜索交付物…")
            .onSubmit(of: .search) {
                Task { await viewModel.reloadItems() }
            }
            .onChange(of: viewModel.searchText) { old, new in
                // Web reloads on every keystroke; we reload on "clear"
                // (native x button fires no onSubmit) and keep the
                // explicit submit for typed-in queries.
                if !old.isEmpty, new.isEmpty {
                    Task { await viewModel.reloadItems() }
                }
            }
            .onChange(of: viewModel.statusFilter) { _, _ in
                Task { await viewModel.reloadItems() }
            }
            .onChange(of: viewModel.projectFilter) { _, _ in
                Task { await viewModel.reloadItems() }
            }
            .onChange(of: viewModel.assigneeFilter) { _, _ in
                Task { await viewModel.reloadItems() }
            }
            .onChange(of: viewModel.dateFrom) { _, _ in
                Task { await viewModel.reloadItems() }
            }
            .onChange(of: viewModel.dateTo) { _, _ in
                Task { await viewModel.reloadItems() }
            }
            .refreshable {
                await viewModel.loadAll()
            }
            .task {
                await viewModel.loadAll()
            }
            .zyErrorBanner($viewModel.errorMessage)
    }
}
