import Foundation

/// Mirrors Web's `Objective` type in `BrainStorm+-Web/src/lib/actions/okr.ts`
/// and the `public.objectives` table (Web schema: `supabase/schema.sql:100-110`
/// + migrations `004_schema_alignment.sql:37` adding `org_id`,
/// `019_kpi_performance_reviews.sql:8-10` adding `status` + `assignee_id`).
///
/// Fields NOT surfaced on iOS for this read-only pass:
/// - `org_id` — scoping is enforced server-side by RLS + insert policy
/// - `updated_at` — list/detail only show `created_at`
/// - `description` — surfaced via detail, optional in list
public struct Objective: Identifiable, Codable, Hashable {
    public let id: UUID
    public let title: String
    public let description: String?
    public let ownerId: UUID?
    public let assigneeId: UUID?
    public let period: String?
    public let status: ObjectiveStatus
    /// Web stores a denormalized `progress` integer on `objectives`, but both
    /// Web's list and iOS recompute it as the mean of its KRs' `current/target`
    /// to avoid relying on a stale cache. Kept here for forward-compat.
    public let progress: Int
    public let createdAt: Date?

    /// Embedded child rows when the caller selects `objectives(*, key_results(*))`.
    /// Nil when the query didn't embed KRs; empty array when the KR list is
    /// legitimately empty for this objective.
    public let keyResults: [KeyResult]?

    public enum ObjectiveStatus: String, Codable, Hashable {
        case draft
        case active
        case completed
        case cancelled

        /// Chinese label matching Web's `STATUS_CFG` in
        /// `BrainStorm+-Web/src/app/dashboard/okr/page.tsx:16-21`.
        public var displayLabel: String {
            switch self {
            case .draft: return "草稿"
            case .active: return "进行中"
            case .completed: return "已完成"
            case .cancelled: return "已取消"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case ownerId = "owner_id"
        case assigneeId = "assignee_id"
        case period
        case status
        case progress
        case createdAt = "created_at"
        case keyResults = "key_results"
    }

    /// Custom decoder: Web's `progress` column is nullable in older rows and
    /// status may come back as an unknown string if a newer web-side migration
    /// lands before iOS catches up — we soft-default rather than crash.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.ownerId = try c.decodeIfPresent(UUID.self, forKey: .ownerId)
        self.assigneeId = try c.decodeIfPresent(UUID.self, forKey: .assigneeId)
        self.period = try c.decodeIfPresent(String.self, forKey: .period)
        let rawStatus = try c.decodeIfPresent(String.self, forKey: .status) ?? "active"
        self.status = ObjectiveStatus(rawValue: rawStatus) ?? .active
        self.progress = try c.decodeIfPresent(Int.self, forKey: .progress) ?? 0
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        self.keyResults = try c.decodeIfPresent([KeyResult].self, forKey: .keyResults)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(ownerId, forKey: .ownerId)
        try c.encodeIfPresent(assigneeId, forKey: .assigneeId)
        try c.encodeIfPresent(period, forKey: .period)
        try c.encode(status.rawValue, forKey: .status)
        try c.encode(progress, forKey: .progress)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(keyResults, forKey: .keyResults)
    }

    // MARK: - Derived

    /// Computed progress = mean of each KR's `current/target * 100`, capped at 100.
    /// Mirrors Web `page.tsx:172-176` + `fetchOkrStats` in
    /// `BrainStorm+-Web/src/lib/actions/okr.ts:128-135`. Returns the persisted
    /// `progress` column when no KRs are embedded (e.g. list without join).
    public var computedProgress: Int {
        guard let krs = keyResults else { return progress }
        if krs.isEmpty { return 0 }
        let sum = krs.reduce(0.0) { acc, kr in
            guard kr.targetValue > 0 else { return acc }
            return acc + (kr.currentValue / kr.targetValue) * 100
        }
        return min(Int((sum / Double(krs.count)).rounded()), 100)
    }
}
