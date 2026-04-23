import Foundation

public struct TaskModel: Identifiable, Codable, Hashable {
    public let id: UUID
    public let title: String
    public let description: String?
    public let status: TaskStatus
    public let priority: TaskPriority
    public let projectId: UUID?
    public let assigneeId: UUID?
    public let ownerId: UUID?
    public let reporterId: UUID?
    public let progress: Int
    public let participants: [UUID]
    public let project: EmbeddedProject?
    public let dueDate: Date?
    public let createdAt: Date?
    public let updatedAt: Date?

    public enum TaskStatus: String, Codable, Hashable {
        case todo = "todo"
        case inProgress = "in_progress"
        case review = "review"
        case done = "done"
    }

    public enum TaskPriority: String, Codable, Hashable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case urgent = "urgent"
    }

    // Embedded shape from Supabase `projects:project_id(id,name)` join.
    // Mirrors Web's `projects?: { name: string } | null` (tasks.ts:34), extended
    // with `id` to match the iOS-scope spec `projects(id,name)` embed.
    public struct EmbeddedProject: Codable, Hashable {
        public let id: UUID?
        public let name: String
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case status
        case priority
        case projectId = "project_id"
        case assigneeId = "assignee_id"
        case ownerId = "owner_id"
        case reporterId = "reporter_id"
        case progress
        case taskParticipants = "task_participants"
        case projects
        case dueDate = "due_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Nested row coming back from the `task_participants(user_id, role, ...)` join.
    private struct ParticipantRow: Codable {
        let user_id: UUID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.status = try c.decode(TaskStatus.self, forKey: .status)
        self.priority = try c.decode(TaskPriority.self, forKey: .priority)
        self.projectId = try c.decodeIfPresent(UUID.self, forKey: .projectId)
        self.assigneeId = try c.decodeIfPresent(UUID.self, forKey: .assigneeId)
        self.ownerId = try c.decodeIfPresent(UUID.self, forKey: .ownerId)
        self.reporterId = try c.decodeIfPresent(UUID.self, forKey: .reporterId)
        self.progress = try c.decodeIfPresent(Int.self, forKey: .progress) ?? 0
        self.project = try c.decodeIfPresent(EmbeddedProject.self, forKey: .projects)
        let rows = try c.decodeIfPresent([ParticipantRow].self, forKey: .taskParticipants) ?? []
        self.participants = rows.map { $0.user_id }
        self.dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(status, forKey: .status)
        try c.encode(priority, forKey: .priority)
        try c.encodeIfPresent(projectId, forKey: .projectId)
        try c.encodeIfPresent(assigneeId, forKey: .assigneeId)
        try c.encodeIfPresent(ownerId, forKey: .ownerId)
        try c.encodeIfPresent(reporterId, forKey: .reporterId)
        try c.encode(progress, forKey: .progress)
        try c.encodeIfPresent(project, forKey: .projects)
        try c.encodeIfPresent(dueDate, forKey: .dueDate)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}
