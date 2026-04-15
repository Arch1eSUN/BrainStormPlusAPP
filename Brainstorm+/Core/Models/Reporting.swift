import Foundation

public struct DailyLog: Identifiable, Codable, Hashable {
    public let id: UUID
    public let userId: UUID
    public let date: Date
    public let content: String
    public let mood: Mood?
    public let createdAt: Date?
    public let updatedAt: Date?

    public enum Mood: String, Codable, Hashable {
        case great = "great"
        case good = "good"
        case okay = "okay"
        case bad = "bad"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case content
        case mood
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct WeeklyReport: Identifiable, Codable, Hashable {
    public let id: UUID
    public let userId: UUID
    public let weekStartDate: Date
    public let content: String
    public let status: ReportStatus
    public let reviewerId: UUID?
    public let reviewedAt: Date?
    public let reviewerNotes: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    public enum ReportStatus: String, Codable, Hashable {
        case draft = "draft"
        case submitted = "submitted"
        case reviewed = "reviewed"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case weekStartDate = "week_start_date"
        case content
        case status
        case reviewerId = "reviewer_id"
        case reviewedAt = "reviewed_at"
        case reviewerNotes = "reviewer_notes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
