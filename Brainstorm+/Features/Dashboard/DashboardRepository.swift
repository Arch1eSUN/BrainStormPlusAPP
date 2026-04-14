import Foundation
import Supabase

public final class DashboardRepository {
    public init() {}
    
    /// Fetches the profile of the currently logged in user
    public func fetchCurrentProfile(userId: UUID) async throws -> Profile {
        let profile: Profile = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .single()
            .execute()
            .value
            
        return profile
    }
    
    /// Fetches schedules that overlap with today
    public func fetchTodaySchedules(userId: UUID) async throws -> [Schedule] {
        // Today's boundaries in ISO8601 for comparison, or we could rely on the `date` field in SQL
        // The schema looks like it has a `date` DATE column.
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let todayString = formatter.string(from: Date())
        
        let schedules: [Schedule] = try await supabase
            .from("schedules")
            .select()
            .eq("user_id", value: userId)
            .eq("date", value: todayString)
            .order("start_time", ascending: true)
            .execute()
            .value
            
        return schedules
    }
}
