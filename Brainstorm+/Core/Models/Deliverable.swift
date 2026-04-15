import Foundation

public struct Deliverable: Identifiable, Codable, Hashable {
    public let id: UUID
    public let title: String
    public let description: String?
    public let projectId: UUID?
    public let assigneeId: UUID?
    public let dueDate: Date?
    public let status: DeliverableStatus
    public let submittedAt: Date?
    public let fileUrl: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    public enum DeliverableStatus: String, Codable, Hashable {
        case pending = "pending"
        case inProgress = "in_progress"
        case submitted = "submitted"
        case approved = "approved"
        case rejected = "rejected"
        case notStarted = "not_started"
        case accepted = "accepted"
        case revision = "revision"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case projectId = "project_id"
        case assigneeId = "assignee_id"
        case dueDate = "due_date"
        case status
        case submittedAt = "submitted_at"
        case fileUrl = "file_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
