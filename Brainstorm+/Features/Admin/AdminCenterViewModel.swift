import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 4.1 — 管理后台 (Admin Center) 顶层 ViewModel
// Parity target: Web `src/app/dashboard/admin/page.tsx` (AdminPage)
// + nested routes `admin/holidays`, `admin/evaluations`, `admin/config`.
// 负责：
//   1) 拉取顶层概览计数（用户、今日活跃、任务、项目）
//   2) 解析当前 viewer 的 primaryRole + effectiveCapabilities，驱动
//      子模块入口显隐（HR / 考勤 / 调休 / AI / 审计 / 公休）
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class AdminCenterViewModel: ObservableObject {
    public struct Stats {
        public var totalUsers: Int = 0
        public var activeToday: Int = 0
        public var totalTasks: Int = 0
        public var totalProjects: Int = 0
    }

    @Published public private(set) var stats: Stats = Stats()
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?

    @Published public private(set) var viewerPrimaryRole: PrimaryRole = .employee
    @Published public private(set) var viewerCapabilities: [Capability] = []

    private let client: SupabaseClient

    public init(client: SupabaseClient = supabase) {
        self.client = client
    }

    // ── Capability gates (mirror Web admin/page.tsx L103-112) ──
    public var canEnterAdmin: Bool {
        viewerPrimaryRole == .admin || viewerPrimaryRole == .superadmin
    }
    public var canAssignPrivileges: Bool { viewerPrimaryRole == .superadmin }
    public var canManagePeople: Bool {
        viewerCapabilities.contains(.hr_ops) || canAssignPrivileges
    }
    public var canViewAudit: Bool { canEnterAdmin }
    public var canManageOrg: Bool { canEnterAdmin }
    public var canManageHolidays: Bool {
        viewerCapabilities.contains(.holiday_admin) || canAssignPrivileges
    }
    public var canManageLeaveQuota: Bool {
        viewerCapabilities.contains(.leave_quota_admin) || canAssignPrivileges
    }
    public var canManageAttendanceRules: Bool {
        viewerCapabilities.contains(.attendance_admin) || canAssignPrivileges
    }
    /// AI 设置入口：与 Web `ai-settings-section.tsx` 对齐 — 仅超管可见配置面板；
    /// 持有 ai_provider_admin / apikey_admin 的 admin 也放行。
    public var canManageAISettings: Bool {
        canAssignPrivileges
            || viewerCapabilities.contains(.ai_provider_admin)
            || viewerCapabilities.contains(.apikey_admin)
    }
    public var canManageEvaluations: Bool {
        // iOS `.ai_evaluation_access` rawValue == DB rename 前的 token；
        // superadmin 默认集合已含此 cap，admin + HR 包亦已授予。
        viewerCapabilities.contains(.ai_evaluation_access) || canAssignPrivileges
    }

    public func bind(sessionProfile: Profile?) {
        guard let profile = sessionProfile else {
            viewerPrimaryRole = .employee
            viewerCapabilities = []
            return
        }
        viewerPrimaryRole = RBACManager.shared.migrateLegacyRole(profile.role).primaryRole
        viewerCapabilities = RBACManager.shared.getEffectiveCapabilities(for: profile)
    }

    public func loadStats() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let usersCountTask = headCount(table: "profiles")
            async let tasksCountTask = headCount(table: "tasks")
            async let projectsCountTask = headCount(table: "projects")
            async let activeCountTask = activeTodayCount()

            let (users, tasks, projects, active) = try await (
                usersCountTask, tasksCountTask, projectsCountTask, activeCountTask
            )

            stats = Stats(
                totalUsers: users,
                activeToday: active,
                totalTasks: tasks,
                totalProjects: projects
            )
        } catch {
            errorMessage = "加载概览失败：\(ErrorLocalizer.localize(error))"
        }
    }

    private func headCount(table: String) async throws -> Int {
        let res = try await client
            .from(table)
            .select("*", head: true, count: .exact)
            .execute()
        return res.count ?? 0
    }

    private func activeTodayCount() async throws -> Int {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: Date())
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let startStr = iso.string(from: start)
        let res = try await client
            .from("attendance")
            .select("*", head: true, count: .exact)
            .gte("clock_in", value: startStr)
            .execute()
        return res.count ?? 0
    }
}
