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
    public var schedules: [Schedule] = []
    
    private let repository: DashboardRepository
    
    public init(repository: DashboardRepository = DashboardRepository()) {
        self.repository = repository
    }
    
    public func loadData() async {
        state = .loading
        
        do {
            // First we need the authenticated user
            let session = try await supabase.auth.session
            let userId = session.user.id
            
            // Execute parallel fetch Using `async let` pattern
            async let fetchedProfile = repository.fetchCurrentProfile(userId: userId)
            async let fetchedSchedules = repository.fetchTodaySchedules(userId: userId)
            
            self.profile = try await fetchedProfile
            self.schedules = try await fetchedSchedules
            
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
