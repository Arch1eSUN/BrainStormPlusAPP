import Foundation

public struct Schedule: Codable, Identifiable, Hashable {
    public let id: UUID
    public let userId: UUID
    public let title: String
    public let description: String?
    public let startTime: Date
    public let endTime: Date
    public let date: String? // DATE in SQL, usually maps to string "YYYY-MM-DD"
    public let shiftStart: String? // TIME in SQL
    public let shiftEnd: String? // TIME in SQL
    public let shiftType: String?
    public let location: String?
    public let type: String? // 'work', 'meeting', 'training', 'other'
    public let status: String? // 'scheduled', 'completed', 'cancelled'
    public let createdBy: UUID?
    public let createdAt: Date?
    public let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case description
        case startTime = "start_time"
        case endTime = "end_time"
        case date
        case shiftStart = "shift_start"
        case shiftEnd = "shift_end"
        case shiftType = "shift_type"
        case location
        case type
        case status
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
