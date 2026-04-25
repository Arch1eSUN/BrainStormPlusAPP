import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════
// BrainStorm+ iOS — Dashboard Widget Data (Batch D.1)
//
// 1:1 port of Web `BrainStorm+-Web/src/lib/actions/dashboard-workbench.ts`
// `fetchWorkbenchData()`. Web does it as one aggregated Server Action that
// returns every slice (myTasks / myOkr / activeProjects / recentActivity /
// monthlySnapshot / teamStats / executiveKpis / riskOverview) in a single
// call. iOS does not have Server Actions, so we run the same queries
// directly from this ViewModel — one `fetchAll()` that fans out with
// `async let` / `TaskGroup` so each section lands as soon as its query
// returns. Per-section state keeps the UI partial-load-tolerant (a failing
// objectives query doesn't blank the whole dashboard).
//
// Scope: admin/superadmin-only sections (teamStats / exec KPIs / risk
// overview) only hit the DB when `canViewManagementData` is true — matches
// Web's `hasCapability(hr_ops) || superadmin` gate.
// ══════════════════════════════════════════════════

@MainActor
public final class DashboardWidgetsViewModel: ObservableObject {

    // ── Per-widget state ────────────────────────────────────────
    @Published public private(set) var myTasks: MyTasksSummary = .empty
    @Published public private(set) var monthlySnapshot: MonthlySnapshot = .empty
    @Published public private(set) var activeProjects: [ProjectSummary] = []
    @Published public private(set) var myOkr: [ObjectiveSummary] = []
    @Published public private(set) var recentActivity: [ActivityEntry] = []
    @Published public private(set) var pendingApprovals: Int = 0
    @Published public private(set) var riskOverview: RiskOverview = .empty
    @Published public private(set) var teamStats: TeamStats = .empty
    @Published public private(set) var executiveKpis: ExecutiveKpis = .empty
    @Published public private(set) var teamTodoAlerts: [TeamTodoAlert] = []

    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?

    private let client: SupabaseClient

    public init(client: SupabaseClient = supabase) {
        self.client = client
    }

    // ── Public models ───────────────────────────────────────────

    public struct MyTasksSummary: Equatable {
        public let todo: Int
        public let inProgress: Int
        public let review: Int
        public let done: Int
        public let overdue: Int
        public var activeCount: Int { todo + inProgress }
        public static let empty = MyTasksSummary(todo: 0, inProgress: 0, review: 0, done: 0, overdue: 0)
    }

    public struct MonthlySnapshot: Equatable {
        public let attendanceDays: Int
        public let businessTripDays: Int
        public let leaveDays: Int
        public let compTimeDays: Int
        public let absentDays: Int
        public let workDaysInMonth: Int
        public let flexibleHours: Bool
        public static let empty = MonthlySnapshot(
            attendanceDays: 0, businessTripDays: 0, leaveDays: 0,
            compTimeDays: 0, absentDays: 0, workDaysInMonth: 0, flexibleHours: false
        )
    }

    public struct ProjectSummary: Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public let status: String
        public let progress: Int
        public let taskTotal: Int
        public let taskDone: Int
        public let targetDate: String?
    }

    public struct ObjectiveSummary: Identifiable, Equatable {
        public let id: UUID
        public let title: String
        public let progress: Int
        public let status: String
        public let krCount: Int
        public let period: String
    }

    public struct ActivityEntry: Identifiable, Equatable {
        public let id: String
        public let action: String
        public let userName: String
        public let createdAt: Date?
    }

    public struct RiskOverview: Equatable {
        public let activeRisks: Int
        public let highSeverityRisks: Int
        public let blockedTasks: Int
        public let overdueTasks: Int
        public static let empty = RiskOverview(
            activeRisks: 0, highSeverityRisks: 0, blockedTasks: 0, overdueTasks: 0
        )
    }

    public struct TeamStats: Equatable {
        public let members: Int
        public let tasksDone7d: Int
        public let pendingLeaves: Int
        public let overdueTasks: Int
        public let dailyLogRate: Int
        public static let empty = TeamStats(
            members: 0, tasksDone7d: 0, pendingLeaves: 0, overdueTasks: 0, dailyLogRate: 0
        )
    }

    public struct ExecutiveKpis: Equatable {
        public let pendingApprovals: Int
        public let teamMembers: Int
        public let tasksDone7d: Int
        public let dailyLogRate: Int
        public static let empty = ExecutiveKpis(
            pendingApprovals: 0, teamMembers: 0, tasksDone7d: 0, dailyLogRate: 0
        )
    }

    /// Team-level to-do for the admin+ TeamMonitorCard scroll list.
    /// 1:1 with Web `WorkbenchTodoItem` in
    /// `src/lib/actions/dashboard-workbench.ts:72-79`. Web also emits a
    /// `href` for <Link>; on iOS we collapse to the module enum and let
    /// the view build a NavigationLink destination.
    public struct TeamTodoAlert: Identifiable, Equatable {
        public let id: String
        public let type: AlertType
        public let title: String
        public let detail: String
        public let severity: Severity

        public enum AlertType: String, Equatable {
            case overdueTask = "overdue_task"
            case pendingApproval = "approval"
            case blockedTask = "blocked_task"
        }

        public enum Severity: String, Equatable {
            case low, medium, high
        }
    }

    // ── Entrypoint ──────────────────────────────────────────────

    /// Fan-out of every slice `fetchWorkbenchData` returns on Web. `isManager`
    /// gates the admin-tier queries — keeps RLS-blocked calls off the wire
    /// for employees.
    public func fetchAll(isManager: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let userId: UUID
        do {
            userId = try await client.auth.session.user.id
        } catch {
            errorMessage = "请先登录"
            return
        }

        // Parallel employee-scope queries.
        async let tasks: Void = loadMyTasks(userId: userId)
        async let snapshot: Void = loadMonthlySnapshot(userId: userId)
        async let projects: Void = loadActiveProjects(userId: userId)
        async let okr: Void = loadMyOkr(userId: userId)
        async let activity: Void = loadRecentActivity()

        // Manager-tier queries (only when capability permits).
        async let approvals: Void = isManager ? loadPendingApprovals() : ()
        async let risk: Void = isManager ? loadRiskOverview() : ()
        async let team: Void = isManager ? loadTeamStats() : ()
        async let alerts: Void = isManager ? loadTeamTodoAlerts() : ()

        _ = await (tasks, snapshot, projects, okr, activity, approvals, risk, team, alerts)

        // Exec KPIs reuse the values already fetched above — compose last.
        if isManager {
            self.executiveKpis = ExecutiveKpis(
                pendingApprovals: self.pendingApprovals,
                teamMembers: self.teamStats.members,
                tasksDone7d: self.teamStats.tasksDone7d,
                dailyLogRate: self.teamStats.dailyLogRate
            )
        }
    }

    // ── 1. My Tasks ─────────────────────────────────────────────
    // Web: `supabase.from('tasks').select('status, due_date').eq('assignee_id', user.id)`
    private struct TaskRow: Decodable {
        let status: String
        let due_date: String?
    }

    private func loadMyTasks(userId: UUID) async {
        do {
            let rows: [TaskRow] = try await client
                .from("tasks")
                .select("status, due_date")
                .eq("assignee_id", value: userId.uuidString)
                .execute()
                .value
            let today = DashboardWidgetsViewModel.isoDate(Date())
            self.myTasks = MyTasksSummary(
                todo: rows.filter { $0.status == "todo" }.count,
                inProgress: rows.filter { $0.status == "in_progress" }.count,
                review: rows.filter { $0.status == "review" }.count,
                done: rows.filter { $0.status == "done" }.count,
                overdue: rows.filter {
                    guard let due = $0.due_date else { return false }
                    return due < today && $0.status != "done"
                }.count
            )
        } catch {
            // Soft-fail — leave myTasks at .empty, log once.
            logFetchError("my-tasks", error)
        }
    }

    // ── 2. Monthly Snapshot ─────────────────────────────────────
    // Web: `daily_work_state` filtered by month window, bucketed by `state`.
    private struct WorkStateRow: Decodable {
        let state: String
        let flexible_hours: Bool?
    }

    private func loadMonthlySnapshot(userId: UUID) async {
        // 时区口径（Phase 25.c 复核）：
        //   • `Calendar.current` + `isoFormatter.timeZone = .current` 双用设备本地
        //     时区，保证北京 00:00~08:00 期间的"今天"不会被算成 UTC 前一天。
        //   • Web dashboard-workbench.ts 用 `new Date().toISOString().split('T')[0]`
        //     —— 实际跟 UTC 对齐，跨时区时 Web 与 iOS 结果可能差 1 天；以 iOS
        //     本地口径为准（用户身处 CNST）。
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) else {
            return
        }
        let monthStartIso = DashboardWidgetsViewModel.isoDate(monthStart)
        let todayIso = DashboardWidgetsViewModel.isoDate(now)

        do {
            let rows: [WorkStateRow] = try await client
                .from("daily_work_state")
                .select("state, flexible_hours")
                .eq("user_id", value: userId.uuidString)
                .gte("work_date", value: monthStartIso)
                .lte("work_date", value: todayIso)
                .execute()
                .value
            self.monthlySnapshot = MonthlySnapshot(
                attendanceDays: rows.filter { $0.state == "normal" || $0.state == "field_work" }.count,
                businessTripDays: rows.filter { $0.state == "business_trip" }.count,
                leaveDays: rows.filter { $0.state == "personal_leave" }.count,
                compTimeDays: rows.filter { $0.state == "comp_time" }.count,
                absentDays: rows.filter { $0.state == "absent" }.count,
                workDaysInMonth: rows.count,
                flexibleHours: rows.contains { $0.flexible_hours == true }
            )
        } catch {
            logFetchError("monthly-snapshot", error)
        }
    }

    // ── 3. Active Projects ──────────────────────────────────────
    // Web: `projects` where status in (active, planning). iOS narrows via
    // `project_members` scope to match the widget's "projects the user is on".
    private struct ProjectRow: Decodable {
        let id: UUID
        let name: String
        let status: String
        let progress: Int?
        let target_date: String?
        let tasks: [ProjectTaskRow]?

        struct ProjectTaskRow: Decodable {
            let status: String
        }
    }

    private struct ProjectMemberRow: Decodable {
        let projectId: UUID
        enum CodingKeys: String, CodingKey { case projectId = "project_id" }
    }

    private func loadActiveProjects(userId: UUID) async {
        do {
            let memberRows: [ProjectMemberRow] = try await client
                .from("project_members")
                .select("project_id")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            let memberIds = memberRows.map { $0.projectId.uuidString }

            // Membership scope: match Web's "projects the user is on".
            // Empty => no active projects to render.
            guard !memberIds.isEmpty else {
                self.activeProjects = []
                return
            }

            let rows: [ProjectRow] = try await client
                .from("projects")
                .select("id, name, status, progress, target_date, tasks(status)")
                .in("id", values: memberIds)
                .in("status", values: ["active", "planning"])
                .order("updated_at", ascending: false)
                .limit(5)
                .execute()
                .value

            self.activeProjects = rows.map { r in
                let pTasks = r.tasks ?? []
                return ProjectSummary(
                    id: r.id,
                    name: r.name,
                    status: r.status,
                    progress: r.progress ?? 0,
                    taskTotal: pTasks.count,
                    taskDone: pTasks.filter { $0.status == "done" }.count,
                    targetDate: r.target_date
                )
            }
        } catch {
            logFetchError("active-projects", error)
        }
    }

    // ── 4. My OKR ───────────────────────────────────────────────
    // Web: `objectives` + nested `key_results(id)` count. Limit 5.
    private struct ObjectiveRow: Decodable {
        let id: UUID
        let title: String
        let progress: Int?
        let status: String?
        let period: String?
        let key_results: [KeyResultIdRow]?

        struct KeyResultIdRow: Decodable {
            let id: UUID
        }
    }

    private func loadMyOkr(userId: UUID) async {
        do {
            let rows: [ObjectiveRow] = try await client
                .from("objectives")
                .select("id, title, progress, status, period, key_results(id)")
                .eq("owner_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .limit(5)
                .execute()
                .value
            self.myOkr = rows.map { o in
                ObjectiveSummary(
                    id: o.id,
                    title: o.title,
                    progress: o.progress ?? 0,
                    status: o.status ?? "draft",
                    krCount: o.key_results?.count ?? 0,
                    period: o.period ?? "—"
                )
            }
        } catch {
            logFetchError("my-okr", error)
        }
    }

    // ── 5. Recent Activity ──────────────────────────────────────
    // Web: `activity_log` + nested `profiles:user_id(full_name)`. Top 6.
    private struct ActivityRow: Decodable {
        let id: String
        let action: String?
        let created_at: String?
        let profiles: ProfileNameRow?

        struct ProfileNameRow: Decodable {
            let full_name: String?
        }
    }

    private func loadRecentActivity() async {
        do {
            let rows: [ActivityRow] = try await client
                .from("activity_log")
                .select("id, action, created_at, profiles:user_id(full_name)")
                .order("created_at", ascending: false)
                .limit(6)
                .execute()
                .value
            self.recentActivity = rows.map { r in
                ActivityEntry(
                    id: r.id,
                    action: r.action ?? "",
                    userName: r.profiles?.full_name ?? "系统",
                    createdAt: r.created_at.flatMap(DashboardWidgetsViewModel.parseIsoDate)
                )
            }
        } catch {
            logFetchError("recent-activity", error)
        }
    }

    // ── 6. Pending Approvals (Admin+) ───────────────────────────
    // Web: `approval_requests` head count where status='pending'. iOS hits
    // the anon client + RLS — admins see org-wide rows, non-admins wouldn't
    // be on this code path (gated by `isManager`).
    private func loadPendingApprovals() async {
        do {
            let response = try await client
                .from("approval_requests")
                .select("*", head: true, count: .exact)
                .eq("status", value: "pending")
                .execute()
            self.pendingApprovals = response.count ?? 0
        } catch {
            logFetchError("pending-approvals", error)
        }
    }

    // ── 7. Risk Overview (Admin+) ───────────────────────────────
    // Web: `risk_actions` + org-wide tasks snapshot for blocked/overdue.
    private struct RiskActionRow: Decodable {
        let severity: String?
        let status: String?
    }
    private struct AllTaskRow: Decodable {
        let status: String
        let due_date: String?
    }

    private func loadRiskOverview() async {
        let today = DashboardWidgetsViewModel.isoDate(Date())
        do {
            // Sequential — two independent selects, both cheap. Avoids the
            // `async let` generic-inference snag on Supabase `.value`.
            let risks: [RiskActionRow] = try await client
                .from("risk_actions")
                .select("severity, status")
                .in("status", values: ["open", "acknowledged", "in_progress"])
                .execute()
                .value
            let allTasks: [AllTaskRow] = try await client
                .from("tasks")
                .select("status, due_date")
                .execute()
                .value

            let overdue = allTasks.filter { t in
                guard let due = t.due_date else { return false }
                return due < today && t.status != "done"
            }
            let blocked = allTasks.filter { $0.status == "review" }

            self.riskOverview = RiskOverview(
                activeRisks: risks.count,
                highSeverityRisks: risks.filter { $0.severity == "high" }.count,
                blockedTasks: blocked.count,
                overdueTasks: overdue.count
            )
        } catch {
            logFetchError("risk-overview", error)
        }
    }

    // ── 8. Team Stats + Executive KPIs backing (Admin+) ─────────
    // Web: cross-user counts via admin client. iOS uses RLS — head counts
    // on `profiles`, `approval_requests`, `tasks`, `daily_logs`.
    private struct DailyLogUserRow: Decodable {
        let user_id: UUID
    }

    private struct TaskDoneRow: Decodable {
        let status: String
        let updated_at: String?
        let due_date: String?
    }

    private func loadTeamStats() async {
        let today = DashboardWidgetsViewModel.isoDate(Date())
        let sevenDaysAgo = DashboardWidgetsViewModel.isoDate(
            Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        )
        do {
            // Head-only counts
            let membersCountResp = try await client
                .from("profiles")
                .select("*", head: true, count: .exact)
                .execute()
            let members = membersCountResp.count ?? 0

            let pendingLeavesResp = try await client
                .from("approval_requests")
                .select("*", head: true, count: .exact)
                .eq("request_type", value: "leave")
                .eq("status", value: "pending")
                .execute()
            let pendingLeaves = pendingLeavesResp.count ?? 0

            let allTasks: [TaskDoneRow] = try await client
                .from("tasks")
                .select("status, updated_at, due_date")
                .execute()
                .value

            let dailyLogs: [DailyLogUserRow] = try await client
                .from("daily_logs")
                .select("user_id")
                .eq("date", value: today)
                .execute()
                .value

            let overdueCount = allTasks.filter { t in
                guard let due = t.due_date else { return false }
                return due < today && t.status != "done"
            }.count
            let tasksDone7d = allTasks.filter { t in
                guard let u = t.updated_at else { return false }
                return t.status == "done" && u >= sevenDaysAgo
            }.count
            let uniqueLogUsers = Set(dailyLogs.map { $0.user_id }).count
            let rate = members > 0 ? Int((Double(uniqueLogUsers) / Double(members) * 100).rounded()) : 0

            self.teamStats = TeamStats(
                members: members,
                tasksDone7d: tasksDone7d,
                pendingLeaves: pendingLeaves,
                overdueTasks: overdueCount,
                dailyLogRate: rate
            )
        } catch {
            logFetchError("team-stats", error)
        }
    }

    // ── 9. Team Todo Alerts (Admin+) ────────────────────────────
    // Web parity: `dashboard-workbench.ts:217-316`. Three sources are
    // merged into one severity-sorted list (cap 6 on Web; iOS caps the
    // underlying queries + renders max 8 rows in the scroll list).
    //
    //   1. Pending-leave aggregated alert (single row when count > 0).
    //   2. Overdue tasks — per-task rows, limit 3, severity scales
    //      with `daysPast` (>5 → high).
    //   3. Blocked tasks (status='review') — per-task rows, limit 2,
    //      severity always medium.
    //
    // Daily-log "missing" reporters are intentionally SKIPPED per the
    // task brief — the cross-join against `profiles` to find who
    // DIDN'T log today is a second admin-client read that complicates
    // the single-shot fan-out. Left as a follow-up if signal demands.
    private struct OverdueTaskRow: Decodable {
        let id: UUID
        let title: String?
        let status: String
        let due_date: String?
    }

    private func loadTeamTodoAlerts() async {
        let today = DashboardWidgetsViewModel.isoDate(Date())
        var alerts: [TeamTodoAlert] = []

        // ── 1) Pending leaves (aggregated)
        do {
            let resp = try await client
                .from("approval_requests")
                .select("*", head: true, count: .exact)
                .eq("request_type", value: "leave")
                .eq("status", value: "pending")
                .execute()
            let count = resp.count ?? 0
            if count > 0 {
                alerts.append(
                    TeamTodoAlert(
                        id: "pending-leaves",
                        type: .pendingApproval,
                        title: "\(count) 个待审批请假",
                        detail: "有员工的请假申请等待处理",
                        severity: count > 3 ? .high : .medium
                    )
                )
            }
        } catch {
            logFetchError("team-todo-alerts:leaves", error)
        }

        // ── 2) Overdue tasks (top 3 by age)
        do {
            let rows: [OverdueTaskRow] = try await client
                .from("tasks")
                .select("id, title, status, due_date")
                .lt("due_date", value: today)
                .neq("status", value: "done")
                .order("due_date", ascending: true)
                .limit(3)
                .execute()
                .value

            let overdueFmt = DashboardWidgetsViewModel.isoFormatter
            let todayDate = Date()

            for r in rows {
                let daysPast: Int = {
                    guard let raw = r.due_date, let due = overdueFmt.date(from: raw) else { return 1 }
                    return max(1, Int(ceil(todayDate.timeIntervalSince(due) / 86_400)))
                }()
                alerts.append(
                    TeamTodoAlert(
                        id: "overdue-\(r.id.uuidString)",
                        type: .overdueTask,
                        title: (r.title?.isEmpty == false) ? r.title! : "未命名任务",
                        detail: "已逾期 \(daysPast) 天",
                        severity: daysPast > 5 ? .high : .medium
                    )
                )
            }
        } catch {
            logFetchError("team-todo-alerts:overdue", error)
        }

        // ── 3) Blocked tasks (status = review, top 2)
        do {
            let rows: [OverdueTaskRow] = try await client
                .from("tasks")
                .select("id, title, status, due_date")
                .eq("status", value: "review")
                .order("updated_at", ascending: false)
                .limit(2)
                .execute()
                .value
            for r in rows {
                alerts.append(
                    TeamTodoAlert(
                        id: "blocked-\(r.id.uuidString)",
                        type: .blockedTask,
                        title: (r.title?.isEmpty == false) ? r.title! : "未命名任务",
                        detail: "需要审核",
                        severity: .medium
                    )
                )
            }
        } catch {
            logFetchError("team-todo-alerts:blocked", error)
        }

        // Severity sort: high → medium → low. Web
        // dashboard-workbench.ts:315 uses the same order.
        let sevOrder: [TeamTodoAlert.Severity: Int] = [.high: 3, .medium: 2, .low: 1]
        alerts.sort {
            (sevOrder[$0.severity] ?? 0) > (sevOrder[$1.severity] ?? 0)
        }

        self.teamTodoAlerts = alerts
    }

    // ── Helpers ─────────────────────────────────────────────────

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func isoDate(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601NoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func parseIsoDate(_ raw: String) -> Date? {
        if let d = iso8601.date(from: raw) { return d }
        if let d = iso8601NoFraction.date(from: raw) { return d }
        return nil
    }

    private func logFetchError(_ slot: String, _ error: Error) {
        // Non-fatal — each widget keeps its .empty state and renders the
        // "暂无数据" branch. Errors bubble to console for triage.
        #if DEBUG
        print("[DashboardWidgets] \(slot) fetch failed:", error.localizedDescription)
        #endif
    }
}

// MARK: - Action label mapping
// Mirror of Web `activity-projects.tsx:123-141` ACTION_LABELS dict.

public enum ActivityActionLabels {
    public static let table: [String: String] = [
        "approval_approve": "批准了一项审批申请",
        "approval_reject": "驳回了一项审批申请",
        "approval_submitted": "提交了一项审批申请",
        "clock_in": "完成上班打卡",
        "clock_out": "完成下班打卡",
        "config_change": "修改了系统配置",
        "config_update": "更新了系统配置",
        "password_changed": "修改了登录密码",
        "payroll_batch_compute": "执行了工资批量核算",
        "payroll_clear": "清理了工资数据",
        "payroll_full_export": "导出了完整工资表",
        "payroll_update": "更新了工资记录",
        "role_change": "调整了成员角色",
        "task_created": "创建了一项任务",
        "task_updated": "更新了一项任务",
        "user_create": "创建了一位成员",
        "user_deactivate": "停用了一位成员",
    ]

    public static func describe(_ action: String) -> String? {
        table[action]
    }
}
