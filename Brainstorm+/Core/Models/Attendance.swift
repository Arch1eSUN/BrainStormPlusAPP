import Foundation

public struct Attendance: Codable, Identifiable, Hashable {
    public let id: UUID
    public let userId: UUID
    public let date: String // e.g., "YYYY-MM-DD"
    public var clockIn: Date?
    public var clockOut: Date?
    public var status: String?
    public var notes: String?
    public var workHours: Double?
    public var lateMinutes: Int?
    public var isFieldWork: Bool?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case clockIn = "clock_in"
        case clockOut = "clock_out"
        case status
        case notes
        case workHours = "work_hours"
        case lateMinutes = "late_minutes"
        case isFieldWork = "is_field_work"
        case createdAt = "created_at"
    }
}
