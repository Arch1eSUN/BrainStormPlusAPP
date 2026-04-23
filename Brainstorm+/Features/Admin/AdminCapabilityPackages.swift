import Foundation

// ══════════════════════════════════════════════════════════════════
// Mirror of Web `src/lib/capabilities.ts:254` CAPABILITY_PACKAGES.
// iOS 不通过 server action 解析 package_ids；创建/编辑用户时直接把
// resolvePackages() 展开后的 capabilities 数组写入 profiles.capabilities。
// ══════════════════════════════════════════════════════════════════

public enum AdminCapabilityPackageId: String, CaseIterable, Codable {
    case hr_package
    case finance_package
    case media_package
}

public struct AdminCapabilityPackage: Identifiable, Hashable {
    public let id: AdminCapabilityPackageId
    public let label: String
    public let description: String
    public let capabilities: [Capability]

    public static let all: [AdminCapabilityPackage] = [
        .init(
            id: .hr_package,
            label: "人事管理",
            description: "团队 · 账号 · 招聘与请假审批 · 考勤规则 · 调休 · AI 评估 · 公休日历",
            capabilities: [
                .hr_ops,
                .approval_access,
                .leave_approval,
                .attendance_exception_approval,
                .recruitment_approval,
                .ai_resume_screening,
                .ai_interview_entry,
                .attendance_admin,
                .leave_quota_admin,
                .ai_evaluation_access, // iOS 对应 Web 的 ai_evaluation_ops
                .holiday_admin
            ]
        ),
        .init(
            id: .finance_package,
            label: "财务管理",
            description: "薪资 · 财务 AI · 采购与报销审批",
            capabilities: [
                .finance_ops,
                .approval_access,
                .purchase_approval,
                .expense_approval,
                .reimbursement_approval,
                .ai_finance_docs,
                .ai_finance_reports,
                .ai_finance_data_processing
            ]
        ),
        .init(
            id: .media_package,
            label: "媒体运营",
            description: "内容分析 · AI 媒体分析",
            capabilities: [.media_ops, .ai_media_analysis]
        )
    ]

    /// Reverse-resolve a user's current capability set to the package IDs whose
    /// capabilities are ALL present (mirrors Web admin/page.tsx EditUserModal).
    public static func matchingPackages(from caps: [Capability]) -> [AdminCapabilityPackageId] {
        let set = Set(caps)
        return all.filter { pkg in
            pkg.capabilities.allSatisfy { set.contains($0) }
        }.map(\.id)
    }

    /// Flatten a set of package IDs to a unique capability list.
    public static func resolve(_ ids: [AdminCapabilityPackageId]) -> [Capability] {
        var seen = Set<Capability>()
        for id in ids {
            guard let pkg = all.first(where: { $0.id == id }) else { continue }
            for c in pkg.capabilities { seen.insert(c) }
        }
        return Array(seen)
    }
}

// Human-readable Chinese labels for individual capabilities
// (mirror Web CAPABILITY_LABELS at admin/page.tsx:35)
public enum AdminCapabilityLabels {
    public static func label(_ cap: Capability) -> String {
        switch cap {
        case .hr_ops: return "团队人事 (HR)"
        case .finance_ops: return "财务管理"
        case .media_ops: return "媒体运营"
        case .approval_access: return "审批中心"
        case .leave_approval: return "请假审批"
        case .attendance_exception_approval: return "考勤异常审批"
        case .purchase_approval: return "采购审批"
        case .expense_approval: return "报销审批"
        case .reimbursement_approval: return "报销入账"
        case .recruitment_approval: return "招聘审批"
        case .document_publish_approval: return "文件发布审批"
        case .field_work_approval: return "外勤审批"
        case .daily_log_approval: return "日报审批"
        case .weekly_report_approval: return "周报审批"
        case .ai_chatbot_access: return "AI 助手"
        case .ai_media_analysis: return "AI 媒体分析"
        case .ai_resume_screening: return "AI 简历筛选"
        case .ai_finance_docs: return "AI 财务文档"
        case .ai_finance_reports: return "AI 财务报表"
        case .ai_finance_data_processing: return "AI 财务数据处理"
        case .ai_interview_entry: return "AI 面试入口"
        case .attendance_admin: return "考勤规则管理"
        case .leave_quota_admin: return "调休额度管理"
        case .ai_evaluation_access: return "AI 月度评估"
        case .holiday_admin: return "公休日历管理"
        case .ai_provider_admin: return "AI 供应商管理"
        case .apikey_admin: return "API Key 管理"
        case .role_policy_admin: return "角色策略管理"
        case .sensitive_settings_read: return "敏感设置查看"
        case .sensitive_settings_write: return "敏感设置写入"
        }
    }
}
