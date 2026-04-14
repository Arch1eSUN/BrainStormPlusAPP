import Foundation
import Supabase

@Observable
public final class ScheduleViewModel {
    public var schedules: [Schedule] = []
    public var isLoading = false
    public var errorMessage: String?
    
    // For date selection
    public var selectedDate = Date()
    
    @MainActor
    public func loadSchedules() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let session = try await supabase.auth.session
            let currentUser = session.user
            
            // Format start and end of selected day to filter
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: selectedDate)
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
                isLoading = false
                return
            }
            
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let startString = dateFormatter.string(from: startOfDay)
            let endString = Formatter.iso8601.string(from: endOfDay) // fallback
            
            // Re-using fetch logic, here fetching all schedules for user
            let fetched: [Schedule] = try await supabase
                .from("schedules")
                .select()
                .eq("user_id", value: currentUser.id)
                .order("start_time", ascending: true)
                .execute()
                .value
            
            // Filter locally for the selected day for simplicity in the MVP
            self.schedules = fetched.filter { schedule in
                calendar.isDate(schedule.startTime, inSameDayAs: selectedDate)
            }
            
        } catch {
            self.errorMessage = "Failed to load schedules: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

// Helper formatter
extension Formatter {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
