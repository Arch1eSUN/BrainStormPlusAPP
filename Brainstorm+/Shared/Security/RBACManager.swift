import Foundation

/// ── Primary Roles ──────────────────────────────────────────
public enum PrimaryRole: String, Codable {
    case employee
    case admin
    case superadmin
    case chairperson
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
        .superadmin: AttendanceRule(attendanceRequired: true, reportingRequired: true),
        .chairperson: AttendanceRule(attendanceRequired: true, reportingRequired: false)
    ]
    
    public let defaultCapabilities: [PrimaryRole: [Capability]] = [
        .employee: [],
        .admin: [
            .ai_chatbot_access, .approval_access, .field_work_approval,
            .daily_log_approval, .weekly_report_approval
        ],
        .superadmin: [
            .approval_access, .leave_approval, .attendance_exception_approval,
            .purchase_approval, .expense_approval, .reimbursement_approval,
            .recruitment_approval, .document_publish_approval, .field_work_approval,
            .daily_log_approval, .weekly_report_approval, .ai_chatbot_access,
            .ai_provider_admin, .apikey_admin, .role_policy_admin,
            .sensitive_settings_read, .sensitive_settings_write,
            .hr_ops, .finance_ops, .media_ops, .ai_resume_screening,
            .ai_media_analysis, .ai_finance_docs, .ai_finance_reports,
            .ai_finance_data_processing
        ],
        .chairperson: [
            .approval_access, .leave_approval, .attendance_exception_approval,
            .purchase_approval, .expense_approval, .reimbursement_approval,
            .recruitment_approval, .document_publish_approval, .field_work_approval,
            .daily_log_approval, .weekly_report_approval, .ai_chatbot_access,
            .role_policy_admin, .sensitive_settings_read, .sensitive_settings_write
        ]
    ]
    
    /// Provides the migration result for a legacy role string
    public func migrateLegacyRole(_ oldRoleStr: String?) -> MigrationResult {
        let role = oldRoleStr?.lowercased() ?? "employee"
        
        switch role {
        case "chairperson":
            return MigrationResult(primaryRole: .chairperson, capabilities: [], attendanceRule: attendanceRules[.chairperson]!)
        case "superadmin", "super_admin":
            return MigrationResult(primaryRole: .superadmin, capabilities: [], attendanceRule: attendanceRules[.superadmin]!)
        case "admin", "manager", "team_lead":
            return MigrationResult(primaryRole: .admin, capabilities: [], attendanceRule: attendanceRules[.admin]!)
        case "hr":
            return MigrationResult(
                primaryRole: .employee,
                capabilities: [.hr_ops, .approval_access, .leave_approval, .recruitment_approval, .ai_resume_screening, .ai_interview_entry],
                attendanceRule: attendanceRules[.employee]!
            )
        case "finance":
            return MigrationResult(
                primaryRole: .employee,
                capabilities: [.finance_ops, .approval_access, .purchase_approval, .expense_approval, .reimbursement_approval, .ai_finance_docs, .ai_finance_reports, .ai_finance_data_processing],
                attendanceRule: attendanceRules[.employee]!
            )
        case "employee", "contractor", "intern":
            fallthrough
        default:
            return MigrationResult(primaryRole: .employee, capabilities: [], attendanceRule: attendanceRules[.employee]!)
        }
    }
    
    /// Calculate effective abilities
    public func getEffectiveCapabilities(for profile: Profile?) -> [Capability] {
        guard let profile = profile else { return [] }
        
        let migration = migrateLegacyRole(profile.role)
        let defaults = defaultCapabilities[migration.primaryRole] ?? []
        
        // Parse DB capabilities
        var dbCapabilities: [Capability] = []
        if let rawCaps = profile.capabilities {
            dbCapabilities = rawCaps.compactMap { Capability(rawValue: $0) }
        }
        
        // Merge capabilities without duplicates
        var allCapsSet = Set(defaults)
        migration.capabilities.forEach { allCapsSet.insert($0) }
        dbCapabilities.forEach { allCapsSet.insert($0) }
        
        return Array(allCapsSet)
    }
    
    public func hasCapability(_ cap: Capability, in effectiveCaps: [Capability]) -> Bool {
        return effectiveCaps.contains(cap)
    }
}
