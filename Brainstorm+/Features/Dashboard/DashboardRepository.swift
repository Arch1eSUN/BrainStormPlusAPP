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

    /// Fetches today's `daily_work_state` row (replaces legacy `schedules` table).
    /// Returns nil if no row exists yet (RLS trigger may not have backfilled).
    public func fetchTodayWorkState(userId: UUID) async throws -> DailyWorkState? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let todayString = formatter.string(from: Date())

        let rows: [DailyWorkState] = try await supabase
            .from("daily_work_state")
            .select("*")
            .eq("user_id", value: userId.uuidString)
            .eq("work_date", value: todayString)
            .limit(1)
            .execute()
            .value

        return rows.first
    }
}
