import Foundation

// ══════════════════════════════════════════════════════════════════
// MonthlyEvaluation — iOS 侧 DTO
// Parity target: Web `src/lib/actions/user-evaluations.ts`
//   - EvaluationRow（数据库行）
//   - MonthlyMatrixRow（矩阵行 = profile + 可空 evaluation）
//
// DB 约束（来自 058_user_monthly_evaluations.sql）：
//   - month TEXT 格式 `YYYY-MM`
//   - 唯一键 (user_id, month)；重跑覆盖
//   - overall_score NOT NULL 1-100；五维可空 = 该维度数据不足
//   - triggered_by ∈ {manual, cron}
//   - evidence JSONB 解码到 iOS 里保留原始字符串供详情展示
// ══════════════════════════════════════════════════════════════════

public struct MonthlyEvaluation: Decodable, Hashable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let month: String
    public let overallScore: Int?
    public let scoreAttendance: Int?
    public let scoreDelivery: Int?
    public let scoreCollaboration: Int?
    public let scoreReporting: Int?
    public let scoreGrowth: Int?
    public let narrative: String?
    public let riskFlags: [String]?
    public let requiresManualReview: Bool
    public let triggeredBy: String?
    public let modelUsed: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case month
        case overallScore = "overall_score"
        case scoreAttendance = "score_attendance"
        case scoreDelivery = "score_delivery"
        case scoreCollaboration = "score_collaboration"
        case scoreReporting = "score_reporting"
        case scoreGrowth = "score_growth"
        case narrative
        case riskFlags = "risk_flags"
        case requiresManualReview = "requires_manual_review"
        case triggeredBy = "triggered_by"
        case modelUsed = "model_used"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct MonthlyMatrixRow: Hashable, Identifiable {
    public let userId: UUID
    public let fullName: String
    public let department: String?
    public let primaryRole: String       // employee / admin / superadmin (mapped from legacy role)
    public var evaluation: MonthlyEvaluation?

    public var id: UUID { userId }

    public var displayName: String { fullName.isEmpty ? "未命名" : fullName }
}

public enum MonthlyEvaluationStatus: String, CaseIterable, Identifiable {
    case all
    case pending
    case evaluated
    case reviewRequired

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "全部"
        case .pending: return "待评"
        case .evaluated: return "已评"
        case .reviewRequired: return "需复核"
        }
    }
}
