import SwiftUI
import Supabase

public struct ActionItemHelper {
    
    /// Stricter module handler providing exact module to view translation mapping.
    @ViewBuilder
    public static func destination(for module: AppModule) -> some View {
        switch module {
        case .tasks:
            TaskListView(viewModel: TaskListViewModel(client: supabase))
        case .projects:
            ProjectListView(viewModel: ProjectListViewModel(client: supabase), isEmbedded: true)
        case .okr:
            // Phase 2.3 — read-only OKR list + detail ported from
            // BrainStorm+-Web/src/app/dashboard/okr. Create/edit/check-in
            // are deliberately out of scope this pass.
            OKRListView(viewModel: OKRListViewModel(client: supabase), isEmbedded: true)
        case .daily, .weekly:
            ReportingListView(viewModel: ReportingViewModel(client: supabase), isEmbedded: true)
        case .schedules:
            ScheduleView(isEmbedded: true)
        case .leaves:
            // Phase 2.2 — balance + history center (read-only user view).
            // Submission modal is presented from inside LeavesView via
            // the existing `LeaveSubmitView`; the approval queue is a
            // separate destination under `.approval`.
            LeavesView(client: supabase, isEmbedded: true)
        case .attendance:
            AttendanceView(isEmbedded: true)
        case .chat:
            ChatListView(viewModel: ChatListViewModel(client: supabase))
        case .approval:
            // Sprint 4.3 — routes to the 7-tab approval center
            // (mine + 6 approver queues). ApprovalsListView (4.1) is
            // now the "我提交的" body *inside* the center, not a
            // top-level destination.
            ApprovalCenterView(client: supabase)
        case .knowledge:
            KnowledgeListView(viewModel: KnowledgeListViewModel(client: supabase), isEmbedded: true)
        case .team:
            TeamDirectoryView(isEmbedded: true)
        case .announcements:
            AnnouncementsListView(viewModel: AnnouncementsListViewModel(client: supabase), isEmbedded: true)
        case .deliverables:
            // Phase 2.1 — iOS list+detail; Phase 6.3 补齐 create 流
            // (DeliverableCreateSheet via toolbar "+" and empty-state CTA).
            DeliverableListView(viewModel: DeliverableListViewModel(client: supabase), isEmbedded: true)
        case .notifications:
            NotificationListView(viewModel: NotificationListViewModel(client: supabase), isEmbedded: true)
        case .activity:
            // Phase 3 — 1:1 port of BrainStorm+-Web/src/app/dashboard/activity.
            // Read-only feed reachable from the Communication quick-link tile
            // (DashboardRoleSections.swift L160) or the sidebar.
            ActivityFeedView(viewModel: ActivityFeedViewModel(client: supabase), isEmbedded: true)
        case .payroll:
            PayrollListView(viewModel: PayrollListViewModel(client: supabase), isEmbedded: true)
        case .hiring:
            // Phase 4.4 — 1:1 port of BrainStorm+-Web/src/app/dashboard/hiring.
            // Capability gate (hr_ops / admin+) lives inside HiringCenterView
            // so sidebar / quick-action tiles can link unconditionally.
            HiringCenterView(isEmbedded: true)
        case .finance:
            // Phase 4.3 + 5.3 — 1:1 port of
            // BrainStorm+-Web/src/app/dashboard/finance. Submit action goes
            // through POST /api/mobile/finance/ai-process; history + chart +
            // structured-output viewer all live-fed from ai_work_records.
            FinanceView(client: supabase, isEmbedded: true)
        case .settings:
            SettingsView()
        case .aiAnalysis:
            // Phase 4.2 — 1:1 port of
            // BrainStorm+-Web/src/app/dashboard/ai-analysis/page.tsx.
            // Streams `/api/ai/analyze` SSE and renders the intel-card report.
            AIAnalysisView(isEmbedded: true)
        case .admin:
            // Phase 4.1 — 1:1 port of BrainStorm+-Web/src/app/dashboard/admin.
            // 子模块：用户 / 组织 / 公休 / 广播 / 审计；创建用户受 service_role
            // 限制仍需 Web 端操作（见 AdminUserCreateSheet 注释）。
            AdminCenterView(isEmbedded: true)
        default:
            ParityBacklogDestination(moduleName: module.displayName, webRoute: module.webRoute)
        }
    }
    
    /// Legacy alias, keeping the original string mapping for untyped elements like quick links
    /// which may solely be providing strings at the initial layer.
    /// This should gradually be phased out entirely as the calling components strongly-type their values.
    @ViewBuilder
    @available(*, deprecated, message: "Use destination(for module:) instead. This fuzzy text match is only for backward compatibility.")
    public static func destination(for title: String) -> some View {

        let appModule = getAppModule(for: title)
        
        if let module = appModule {
            destination(for: module)
        } else {
            ParityBacklogDestination(moduleName: title, webRoute: "Unknown")
        }
    }
    
    private static func getAppModule(for string: String) -> AppModule? {
        let normalized = string.lowercased()
        if normalized.contains("task") { return .tasks }
        if normalized.contains("project") { return .projects }
        if normalized.contains("okr") { return .okr }
        if normalized.contains("deliverable") { return .deliverables }
        if normalized.contains("daily") { return .daily }
        if normalized.contains("weekly") { return .weekly }
        if normalized.contains("approval") { return .approval }
        if normalized.contains("request") { return .request }
        if normalized.contains("schedule") { return .schedules }
        if normalized.contains("leave") { return .leaves }
        if normalized.contains("attendance") { return .attendance }
        if normalized.contains("hiring") { return .hiring }
        if normalized.contains("team") { return .team }
        if normalized.contains("chat") { return .chat }
        if normalized.contains("announcement") { return .announcements }
        if normalized.contains("knowledge") { return .knowledge }
        if normalized.contains("notification") { return .notifications }
        if normalized.contains("activity") { return .activity }
        if normalized.contains("payroll") { return .payroll }
        if normalized.contains("setting") { return .settings }
        if normalized.contains("admin") { return .admin }
        if normalized.contains("finance") { return .finance }
        if normalized.contains("analytics") { return .analytics }
        if normalized.contains("ai") { return .aiAnalysis }
        return nil
    }
}
