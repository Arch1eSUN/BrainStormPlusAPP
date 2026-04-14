import Foundation
import Supabase

@Observable
public final class AttendanceViewModel {
    public var currentAttendance: Attendance?
    public var isLoading = false
    public var errorMessage: String?
    
    // Internal date formatter for Supabase 'date' column
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
    
    @MainActor
    public func fetchTodayAttendance() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let session = try await supabase.auth.session
            let userId = session.user.id
            let todayStr = dateFormatter.string(from: Date())
            
            // Check if there is already a record for today
            let records: [Attendance] = try await supabase
                .from("attendance")
                .select()
                .eq("user_id", value: userId)
                .eq("date", value: todayStr)
                .execute()
                .value
            
            self.currentAttendance = records.first
        } catch {
            self.errorMessage = "Failed to fetch attendance: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    @MainActor
    public func toggleClockStatus() async {
        guard !isLoading else { return }
        
        if currentAttendance == nil {
            await clockIn()
        } else if currentAttendance?.clockOut == nil {
            await clockOut()
        } else {
            // Already clocked out
            self.errorMessage = "You have already clocked out for today."
        }
    }
    
    @MainActor
    private func clockIn() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let session = try await supabase.auth.session
            let userId = session.user.id
            let todayStr = dateFormatter.string(from: Date())
            
            struct InsertMode: Codable {
                let user_id: UUID
                let date: String
                let clock_in: Date
                let status: String
            }
            
            let newRecord = InsertMode(
                user_id: userId,
                date: todayStr,
                clock_in: Date(),
                status: "normal"
            )
            
            let result: Attendance = try await supabase
                .from("attendance")
                .insert(newRecord)
                .select()
                .single()
                .execute()
                .value
            
            self.currentAttendance = result
            HapticManager.shared.trigger(.heavy)
        } catch {
            self.errorMessage = "Clock in failed: \(error.localizedDescription)"
            HapticManager.shared.trigger(.error)
        }
        
        isLoading = false
    }
    
    @MainActor
    private func clockOut() async {
        guard let id = currentAttendance?.id else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            struct UpdateMode: Codable {
                let clock_out: Date
            }
            
            let result: Attendance = try await supabase
                .from("attendance")
                .update(UpdateMode(clock_out: Date()))
                .eq("id", value: id)
                .select()
                .single()
                .execute()
                .value
            
            self.currentAttendance = result
            HapticManager.shared.trigger(.success)
        } catch {
            self.errorMessage = "Clock out failed: \(error.localizedDescription)"
            HapticManager.shared.trigger(.error)
        }
        
        isLoading = false
    }
}
