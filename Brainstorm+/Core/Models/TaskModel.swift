import Foundation

public struct TaskModel: Identifiable, Codable, Hashable {
    public let id: UUID
    public let title: String
    public let description: String?
    public let status: TaskStatus
    public let priority: TaskPriority
    public let projectId: UUID?
    public let assigneeId: UUID?
    public let dueDate: Date?
    public let createdAt: Date?
    public let updatedAt: Date?

    public enum TaskStatus: String, Codable, Hashable {
        case todo = "todo"
        case inProgress = "in_progress"
        case inReview = "in_review"
        case done = "done"
        case canceled = "canceled"
    }

    public enum TaskPriority: String, Codable, Hashable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case urgent = "urgent"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case status
        case priority
        case projectId = "project_id"
        case assigneeId = "assignee_id"
        case dueDate = "due_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
