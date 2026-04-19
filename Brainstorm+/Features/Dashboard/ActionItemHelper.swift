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
            ProjectListView(viewModel: ProjectListViewModel(client: supabase))
        case .daily, .weekly:
            ReportingListView(viewModel: ReportingViewModel(client: supabase))
        case .schedules:
            ScheduleView()
        case .attendance:
            AttendanceView()
        case .chat:
            ChatListView(viewModel: ChatListViewModel(client: supabase))
        case .knowledge:
            KnowledgeListView(viewModel: KnowledgeListViewModel(client: supabase))
        case .notifications:
            NotificationListView(viewModel: NotificationListViewModel(client: supabase))
        case .payroll:
            PayrollListView(viewModel: PayrollListViewModel(client: supabase))
        case .settings:
            SettingsView()
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
        return nil
    }
}
