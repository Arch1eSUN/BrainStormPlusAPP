import Foundation

public enum AppImplementationStatus: String, Codable {
    case implemented
    case partial
    case backlog
}

public enum AppModule: String, CaseIterable, Identifiable {
    public var id: String { rawValue }
    
    // Execution
    case tasks
    case projects
    case okr
    case deliverables
    
    // Reporting
    case daily
    case weekly
    
    // Admin & HR
    case approval
    case request
    case schedules
    case leaves
    case attendance
    case hiring
    case team
    
    // Communication
    case chat
    case announcements
    case knowledge
    case notifications
    case activity
    
    // Smart & Admin
    case aiAnalysis
    case finance
    case analytics
    case payroll
    case admin
    case settings
    
    public var displayName: String {
        switch self {
        case .tasks: return "Tasks"
        case .projects: return "Projects"
        case .okr: return "OKRs"
        case .deliverables: return "Deliverables"
        case .daily: return "Daily Log"
        case .weekly: return "Weekly Report"
        case .approval: return "Approvals"
        case .request: return "Requests"
        case .schedules: return "Schedules"
        case .leaves: return "Leaves"
        case .attendance: return "Attendance"
        case .hiring: return "Hiring"
        case .team: return "Team"
        case .chat: return "Chat"
        case .announcements: return "Announcements"
        case .knowledge: return "Knowledge Base"
        case .notifications: return "Notifications"
        case .activity: return "Activity Log"
        case .aiAnalysis: return "AI Analysis"
        case .finance: return "Finance AI"
        case .analytics: return "Analytics"
        case .payroll: return "Payroll"
        case .admin: return "Admin Config"
        case .settings: return "Settings"
        }
    }
    
    public var webRoute: String {
        switch self {
        case .request: return "/dashboard/request"
        case .aiAnalysis: return "/dashboard/ai-analysis"
        default: return "/dashboard/\(self.rawValue)"
        }
    }
    
    public var iconName: String {
        switch self {
        case .tasks: return "checkmark.square"
        case .projects: return "folder"
        case .okr: return "target"
        case .deliverables: return "briefcase"
        case .daily: return "doc.append"
        case .weekly: return "calendar.day.timeline.left"
        case .approval: return "checkmark.seal"
        case .request: return "paperplane"
        case .schedules: return "calendar"
        case .leaves: return "moon.zzz"
        case .attendance: return "clock"
        case .hiring: return "person.badge.plus"
        case .team: return "person.3"
        case .chat: return "bubble.left.and.bubble.right"
        case .announcements: return "megaphone"
        case .knowledge: return "book"
        case .notifications: return "bell"
        case .activity: return "list.bullet.clipboard"
        case .aiAnalysis: return "brain"
        case .finance: return "dollarsign.circle"
        case .analytics: return "chart.bar"
        case .payroll: return "banknote"
        case .admin: return "gearshape.2"
        case .settings: return "gear"
        }
    }
    
    public var implementationStatus: AppImplementationStatus {
        switch self {
        case .tasks, .daily, .weekly, .schedules, .attendance, .chat, .knowledge, .notifications, .payroll, .settings, .leaves, .activity, .announcements, .team, .projects, .deliverables, .okr:
            // okr (2026-04-24)、deliverables / projects 均已 ship create + edit。
            // OKR KR add/check-in VM 方法（addKeyResult / updateKeyResultProgress）
            // 就绪但 UI 暂无 sheet — 属于次级编辑场景，不影响首发 ship 判定。
            return .implemented
        case .finance:
            // Phase 4.3 — read-only viewer for ai_work_records + charts.
            // Submit/orchestrator wiring deferred (TODO finance-ai-orchestrator-bridge).
            return .partial
        default:
            return .backlog
        }
    }
    
    public var group: String {
        switch self {
        case .tasks, .projects, .okr, .deliverables: return "Execution"
        case .daily, .weekly: return "Reporting"
        case .approval, .request, .schedules, .leaves, .attendance, .hiring, .team: return "Admin & HR"
        case .chat, .announcements, .knowledge, .notifications, .activity: return "Communication"
        case .aiAnalysis, .finance, .analytics, .payroll, .admin, .settings: return "Smart & Admin"
        }
    }
    
    public var requiredCapabilities: [Capability] {
        switch self {
        case .approval, .request:
            return [.approval_access]
        case .hiring:
            return [.recruitment_approval]
        case .aiAnalysis:
            return [.ai_media_analysis]
        case .finance:
            return [.ai_finance_data_processing]
        case .admin:
            return [.role_policy_admin] 
        case .payroll:
            return [.finance_ops]
        case .settings, .tasks, .projects, .okr, .deliverables, .daily, .weekly, .schedules, .leaves, .attendance, .team, .chat, .announcements, .knowledge, .notifications, .activity, .analytics:
            // `.leaves` is the user-facing balance + history center
            // (Phase 2.2). Every employee can view their own quotas;
            // manager-side bulk view lives behind `.approval` / HR caps.
            return [] // Base features requiring minimal capabilities mapped out.
        }
    }
}