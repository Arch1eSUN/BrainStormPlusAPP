import Foundation

// ══════════════════════════════════════════════════════════════════
// Phase 2.1 — Deliverables port.
//
// Source of truth: BrainStorm+-Web/src/lib/actions/deliverables.ts
// + supabase/schema.sql::public.deliverables (+ migration 040 for the
// `url` column, + migration 001 for `org_id`).
//
// The Web page uses status keys { not_started, in_progress, submitted,
// accepted, revision }; the schema CHECK constraint also allows the
// legacy { pending, approved, rejected } keys from the initial schema.
// We keep all of them here so decoding never throws on older rows.
// ══════════════════════════════════════════════════════════════════

public struct Deliverable: Identifiable, Codable, Hashable {
    public let id: UUID
    public let title: String
    public let description: String?
    public let url: String?                  // migration 040 — pasted external link
    public let projectId: UUID?
    public let assigneeId: UUID?
    public let orgId: UUID?                  // migration 001
    public let dueDate: Date?
    public let status: DeliverableStatus
    public let submittedAt: Date?
    public let fileUrl: String?              // original schema column (kept for back-compat)
    public let createdAt: Date?
    public let updatedAt: Date?

    /// Nested join from `.select(..., projects:project_id(id, name))`.
    public let project: RelatedProject?
    /// Nested join from `.select(..., profiles:assignee_id(full_name, avatar_url))`.
    public let assignee: RelatedProfile?

    public enum DeliverableStatus: String, Codable, Hashable, CaseIterable {
        case notStarted = "not_started"
        case inProgress = "in_progress"
        case submitted = "submitted"
        case accepted = "accepted"
        case revision = "revision"
        // Legacy keys still allowed by the CHECK constraint.
        case pending = "pending"
        case approved = "approved"
        case rejected = "rejected"

        /// Chinese label — mirrors STATUS_CFG in
        /// `BrainStorm+-Web/src/app/dashboard/deliverables/page.tsx:15-21`.
        /// Legacy keys reuse the closest new-key label so the chip never
        /// shows a raw string.
        public var displayName: String {
            switch self {
            case .notStarted: return "未开始"
            case .inProgress: return "进行中"
            case .submitted:  return "已提交"
            case .accepted:   return "已验收"
            case .revision:   return "需修改"
            case .pending:    return "未开始"
            case .approved:   return "已验收"
            case .rejected:   return "需修改"
            }
        }

        /// The five statuses Web actually surfaces in the edit form +
        /// filter chips. Used by the iOS list filter bar and the detail
        /// status picker.
        public static var primaryCases: [DeliverableStatus] {
            [.notStarted, .inProgress, .submitted, .accepted, .revision]
        }
    }

    public struct RelatedProject: Codable, Hashable {
        public let id: UUID?
        public let name: String?
    }

    public struct RelatedProfile: Codable, Hashable {
        public let id: UUID?
        public let fullName: String?
        public let avatarUrl: String?

        enum CodingKeys: String, CodingKey {
            case id
            case fullName = "full_name"
            case avatarUrl = "avatar_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case url
        case projectId = "project_id"
        case assigneeId = "assignee_id"
        case orgId = "org_id"
        case dueDate = "due_date"
        case status
        case submittedAt = "submitted_at"
        case fileUrl = "file_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case project = "projects"
        case assignee = "profiles"
    }
}
