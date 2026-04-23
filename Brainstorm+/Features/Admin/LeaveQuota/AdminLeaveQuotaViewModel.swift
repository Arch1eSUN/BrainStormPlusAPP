import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 4.6c — 调休额度矩阵 ViewModel
// Parity target: Web `src/components/settings/leave-quota-section.tsx`
// + `src/lib/actions/admin.ts::adminListCompTimeQuotas`.
//
// Web 的矩阵是员工 × 月份的 2D 宽表；iOS 改为按月 picker + per-user 列表。
// 数据聚合逻辑与 Web adminListCompTimeQuotas 完全对齐：
//   1) 拉 profiles（排除 status='deleted'），按 department/full_name 排序
//   2) 拉 comp_time_quotas 当月行
//   3) 左连接合并；缺账本行的 profile 默认 total=4 / used=0 / revoked=0
// 写入通过 upsert(user_id, year_month) 对齐 Web adminSetCompTimeQuotaTotal。
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class AdminLeaveQuotaViewModel: ObservableObject {
    public static let defaultTotalDays: Int = 4

    @Published public var yearMonth: String
    @Published public private(set) var rows: [LeaveQuotaAdminRow] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var savingUserId: UUID?
    @Published public var errorMessage: String?

    private let client: SupabaseClient

    public init(client: SupabaseClient = supabase) {
        self.client = client
        self.yearMonth = Self.currentYearMonth()
    }

    // ─── Derived groupings ─────────────────────────────────────

    /// 按部门分组（保持 Web 的 department/full_name 排序）。
    public var groupedRows: [(department: String, rows: [LeaveQuotaAdminRow])] {
        var order: [String] = []
        var bucket: [String: [LeaveQuotaAdminRow]] = [:]
        for row in rows {
            let key = row.displayDepartment
            if bucket[key] == nil {
                bucket[key] = []
                order.append(key)
            }
            bucket[key]?.append(row)
        }
        return order.map { ($0, bucket[$0] ?? []) }
    }

    public var allDepartments: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for r in rows {
            let key = r.displayDepartment
            if !seen.contains(key) {
                seen.insert(key)
                ordered.append(key)
            }
        }
        return ordered
    }

    // ─── Load ──────────────────────────────────────────────────

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let profilesTask = fetchProfiles()
            async let quotasTask = fetchQuotas(for: yearMonth)
            let (profiles, quotas) = try await (profilesTask, quotasTask)

            var quotaMap: [UUID: LeaveQuotaLedgerRow] = [:]
            for q in quotas {
                quotaMap[q.userId] = q
            }

            let rows: [LeaveQuotaAdminRow] = profiles
                .filter { ($0.status ?? "") != "deleted" }
                .map { p in
                    let q = quotaMap[p.id]
                    return LeaveQuotaAdminRow(
                        userId: p.id,
                        fullName: p.fullName,
                        department: p.department,
                        yearMonth: self.yearMonth,
                        totalDays: Int(q?.totalDays ?? Double(Self.defaultTotalDays)),
                        usedDays: q?.usedDays ?? 0,
                        revokedDays: q?.revokedDays ?? 0
                    )
                }
            self.rows = rows
        } catch {
            errorMessage = "加载调休额度失败：\(ErrorLocalizer.localize(error))"
        }
    }

    private func fetchProfiles() async throws -> [LeaveQuotaProfileRow] {
        try await client
            .from("profiles")
            .select("id, full_name, department, status")
            .order("department", ascending: true)
            .order("full_name", ascending: true)
            .execute()
            .value
    }

    private func fetchQuotas(for yearMonth: String) async throws -> [LeaveQuotaLedgerRow] {
        try await client
            .from("comp_time_quotas")
            .select("user_id, total_days, used_days, revoked_days")
            .eq("year_month", value: yearMonth)
            .execute()
            .value
    }

    // ─── Save ──────────────────────────────────────────────────

    private struct QuotaUpsertPayload: Encodable {
        let user_id: String
        let year_month: String
        let total_days: Int
    }

    /// Upsert 单人当月 total_days；成功后本地同步 availableDays。
    @discardableResult
    public func setTotal(for userId: UUID, totalDays: Int) async -> Bool {
        guard validate(totalDays: totalDays) else {
            errorMessage = "额度天数必须在 0 ~ 31 之间"
            return false
        }

        savingUserId = userId
        defer { savingUserId = nil }

        do {
            let payload = QuotaUpsertPayload(
                user_id: userId.uuidString,
                year_month: yearMonth,
                total_days: totalDays
            )
            _ = try await client
                .from("comp_time_quotas")
                .upsert(payload, onConflict: "user_id,year_month")
                .execute()
            if let idx = rows.firstIndex(where: { $0.userId == userId }) {
                rows[idx].totalDays = totalDays
            }
            return true
        } catch {
            errorMessage = "保存失败：\(ErrorLocalizer.localize(error))"
            return false
        }
    }

    /// 重置为默认 4 天。
    @discardableResult
    public func resetToDefault(for userId: UUID) async -> Bool {
        await setTotal(for: userId, totalDays: Self.defaultTotalDays)
    }

    /// 批量应用同一额度给一组员工（部门筛选或手选）。
    /// 按串行方式 upsert 以便单人失败不影响其他；返回成功数量。
    @discardableResult
    public func applyBatch(to userIds: [UUID], totalDays: Int) async -> (ok: Int, failed: Int) {
        guard validate(totalDays: totalDays) else {
            errorMessage = "额度天数必须在 0 ~ 31 之间"
            return (0, userIds.count)
        }
        var ok = 0
        var failed = 0
        for uid in userIds {
            let success = await setTotal(for: uid, totalDays: totalDays)
            if success { ok += 1 } else { failed += 1 }
        }
        if failed > 0 && errorMessage == nil {
            errorMessage = "部分员工保存失败（\(failed)/\(userIds.count)）"
        }
        return (ok, failed)
    }

    public func userIds(inDepartment department: String) -> [UUID] {
        rows.filter { $0.displayDepartment == department }.map(\.userId)
    }

    private func validate(totalDays: Int) -> Bool {
        totalDays >= 0 && totalDays <= 31
    }

    // ─── year-month helpers ────────────────────────────────────

    public static func currentYearMonth(reference: Date = Date()) -> String {
        let cal = Calendar(identifier: .gregorian)
        let y = cal.component(.year, from: reference)
        let m = cal.component(.month, from: reference)
        return String(format: "%04d-%02d", y, m)
    }

    /// 将 Date 转成 YYYY-MM。
    public static func yearMonth(from date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        return String(format: "%04d-%02d", y, m)
    }

    /// 将 YYYY-MM 转成该月 1 日的 Date（DatePicker 绑定用）。
    public static func date(fromYearMonth s: String) -> Date {
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        comps.day = 1
        let parts = s.split(separator: "-")
        if parts.count == 2,
           let y = Int(parts[0]),
           let m = Int(parts[1]) {
            comps.year = y
            comps.month = m
        } else {
            comps.year = 2026
            comps.month = 1
        }
        return comps.date ?? Date()
    }
}
