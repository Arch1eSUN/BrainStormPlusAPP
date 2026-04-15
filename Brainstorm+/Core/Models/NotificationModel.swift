import Foundation

public struct AppNotification: Identifiable, Codable, Hashable {
    public let id: UUID
    public let userId: UUID
    public let title: String
    public let body: String?
    public let message: String?
    public let type: NotificationType
    public let link: String?
    public let isRead: Bool
    public let read: Bool?
    public let createdAt: Date?

    public enum NotificationType: String, Codable, Hashable {
        case info = "info"
        case success = "success"
        case warning = "warning"
        case error = "error"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case body
        case message
        case type
        case link
        case isRead = "is_read"
        case read
        case createdAt = "created_at"
    }
    
    // Helper to get the actual content regardless of the migration state
    public var displayMessage: String {
        return body ?? message ?? ""
    }
    
    // Helper to get actual read state
    public var isEffectivelyRead: Bool {
        return read ?? isRead
    }
}
