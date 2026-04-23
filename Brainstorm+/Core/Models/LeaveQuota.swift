import Foundation

// ══════════════════════════════════════════════════════════════════
// Phase 4.6c — 调休额度矩阵 (comp_time_quotas 管理端)
// Parity target: Web `src/components/settings/leave-quota-section.tsx`
// + `src/lib/actions/admin.ts::adminListCompTimeQuotas / adminSetCompTimeQuotaTotal`.
//
// 这不是 `LeaveBalance` 的旁路：
//   - `LeaveBalance` 是给员工自己看的每假期类型 1 行 presentation card
//     （annual/sick/personal/comp_time 并列）；来源是 `leave_balances` +
//     `approval_requests` 本月聚合。
//   - `LeaveQuotaAdminRow` 是 HR 管理端的按月 per-user 账本行，直接来自
//     `comp_time_quotas` 主表（044_comp_time_quotas.sql）— 字段含义和键
//     完全不同（total / used / revoked + available 推导）。
//
// 所以这里独立建模，不挤进 LeaveBalance.swift。
// ══════════════════════════════════════════════════════════════════

/// 一个员工在某个月份的调休额度快照。
public struct LeaveQuotaAdminRow: Identifiable, Hashable {
    public let userId: UUID
    public let fullName: String?
    public let department: String?
    public let yearMonth: String
    public var totalDays: Int
    public var usedDays: Double
    public var revokedDays: Double

    public var id: UUID { userId }

    /// 剩余 = total - used + revoked（不低于 0），与 Web 保持一致。
    public var availableDays: Double {
        max(0, Double(totalDays) - usedDays + revokedDays)
    }

    public var displayName: String {
        fullName?.trimmingCharacters(in: .whitespaces).nonEmpty ?? "未命名"
    }

    public var displayDepartment: String {
        department?.trimmingCharacters(in: .whitespaces).nonEmpty ?? "—"
    }

    public init(
        userId: UUID,
        fullName: String?,
        department: String?,
        yearMonth: String,
        totalDays: Int,
        usedDays: Double,
        revokedDays: Double
    ) {
        self.userId = userId
        self.fullName = fullName
        self.department = department
        self.yearMonth = yearMonth
        self.totalDays = totalDays
        self.usedDays = usedDays
        self.revokedDays = revokedDays
    }
}

// ─── Supabase raw DTOs ────────────────────────────────────────────

/// `profiles` projection used by the admin list.
struct LeaveQuotaProfileRow: Decodable {
    let id: UUID
    let fullName: String?
    let department: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case department
        case status
    }
}

/// `comp_time_quotas` projection for the month being edited.
struct LeaveQuotaLedgerRow: Decodable {
    let userId: UUID
    let totalDays: Double
    let usedDays: Double
    let revokedDays: Double

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case totalDays = "total_days"
        case usedDays = "used_days"
        case revokedDays = "revoked_days"
    }
}

// ─── helpers ──────────────────────────────────────────────────────

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
