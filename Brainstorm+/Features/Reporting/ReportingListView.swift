import SwiftUI
import UIKit

// ══════════════════════════════════════════════════════════════════
// Batch B.1 — Reporting list with CRUD entry points.
//
// One-view parity with Web's two pages (/dashboard/daily and
// /dashboard/weekly). iOS keeps the single tab in the app module
// registry and splits the content via a local segmented picker.
// ══════════════════════════════════════════════════════════════════

public struct ReportingListView: View {
    @StateObject private var viewModel: ReportingViewModel
    /// iter6 §A.3 — "全员" 视图的 VM。delay 创建：只在 admin/HR 切到全员 tab
    /// 时才 .task fire load,避免普通员工的视图额外打一次 RLS 受限请求。
    @StateObject private var teamViewModel = AdminTeamReportsViewModel()
    /// iter6 §A.3 — 顶层 scope picker。"我的" 默认；"全员" 仅在
    /// canViewTeam = true 时露出（admin/HR）。
    @State private var scope: Scope = .mine
    /// Iter 8 P2 — preserve scroll across tab swap (one position
    /// shared across daily / weekly sub-tabs; that mirrors what users
    /// expect — leaving the report tab and coming back to the same
    /// scrolled-down day list).
    @State private var scrollPosition = ScrollPosition()

    @EnvironmentObject private var scrollStore: ScrollStateStore
    @Environment(SessionManager.self) private var sessionManager

    @State private var dailyEditTarget: DailyLogEditTarget?
    @State private var weeklyEditTarget: WeeklyEditTarget?
    // Long-press 增强 (longpress-system §菜单结构原则: hoisted destructive state):
    // 删除走 confirmationDialog 二次确认而不是 contextMenu 直接 mutate。
    // hoisted 到 view 根,daily / weekly 共用同一对 state 互不干扰。
    @State private var pendingDeleteDaily: DailyLog?
    @State private var pendingDeleteWeekly: WeeklyReport?
    /// Iter 6 §B.7 — 数据导出，弹 ExportSheet
    @State private var isShowingExport = false

    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    public enum Scope: String, CaseIterable, Identifiable {
        case mine, team
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .mine: return "我的"
            case .team: return "全员"
            }
        }
    }

    public init(viewModel: ReportingViewModel, isEmbedded: Bool = false) {
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

    /// 是否露出"全员"入口。RBAC 镜像 AdminCenterViewModel.canManagePeople /
    /// canEnterAdmin —— admin / superadmin 或持有 hr_ops cap 的员工。
    /// 普通员工根本看不到 segmented control 的"全员"段,UI 不需多余 disable
    /// 态。
    private var canViewTeam: Bool {
        guard let profile = sessionManager.currentProfile else { return false }
        let migration = RBACManager.shared.migrateLegacyRole(profile.role)
        if migration.primaryRole == .admin || migration.primaryRole == .superadmin {
            return true
        }
        let caps = RBACManager.shared.getEffectiveCapabilities(for: profile)
        return caps.contains(.hr_ops)
    }

    private var coreContent: some View {
        ScrollView {
            // Iter 8 P2 scrollPosition is bound at the ScrollView level.
            VStack(spacing: 16) {
                if canViewTeam {
                    // iter6 §A.3 — 顶层 scope picker（我的 / 全员）。
                    Picker("范围", selection: $scope) {
                        ForEach(Scope.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                switch scope {
                case .mine:
                    mineContent
                case .team:
                    teamContent
                }
            }
            .padding(.vertical)
        }
        .scrollPosition($scrollPosition)
        .navigationTitle("报告")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if scope == .mine {
                        Button {
                            switch viewModel.selectedTab {
                            case .daily:  dailyEditTarget = .new
                            case .weekly: weeklyEditTarget = .new
                            }
                        } label: {
                            Label("新建报告", systemImage: "plus")
                        }
                    }
                    Button {
                        isShowingExport = true
                    } label: {
                        Label(
                            viewModel.selectedTab == .daily ? "导出日报 CSV" : "导出周报 CSV",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多操作")
            }
        }
        .sheet(isPresented: $isShowingExport) {
            ExportSheet(
                module: viewModel.selectedTab == .daily ? .dailyLogs : .weeklyReports
            )
        }
        .refreshable {
            switch scope {
            case .mine: await viewModel.fetchReports()
            case .team: await teamViewModel.load()
            }
        }
        .task {
            await viewModel.fetchReports()
            // Iter 8 P1 §B.9 — realtime cross-device sync (Web ↔ iOS)
            await viewModel.subscribeRealtime()
        }
        .onAppear {
            // Iter 8 P2 — restore scroll position across tab swap.
            let key = viewModel.selectedTab == .daily
                ? ScrollStateStore.Key.reportingDaily
                : ScrollStateStore.Key.reportingWeekly
            if let saved = scrollStore.position(for: key) {
                scrollPosition = saved
            }
        }
        .onDisappear {
            Task { await viewModel.unsubscribeRealtime() }
            let key = viewModel.selectedTab == .daily
                ? ScrollStateStore.Key.reportingDaily
                : ScrollStateStore.Key.reportingWeekly
            scrollStore.save(scrollPosition, for: key)
        }
        .task(id: scope) {
            // 切到 team 时延迟加载（首次切才 fetch）。
            if scope == .team { await teamViewModel.load() }
        }
        .sheet(item: $dailyEditTarget) { target in
            DailyLogEditView(
                viewModel: viewModel,
                existingLog: target.log
            )
            .bsSheetStyle(.form)
        }
        .sheet(item: $weeklyEditTarget) { target in
            WeeklyReportEditView(
                viewModel: viewModel,
                existingReport: target.report
            )
            .bsSheetStyle(.form)
        }
        .confirmationDialog(
            "确认删除",
            isPresented: Binding(
                get: { pendingDeleteDaily != nil },
                set: { if !$0 { pendingDeleteDaily = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteDaily
        ) { target in
            Button("删除", role: .destructive) {
                Haptic.error()
                Task { await viewModel.deleteLog(target) }
                pendingDeleteDaily = nil
            }
            Button("取消", role: .cancel) { pendingDeleteDaily = nil }
        } message: { _ in
            Text("将删除该日报,该操作无法撤销。")
        }
        .confirmationDialog(
            "确认删除",
            isPresented: Binding(
                get: { pendingDeleteWeekly != nil },
                set: { if !$0 { pendingDeleteWeekly = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteWeekly
        ) { target in
            Button("删除", role: .destructive) {
                Haptic.error()
                Task { await viewModel.deleteWeeklyReport(target) }
                pendingDeleteWeekly = nil
            }
            Button("取消", role: .cancel) { pendingDeleteWeekly = nil }
        } message: { _ in
            Text("将删除该周报,该操作无法撤销。")
        }
        .zyErrorBanner($viewModel.errorMessage)
        .zyErrorBanner($teamViewModel.errorMessage)
    }

    // ── 我的 (个人日报/周报) ──────────────────────────────────────
    @ViewBuilder
    private var mineContent: some View {
        // Iter 7 §C.1 — skeleton-first via bsLoadingState。section 始终挂载,
        // bsLoadingState 决定 redacted shimmer / 错误 / 空态 chrome。
        VStack(spacing: 16) {
            Picker("视图", selection: $viewModel.selectedTab) {
                ForEach(ReportingViewModel.Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Group {
                switch viewModel.selectedTab {
                case .daily:  dailySection
                case .weekly: weeklySection
                }
            }
            .bsLoadingState(BsLoadingState.derive(
                isLoading: viewModel.isLoading,
                hasItems: hasMineItems,
                errorMessage: nil,                              // banner 走 zyErrorBanner
                emptySystemImage: viewModel.selectedTab == .daily ? "calendar.badge.clock" : "doc.text",
                emptyTitle: viewModel.selectedTab == .daily ? "暂无日报" : "暂无周报",
                emptyDescription: "点击右上角「+」新建一条"
            ))
            .animation(
                .smooth(duration: 0.25),
                value: viewModel.selectedTab == .daily
                    ? viewModel.dailyLogs.count
                    : viewModel.weeklyReports.count
            )
        }
    }

    /// hasItems 选择器 —— daily / weekly 各自的 list count。
    private var hasMineItems: Bool {
        switch viewModel.selectedTab {
        case .daily:  return !viewModel.dailyLogs.isEmpty
        case .weekly: return !viewModel.weeklyReports.isEmpty
        }
    }

    // ── 全员 (admin/HR 聚合视图) ──────────────────────────────────
    @ViewBuilder
    private var teamContent: some View {
        // iter7 fix: 顶部筛选简化 — 拿掉日期 range pickers; 保留 segmented +
        // 人员筛选 Menu。下方按日期 Section 分组。
        VStack(spacing: BsSpacing.md) {
            BsContentCard(padding: .medium) {
                VStack(alignment: .leading, spacing: BsSpacing.md) {
                    Picker("视图", selection: $teamViewModel.segment) {
                        ForEach(AdminTeamReportsViewModel.Segment.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: teamViewModel.segment) { _, _ in
                        Task { await teamViewModel.load() }
                    }

                    // iter6 §A.3 — 人员筛选 Menu+Picker (保留)。
                    memberFilterMenu
                }
            }
            .padding(.horizontal)

            if teamViewModel.isLoading && teamCurrentRowsEmpty {
                ProgressView()
                    .padding(.top, 40)
            } else if teamCurrentRowsEmpty {
                BsEmptyState(
                    title: "暂无报告",
                    systemImage: teamViewModel.segment == .daily ? "doc.text" : "calendar",
                    description: "调整成员后再试"
                )
                .padding(.top, 40)
            } else {
                // iter7: 按日期分组渲染 (用户原话"全员的日报按照每一天和
                // 日期分类好")。LazyVStack 内手卷 Section header 而非 List —
                // ReportingListView 上层已是 ScrollView, 嵌 List 高度会塌。
                LazyVStack(spacing: BsSpacing.md, pinnedViews: [.sectionHeaders]) {
                    switch teamViewModel.segment {
                    case .daily:
                        ForEach(teamViewModel.dailyGroups) { group in
                            Section {
                                ForEach(group.rows) { row in
                                    teamDailyCard(row).padding(.horizontal)
                                }
                            } header: {
                                teamSectionHeader(group.label)
                            }
                        }
                    case .weekly:
                        ForEach(teamViewModel.weeklyGroups) { group in
                            Section {
                                ForEach(group.rows) { row in
                                    teamWeeklyCard(row).padding(.horizontal)
                                }
                            } header: {
                                teamSectionHeader(group.label)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func teamSectionHeader(_ label: String) -> some View {
        HStack {
            Text(label)
                .font(BsTypography.cardSubtitle)
                .foregroundStyle(BsColor.ink)
            Spacer()
        }
        .padding(.horizontal, BsSpacing.lg)
        .padding(.vertical, BsSpacing.sm)
        .background(BsColor.pageBackground.opacity(0.95))
    }

    private var teamCurrentRowsEmpty: Bool {
        switch teamViewModel.segment {
        case .daily:  return teamViewModel.dailyRows.isEmpty
        case .weekly: return teamViewModel.weeklyRows.isEmpty
        }
    }

    @ViewBuilder
    private var memberFilterMenu: some View {
        // iter6 §A.3 —— iOS-native 写法：Menu { Picker } 让系统画全屏弹层 +
        // 自带搜索+滚动；优于横向 chip 滚动条（chip 滚动在 100+ 人公司体验
        // 极差，找人靠肉眼）。
        let selectedLabel: String = {
            if let uid = teamViewModel.memberFilter,
               let m = teamViewModel.members.first(where: { $0.id == uid }) {
                return m.fullName
            }
            return "全部成员"
        }()
        Menu {
            Picker("成员", selection: $teamViewModel.memberFilter) {
                Text("全部成员").tag(UUID?.none)
                ForEach(teamViewModel.members, id: \.id) { m in
                    if let dept = m.department, !dept.isEmpty {
                        Text("\(m.fullName) · \(dept)").tag(UUID?.some(m.id))
                    } else {
                        Text(m.fullName).tag(UUID?.some(m.id))
                    }
                }
            }
        } label: {
            HStack {
                Label(selectedLabel, systemImage: "person.2.fill")
                    .font(BsTypography.bodyMedium)
                    .foregroundStyle(BsColor.ink)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(BsColor.inkFaint)
            }
            .padding(.horizontal, BsSpacing.md)
            .padding(.vertical, BsSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BsColor.inkMuted.opacity(0.08))
            )
        }
        .onChange(of: teamViewModel.memberFilter) { _, _ in
            Task { await teamViewModel.load() }
        }
    }

    @ViewBuilder
    private func teamDailyCard(_ row: AdminTeamReportsViewModel.DailyRow) -> some View {
        BsContentCard(padding: .medium) {
            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                HStack(spacing: BsSpacing.sm) {
                    Text(row.author?.fullName ?? "未知作者")
                        .font(BsTypography.cardSubtitle)
                        .foregroundStyle(BsColor.ink)
                    if let dept = row.author?.department, !dept.isEmpty {
                        Text(dept)
                            .font(BsTypography.captionSmall)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                    Spacer()
                    Text(row.log.date.formatted(.dateTime.month().day()))
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
                Text(row.log.content)
                    .font(BsTypography.bodySmall)
                    .foregroundStyle(BsColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress = row.log.progress, !progress.isEmpty {
                    Label(progress, systemImage: "checkmark.circle")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.success)
                }
                if let blockers = row.log.blockers, !blockers.isEmpty {
                    Label(blockers, systemImage: "exclamationmark.triangle")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.warning)
                }
            }
        }
    }

    @ViewBuilder
    private func teamWeeklyCard(_ row: AdminTeamReportsViewModel.WeeklyRow) -> some View {
        BsContentCard(padding: .medium) {
            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                HStack(spacing: BsSpacing.sm) {
                    Text(row.author?.fullName ?? "未知作者")
                        .font(BsTypography.cardSubtitle)
                        .foregroundStyle(BsColor.ink)
                    if let dept = row.author?.department, !dept.isEmpty {
                        Text(dept)
                            .font(BsTypography.captionSmall)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                    Spacer()
                    Text(row.report.weekStart.formatted(.dateTime.month().day()))
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
                if let summary = row.report.summary, !summary.isEmpty {
                    Text(summary)
                        .font(BsTypography.bodySmall)
                        .foregroundStyle(BsColor.ink)
                        .lineLimit(8)
                }
                if let acc = row.report.accomplishments, !acc.isEmpty {
                    Text("成就：\(acc)")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.success)
                        .lineLimit(4)
                }
                if let plans = row.report.plans, !plans.isEmpty {
                    Text("计划：\(plans)")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.brandAzure)
                        .lineLimit(4)
                }
                if let blockers = row.report.blockers, !blockers.isEmpty {
                    Text("阻碍：\(blockers)")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.warning)
                        .lineLimit(4)
                }
            }
        }
    }

    // ── Daily ────────────────────────────────────────────────────
    @ViewBuilder
    private var dailySection: some View {
        if viewModel.dailyLogs.isEmpty {
            BsEmptyState(
                title: "暂无日志",
                systemImage: "doc.text",
                description: "开始记录你的第一篇工作日志"
            )
            .padding(.top, 40)
        } else {
            // v1.3.1 perf: VStack → LazyVStack —— daily logs 可能累积到 30-60 条，
            // 非 lazy 版本开屏会一次性构建所有 card body，在 ProMotion 下明显掉帧
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.dailyLogs) { log in
                    DailyLogCardView(log: log)
                        .padding(.horizontal)
                        .onTapGesture {
                            dailyEditTarget = .edit(log)
                        }
                        .contextMenu {
                            // Long-press 增强 (longpress-system §5 日报项):
                            // 编辑 / 复制 / 删除三段式 + Label icon 化。删除走
                            // hoisted confirmationDialog,不再 inline mutate。
                            Button {
                                Haptic.light()
                                dailyEditTarget = .edit(log)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }

                            Button {
                                let dateStr = log.date.formatted(.dateTime.year().month().day())
                                let summary = "\(dateStr)\n\(log.content)"
                                UIPasteboard.general.string = summary
                                Haptic.light()
                            } label: {
                                Label("复制内容", systemImage: "doc.on.doc")
                            }

                            Divider()

                            Button(role: .destructive) {
                                Haptic.warning()
                                pendingDeleteDaily = log
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeleteDaily = log
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                dailyEditTarget = .edit(log)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                }
            }
        }
    }

    // ── Weekly ───────────────────────────────────────────────────
    @ViewBuilder
    private var weeklySection: some View {
        if viewModel.weeklyReports.isEmpty {
            BsEmptyState(
                title: "暂无周报",
                systemImage: "calendar",
                description: "保存你的第一篇周报"
            )
            .padding(.top, 40)
        } else {
            // v1.3.1 perf: 同 dailySection，改 LazyVStack
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.weeklyReports) { r in
                    WeeklyReportCardView(report: r)
                        .padding(.horizontal)
                        .onTapGesture {
                            weeklyEditTarget = .edit(r)
                        }
                        .contextMenu {
                            // Long-press 增强 (longpress-system §5 周报项)
                            Button {
                                Haptic.light()
                                weeklyEditTarget = .edit(r)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }

                            Button {
                                UIPasteboard.general.string = weeklyClipboardSummary(r)
                                Haptic.light()
                            } label: {
                                Label("复制内容", systemImage: "doc.on.doc")
                            }

                            Divider()

                            Button(role: .destructive) {
                                Haptic.warning()
                                pendingDeleteWeekly = r
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeleteWeekly = r
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                weeklyEditTarget = .edit(r)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                }
            }
        }
    }
}

// MARK: - Long-press clipboard helpers

private func weeklyClipboardSummary(_ r: WeeklyReport) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    let start = f.string(from: r.weekStart)
    let end = r.weekEnd.map { f.string(from: $0) } ?? ""
    let header = end.isEmpty ? "周报 \(start)" : "周报 \(start) ~ \(end)"

    var lines: [String] = [header, ""]
    if let s = r.summary, !s.isEmpty {
        lines.append("摘要:")
        lines.append(s)
        lines.append("")
    }
    if let a = r.accomplishments, !a.isEmpty {
        lines.append("成就:")
        lines.append(a)
        lines.append("")
    }
    if let p = r.plans, !p.isEmpty {
        lines.append("计划:")
        lines.append(p)
        lines.append("")
    }
    if let b = r.blockers, !b.isEmpty {
        lines.append("阻碍:")
        lines.append(b)
    }
    return lines.joined(separator: "\n")
}

// ══════════════════════════════════════════════════════════════════
// Sheet target wrappers (Identifiable) — required by `.sheet(item:)`.
// ══════════════════════════════════════════════════════════════════

private enum DailyLogEditTarget: Identifiable {
    case new
    case edit(DailyLog)

    var id: String {
        switch self {
        case .new:           return "new"
        case .edit(let log): return log.id.uuidString
        }
    }

    var log: DailyLog? {
        switch self {
        case .new:           return nil
        case .edit(let log): return log
        }
    }
}

private enum WeeklyEditTarget: Identifiable {
    case new
    case edit(WeeklyReport)

    var id: String {
        switch self {
        case .new:              return "new"
        case .edit(let report): return report.id.uuidString
        }
    }

    var report: WeeklyReport? {
        switch self {
        case .new:              return nil
        case .edit(let report): return report
        }
    }
}
