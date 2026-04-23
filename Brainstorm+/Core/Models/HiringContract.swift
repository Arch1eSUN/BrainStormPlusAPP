import Foundation

// Web parity: BrainStorm+-Web/src/lib/actions/hiring/_shared.ts (Contract)
// Named `HiringContract` on iOS to avoid colliding with Swift's
// protocol-composition tooling that surfaces `Contract` in autocomplete.

public struct HiringContract: Identifiable, Codable, Hashable {
    public let id: UUID
    public var userId: UUID?
    public var contractType: ContractType
    public var startDate: String
    public var endDate: String?
    public var salary: Double?
    public var status: ContractStatus
    public var documentUrl: String?
    public var notes: String?
    public var createdBy: UUID?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var profiles: LinkedProfile?

    public enum ContractType: String, Codable, CaseIterable, Hashable {
        case permanent
        case fixedTerm = "fixed_term"
        case probation
        case internship

        public var displayLabel: String {
            switch self {
            case .permanent:  return "正式合同"
            case .fixedTerm:  return "固定期限"
            case .probation:  return "试用期"
            case .internship: return "实习"
            }
        }
    }

    public enum ContractStatus: String, Codable, CaseIterable, Hashable {
        case active
        case pending
        case expired
        case terminated

        public var displayLabel: String {
            switch self {
            case .active:     return "生效中"
            case .pending:    return "待生效"
            case .expired:    return "已到期"
            case .terminated: return "已终止"
            }
        }
    }

    public struct LinkedProfile: Codable, Hashable {
        public let fullName: String?
        public let displayName: String?

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case displayName = "display_name"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case contractType = "contract_type"
        case startDate = "start_date"
        case endDate = "end_date"
        case salary
        case status
        case documentUrl = "document_url"
        case notes
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case profiles
    }
}
