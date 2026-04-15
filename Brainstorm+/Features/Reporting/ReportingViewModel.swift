import Foundation
import Combine
import Supabase

@MainActor
public class ReportingViewModel: ObservableObject {
    @Published public var dailyLogs: [DailyLog] = []
    @Published public var weeklyReports: [WeeklyReport] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    private let client: SupabaseClient
    
    public init(client: SupabaseClient) {
        self.client = client
    }
    
    public func fetchReports() async {
        isLoading = true
        errorMessage = nil
        do {
            let session = try await client.auth.session
            let currentUserId = session.user.id
            
            async let fetchedLogs: [DailyLog] = try await client
                .from("daily_logs")
                .select()
                .eq("user_id", value: currentUserId)
                .order("date", ascending: false)
                .limit(7)
                .execute()
                .value
            
            async let fetchedWeekly: [WeeklyReport] = try await client
                .from("weekly_reports")
                .select()
                .eq("user_id", value: currentUserId)
                .order("week_start_date", ascending: false)
                .limit(4)
                .execute()
                .value
            
            self.dailyLogs = try await fetchedLogs
            self.weeklyReports = try await fetchedWeekly
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
