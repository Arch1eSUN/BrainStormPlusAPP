import SwiftUI
import Supabase

public enum ViewState: Equatable {
    case loading
    case loaded
    case error(String)
}

@MainActor
@Observable
public final class DashboardViewModel {
    public var state: ViewState = .loading
    public var profile: Profile?
    public var todayState: DailyWorkState?

    private let repository: DashboardRepository

    public init(repository: DashboardRepository = DashboardRepository()) {
        self.repository = repository
    }

    /// Mirror of Web `getDashboardTemplate(primaryRole)` — 3 templates.
    /// Falls back to `.employee` while profile is still loading (matches Web's
    /// employee-default for any non-admin/non-superadmin primaryRole).
    public var dashboardTemplate: PrimaryRole {
        let role = RBACManager.shared.migrateLegacyRole(profile?.role).primaryRole
        return role
    }

    public var dashboardTemplateLabel: String {
        switch dashboardTemplate {
        case .employee: return "个人工作台"
        case .admin: return "管理工作台"
        case .superadmin: return "治理工作台"
        }
    }

    public var primaryRoleDisplayName: String {
        switch dashboardTemplate {
        case .employee: return "员工"
        case .admin: return "管理员"
        case .superadmin: return "超级管理员"
        }
    }

    public func loadData() async {
        state = .loading

        do {
            // First we need the authenticated user
            let session = try await supabase.auth.session
            let userId = session.user.id

            // Execute parallel fetch Using `async let` pattern
            async let fetchedProfile = repository.fetchCurrentProfile(userId: userId)
            async let fetchedTodayState = repository.fetchTodayWorkState(userId: userId)

            self.profile = try await fetchedProfile
            self.todayState = try await fetchedTodayState
            
            withAnimation {
                self.state = .loaded
            }
        } catch {
            print("Error loading dashboard data: \(error)")
            withAnimation {
                self.state = .error("Failed to load dashboard data. Check your connection.")
            }
        }
    }
}
