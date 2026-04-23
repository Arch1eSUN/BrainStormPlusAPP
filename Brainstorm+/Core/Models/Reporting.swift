import Foundation

// ══════════════════════════════════════════════════════════════════
// Batch B.1 — Reporting models aligned with Web schema.
//
// Schema reference:
//   supabase/schema.sql (daily_logs + weekly_reports)
//   migrations/011_cross_module_linkage.sql (project_id / task_ids /
//     progress / blockers / project_ids / task_summary_data /
//     highlights / challenges)
//   migrations/033_approval_request_report.sql (approval_status join)
//
// Web note (2026-04-21): daily_logs & weekly_reports no longer go
// through approval_requests for *new* rows, but historical rows still
// have entries in approval_request_report. `approvalStatus` is NOT a
// column on either table — it is denormalised on the server
// (see src/lib/actions/daily-logs.ts ≈ line 85 and
// weekly-reports.ts ≈ line 92) from the join table. We accept it from
// the decoder so the VM can populate it client-side too.
// ══════════════════════════════════════════════════════════════════

public enum ReportApprovalStatus: String, Codable, Hashable {
    case pending
    case approved
    case rejected
}

public struct DailyLog: Identifiable, Codable, Hashable {
    public let id: UUID
    public let userId: UUID
    public var orgId: UUID?
    public var date: Date
    public var content: String
    public var mood: Mood?

    // Cross-module linkage (migration 011)
    public var projectId: UUID?
    public var taskIds: [UUID]
    public var progress: String?
    public var blockers: String?

    // Denormalised, not a stored column — populated by the VM after a
    // separate query to `approval_request_report`.
    public var approvalStatus: ReportApprovalStatus?

    public let createdAt: Date?
    public let updatedAt: Date?

    public enum Mood: String, Codable, Hashable, CaseIterable, Identifiable {
        case great
        case good
        case okay
        case bad

        public var id: String { rawValue }

        public var displayLabel: String {
            switch self {
            case .great: return "很好"
            case .good:  return "不错"
            case .okay:  return "一般"
            case .bad:   return "不好"
            }
        }

        public var emoji: String {
            switch self {
            case .great: return "🤩"
            case .good:  return "😊"
            case .okay:  return "😐"
            case .bad:   return "😔"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case orgId = "org_id"
        case date
        case content
        case mood
        case projectId = "project_id"
        case taskIds = "task_ids"
        case progress
        case blockers
        case approvalStatus = "approval_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: UUID,
        userId: UUID,
        orgId: UUID? = nil,
        date: Date,
        content: String,
        mood: Mood? = nil,
        projectId: UUID? = nil,
        taskIds: [UUID] = [],
        progress: String? = nil,
        blockers: String? = nil,
        approvalStatus: ReportApprovalStatus? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.orgId = orgId
        self.date = date
        self.content = content
        self.mood = mood
        self.projectId = projectId
        self.taskIds = taskIds
        self.progress = progress
        self.blockers = blockers
        self.approvalStatus = approvalStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.userId = try c.decode(UUID.self, forKey: .userId)
        self.orgId = try c.decodeIfPresent(UUID.self, forKey: .orgId)
        self.date = try c.decode(Date.self, forKey: .date)
        self.content = try c.decode(String.self, forKey: .content)
        self.mood = try c.decodeIfPresent(Mood.self, forKey: .mood)
        self.projectId = try c.decodeIfPresent(UUID.self, forKey: .projectId)
        self.taskIds = (try c.decodeIfPresent([UUID].self, forKey: .taskIds)) ?? []
        self.progress = try c.decodeIfPresent(String.self, forKey: .progress)
        self.blockers = try c.decodeIfPresent(String.self, forKey: .blockers)
        self.approvalStatus = try c.decodeIfPresent(ReportApprovalStatus.self, forKey: .approvalStatus)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

public struct WeeklyReport: Identifiable, Codable, Hashable {
    public let id: UUID
    public let userId: UUID
    public var orgId: UUID?

    // Web column is `week_start` (not `week_start_date`). The old
    // `weekStartDate` property name is kept as a computed alias for
    // any legacy call sites that still reference it.
    public var weekStart: Date
    public var weekEnd: Date?

    public var summary: String?
    public var accomplishments: String?
    public var plans: String?
    public var blockers: String?
    public var highlights: String?
    public var challenges: String?

    // Cross-module (migration 011)
    public var projectIds: [UUID]
    public var taskSummaryData: TaskSummaryData?

    // Lifecycle (schema.sql)
    public var status: ReportStatus
    public var reviewerId: UUID?
    public var reviewedAt: Date?

    // Web column on weekly_reports is `feedback` (see schema.sql ≈ L162).
    // We surface it as both `feedback` and the legacy iOS name
    // `reviewerNotes` for call-site compatibility.
    public var feedback: String?

    // Denormalised — see note on DailyLog.approvalStatus
    public var approvalStatus: ReportApprovalStatus?

    public let createdAt: Date?
    public let updatedAt: Date?

    public enum ReportStatus: String, Codable, Hashable {
        case draft
        case submitted
        case reviewed
    }

    /// Web `weekly_reports.task_summary_data` is stored as JSONB.
    public struct TaskSummaryData: Codable, Hashable {
        public var tasks: [TaskSnapshot]
        public var total: Int
        public var done: Int

        public init(tasks: [TaskSnapshot] = [], total: Int = 0, done: Int = 0) {
            self.tasks = tasks
            self.total = total
            self.done = done
        }
    }

    public struct TaskSnapshot: Codable, Hashable, Identifiable {
        public let id: UUID
        public var title: String
        public var status: String
        public var priority: String

        public init(id: UUID, title: String, status: String, priority: String) {
            self.id = id
            self.title = title
            self.status = status
            self.priority = priority
        }
    }

    /// Legacy alias — prefer `weekStart`.
    public var weekStartDate: Date { weekStart }
    /// Legacy alias — prefer `feedback`.
    public var reviewerNotes: String? { feedback }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case orgId = "org_id"
        case weekStart = "week_start"
        case weekEnd = "week_end"
        case summary
        case accomplishments
        case plans
        case blockers
        case highlights
        case challenges
        case projectIds = "project_ids"
        case taskSummaryData = "task_summary_data"
        case status
        case reviewerId = "reviewer_id"
        case reviewedAt = "reviewed_at"
        case feedback
        case approvalStatus = "approval_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: UUID,
        userId: UUID,
        orgId: UUID? = nil,
        weekStart: Date,
        weekEnd: Date? = nil,
        summary: String? = nil,
        accomplishments: String? = nil,
        plans: String? = nil,
        blockers: String? = nil,
        highlights: String? = nil,
        challenges: String? = nil,
        projectIds: [UUID] = [],
        taskSummaryData: TaskSummaryData? = nil,
        status: ReportStatus = .draft,
        reviewerId: UUID? = nil,
        reviewedAt: Date? = nil,
        feedback: String? = nil,
        approvalStatus: ReportApprovalStatus? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.orgId = orgId
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.summary = summary
        self.accomplishments = accomplishments
        self.plans = plans
        self.blockers = blockers
        self.highlights = highlights
        self.challenges = challenges
        self.projectIds = projectIds
        self.taskSummaryData = taskSummaryData
        self.status = status
        self.reviewerId = reviewerId
        self.reviewedAt = reviewedAt
        self.feedback = feedback
        self.approvalStatus = approvalStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.userId = try c.decode(UUID.self, forKey: .userId)
        self.orgId = try c.decodeIfPresent(UUID.self, forKey: .orgId)
        self.weekStart = try c.decode(Date.self, forKey: .weekStart)
        self.weekEnd = try c.decodeIfPresent(Date.self, forKey: .weekEnd)
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary)
        self.accomplishments = try c.decodeIfPresent(String.self, forKey: .accomplishments)
        self.plans = try c.decodeIfPresent(String.self, forKey: .plans)
        self.blockers = try c.decodeIfPresent(String.self, forKey: .blockers)
        self.highlights = try c.decodeIfPresent(String.self, forKey: .highlights)
        self.challenges = try c.decodeIfPresent(String.self, forKey: .challenges)
        self.projectIds = (try c.decodeIfPresent([UUID].self, forKey: .projectIds)) ?? []
        self.taskSummaryData = try c.decodeIfPresent(TaskSummaryData.self, forKey: .taskSummaryData)
        self.status = (try c.decodeIfPresent(ReportStatus.self, forKey: .status)) ?? .draft
        self.reviewerId = try c.decodeIfPresent(UUID.self, forKey: .reviewerId)
        self.reviewedAt = try c.decodeIfPresent(Date.self, forKey: .reviewedAt)
        self.feedback = try c.decodeIfPresent(String.self, forKey: .feedback)
        self.approvalStatus = try c.decodeIfPresent(ReportApprovalStatus.self, forKey: .approvalStatus)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}
