import Foundation

public struct Profile: Codable, Identifiable, Hashable {
    public let id: UUID
    public let fullName: String?
    public let displayName: String?
    public let email: String?
    public let avatarUrl: String?
    public let phone: String?
    public let position: String?
    public let department: String?
    public let role: String?
    public let status: String?
    public let capabilities: [String]?
    public let createdAt: Date?
    public let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case displayName = "display_name"
        case email
        case avatarUrl = "avatar_url"
        case phone
        case position
        case department
        case role
        case status
        case capabilities
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
