import Foundation

// Web parity: BrainStorm+-Web/src/lib/actions/hiring/_shared.ts
// Table: candidates. Supports pipeline states new→screening→interview→
// offer→hired→onboarding→completed plus rejected. AI review result is
// persisted as a JSON string in `ai_summary` with `ai_score`.

public struct Candidate: Identifiable, Codable, Hashable {
    public let id: UUID
    public var positionId: UUID?
    public var fullName: String
    public var email: String?
    public var phone: String?
    public var resumeUrl: String?
    public var resumeText: String?
    public var aiScore: Int?
    public var aiSummary: String?
    public var status: CandidateStatus
    public var notes: String?
    public var createdBy: UUID?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var jobPositions: LinkedPosition?

    public enum CandidateStatus: String, Codable, CaseIterable, Hashable {
        case new
        case screening
        case interview
        case offer
        case hired
        case onboarding
        case completed
        case rejected

        public var displayLabel: String {
            switch self {
            case .new:        return "新申请"
            case .screening:  return "筛选中"
            case .interview:  return "面试中"
            case .offer:      return "已发 Offer"
            case .hired:      return "已入职"
            case .onboarding: return "入职中"
            case .completed:  return "已完成"
            case .rejected:   return "已拒绝"
            }
        }

        /// Recommended next-step transitions for the picker UI.
        /// Matches Web dropdown ordering (_lib/constants.ts CAND_STATUSES).
        public var allowedNext: [CandidateStatus] {
            switch self {
            case .new:        return [.screening, .rejected]
            case .screening:  return [.interview, .rejected]
            case .interview:  return [.offer, .rejected]
            case .offer:      return [.hired, .rejected]
            case .hired:      return [.onboarding, .rejected]
            case .onboarding: return [.completed]
            case .completed:  return []
            case .rejected:   return [.new]
            }
        }
    }

    public struct LinkedPosition: Codable, Hashable {
        public let title: String?
    }

    enum CodingKeys: String, CodingKey {
        case id
        case positionId = "position_id"
        case fullName = "full_name"
        case email
        case phone
        case resumeUrl = "resume_url"
        case resumeText = "resume_text"
        case aiScore = "ai_score"
        case aiSummary = "ai_summary"
        case status
        case notes
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case jobPositions = "job_positions"
    }
}

/// Decoded view of the JSON stored in `candidates.ai_summary` when
/// a resume review has been performed. The Web writer in
/// `reviewResumeWithAI` (candidates.ts:185-199) stringifies this shape.
public struct CandidateAIReview: Codable, Hashable {
    public let summary: String
    public let matchItems: [String]
    public let gapItems: [String]
    public let riskPoints: [String]
    public let manualReviewItems: [String]
    public let strengths: [String]
    public let concerns: [String]

    enum CodingKeys: String, CodingKey {
        case summary
        case matchItems = "match_items"
        case gapItems = "gap_items"
        case riskPoints = "risk_points"
        case manualReviewItems = "manual_review_items"
        case strengths
        case concerns
    }
}
