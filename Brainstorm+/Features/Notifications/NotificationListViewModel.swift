import Foundation
import Combine
import Supabase

@MainActor
public class NotificationListViewModel: ObservableObject {
    @Published public var notifications: [AppNotification] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    private let client: SupabaseClient
    
    public init(client: SupabaseClient) {
        self.client = client
    }
    
    public func fetchNotifications() async {
        isLoading = true
        errorMessage = nil
        do {
            let session = try await client.auth.session
            let currentUserId = session.user.id
            
            self.notifications = try await client
                .from("notifications")
                .select()
                .eq("user_id", value: currentUserId)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    public func markAsRead(_ notification: AppNotification) async {
        guard !notification.isEffectivelyRead else { return }
        
        do {
            // Update both fields to be safe against schema changes
            let updateData: [String: AnyJSON] = [
                "is_read": true,
                "read": true
            ]
            
            try await client
                .from("notifications")
                .update(updateData)
                .eq("id", value: notification.id)
                .execute()
            
            // Optimistic update
            if let index = self.notifications.firstIndex(where: { $0.id == notification.id }) {
                // Since AppNotification is a struct, we need to create a new one to update it,
                // but due to Codable strictness we will just re-fetch for safety or ignore optimistic updates for now in this MVP
                await fetchNotifications()
            }
            
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    public func markAllAsRead() async {
        do {
            let session = try await client.auth.session
            let currentUserId = session.user.id
            
            let updateData: [String: AnyJSON] = [
                "is_read": true,
                "read": true
            ]
            
            try await client
                .from("notifications")
                .update(updateData)
                .eq("user_id", value: currentUserId)
                .eq("is_read", value: false)
                .execute()
                
            await fetchNotifications()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
