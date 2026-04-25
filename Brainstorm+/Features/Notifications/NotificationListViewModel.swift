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
            self.errorMessage = ErrorLocalizer.localize(error)
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
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }
    
    /// 标为未读 —— 反向 mutation。Web 没有这个 entry（Web 端只有
    /// markAsRead），但 iOS 长按菜单应支持反悔（iOS 26 Mail/Slack 习惯）。
    /// RLS：notifications 行级策略允许 user 修改 user_id == auth.uid() 的行。
    public func markAsUnread(_ notification: AppNotification) async {
        guard notification.isEffectivelyRead else { return }
        do {
            let updateData: [String: AnyJSON] = [
                "is_read": false,
                "read": false
            ]
            try await client
                .from("notifications")
                .update(updateData)
                .eq("id", value: notification.id)
                .execute()
            await fetchNotifications()
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    /// 删除单条通知（hard delete）。Web 端没有这个 surface ——
    /// 通知作为 ephemeral 提醒，删了即删了。RLS 同上。
    public func delete(_ notification: AppNotification) async {
        // 乐观先从 UI 移除，失败时 errorBanner 弹出再 refetch 还原。
        let snapshot = self.notifications
        self.notifications.removeAll { $0.id == notification.id }
        do {
            try await client
                .from("notifications")
                .delete()
                .eq("id", value: notification.id)
                .execute()
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
            self.notifications = snapshot
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
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }
}
