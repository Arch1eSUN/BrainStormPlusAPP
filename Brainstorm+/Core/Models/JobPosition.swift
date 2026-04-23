import Foundation

// Web parity: BrainStorm+-Web/src/lib/actions/hiring/_shared.ts
// Table: job_positions — includes status lifecycle and employment type.

public struct JobPosition: Identifiable, Codable, Hashable {
    public let id: UUID
    public var title: String
    public var department: String?
    public var description: String?
    public var requirements: String?
    public var salaryRange: String?
    public var employmentType: EmploymentType
    public var status: PositionStatus
    public var createdBy: UUID?
    public var createdAt: Date?
    public var updatedAt: Date?

    public enum PositionStatus: String, Codable, CaseIterable, Hashable {
        case open
        case onHold = "on_hold"
        case filled
        case closed

        public var displayLabel: String {
            switch self {
            case .open:    return "招聘中"
            case .onHold:  return "暂停"
            case .filled:  return "已满员"
            case .closed:  return "已关闭"
            }
        }
    }

    public enum EmploymentType: String, Codable, CaseIterable, Hashable {
        case fullTime = "full_time"
        case partTime = "part_time"
        case contract
        case internship

        public var displayLabel: String {
            switch self {
            case .fullTime:   return "全职"
            case .partTime:   return "兼职"
            case .contract:   return "合同工"
            case .internship: return "实习"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case department
        case description
        case requirements
        case salaryRange = "salary_range"
        case employmentType = "employment_type"
        case status
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
