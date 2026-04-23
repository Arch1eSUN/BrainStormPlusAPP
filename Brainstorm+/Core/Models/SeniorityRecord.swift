import Foundation

// Web parity: BrainStorm+-Web/src/lib/actions/hiring/_shared.ts (SeniorityRecord)
// Table: seniority_records. Represents the hire-date + department + level
// history per user (one per year-of-service anchor).

public struct SeniorityRecord: Identifiable, Codable, Hashable {
    public let id: UUID
    public var userId: UUID?
    public var hireDate: String
    public var department: String?
    public var position: String?
    public var level: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var profiles: HiringContract.LinkedProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case hireDate = "hire_date"
        case department
        case position
        case level
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case profiles
    }
}
