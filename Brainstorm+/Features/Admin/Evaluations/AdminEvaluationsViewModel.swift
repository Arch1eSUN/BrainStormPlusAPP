import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 4.6a — AI 月度评估管理 VM
// Parity target: Web `src/lib/actions/user-evaluations.ts listMonthlyMatrix`
//
// iOS 不能直接调用 Web 的 server action（runEvaluation / runEvaluationBatch）
// —— 它们依赖服务器端的 askAI orchestrator + CRON_SECRET + api_keys 解密。
// 批量触发已通过 POST /api/mobile/admin/evaluations/trigger 接入（见
// triggerBatch 方法 + AdminEvaluationBatchSheet）；iOS 负责拉取矩阵 + 收集
// 员工范围 + 调路由入队到 background_jobs，由 Web 执行器消费。
//
// 权限（与 Web 对齐）：
//   - superadmin：可见所有非超管 + 超管行
//   - ai_evaluation_access（= DB 里 ai_evaluation_ops）：可见所有非超管行
//   - 其他：VM 根本不会被 View 用
// 矩阵候选集：active（status is null or 'active'）且 exclude superadmin/super_admin；
//   superadmin viewer 则再额外拉 superadmin 行拼在前面（不排除自己）。
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class AdminEvaluationsViewModel: ObservableObject {
    @Published public private(set) var rows: [MonthlyMatrixRow] = []
    @Published public var month: String = AdminEvaluationsViewModel.currentMonthCST()
    @Published public var departmentFilter: String = ""
    @Published public var statusFilter: MonthlyEvaluationStatus = .all
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?

    @Published public private(set) var viewerPrimaryRole: PrimaryRole = .employee
    @Published public private(set) var viewerCapabilities: [Capability] = []

    private let client: SupabaseClient

    public init(client: SupabaseClient = supabase) {
        self.client = client
    }

    // ── Gates ────────────────────────────────────────────────────
    public var canAccess: Bool {
        viewerPrimaryRole == .superadmin ||
            viewerCapabilities.contains(.ai_evaluation_access)
    }

    public var canEvaluateSuperadmins: Bool {
        viewerPrimaryRole == .superadmin
    }

    public var departments: [String] {
        Array(Set(rows.compactMap { $0.department })).sorted()
    }

    public var filteredRows: [MonthlyMatrixRow] {
        rows.filter { r in
            if !departmentFilter.isEmpty && r.department != departmentFilter { return false }
            switch statusFilter {
            case .all: return true
            case .pending: return r.evaluation == nil
            case .evaluated:
                return r.evaluation != nil && (r.evaluation?.requiresManualReview == false)
            case .reviewRequired:
                return r.evaluation?.requiresManualReview == true
            }
        }
    }

    public var counts: (total: Int, pending: Int, evaluated: Int, needsReview: Int) {
        let total = rows.count
        var p = 0, e = 0, r = 0
        for row in rows {
            if let ev = row.evaluation {
                if ev.requiresManualReview { r += 1 } else { e += 1 }
            } else {
                p += 1
            }
        }
        return (total, p, e, r)
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

    // ── Data load ───────────────────────────────────────────────
    public func reload() async {
        guard canAccess else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // 1) profiles：active，排除超管（超管 viewer 下再单独拉）
            struct ProfileRow: Decodable {
                let id: UUID
                let full_name: String?
                let department: String?
                let role: String?
                let status: String?
            }

            var allProfiles: [ProfileRow] = []

            // 非超管行（所有 viewer 都能看到）
            let nonSuperRoles = ["employee", "admin", "manager", "team_lead", "hr", "finance", "contractor", "intern"]
            let nonSuper: [ProfileRow] = try await client
                .from("profiles")
                .select("id, full_name, department, role, status")
                .in("role", values: nonSuperRoles)
                .or("status.is.null,status.eq.active")
                .order("department", ascending: true)
                .order("full_name", ascending: true)
                .execute()
                .value
            allProfiles.append(contentsOf: nonSuper)

            // superadmin 自己可以评所有人（含其他超管）
            if canEvaluateSuperadmins {
                let superRoles = ["superadmin", "super_admin", "chairperson"]
                let supers: [ProfileRow] = try await client
                    .from("profiles")
                    .select("id, full_name, department, role, status")
                    .in("role", values: superRoles)
                    .or("status.is.null,status.eq.active")
                    .order("full_name", ascending: true)
                    .execute()
                    .value
                allProfiles.insert(contentsOf: supers, at: 0)
            }

            if allProfiles.isEmpty {
                rows = []
                return
            }

            // 2) evaluations for this month
            let userIds = allProfiles.map { $0.id.uuidString }
            let evals: [MonthlyEvaluation] = try await client
                .from("user_monthly_evaluations")
                .select("id, user_id, month, overall_score, score_attendance, score_delivery, score_collaboration, score_reporting, score_growth, narrative, risk_flags, requires_manual_review, triggered_by, model_used, created_at, updated_at")
                .eq("month", value: month)
                .in("user_id", values: userIds)
                .execute()
                .value

            var byUser: [UUID: MonthlyEvaluation] = [:]
            for ev in evals { byUser[ev.userId] = ev }

            rows = allProfiles.map { p in
                MonthlyMatrixRow(
                    userId: p.id,
                    fullName: p.full_name ?? "",
                    department: p.department,
                    primaryRole: Self.primaryRoleOf(p.role ?? "employee"),
                    evaluation: byUser[p.id]
                )
            }
        } catch {
            errorMessage = "加载评估矩阵失败：\(ErrorLocalizer.localize(error))"
        }
    }

    public func changeMonth(_ next: String) async {
        month = next
        await reload()
    }

    // ── Batch trigger bridge ────────────────────────────────────
    // 已接入 POST /api/mobile/admin/evaluations/trigger（原 TODO(admin-
    // evaluations-ai-bridge)）。Web 路由持有 service-role key + askAI
    // orchestrator；iOS 只透传 Bearer JWT + year_month + user_ids。
    public struct BatchTriggerOutcome: Sendable {
        public let triggeredCount: Int
    }

    public func triggerBatch(userIds: [UUID], forceRegenerate: Bool = false) async -> BatchTriggerOutcome? {
        errorMessage = nil
        guard !userIds.isEmpty else {
            errorMessage = "当前筛选后没有员工可批量评估"
            return nil
        }
        do {
            let session = try await client.auth.session
            let token = session.accessToken
            let url = AppEnvironment.webAPIBaseURL
                .appendingPathComponent("api/mobile/admin/evaluations/trigger")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 45

            let payload: [String: Any] = [
                "year_month": month,
                "user_ids": userIds.map { $0.uuidString },
                "force_regenerate": forceRegenerate,
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "网络异常，请重试"
                return nil
            }

            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if http.statusCode >= 400 {
                let msg = (json?["error"] as? String)
                    ?? String(data: data, encoding: .utf8)
                    ?? "HTTP \(http.statusCode)"
                errorMessage = "批量评估失败：\(msg)"
                return nil
            }

            let triggered = (json?["triggered"] as? Int)
                ?? (json?["count"] as? Int)
                ?? userIds.count
            return BatchTriggerOutcome(triggeredCount: triggered)
        } catch {
            errorMessage = "批量评估失败：\(ErrorLocalizer.localize(error))"
            return nil
        }
    }

    public func shiftMonth(by delta: Int) async {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        let y = parts[0]
        let m = parts[1]
        var comp = DateComponents()
        comp.year = y
        comp.month = m + delta
        comp.day = 1
        let cal = Calendar(identifier: .gregorian)
        guard let d = cal.date(from: comp) else { return }
        let ny = cal.component(.year, from: d)
        let nm = cal.component(.month, from: d)
        await changeMonth(String(format: "%04d-%02d", ny, nm))
    }

    // ── Helpers ─────────────────────────────────────────────────
    public static func currentMonthCST() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone.current
        let now = Date()
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        return String(format: "%04d-%02d", y, m)
    }

    private static func primaryRoleOf(_ role: String) -> String {
        switch role {
        case "superadmin", "super_admin", "chairperson": return "superadmin"
        case "admin", "manager", "team_lead": return "admin"
        default: return "employee"
        }
    }
}
