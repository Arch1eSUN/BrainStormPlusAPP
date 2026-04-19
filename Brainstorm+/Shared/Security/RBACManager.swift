import Foundation

/// ── Primary Roles ──────────────────────────────────────────
/// Phase 2 canonical 3-role model, mirroring Web `src/lib/capabilities.ts:10`.
/// Legacy roles (chairperson / super_admin / manager / team_lead / hr / finance /
/// contractor / intern) are folded via `migrateLegacyRole` — never introduce new
/// references to legacy roles in new code.
public enum PrimaryRole: String, Codable {
    case employee
    case admin
    case superadmin
}

/// ── Capabilities ───────────────────────────────────────────
public enum Capability: String, Codable, CaseIterable {
    // 职能能力
    case hr_ops
    case finance_ops
    case media_ops
    // 审批能力
    case approval_access
    case leave_approval
    case attendance_exception_approval
    case purchase_approval
    case expense_approval
    case reimbursement_approval
    case recruitment_approval
    case document_publish_approval
    case field_work_approval
    case daily_log_approval
    case weekly_report_approval
    // AI 能力
    case ai_chatbot_access
    case ai_media_analysis
    case ai_resume_screening
    case ai_finance_docs
    case ai_finance_reports
    case ai_finance_data_processing
    case ai_interview_entry
    // 管理扩展能力
    case attendance_admin       // 考勤规则 / 地理围栏 / 假勤豁免管理
    case leave_quota_admin      // 调休额度管理
    case ai_evaluation_access   // AI 月度评估 (跨部门)
    case holiday_admin          // 公休日历管理
    // 系统治理能力
    case ai_provider_admin
    case apikey_admin
    case role_policy_admin
    case sensitive_settings_read
    case sensitive_settings_write
}

/// ── RBAC Manager ──────────────────────────────────────────
public final class RBACManager {
    public static let shared = RBACManager()
    
    private init() {}
    
    public struct AttendanceRule {
        public let attendanceRequired: Bool
        public let reportingRequired: Bool
    }
    
    public struct MigrationResult {
        public let primaryRole: PrimaryRole
        public let capabilities: [Capability]
        public let attendanceRule: AttendanceRule
    }
    
    public let attendanceRules: [PrimaryRole: AttendanceRule] = [
        .employee: AttendanceRule(attendanceRequired: true, reportingRequired: true),
        .admin: AttendanceRule(attendanceRequired: true, reportingRequired: true),
        .superadmin: AttendanceRule(attendanceRequired: true, reportingRequired: true)
    ]
    
    /// Mirror of Web `src/lib/capabilities.ts:71-132` DEFAULT_CAPABILITIES.
    /// admin = 18 caps, superadmin = 30 caps. Keep in sync with Web source.
    public let defaultCapabilities: [PrimaryRole: [Capability]] = [
        .employee: [],
        .admin: [
            // HR package core — admin 默认落在人事
            .hr_ops,
            .leave_approval,
            .attendance_exception_approval,
            .recruitment_approval,
            .ai_resume_screening,
            .ai_interview_entry,
            // Base approvals every admin can sign off
            .approval_access,
            .field_work_approval,
            .daily_log_approval,
            .weekly_report_approval,
            // Admin-as-fallback approver (per product: admin+ must never be blocked from a tab)
            .reimbursement_approval,
            .purchase_approval,
            .expense_approval,
            // AI assistant
            .ai_chatbot_access,
            // 管理扩展
            .attendance_admin,
            .leave_quota_admin,
            .ai_evaluation_access,
            .holiday_admin,
        ],
        .superadmin: [
            .approval_access,
            .leave_approval,
            .attendance_exception_approval,
            .purchase_approval,
            .expense_approval,
            .reimbursement_approval,
            .recruitment_approval,
            .document_publish_approval,
            .field_work_approval,
            .daily_log_approval,
            .weekly_report_approval,
            .ai_chatbot_access,
            .ai_provider_admin,
            .apikey_admin,
            .role_policy_admin,
            .sensitive_settings_read,
            .sensitive_settings_write,
            // Functional capabilities
            .hr_ops,
            .finance_ops,
            .media_ops,
            .ai_resume_screening,
            .ai_media_analysis,
            .ai_finance_docs,
            .ai_finance_reports,
            .ai_finance_data_processing,
            .ai_interview_entry,
            // 管理扩展
            .attendance_admin,
            .leave_quota_admin,
            .ai_evaluation_access,
            .holiday_admin,
        ]
    ]
    
    /// Mirror of Web `src/lib/role-migration.ts:113-139`. Canonical 3 roles pass
    /// through silently; every legacy role logs a deprecation warning so we can
    /// spot profile rows migration 049 missed. `chairperson` now folds to
    /// `.superadmin` (previously had its own PrimaryRole case — removed in 3.0).
    public func migrateLegacyRole(_ oldRoleStr: String?) -> MigrationResult {
        let canonical: Set<String> = ["superadmin", "admin", "employee"]
        let role = oldRoleStr?.lowercased() ?? "employee"

        switch role {
        // Canonical pass-through
        case "superadmin":
            return MigrationResult(primaryRole: .superadmin, capabilities: [], attendanceRule: attendanceRules[.superadmin]!)
        case "admin":
            return MigrationResult(primaryRole: .admin, capabilities: [], attendanceRule: attendanceRules[.admin]!)
        case "employee":
            return MigrationResult(primaryRole: .employee, capabilities: [], attendanceRule: attendanceRules[.employee]!)
        // Legacy → canonical (migration 049 fallback)
        case "chairperson", "super_admin":
            logLegacyRoleWarning(role, mappedTo: "superadmin")
            return MigrationResult(primaryRole: .superadmin, capabilities: [], attendanceRule: attendanceRules[.superadmin]!)
        case "manager", "team_lead":
            logLegacyRoleWarning(role, mappedTo: "admin")
            return MigrationResult(primaryRole: .admin, capabilities: [], attendanceRule: attendanceRules[.admin]!)
        case "hr":
            logLegacyRoleWarning(role, mappedTo: "employee + hr capabilities")
            return MigrationResult(
                primaryRole: .employee,
                capabilities: [.hr_ops, .approval_access, .leave_approval, .recruitment_approval, .ai_resume_screening, .ai_interview_entry],
                attendanceRule: attendanceRules[.employee]!
            )
        case "finance":
            logLegacyRoleWarning(role, mappedTo: "employee + finance capabilities")
            return MigrationResult(
                primaryRole: .employee,
                capabilities: [.finance_ops, .approval_access, .purchase_approval, .expense_approval, .reimbursement_approval, .ai_finance_docs, .ai_finance_reports, .ai_finance_data_processing],
                attendanceRule: attendanceRules[.employee]!
            )
        case "contractor", "intern":
            logLegacyRoleWarning(role, mappedTo: "employee")
            return MigrationResult(primaryRole: .employee, capabilities: [], attendanceRule: attendanceRules[.employee]!)
        default:
            if !canonical.contains(role) {
                print("⚠️ [role-migration] unknown role \"\(role)\" → defaulting to employee. Possible corrupt profile row.")
            }
            return MigrationResult(primaryRole: .employee, capabilities: [], attendanceRule: attendanceRules[.employee]!)
        }
    }

    private func logLegacyRoleWarning(_ oldRole: String, mappedTo newRoleDescription: String) {
        print("⚠️ [role-migration] deprecated role \"\(oldRole)\" → \"\(newRoleDescription)\" (fallback). Migration 049 should have removed this; inspect the profile row.")
    }
    
    /// Mirror of Web `getEffectiveCapabilities(primaryRole, assigned, excluded)`:
    /// `(defaults ∪ migration-derived ∪ DB-assigned) − excluded`.
    public func getEffectiveCapabilities(for profile: Profile?) -> [Capability] {
        guard let profile = profile else { return [] }

        let migration = migrateLegacyRole(profile.role)
        let defaults = defaultCapabilities[migration.primaryRole] ?? []

        // Explicit capabilities written to the profile row
        let dbCapabilities: [Capability] = (profile.capabilities ?? []).compactMap { Capability(rawValue: $0) }

        // Merge defaults ∪ migration-derived ∪ DB-explicit
        var merged = Set<Capability>(defaults)
        migration.capabilities.forEach { merged.insert($0) }
        dbCapabilities.forEach { merged.insert($0) }

        // Subtract excluded_capabilities (admin can strip specific caps from a user)
        let excluded: [Capability] = (profile.excludedCapabilities ?? []).compactMap { Capability(rawValue: $0) }
        excluded.forEach { merged.remove($0) }

        return Array(merged)
    }

    public func hasCapability(_ cap: Capability, in effectiveCaps: [Capability]) -> Bool {
        return effectiveCaps.contains(cap)
    }

    /// Matches DB RLS policy for `risk_actions` (migrations 014 + 037):
    /// super_admin / admin / hr_admin / manager can write. Intentionally
    /// narrower than Web's server guard (which via `getRoleLevel` also
    /// admits team_lead / superadmin / chairperson at level ≥ 2) — the
    /// iOS client-side gate mirrors the authoritative DB layer.
    ///
    /// Accepts raw role strings (not PrimaryRole) because DB RLS still
    /// enforces on the legacy `role` column; `superadmin` canonical alias
    /// is included for Phase 2 coverage.
    public func canManageRiskActions(rawRole: String?) -> Bool {
        guard let role = rawRole?.lowercased() else { return false }
        return ["super_admin", "superadmin", "admin", "hr_admin", "manager"].contains(role)
    }

    /// Profile-shaped convenience that forwards to `canManageRiskActions(rawRole:)`.
    public func canManageRiskActions(profile: Profile?) -> Bool {
        return canManageRiskActions(rawRole: profile?.role)
    }
}
