import SwiftUI

// ══════════════════════════════════════════════════
// BrainStorm+ iOS — Dashboard Role-Branching Sections
//
// 1:1 port of Web `src/app/dashboard/_views/{employee,admin,superadmin}-dashboard.tsx`
// Web template resolver lives at `src/lib/dashboard-views.ts`:
//   employee → personal workbench (我的任务 / 月度快照 / 活跃项目 / OKR / 最近活动)
//   admin    → employee sections + 审批概览 / 风险概览 / 团队监控
//   superadmin → admin sections + 经营总览 (Executive KPIs)
//
// Batch D.1 wired every widget to real Supabase data via
// `DashboardWidgetsViewModel` — 1:1 port of Web's
// `fetchWorkbenchData(primaryRole, capabilities)` in
// `src/lib/actions/dashboard-workbench.ts`. Each card renders an empty
// state ("暂无数据") when its slice returns zero rows.
//
// Phase 15 — every main widget now wraps its body in BsWidgetCard
// (4-zone envelope: UPPERCASE label / optional hero number / custom body /
// optional Azure CTA link) so iOS matches Web `role-dashboard-cards.tsx`
// micro-vocabulary harmony. Inline SectionHeader + zyCardStyle are retired
// from these widgets; BsWidgetCard owns the material (BsContentCard) + header.
// ══════════════════════════════════════════════════

// MARK: - Employee Dashboard Body

struct EmployeeDashboardBody: View {
    let viewModel: DashboardViewModel
    @ObservedObject var widgets: DashboardWidgetsViewModel

    var body: some View {
        VStack(spacing: BsSpacing.xl) {
            MyTasksSection(tasks: widgets.myTasks)
            MonthlySnapshotSection(snapshot: widgets.monthlySnapshot)
            ActiveProjectsSection(projects: widgets.activeProjects)
            MyOkrSection(objectives: widgets.myOkr)
            RecentActivitySection(activity: widgets.recentActivity)
        }
    }
}

// MARK: - Admin Dashboard Body

struct AdminDashboardBody: View {
    let viewModel: DashboardViewModel
    @ObservedObject var widgets: DashboardWidgetsViewModel

    var body: some View {
        VStack(spacing: BsSpacing.xl) {
            // Admin-only hero row (Web: admin-dashboard.tsx:15-17)
            HStack(spacing: BsSpacing.md) {
                ApprovalSummaryCard(pending: widgets.pendingApprovals)
                RiskOverviewCard(risk: widgets.riskOverview)
            }

            // Team Monitor (Web: admin-dashboard.tsx:19)
            TeamMonitorCard(stats: widgets.teamStats, alerts: widgets.teamTodoAlerts)

            MyTasksSection(tasks: widgets.myTasks)
            MonthlySnapshotSection(snapshot: widgets.monthlySnapshot)
            ActiveProjectsSection(projects: widgets.activeProjects)
            RecentActivitySection(activity: widgets.recentActivity)
        }
    }
}

// MARK: - Superadmin Dashboard Body

struct SuperadminDashboardBody: View {
    let viewModel: DashboardViewModel
    @ObservedObject var widgets: DashboardWidgetsViewModel

    var body: some View {
        VStack(spacing: BsSpacing.xl) {
            // Executive KPIs — superadmin only (Web: superadmin-dashboard.tsx:18)
            ExecutiveKPIsCard(kpis: widgets.executiveKpis)

            // Admin-tier cards also visible to superadmin
            HStack(spacing: BsSpacing.md) {
                ApprovalSummaryCard(pending: widgets.pendingApprovals)
                RiskOverviewCard(risk: widgets.riskOverview)
            }

            TeamMonitorCard(stats: widgets.teamStats, alerts: widgets.teamTodoAlerts)

            MyTasksSection(tasks: widgets.myTasks)
            MonthlySnapshotSection(snapshot: widgets.monthlySnapshot)
            ActiveProjectsSection(projects: widgets.activeProjects)
            RecentActivitySection(activity: widgets.recentActivity)
        }
    }
}

// MARK: - Quick Actions (per-role)
//
// Web does not render "Quick Actions tiles" on the dashboard itself —
// navigation is driven by the sidebar (desktop) / bottom-tabs (mobile) which
// already branches by role+capabilities (see `components/layout/bottom-tabs.tsx`).
// iOS originally kept a "Workflow Apps" grid as native chrome but filtered the tile
// set by template so higher-tier users got admin/superadmin entry points and
// employees didn't see admin-only modules.
//
// TODO(Phase 20): Currently unused — TabBar now owns navigation, so dumping a
// sitemap onto the dashboard was redundant. Struct definitions are kept for
// potential future reuse, but no body references them any more.

private struct RoleQuickActionsSection: View {
    let template: PrimaryRole

    private let columns = [
        GridItem(.flexible(), spacing: BsSpacing.lg),
        GridItem(.flexible(), spacing: BsSpacing.lg),
        GridItem(.flexible(), spacing: BsSpacing.lg)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: BsSpacing.lg) {
            Text("快捷入口")
                .font(BsTypography.sectionTitle)
                .foregroundStyle(BsColor.ink)

            LazyVGrid(columns: columns, spacing: BsSpacing.lg) {
                ForEach(tiles) { tile in
                    QuickActionTile(tile: tile)
                }
            }
        }
    }

    private var tiles: [QuickActionTile.Descriptor] {
        // 色彩约束:只用品牌 4 色 (azure / mint / coral / ink) 按功能类别分组,
        // 拒绝 teal/purple/pink/indigo/cyan 那种偏离品牌的杂色。
        // azure  = 个人产出类 (任务 / 日报 / 周报 / OKR / 知识库 / 分析)
        // mint   = 协作沟通类 (聊天 / 团队 / 公告 / 活动)
        // coral  = 审批流程类 (审批 / 请假 / 招聘)
        // ink    = 系统管理类 (考勤 / 系统配置 / AI / 财务)
        switch template {
        case .employee:
            return [
                .init(module: .tasks,         title: "任务",     color: BsColor.brandAzure),
                .init(module: .daily,         title: "日报",     color: BsColor.brandAzure),
                .init(module: .weekly,        title: "周报",     color: BsColor.brandAzure),
                .init(module: .okr,           title: "OKR",     color: BsColor.brandAzure),
                .init(module: .approval,      title: "审批",     color: BsColor.brandCoral),
                .init(module: .leaves,        title: "请假",     color: BsColor.brandCoral),
                .init(module: .knowledge,     title: "知识库",   color: BsColor.brandAzure),
                .init(module: .chat,          title: "团队聊天", color: BsColor.brandMint),
                .init(module: .announcements, title: "公告",     color: BsColor.brandMint),
            ]
        case .admin:
            return [
                .init(module: .approval,   title: "审批",   color: BsColor.brandCoral),
                .init(module: .tasks,      title: "任务",   color: BsColor.brandAzure),
                .init(module: .team,       title: "团队",   color: BsColor.brandMint),
                .init(module: .hiring,     title: "招聘",   color: BsColor.brandCoral),
                .init(module: .attendance, title: "考勤",   color: BsColor.ink),
                .init(module: .leaves,     title: "请假",   color: BsColor.brandCoral),
                .init(module: .daily,      title: "日报",   color: BsColor.brandAzure),
                .init(module: .weekly,     title: "周报",   color: BsColor.brandAzure),
                .init(module: .knowledge,  title: "知识库", color: BsColor.brandAzure),
            ]
        case .superadmin:
            return [
                .init(module: .approval,      title: "审批",     color: BsColor.brandCoral),
                .init(module: .admin,         title: "系统配置", color: BsColor.ink),
                .init(module: .aiAnalysis,    title: "AI 分析",  color: BsColor.ink),
                .init(module: .finance,       title: "财务 AI",  color: BsColor.ink),
                // .analytics QuickLink 移除：iOS 不移植 Web BI 仪表板，
                // 相关数据分析走 aiAnalysis + finance AI 视图
                .init(module: .team,          title: "团队",     color: BsColor.brandMint),
                .init(module: .hiring,        title: "招聘",     color: BsColor.brandCoral),
                .init(module: .activity,      title: "活动日志", color: BsColor.brandMint),
                .init(module: .announcements, title: "公告",     color: BsColor.brandMint),
            ]
        }
    }
}

// MARK: - Quick Action Tile

private struct QuickActionTile: View {
    struct Descriptor: Identifiable {
        let module: AppModule
        let title: String
        let color: Color
        var id: String { module.rawValue }
    }

    let tile: Descriptor

    @State private var isPressed = false

    var body: some View {
        NavigationLink(destination: ActionItemHelper.destination(for: tile.module)) {
            VStack(spacing: BsSpacing.sm + 2) {
                ZStack {
                    Circle()
                        .fill(tile.color.opacity(0.08))
                        .frame(width: 44, height: 44)

                    Image(systemName: tile.module.iconName)
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(tile.color)
                }

                Text(tile.title)
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BsSpacing.lg)
            .background(BsColor.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                    .stroke(BsColor.borderSubtle, lineWidth: 0.5)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(BsMotion.Anim.overshoot, value: isPressed)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, perform: {}, onPressingChanged: { pressing in
                if pressing != isPressed {
                    isPressed = pressing
                    if pressing { Haptic.light() }
                }
            })
        }
    }
}

// MARK: - Shared section header
//
// Kept for RoleQuickActionsSection + any future non-BsWidgetCard sections
// (Phase 15 moved the 9 main dashboard widgets off of this and onto
// BsWidgetCard's built-in header).

private struct SectionHeader: View {
    let title: String
    let badge: String?
    let trailing: AnyView?

    init(title: String, badge: String? = nil, trailing: AnyView? = nil) {
        self.title = title
        self.badge = badge
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: BsSpacing.sm) {
            Text(title)
                .font(BsTypography.sectionTitle)
                .foregroundStyle(BsColor.ink)

            if let badge {
                Text(badge)
                    .font(BsTypography.meta)
                    .foregroundStyle(BsColor.brandAzure)
                    .padding(.horizontal, BsSpacing.sm)
                    .padding(.vertical, 2)
                    .background(BsColor.brandAzure.opacity(0.1))
                    .clipShape(Capsule())
            }

            Spacer()

            if let trailing {
                trailing
            }
        }
    }
}

// MARK: - Empty state card (uniform for "暂无数据")

private struct EmptyStateCard: View {
    let iconName: String
    let title: String
    let hint: String?

    var body: some View {
        VStack(spacing: BsSpacing.sm) {
            ZStack {
                Circle()
                    .fill(BsColor.brandAzure.opacity(0.06))
                    .frame(width: 56, height: 56)
                Image(systemName: iconName)
                    .font(.system(.title3, weight: .light))
                    .foregroundStyle(BsColor.brandAzure.opacity(0.55))
            }
            Text(title)
                .font(BsTypography.cardSubtitle)
                .foregroundStyle(BsColor.inkMuted)
            if let hint {
                Text(hint)
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkFaint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BsSpacing.xl - 2)
    }
}

// ════════════════════════════════════════════════════════
// MARK: - 1. My Tasks Section (employee+admin+superadmin)
// Mirror of Web `my-tasks-card.tsx`. Phase 15 → BsWidgetCard envelope.
// ════════════════════════════════════════════════════════

private struct MyTasksSection: View {
    let tasks: DashboardWidgetsViewModel.MyTasksSummary

    // Phase 24 collapse: if there's nothing to show (no active tasks,
    // no todo/inProgress/overdue queue), surface a welcoming placeholder
    // instead of a "0 0 0 0" tile grid that reads like a failure report.
    private var isEmpty: Bool {
        tasks.activeCount + tasks.todo + tasks.inProgress + tasks.overdue == 0
    }

    var body: some View {
        if isEmpty {
            BsWidgetCard(
                label: "我的任务",
                cta: .link("查看全部") {
                    AnyView(ActionItemHelper.destination(for: .tasks))
                }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(.title2))
                        .foregroundStyle(BsColor.brandMint)
                    Text("今日无待办")
                        .font(BsTypography.cardTitle)
                        .foregroundStyle(BsColor.ink)
                    Text("点击右下角 + 新建任务开始")
                        .font(BsTypography.bodySmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, BsSpacing.sm)
            }
        } else {
            BsWidgetCard(
                label: "我的任务",
                hero: .number("\(tasks.activeCount)", sublabel: "活跃任务"),
                cta: .link("查看全部") {
                    AnyView(ActionItemHelper.destination(for: .tasks))
                }
            ) {
                BsStatTileRow([
                    .init(value: "\(tasks.inProgress)", label: "进行中", tone: .azure),
                    .init(value: "\(tasks.todo)",       label: "待处理", tone: .neutral),
                    .init(value: "\(tasks.overdue)",    label: "逾期",   tone: .danger),
                ])
            }
        }
    }
}

// ════════════════════════════════════════════════════════
// MARK: - 2. Monthly Snapshot Section
// Mirror of Web `monthly-snapshot-card.tsx`. Phase 15 → BsWidgetCard envelope.
// 5 attendance rows stay as a vertical icon+value+label list (not tiles)
// because BsStatTileRow is horizontal-only and the tokenised icon colours
// from Phase 11.3 are part of the visual semantics (success/mint/azure/
// warning/danger-on-absent).
// ════════════════════════════════════════════════════════

private struct MonthlySnapshotSection: View {
    let snapshot: DashboardWidgetsViewModel.MonthlySnapshot

    private struct Item { let label: String; let value: Int; let icon: String; let fg: Color; let bg: Color }

    private var items: [Item] {
        // 口径（与 Web dashboard-workbench.ts 一致）：
        //   出勤天数 = state ∈ {normal, field_work} 的行数
        //     normal    = 正常打卡日
        //     field_work = 外勤打卡（还是"在岗"）
        //   出差天数 = state = business_trip
        //   事假天数 = state = personal_leave   ← 公司只有事假 + 调休两种制度，
        //                                         标签直接写"事假"避免用户误以为
        //                                         包含调休
        //   调休天数 = state = comp_time
        //   旷工天数 = state = absent
        let absentColor: Color = snapshot.absentDays > 0 ? BsColor.danger : BsColor.success
        return [
            Item(label: "出勤天数", value: snapshot.attendanceDays, icon: "checkmark.circle", fg: BsColor.success, bg: BsColor.success.opacity(0.12)),
            Item(label: "出差天数", value: snapshot.businessTripDays, icon: "airplane", fg: BsColor.brandMint, bg: BsColor.brandMint.opacity(0.12)),
            Item(label: "事假天数", value: snapshot.leaveDays, icon: "doc.text", fg: BsColor.brandAzure, bg: BsColor.brandAzure.opacity(0.12)),
            Item(label: "调休天数", value: snapshot.compTimeDays, icon: "arrow.triangle.2.circlepath", fg: BsColor.warning, bg: BsColor.warning.opacity(0.12)),
            Item(label: "旷工天数", value: snapshot.absentDays, icon: "exclamationmark.octagon", fg: absentColor, bg: absentColor.opacity(0.12)),
        ]
    }

    var body: some View {
        BsWidgetCard(
            label: "本月快照",
            accessory: {
                if snapshot.flexibleHours {
                    AnyView(BsTagPill("弹性工时", tone: .admin, icon: "clock.arrow.circlepath"))
                } else {
                    AnyView(EmptyView())
                }
            }
        ) {
            VStack(spacing: BsSpacing.md) {
                ForEach(0..<items.count, id: \.self) { idx in
                    HStack(spacing: BsSpacing.sm + 2) {
                        ZStack {
                            RoundedRectangle(cornerRadius: BsRadius.md - 2, style: .continuous)
                                .fill(items[idx].bg)
                                .frame(width: 36, height: 36)
                            Image(systemName: items[idx].icon)
                                .font(.system(.callout, weight: .medium))
                                .foregroundStyle(items[idx].fg)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(items[idx].value)")
                                .font(BsTypography.statSmall)
                                .foregroundStyle(BsColor.ink)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text(items[idx].label)
                                .font(BsTypography.meta)
                                .foregroundStyle(BsColor.inkMuted)
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}

// ════════════════════════════════════════════════════════
// MARK: - 3. Active Projects Section
// Mirror of Web `activity-projects.tsx` RealProjectsWidget.
// ════════════════════════════════════════════════════════

private struct ActiveProjectsSection: View {
    let projects: [DashboardWidgetsViewModel.ProjectSummary]

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active": return BsColor.success
        case "planning": return BsColor.brandAzure  // TODO(batch-3): evaluate .purple → brandAzure
        case "on_hold": return BsColor.brandCoral
        case "completed": return BsColor.inkMuted
        default: return BsColor.inkMuted
        }
    }

    var body: some View {
        BsWidgetCard(
            label: "活跃项目",
            cta: .link("所有项目") {
                AnyView(ActionItemHelper.destination(for: .projects))
            }
        ) {
            if projects.isEmpty {
                EmptyStateCard(iconName: "folder", title: "暂无活跃项目", hint: "创建新项目以开始跟踪进度")
            } else {
                VStack(spacing: BsSpacing.sm + 2) {
                    ForEach(projects) { project in
                        ProjectRowCard(project: project, accent: statusColor(project.status))
                    }
                }
            }
        }
    }
}

private struct ProjectRowCard: View {
    let project: DashboardWidgetsViewModel.ProjectSummary
    let accent: Color

    var body: some View {
        NavigationLink(destination: ActionItemHelper.destination(for: .projects)) {
            VStack(alignment: .leading, spacing: BsSpacing.sm + 2) {
                HStack(spacing: BsSpacing.sm + 2) {
                    ZStack {
                        RoundedRectangle(cornerRadius: BsRadius.md - 2, style: .continuous)
                            .fill(accent.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "folder")
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(accent)
                    }
                    Text(project.name)
                        .font(BsTypography.cardSubtitle)
                        .foregroundStyle(BsColor.ink)
                        .lineLimit(1)
                    Spacer()
                    Text("\(project.progress)%")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                        .monospacedDigit()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(BsColor.inkFaint.opacity(0.2))
                        Capsule()
                            .fill(accent)
                            .frame(width: geo.size.width * CGFloat(min(max(project.progress, 0), 100)) / 100)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("\(project.taskDone)/\(project.taskTotal) 完成")
                        .font(BsTypography.meta)
                        .foregroundStyle(BsColor.inkMuted)
                    Spacer()
                    if let date = project.targetDate {
                        Text(date)
                            .font(BsTypography.meta)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                }
            }
            .padding(BsSpacing.md + 2)
            .background(BsColor.surfacePrimary.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                    .stroke(BsColor.borderSubtle, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// ════════════════════════════════════════════════════════
// MARK: - 4. My OKR Section
// Mirror of Web `activity-projects.tsx` RealOkrWidget.
// ════════════════════════════════════════════════════════

private struct MyOkrSection: View {
    let objectives: [DashboardWidgetsViewModel.ObjectiveSummary]

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active": return BsColor.brandAzure
        case "completed": return BsColor.success
        case "cancelled": return BsColor.danger
        default: return BsColor.inkMuted
        }
    }

    var body: some View {
        BsWidgetCard(
            label: "我的 OKR",
            cta: .link("OKR 详情") {
                AnyView(ActionItemHelper.destination(for: .okr))
            }
        ) {
            if objectives.isEmpty {
                EmptyStateCard(iconName: "target", title: "暂无 OKR 目标", hint: "前往 OKR 页面创建目标")
            } else {
                VStack(spacing: BsSpacing.md) {
                    ForEach(objectives) { obj in
                        ObjectiveRow(obj: obj, accent: statusColor(obj.status))
                    }
                }
            }
        }
    }
}

private struct ObjectiveRow: View {
    let obj: DashboardWidgetsViewModel.ObjectiveSummary
    let accent: Color

    var body: some View {
        HStack(spacing: BsSpacing.md) {
            ProgressRing(progress: obj.progress, accent: accent, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(obj.title)
                    .font(BsTypography.caption)
                    .foregroundStyle(BsColor.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(obj.krCount) 个 KR · \(obj.period)")
                    .font(BsTypography.meta)
                    .foregroundStyle(BsColor.inkMuted)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

private struct ProgressRing: View {
    let progress: Int
    let accent: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(BsColor.inkFaint.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 100)) / 100)
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(progress)%")
                .font(Font.custom("Outfit-Bold", size: 9, relativeTo: .caption2))
                .foregroundStyle(BsColor.ink)
        }
        .frame(width: size, height: size)
    }
}

// ════════════════════════════════════════════════════════
// MARK: - 5. Recent Activity Section
// Mirror of Web `activity-projects.tsx` RecentActivityFeed.
// Phase 15 → BsWidgetCard envelope; no CTA.
// ════════════════════════════════════════════════════════

private struct RecentActivitySection: View {
    let activity: [DashboardWidgetsViewModel.ActivityEntry]

    var body: some View {
        BsWidgetCard(
            label: "最近动态",
            accessory: {
                if activity.isEmpty {
                    AnyView(EmptyView())
                } else {
                    AnyView(BsBadge("\(activity.count) 条", tone: .azure, size: .small))
                }
            }
        ) {
            if activity.isEmpty {
                EmptyStateCard(iconName: "clock", title: "暂无近期动态", hint: "团队成员开始行动后将在此显示")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(activity.enumerated()), id: \.element.id) { index, entry in
                        VStack(spacing: 0) {
                            ActivityRow(entry: entry)
                            if index < activity.count - 1 {
                                Divider()
                                    .background(BsColor.borderSubtle)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ActivityRow: View {
    let entry: DashboardWidgetsViewModel.ActivityEntry

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f
    }()

    private static let fallbackFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    /// 近 24h 用相对时间（"3 分钟前"），更久用绝对日期避免"5 天前"这种模糊描述。
    private func formatTime(_ d: Date) -> String {
        let diff = abs(d.timeIntervalSinceNow)
        if diff < 60 * 60 * 24 {
            return Self.relativeFormatter.localizedString(for: d, relativeTo: Date())
        }
        return Self.fallbackFormatter.string(from: d)
    }

    var body: some View {
        HStack(alignment: .top, spacing: BsSpacing.sm + 2) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.userName)
                        .font(BsTypography.caption)
                        .foregroundStyle(BsColor.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if let d = entry.createdAt {
                        Text(formatTime(d))
                            .font(BsTypography.meta)
                            .foregroundStyle(BsColor.inkMuted)
                            .monospacedDigit()
                    }
                }
                if let label = ActivityActionLabels.describe(entry.action) {
                    Text(label)
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, BsSpacing.sm)
    }
}

// ════════════════════════════════════════════════════════
// MARK: - 6. Approval Summary Card (admin+)
// Mirror of Web `role-dashboard-cards.tsx` ApprovalSummaryCard.
// Phase 15 → BsWidgetCard envelope with hero number + CTA link.
// Rendered side-by-side with RiskOverviewCard in an HStack —
// BsWidgetCard's maxWidth: .infinity flexes to half-width.
// ════════════════════════════════════════════════════════

private struct ApprovalSummaryCard: View {
    let pending: Int

    var body: some View {
        if pending == 0 {
            // Phase 24 collapse: skip the 120pt-tall "0 · 待我处理" hero
            // and render a compact one-liner so cleared inboxes feel
            // like an accomplishment rather than a dead cell.
            BsWidgetCard(label: "待审批") {
                HStack(spacing: BsSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BsColor.success)
                    Text("审批已全部处理")
                        .font(BsTypography.bodyMedium)
                        .foregroundStyle(BsColor.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            BsWidgetCard(
                label: "待审批",
                hero: .number("\(pending)", sublabel: "待我处理"),
                cta: .link("查看") {
                    AnyView(ActionItemHelper.destination(for: .approval))
                }
            ) {
                EmptyView()
            }
        }
    }
}

// ════════════════════════════════════════════════════════
// MARK: - 7. Risk Overview Card (admin+)
// Mirror of Web `role-dashboard-cards.tsx` RiskOverviewCard.
// Phase 15 → BsWidgetCard envelope with 2x2 BsStatTile grid + footer hint.
// ════════════════════════════════════════════════════════

private struct RiskOverviewCard: View {
    let risk: DashboardWidgetsViewModel.RiskOverview

    // Phase 24 collapse: four zeros across 活跃/高优/阻塞/逾期 shouldn't
    // render as a 2×2 grid of "0"s — that looks like a degraded status
    // card. Instead, swap to a reassuring single-line footer.
    private var isEmpty: Bool {
        risk.activeRisks + risk.highSeverityRisks + risk.blockedTasks + risk.overdueTasks == 0
    }

    var body: some View {
        BsWidgetCard(
            label: "风险概览"
        ) {
            if isEmpty {
                HStack(spacing: BsSpacing.sm) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(BsColor.success)
                    Text("暂无风险事项，保持观察")
                        .font(BsTypography.bodySmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: BsSpacing.sm) {
                    // 4 stat tiles in a 2x2 grid — HStack of 2 BsStatTileRows
                    // since BsStatTileRow already equal-widths horizontally.
                    BsStatTileRow([
                        .init(value: "\(risk.activeRisks)",       label: "活跃风险", tone: .warning),
                        .init(value: "\(risk.highSeverityRisks)", label: "高优风险", tone: .danger),
                    ])
                    BsStatTileRow([
                        .init(value: "\(risk.blockedTasks)", label: "阻塞任务", tone: .danger),
                        .init(value: "\(risk.overdueTasks)", label: "逾期任务", tone: .warning),
                    ])

                    HStack(spacing: BsSpacing.xs) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(.caption2))
                            .foregroundStyle(BsColor.success)
                        Text(risk.activeRisks > 0 ? "优先处理高优风险和阻塞任务。" : "当前没有活跃风险，保持观察。")
                            .font(BsTypography.meta)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                    .padding(.top, BsSpacing.xs)
                }
            }
        }
    }
}

// ════════════════════════════════════════════════════════
// MARK: - 8. Team Monitor Card (admin+)
// Mirror of Web `team-panels.tsx` TeamMonitorCard. Web stacks two
// halves side-by-side in a 2-col grid (团队概览 + 待处理事项); iOS
// stacks vertically because the card is full-width on a phone.
// Alert list is merged from 3 Supabase queries (pending leaves
// aggregate + overdue task rows + blocked task rows) in
// `DashboardWidgetsViewModel.loadTeamTodoAlerts` — see that file for
// the parity notes with Web `dashboard-workbench.ts:217-316`.
// Visibility gate: this view is only constructed by
// AdminDashboardBody / SuperadminDashboardBody in DashboardView.swift,
// so the admin+ gate is structural, not behavioural.
// Phase 15 → BsWidgetCard envelope with "管理员+" badge accessory + CTA.
// ════════════════════════════════════════════════════════

private struct TeamMonitorCard: View {
    let stats: DashboardWidgetsViewModel.TeamStats
    let alerts: [DashboardWidgetsViewModel.TeamTodoAlert]

    var body: some View {
        BsWidgetCard(
            label: "团队监控",
            cta: .link("全部告警") {
                AnyView(ActionItemHelper.destination(for: .team))
            },
            accessory: {
                AnyView(BsBadge("管理员+", tone: .azure, size: .small))
            }
        ) {
            VStack(alignment: .leading, spacing: BsSpacing.md + 2) {
                let items: [(label: String, value: String, icon: String, color: Color)] = [
                    ("团队成员", "\(stats.members)", "person.2", BsColor.brandAzure),
                    ("待审批请假", "\(stats.pendingLeaves)", "doc.text", stats.pendingLeaves > 0 ? BsColor.warning : BsColor.inkMuted),
                    ("逾期任务", "\(stats.overdueTasks)", "exclamationmark.triangle", stats.overdueTasks > 0 ? BsColor.danger : BsColor.success),
                    ("今日日报率", "\(stats.dailyLogRate)%", "chart.line.uptrend.xyaxis", BsColor.brandMint),
                ]

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BsSpacing.sm) {
                    ForEach(0..<items.count, id: \.self) { idx in
                        TeamStatTile(
                            label: items[idx].label,
                            value: items[idx].value,
                            icon: items[idx].icon,
                            color: items[idx].color
                        )
                    }
                }

                teamTodoAlertsSection
            }
        }
    }

    // Max rows shown in the scroll column before scroll kicks in.
    // Web uses `max-h-56` (≈ 6 rows); iOS caps at 8 to match the
    // larger font size and still fit on an iPhone 13 mini.
    private static let alertScrollCap: Int = 8

    @ViewBuilder
    private var teamTodoAlertsSection: some View {
        VStack(alignment: .leading, spacing: BsSpacing.sm) {
            HStack(spacing: BsSpacing.xs + 2) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(BsColor.warning)
                Text("待处理事项")
                    .font(BsTypography.label)
                    .foregroundStyle(BsColor.inkMuted)
                    .textCase(.uppercase)
                if !alerts.isEmpty {
                    Text("\(alerts.count)")
                        .font(BsTypography.meta)
                        .foregroundStyle(BsColor.warning)
                        .padding(.horizontal, BsSpacing.xs + 2)
                        .padding(.vertical, 1)
                        .background(BsColor.warning.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
            }

            if alerts.isEmpty {
                Text("无待处理事项")
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkFaint)
                    .padding(.vertical, BsSpacing.xs)
            } else {
                // 8-row cap + ~4-row viewport before scrolling kicks
                // in. LazyVStack so rows below the fold stay cheap.
                let visible = Array(alerts.prefix(Self.alertScrollCap))
                let rowHeight: CGFloat = 44
                let spacing: CGFloat = 6
                // When there are <= 4 rows the list fits without
                // scrolling — collapse to content height so the card
                // doesn't reserve empty space.
                let rowsInViewport = min(visible.count, 4)
                let viewport: CGFloat = CGFloat(rowsInViewport) * rowHeight
                    + CGFloat(max(0, rowsInViewport - 1)) * spacing
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: spacing) {
                        ForEach(visible) { alert in
                            TeamTodoAlertRow(alert: alert)
                        }
                    }
                }
                .frame(maxHeight: viewport)
            }
        }
    }
}

private struct TeamTodoAlertRow: View {
    let alert: DashboardWidgetsViewModel.TeamTodoAlert

    private var severityColor: Color {
        switch alert.severity {
        case .high:   return BsColor.danger
        case .medium: return BsColor.warning
        case .low:    return BsColor.brandAzure
        }
    }

    private var iconName: String {
        switch alert.type {
        case .overdueTask:      return "exclamationmark.triangle"
        case .pendingApproval:  return "doc.text"
        case .blockedTask:      return "pause.circle"
        }
    }

    private var destination: AppModule {
        switch alert.type {
        case .overdueTask, .blockedTask: return .tasks
        case .pendingApproval:           return .approval
        }
    }

    var body: some View {
        NavigationLink(destination: ActionItemHelper.destination(for: destination)) {
            HStack(spacing: BsSpacing.sm + 2) {
                Rectangle()
                    .fill(severityColor)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))

                Image(systemName: iconName)
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(severityColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.ink)
                        .lineLimit(1)
                    Text(alert.detail)
                        .font(BsTypography.meta)
                        .foregroundStyle(BsColor.inkMuted)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(BsColor.inkFaint)
            }
            .padding(.horizontal, BsSpacing.sm + 2)
            .padding(.vertical, BsSpacing.xs + 2)
            .background(
                RoundedRectangle(cornerRadius: BsRadius.md - 2, style: .continuous)
                    .fill(severityColor.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TeamStatTile: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: BsSpacing.sm + 2) {
            ZStack {
                RoundedRectangle(cornerRadius: BsRadius.md - 2, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(BsTypography.statSmall)
                    .foregroundStyle(BsColor.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(label)
                    .font(BsTypography.meta)
                    .foregroundStyle(BsColor.inkMuted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(BsSpacing.sm + 2)
        .background(BsColor.surfacePrimary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
    }
}

// ════════════════════════════════════════════════════════
// MARK: - 9. Executive KPIs Card (superadmin only)
// Mirror of Web `role-dashboard-cards.tsx` ExecutiveKPIsCard.
// Phase 15 → BsWidgetCard envelope with "高管" badge accessory +
// 3-tile BsStatTileRow (azure/mint/brandAzure tones per spec).
// ════════════════════════════════════════════════════════

private struct ExecutiveKPIsCard: View {
    let kpis: DashboardWidgetsViewModel.ExecutiveKpis

    // Phase 24 collapse: if all 3 KPI counters are zero, drop the
    // "0 0 0" tile row and surface a single inkMuted line. dailyLogRate
    // is a % coverage (not a count) — still hidden when all main counters
    // are 0 because a 0%/null coverage on an empty org is non-signal.
    private var isEmpty: Bool {
        kpis.pendingApprovals + kpis.teamMembers + kpis.tasksDone7d == 0
    }

    var body: some View {
        BsWidgetCard(
            label: "经营总览",
            accessory: {
                AnyView(BsBadge("高管", tone: .coral, size: .small))
            }
        ) {
            if isEmpty {
                HStack(spacing: BsSpacing.xs) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(.footnote))
                        .foregroundStyle(BsColor.inkFaint)
                    Text("今日暂无经营数据 · 下拉可刷新")
                        .font(BsTypography.bodySmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: BsSpacing.sm) {
                    BsStatTileRow([
                        .init(value: "\(kpis.pendingApprovals)", label: "待处理审批", tone: .azure),
                        .init(value: "\(kpis.teamMembers)",      label: "团队规模",   tone: .mint),
                        .init(value: "\(kpis.tasksDone7d)",      label: "近 7 日产出", tone: .azure),
                    ])

                    // Phase 24: ratio → visual. The footer "日报覆盖 X%" now
                    // has a 6pt inline bar beneath it so the % reads as
                    // progress instead of loose text.
                    VStack(alignment: .leading, spacing: BsSpacing.xs) {
                        Text("日报覆盖 \(kpis.dailyLogRate)%")
                            .font(BsTypography.meta)
                            .foregroundStyle(BsColor.inkMuted)
                        BsProgressBar(
                            progress: Double(kpis.dailyLogRate) / 100.0,
                            tint: BsColor.brandAzure
                        )
                    }
                    .padding(.top, BsSpacing.xs)
                }
            }
        }
    }
}
