import Foundation

public struct Project: Identifiable, Codable, Hashable {
    public let id: UUID
    public let name: String
    public let description: String?
    public let status: ProjectStatus
    public let ownerId: UUID?
    public let startDate: Date?
    public let endDate: Date?
    public let progress: Int
    public let createdAt: Date?
    public let updatedAt: Date?

    public enum ProjectStatus: String, Codable, Hashable {
        case planning = "planning"
        case active = "active"
        case onHold = "on_hold"
        case completed = "completed"
        case archived = "archived"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case status
        case ownerId = "owner_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case progress
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
