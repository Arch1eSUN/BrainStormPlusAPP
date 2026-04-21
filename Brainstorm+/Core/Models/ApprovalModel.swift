import Foundation

// ══════════════════════════════════════════════════
// Approvals iOS domain types — Sprint 4.1 foundation
//
// Mirrors the narrower shape of Web's "我提交的" list view
// (`src/app/dashboard/approval/_tabs/my-submissions.tsx`), not the full
// `src/lib/approvals/types.ts` catalog. See
// `docs/parity/56-approvals-foundation-scope.md` for the sprint split
// and carry-forward items (reimbursement / procurement detail types,
// approver queue, approve/reject write paths etc. arrive in 4.2+).
// ══════════════════════════════════════════════════

/// Row type returned by the `listMySubmissions` read path. Field set is a
/// strict subset of `approval_requests` + a nested 1:1 left-join into
/// `approval_request_leave`.
///
/// Web source of truth: `src/lib/actions/approval-requests.ts:540-621
/// MySubmissionRow`. We keep field names in Swift camelCase and map to
/// snake_case via `CodingKeys`, same pattern as every other model in this
/// project (Projects, Chat, Attendance, etc).
public struct ApprovalMySubmissionRow: Identifiable, Codable, Hashable {
    public let id: UUID
    public let requestType: ApprovalRequestType
    public let status: ApprovalStatus
    public let priorityByRequester: RequestPriority
    public let businessReason: String?
    public let reviewerNote: String?
    public let reviewedAt: Date?
    public let createdAt: Date
    /// PostgREST emits the nested select as either an object or a 1-element
    /// array, depending on whether the FK declares `is unique`. We store an
    /// array and read `.first` — matches the defensive handling in Web's
    /// `my-submissions` mapping (approval-requests.ts:596-614).
    public let leaveDetails: [ApprovalLeaveDetail]

    enum CodingKeys: String, CodingKey {
        case id
        case requestType = "request_type"
        case status
        case priorityByRequester = "priority_by_requester"
        case businessReason = "business_reason"
        case reviewerNote = "reviewer_note"
        case reviewedAt = "reviewed_at"
        case createdAt = "created_at"
        case leaveDetails = "approval_request_leave"
    }

    /// Convenience accessor — 4.1's row preview only needs the single
    /// matched detail row (schema is 1:1 on `request_id`, defensive array
    /// handling notwithstanding).
    public var leave: ApprovalLeaveDetail? { leaveDetails.first }

    /// Resilient decoder: the nested field may be a single object, a
    /// JSON array, or missing entirely. Normalize to `[]` for the callsite.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.requestType = try container.decode(ApprovalRequestType.self, forKey: .requestType)
        self.status = try container.decode(ApprovalStatus.self, forKey: .status)
        self.priorityByRequester = try container.decode(RequestPriority.self, forKey: .priorityByRequester)
        self.businessReason = try container.decodeIfPresent(String.self, forKey: .businessReason)
        self.reviewerNote = try container.decodeIfPresent(String.self, forKey: .reviewerNote)
        self.reviewedAt = try container.decodeIfPresent(Date.self, forKey: .reviewedAt)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)

        // Nested decode — three accepted shapes.
        if let array = try? container.decodeIfPresent([ApprovalLeaveDetail].self, forKey: .leaveDetails) {
            self.leaveDetails = array
        } else if let single = try? container.decodeIfPresent(ApprovalLeaveDetail.self, forKey: .leaveDetails) {
            self.leaveDetails = [single]
        } else {
            self.leaveDetails = []
        }
    }
}

/// Narrow projection of `approval_request_leave`. 4.1 only needs the four
/// row-preview fields; 4.2's detail sprint will widen this into a full
/// `ApprovalLeaveRequestDetail` model.
public struct ApprovalLeaveDetail: Codable, Hashable {
    public let leaveType: LeaveType
    public let startDate: String  // ISO date "YYYY-MM-DD", kept as String because Supabase returns `date` columns unquoted and the default ISO8601 formatter expects a time component. Attendance.swift uses the same convention.
    public let endDate: String
    public let days: Double       // DB column is `numeric`, Swift decodes as Double; Web's `Number(leaveDetail.days)` coerces from any numeric.

    enum CodingKeys: String, CodingKey {
        case leaveType = "leave_type"
        case startDate = "start_date"
        case endDate = "end_date"
        case days
    }
}

// ─── Enum types ──────────────────────────────────────────────

/// Subset of Web's `ApprovalRequestType` (types.ts:8-13) that actually
/// shows up in "我提交的" rows. `field_work` / `business_trip` /
/// `daily_log` / `weekly_report` / `recruitment` / `revoke_comp_time`
/// are surfaced via Web's broader routing enum (`lib/approval/routing.ts`)
/// but the user-submission list only displays the six below. We use
/// `unknown` as an escape hatch so a DB row carrying an unexpected
/// request_type doesn't crash decode — matches the `TYPE_LABEL[r.request_type]
/// ?? r.request_type` fallback in Web `my-submissions.tsx:123-125`.
public enum ApprovalRequestType: String, Codable, Hashable {
    case leave
    case fieldWork = "field_work"
    case businessTrip = "business_trip"
    case reimbursement
    case procurement
    case generic
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ApprovalRequestType(rawValue: raw) ?? .unknown
    }

    /// Chinese label matching Web `my-submissions.tsx:15-22 TYPE_LABEL`.
    /// For types we've never rendered in Web's row (but might exist in the
    /// DB) fall back to the raw value.
    public var displayLabel: String {
        switch self {
        case .leave:        return "请假"
        case .fieldWork:    return "外勤"
        case .businessTrip: return "出差"
        case .reimbursement: return "报销"
        case .procurement:  return "采购"
        case .generic:      return "通用"
        case .unknown:      return "未知类型"
        }
    }
}

/// Web `ApprovalStatus` (types.ts:15-21) declares 6 states, but the
/// "我提交的" tab only surfaces 5 chip variants (my-submissions.tsx:24-30).
/// We keep a slightly broader iOS enum to be robust against rows carrying
/// `draft` or `needs_revision` — they'll display with their raw string and
/// default gray tint. Same escape-hatch posture as `request_type`.
public enum ApprovalStatus: String, Codable, Hashable {
    case draft
    case pending
    case approved
    case rejected
    case withdrawn
    case cancelled
    case revoked
    case needsRevision = "needs_revision"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ApprovalStatus(rawValue: raw) ?? .unknown
    }

    /// Chinese label + semantic bucket. Bucket drives the chip tint at the
    /// view layer without hard-coding a Color here (keeping Core/Models
    /// View-framework-free).
    public var displayLabel: String {
        switch self {
        case .draft:         return "草稿"
        case .pending:       return "待审批"
        case .approved:      return "已通过"
        case .rejected:      return "已拒绝"
        case .withdrawn:     return "已撤回"
        case .cancelled:     return "已取消"
        case .revoked:       return "已撤回"   // Web uses 已撤回 for both cancelled/revoked per my-submissions.tsx:28-29
        case .needsRevision: return "需修改"
        case .unknown:       return "未知状态"
        }
    }

    public enum Tone { case warning, success, danger, neutral, info }

    public var tone: Tone {
        switch self {
        case .pending, .needsRevision: return .warning
        case .approved:                return .success
        case .rejected:                return .danger
        case .draft, .withdrawn, .cancelled, .revoked, .unknown: return .neutral
        }
    }
}

/// Web `RequestPriority` (types.ts:23). Not rendered in the 4.1 row but
/// decoded so the field can flow through to the 4.2 detail sprint
/// without re-migrating the model.
public enum RequestPriority: String, Codable, Hashable {
    case low, medium, high, urgent
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RequestPriority(rawValue: raw) ?? .unknown
    }
}

/// Web `LeaveType` (types.ts:53). Same escape-hatch decoder pattern.
public enum LeaveType: String, Codable, Hashable {
    case annual
    case sick
    case personal
    case compTime = "comp_time"
    case maternity
    case paternity
    case bereavement
    case other
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LeaveType(rawValue: raw) ?? .unknown
    }

    /// Short Chinese label. Web `my-submissions.tsx:147` interpolates the
    /// raw enum — iOS gives it a friendlier display.
    public var displayLabel: String {
        switch self {
        case .annual:      return "年假"
        case .sick:        return "病假"
        case .personal:    return "事假"
        case .compTime:    return "调休"
        case .maternity:   return "产假"
        case .paternity:   return "陪产假"
        case .bereavement: return "丧假"
        case .other:       return "其他"
        case .unknown:     return "未知"
        }
    }
}
