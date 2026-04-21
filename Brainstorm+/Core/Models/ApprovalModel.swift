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
    case attendanceException = "attendance_exception"
    case dailyLog = "daily_log"
    case weeklyReport = "weekly_report"
    case revokeCompTime = "revoke_comp_time"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ApprovalRequestType(rawValue: raw) ?? .unknown
    }

    /// Chinese label matching Web detail dialog `TYPE_LABEL`
    /// (`approval-detail-dialog.tsx:74-85`). For types we've never rendered
    /// fall back to a neutral "未知类型".
    public var displayLabel: String {
        switch self {
        case .leave:              return "请假"
        case .fieldWork:          return "外勤"
        case .businessTrip:       return "出差"
        case .reimbursement:      return "报销"
        case .procurement:        return "采购"
        case .generic:            return "通用"
        case .attendanceException: return "考勤异常"
        case .dailyLog:           return "日报"
        case .weeklyReport:       return "周报"
        case .revokeCompTime:     return "撤回调休"
        case .unknown:            return "未知类型"
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

// ══════════════════════════════════════════════════════════════════
// Sprint 4.2 — Approval detail domain
//
// Layered on top of the 4.1 "我提交的" foundation. These types back
// `ApprovalDetailView` and mirror Web's `/api/approval/detail` response
// + the type-specific renderers in `approval-detail-dialog.tsx:383-615`.
//
// Tables touched (SELECT-only for most; revoke path goes through a
// SECURITY DEFINER RPC — see migration
// `20260421160000_approvals_revoke_comp_time_rpc.sql`):
//   approval_requests          — core row (020)
//   approval_request_leave     — leave full row (020)
//   approval_request_reimbursement / _procurement  (020)
//   approval_request_field_work          (032)
//   approval_request_report              (032) — indirection to real report
//   daily_logs / weekly_reports          — joined via approval_request_report
//   business_trip_requests               (045)
//   approval_request_revoke_comp_time    (051)
//   approval_actions                     (020) — audit trail
//   profiles                             — resolved separately for requester + actors
// ══════════════════════════════════════════════════════════════════

// ─── Shared building blocks ─────────────────────────────────────

/// Minimal profile projection we fetch separately because Web reports
/// that `approval_requests.requester_id` and `approval_actions.actor_id`
/// FK to `auth.users` rather than `public.profiles`, so PostgREST cannot
/// infer a nested join shape. Batch-fetched per-detail by the ViewModel.
public struct ApprovalActorProfile: Codable, Hashable {
    public let id: UUID?
    public let fullName: String?
    public let avatarUrl: String?
    public let department: String?

    public init(id: UUID?, fullName: String?, avatarUrl: String?, department: String?) {
        self.id = id
        self.fullName = fullName
        self.avatarUrl = avatarUrl
        self.department = department
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case avatarUrl = "avatar_url"
        case department
    }

    /// 1-char initial used for avatar fallback. Mirrors Web
    /// `<Avatar name={full_name || '?'}>` (detail-dialog:206-210).
    public var initial: String {
        if let name = fullName?.trimmingCharacters(in: .whitespaces), let first = name.first {
            return String(first)
        }
        return "?"
    }
}

/// JSONB row item under `approval_requests.attachments`. Web expects
/// `{ url, name/filename }` shape but is defensive against heterogeneity
/// (detail-dialog:254-282). We mirror that: optional fields + a
/// computed display name.
public struct ApprovalAttachment: Codable, Hashable, Identifiable {
    public let url: String?
    public let name: String?
    public let filename: String?

    public var id: String { url ?? (name ?? (filename ?? UUID().uuidString)) }

    public var displayName: String {
        if let n = name, !n.isEmpty { return n }
        if let f = filename, !f.isEmpty { return f }
        return url ?? "附件"
    }
}

// ─── Core request detail row ────────────────────────────────────

/// Full `approval_requests` row for the detail screen. This is the
/// response shape of `GET /api/approval/detail?id=X` minus per-type
/// `detail` + `actions` (those live as sibling types so the fetch can
/// run in parallel).
///
/// `requesterProfile` is a non-decoded companion — Supabase doesn't
/// return a nested profile join, so the ViewModel fills it after a
/// second round-trip. Kept optional for that reason.
public struct ApprovalRequestDetail: Identifiable, Codable, Hashable {
    public let id: UUID
    public let requestType: ApprovalRequestType
    public let status: ApprovalStatus
    public let priorityByRequester: RequestPriority
    public let businessReason: String?
    public let requesterId: UUID
    public let reviewerId: UUID?
    public let reviewerNote: String?
    public let reviewedAt: Date?
    public let createdAt: Date
    public let requestedAt: Date?
    public let department: String?
    public let relatedProject: String?
    public let attachments: [ApprovalAttachment]
    public let aiSummary: String?

    /// Filled by the ViewModel after decoding — never sent by PostgREST.
    public var requesterProfile: ApprovalActorProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case requestType = "request_type"
        case status
        case priorityByRequester = "priority_by_requester"
        case businessReason = "business_reason"
        case requesterId = "requester_id"
        case reviewerId = "reviewer_id"
        case reviewerNote = "reviewer_note"
        case reviewedAt = "reviewed_at"
        case createdAt = "created_at"
        case requestedAt = "requested_at"
        case department
        case relatedProject = "related_project"
        case attachments
        case aiSummary = "ai_summary"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.requestType = try c.decode(ApprovalRequestType.self, forKey: .requestType)
        self.status = try c.decode(ApprovalStatus.self, forKey: .status)
        self.priorityByRequester = try c.decode(RequestPriority.self, forKey: .priorityByRequester)
        self.businessReason = try c.decodeIfPresent(String.self, forKey: .businessReason)
        self.requesterId = try c.decode(UUID.self, forKey: .requesterId)
        self.reviewerId = try c.decodeIfPresent(UUID.self, forKey: .reviewerId)
        self.reviewerNote = try c.decodeIfPresent(String.self, forKey: .reviewerNote)
        self.reviewedAt = try c.decodeIfPresent(Date.self, forKey: .reviewedAt)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.requestedAt = try c.decodeIfPresent(Date.self, forKey: .requestedAt)
        self.department = try c.decodeIfPresent(String.self, forKey: .department)
        self.relatedProject = try c.decodeIfPresent(String.self, forKey: .relatedProject)
        self.aiSummary = try c.decodeIfPresent(String.self, forKey: .aiSummary)

        // Attachments: JSONB `[]` or `[{url, name}, …]`. Tolerate absence.
        if let arr = try? c.decodeIfPresent([ApprovalAttachment].self, forKey: .attachments) {
            self.attachments = arr
        } else {
            self.attachments = []
        }

        self.requesterProfile = nil
    }

    /// Lightweight equality: ignores `requesterProfile` since it's
    /// post-injected and never part of decoded identity.
    public static func == (lhs: ApprovalRequestDetail, rhs: ApprovalRequestDetail) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// ─── Per-type detail rows ───────────────────────────────────────

/// Full leave-detail row from `approval_request_leave`. Wider than the
/// 4.1 list projection (`ApprovalLeaveDetail`) — adds hours / reason /
/// medical cert flags.
public struct ApprovalLeaveFullDetail: Codable, Hashable {
    public let leaveType: LeaveType
    public let startDate: String
    public let endDate: String
    public let days: Double
    public let hours: Double?
    public let reason: String?
    public let medicalCertRequired: Bool?
    public let medicalCertUploaded: Bool?

    enum CodingKeys: String, CodingKey {
        case leaveType = "leave_type"
        case startDate = "start_date"
        case endDate = "end_date"
        case days
        case hours
        case reason
        case medicalCertRequired = "medical_cert_required"
        case medicalCertUploaded = "medical_cert_uploaded"
    }
}

/// `approval_request_reimbursement`. `amount` is stored in cents per
/// migration 020:125. The view formats via `formatYuan()`.
public struct ApprovalReimbursementDetail: Codable, Hashable {
    public let itemDescription: String?
    public let category: String?
    public let purchaseDate: String?
    public let amount: Int?
    public let currency: String?
    public let merchant: String?
    public let paymentMethod: String?
    public let purpose: String?
    public let receiptUrls: [ApprovalReceiptLink]

    enum CodingKeys: String, CodingKey {
        case itemDescription = "item_description"
        case category
        case purchaseDate = "purchase_date"
        case amount
        case currency
        case merchant
        case paymentMethod = "payment_method"
        case purpose
        case receiptUrls = "receipt_urls"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.itemDescription = try c.decodeIfPresent(String.self, forKey: .itemDescription)
        self.category = try c.decodeIfPresent(String.self, forKey: .category)
        self.purchaseDate = try c.decodeIfPresent(String.self, forKey: .purchaseDate)
        self.amount = try c.decodeIfPresent(Int.self, forKey: .amount)
        self.currency = try c.decodeIfPresent(String.self, forKey: .currency)
        self.merchant = try c.decodeIfPresent(String.self, forKey: .merchant)
        self.paymentMethod = try c.decodeIfPresent(String.self, forKey: .paymentMethod)
        self.purpose = try c.decodeIfPresent(String.self, forKey: .purpose)

        // receipt_urls JSONB can be `[string]` or `[{url: string}]` — tolerate both.
        if let strings = try? c.decodeIfPresent([String].self, forKey: .receiptUrls) {
            self.receiptUrls = strings.map { ApprovalReceiptLink(url: $0) }
        } else if let objs = try? c.decodeIfPresent([ApprovalReceiptLink].self, forKey: .receiptUrls) {
            self.receiptUrls = objs
        } else {
            self.receiptUrls = []
        }
    }
}

public struct ApprovalReceiptLink: Codable, Hashable, Identifiable {
    public let url: String
    public var id: String { url }
}

/// `approval_request_procurement`. Unit prices are cents.
public struct ApprovalProcurementDetail: Codable, Hashable {
    public let procurementType: String?
    public let itemDescription: String?
    public let vendor: String?
    public let quantity: Int?
    public let unitPrice: Int?
    public let totalPrice: Int?
    public let currency: String?
    public let userOrDepartment: String?
    public let purpose: String?
    public let alternativesConsidered: String?
    public let justification: String?
    public let budgetAvailable: Bool?
    public let expectedPurchaseDate: String?

    enum CodingKeys: String, CodingKey {
        case procurementType = "procurement_type"
        case itemDescription = "item_description"
        case vendor
        case quantity
        case unitPrice = "unit_price"
        case totalPrice = "total_price"
        case currency
        case userOrDepartment = "user_or_department"
        case purpose
        case alternativesConsidered = "alternatives_considered"
        case justification
        case budgetAvailable = "budget_available"
        case expectedPurchaseDate = "expected_purchase_date"
    }
}

/// `approval_request_field_work` (migration 032).
public struct ApprovalFieldWorkDetail: Codable, Hashable {
    public let targetDate: String?
    public let location: String?
    public let reason: String?
    public let expectedReturn: String?

    enum CodingKeys: String, CodingKey {
        case targetDate = "target_date"
        case location
        case reason
        case expectedReturn = "expected_return"
    }
}

/// `business_trip_requests` row (migration 045). Note estimated_cost is
/// a NUMERIC(10,2) in yuan (not cents) — different convention from
/// reimbursement/procurement, preserved from Web.
public struct ApprovalBusinessTripDetail: Codable, Hashable {
    public let destination: String?
    public let startDate: String?
    public let endDate: String?
    public let purpose: String?
    public let transportation: String?
    public let estimatedCost: Double?
    public let cancellationReason: String?

    enum CodingKeys: String, CodingKey {
        case destination
        case startDate = "start_date"
        case endDate = "end_date"
        case purpose
        case transportation
        case estimatedCost = "estimated_cost"
        case cancellationReason = "cancellation_reason"
    }
}

/// Composite for daily_log / weekly_report. Web merges the
/// `approval_request_report` row (report_date / week_start) with the
/// actual `daily_logs` / `weekly_reports` body. Body shapes differ so we
/// store a bag of optional fields keyed on what both Web renderers read
/// (detail-dialog:492-568).
public struct ApprovalReportDetail: Codable, Hashable {
    public let reportDate: String?
    public let weekStart: String?

    public let bodyDate: String?
    public let bodyWeekStart: String?
    public let bodyWeekEnd: String?
    public let mood: String?
    public let progress: String?
    public let blockers: String?
    public let content: String?
    public let accomplishments: String?
    public let plans: String?
    public let summary: String?

    public init(
        reportDate: String?,
        weekStart: String?,
        bodyDate: String?,
        bodyWeekStart: String?,
        bodyWeekEnd: String?,
        mood: String?,
        progress: String?,
        blockers: String?,
        content: String?,
        accomplishments: String?,
        plans: String?,
        summary: String?
    ) {
        self.reportDate = reportDate
        self.weekStart = weekStart
        self.bodyDate = bodyDate
        self.bodyWeekStart = bodyWeekStart
        self.bodyWeekEnd = bodyWeekEnd
        self.mood = mood
        self.progress = progress
        self.blockers = blockers
        self.content = content
        self.accomplishments = accomplishments
        self.plans = plans
        self.summary = summary
    }
}

/// `approval_request_revoke_comp_time` row (migration 051) joined with
/// a label for the original approval being revoked.
public struct ApprovalRevokeCompTimeDetail: Codable, Hashable {
    public let originalApprovalId: UUID
    public let reason: String?
    public let originalStartDate: String?
    public let originalEndDate: String?

    enum CodingKeys: String, CodingKey {
        case originalApprovalId = "original_approval_id"
        case reason
        case originalStartDate = "original_start_date"
        case originalEndDate = "original_end_date"
    }
}

/// Envelope enum the ViewModel exposes to the view — lets the view
/// switch on a single `typedDetail` instead of juggling optionals.
public enum ApprovalTypedDetail: Hashable {
    case leave(ApprovalLeaveFullDetail)
    case reimbursement(ApprovalReimbursementDetail)
    case procurement(ApprovalProcurementDetail)
    case fieldWork(ApprovalFieldWorkDetail)
    case businessTrip(ApprovalBusinessTripDetail)
    case report(ApprovalReportDetail)
    case revokeCompTime(ApprovalRevokeCompTimeDetail)
    case none
}

// ─── Action log (audit trail) ───────────────────────────────────

/// Web `ACTION_META` (detail-dialog:109-118) accepts both old-style and
/// new-style labels (`approve` + `approved`, `reject` + `rejected`,
/// `request_changes`, `withdraw`, `revoke`). DB enum `approval_action_type`
/// (migration 020:57-61) defines only 5 canonical values but runtime
/// payloads have surfaced the past-tense variants, so we keep the full
/// superset with `unknown` as the fallback.
public enum ApprovalActionType: String, Codable, Hashable {
    case approve
    case approved
    case reject
    case rejected
    case comment
    case requestRevision = "request_revision"
    case requestChanges = "request_changes"
    case escalate
    case withdraw
    case revoke
    case submit
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ApprovalActionType(rawValue: raw) ?? .unknown
    }

    public var displayLabel: String {
        switch self {
        case .approve, .approved:                 return "批准"
        case .reject, .rejected:                  return "拒绝"
        case .comment:                            return "评论"
        case .requestRevision, .requestChanges:   return "要求修改"
        case .escalate:                           return "上报"
        case .withdraw:                           return "撤回"
        case .revoke:                             return "撤销"
        case .submit:                             return "提交"
        case .unknown:                            return "操作"
        }
    }

    public var tone: ApprovalStatus.Tone {
        switch self {
        case .approve, .approved:       return .success
        case .reject, .rejected:        return .danger
        case .requestRevision, .requestChanges: return .warning
        case .comment, .submit, .escalate, .unknown: return .info
        case .withdraw, .revoke:        return .neutral
        }
    }
}

/// `approval_actions` row + batch-joined actor profile. Matches the Web
/// timeline item (detail-dialog:310-344).
public struct ApprovalAuditLogEntry: Identifiable, Codable, Hashable {
    public let id: UUID
    public let actionType: ApprovalActionType
    public let comment: String?
    public let createdAt: Date
    public let actorId: UUID?

    /// Post-injected by the ViewModel after the batch profiles fetch.
    public var actor: ApprovalActorProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case actionType = "action_type"
        case comment
        case createdAt = "created_at"
        case actorId = "actor_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.actionType = try c.decode(ApprovalActionType.self, forKey: .actionType)
        self.comment = try c.decodeIfPresent(String.self, forKey: .comment)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.actorId = try c.decodeIfPresent(UUID.self, forKey: .actorId)
        self.actor = nil
    }

    public static func == (lhs: ApprovalAuditLogEntry, rhs: ApprovalAuditLogEntry) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// ══════════════════════════════════════════════════════════════════
// Sprint 4.3 — Approver queue domain
//
// Layered on top of 4.1 / 4.2. Backs `ApprovalCenterView` (tab
// switcher) + `ApprovalQueueView` (per-tab approver list) + the
// apply-action write path.
//
// Web source of truth:
//   - `src/app/dashboard/approval/page.tsx` — 7-tab layout
//   - `src/app/dashboard/approval/_tabs/*-list.tsx` — per-tab template
//   - `src/lib/actions/approval-requests.ts:343-358 ApprovalListRow`
//   - `src/lib/actions/approval-requests.ts:389-533 fetchApprovalsByType`
//   - `src/lib/actions/approval-requests.ts:672-818 approveWithAudit/rejectWithAudit`
//
// Writes go through the SECURITY DEFINER RPC
// `approvals_apply_action(p_request_id, p_decision, p_comment)` (see
// migration `20260421170000_approvals_apply_action_rpc.sql`). The RPC
// rejects `request_type='leave'` because Web's `decideLeaveRequest`
// dispatches side-effects (comp_time quota debit + DWS refresh) via the
// Next.js hook layer that cannot run from SQL. Leave rows are still
// SELECTable here so approvers see the queue; the action buttons wire
// through the same RPC and surface the Chinese error if tapped.
// ══════════════════════════════════════════════════════════════════

/// Approver-queue row. Equivalent of Web `ApprovalListRow`
/// (approval-requests.ts:343-358) — flattens the 1:1 leave detail into
/// four nullable columns and carries a `requesterProfile` field we
/// post-inject after a batch `profiles` fetch (requester_id FKs to
/// auth.users, so PostgREST can't embed the join).
///
/// Distinct from `ApprovalMySubmissionRow` (4.1): that one is for the
/// viewer's own submissions and doesn't need requester identity; this
/// one shows someone else's submission to an approver and needs name +
/// avatar.
public struct ApprovalListRow: Identifiable, Codable, Hashable {
    public let id: UUID
    public let requestType: ApprovalRequestType
    public let status: ApprovalStatus
    public let priorityByRequester: RequestPriority
    public let businessReason: String?
    public let requesterId: UUID
    public let reviewerId: UUID?
    public let reviewerNote: String?
    public let reviewedAt: Date?
    public let createdAt: Date

    /// Flattened leave preview — same shape as Web's flat columns.
    public let leaveType: LeaveType?
    public let startDate: String?
    public let endDate: String?
    public let days: Double?

    /// Post-injected by the ViewModel after a batch `profiles` fetch.
    /// Never present in decoded payload.
    public var requesterProfile: ApprovalActorProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case requestType = "request_type"
        case status
        case priorityByRequester = "priority_by_requester"
        case businessReason = "business_reason"
        case requesterId = "requester_id"
        case reviewerId = "reviewer_id"
        case reviewerNote = "reviewer_note"
        case reviewedAt = "reviewed_at"
        case createdAt = "created_at"
        case leaveDetails = "approval_request_leave"
    }

    /// Decoder eats the nested `approval_request_leave` array (1-element
    /// left-join) and flattens its four fields up to the row. Mirrors
    /// the Web mapping step in `fetchApprovalsByType` (approval-requests.ts:494-515).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.requestType = try c.decode(ApprovalRequestType.self, forKey: .requestType)
        self.status = try c.decode(ApprovalStatus.self, forKey: .status)
        self.priorityByRequester = try c.decode(RequestPriority.self, forKey: .priorityByRequester)
        self.businessReason = try c.decodeIfPresent(String.self, forKey: .businessReason)
        self.requesterId = try c.decode(UUID.self, forKey: .requesterId)
        self.reviewerId = try c.decodeIfPresent(UUID.self, forKey: .reviewerId)
        self.reviewerNote = try c.decodeIfPresent(String.self, forKey: .reviewerNote)
        self.reviewedAt = try c.decodeIfPresent(Date.self, forKey: .reviewedAt)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)

        // Nested leave details — three accepted shapes.
        let leave: ApprovalLeaveDetail?
        if let arr = try? c.decodeIfPresent([ApprovalLeaveDetail].self, forKey: .leaveDetails) {
            leave = arr.first
        } else if let single = try? c.decodeIfPresent(ApprovalLeaveDetail.self, forKey: .leaveDetails) {
            leave = single
        } else {
            leave = nil
        }
        self.leaveType = leave?.leaveType
        self.startDate = leave?.startDate
        self.endDate = leave?.endDate
        self.days = leave?.days

        self.requesterProfile = nil
    }

    /// Encode-side — kept flat, not expected to round-trip through the
    /// queue fetch. Safe stub so the Codable synth remains usable for
    /// snapshot/testing.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(requestType, forKey: .requestType)
        try c.encode(status, forKey: .status)
        try c.encode(priorityByRequester, forKey: .priorityByRequester)
        try c.encodeIfPresent(businessReason, forKey: .businessReason)
        try c.encode(requesterId, forKey: .requesterId)
        try c.encodeIfPresent(reviewerId, forKey: .reviewerId)
        try c.encodeIfPresent(reviewerNote, forKey: .reviewerNote)
        try c.encodeIfPresent(reviewedAt, forKey: .reviewedAt)
        try c.encode(createdAt, forKey: .createdAt)
    }

    public static func == (lhs: ApprovalListRow, rhs: ApprovalListRow) -> Bool {
        lhs.id == rhs.id
            && lhs.status == rhs.status
            && lhs.reviewerId == rhs.reviewerId
            && lhs.reviewerNote == rhs.reviewerNote
            && lhs.reviewedAt == rhs.reviewedAt
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The 6 approver-queue tabs. Mirrors Web's `ApprovalTabKey` minus
/// `mine` (which routes to `ApprovalsListView` / `MySubmissionsViewModel`
/// from 4.1).
///
/// The mappings on this enum are the source of truth for
/// `typeToRequestTypes` (DB filter) and `tabToCapTypes` (capability
/// gate) — kept as struct-level static data so both the ViewModel and
/// the tab header can read the same definition.
public enum ApprovalQueueKind: String, CaseIterable, Identifiable, Hashable {
    case leave
    case fieldWork = "field_work"
    case businessTrip = "business_trip"
    case expense
    case report
    case generic

    public var id: String { rawValue }

    /// Chinese tab label. Matches page.tsx:120-150 tab labels.
    public var displayLabel: String {
        switch self {
        case .leave:        return "请假"
        case .fieldWork:    return "外勤"
        case .businessTrip: return "出差"
        case .expense:      return "报销/采购"
        case .report:       return "日报/周报"
        case .generic:      return "通用"
        }
    }

    /// DB `request_type` values included in this queue. Mirrors
    /// `typeToRequestTypes` (approval-requests.ts:361-371).
    public var requestTypes: [String] {
        switch self {
        case .leave:        return ["leave"]
        case .fieldWork:    return ["field_work"]
        case .businessTrip: return ["business_trip"]
        case .expense:      return ["reimbursement", "procurement"]
        case .report:       return ["daily_log", "weekly_report"]
        case .generic:      return ["generic"]
        }
    }

    /// Whether apply-action writes are supported for this queue on
    /// iOS. Leave is intentionally read-only (see RPC rationale in the
    /// migration header). UI disables approve/reject and surfaces a
    /// Chinese hint on the leave queue.
    public var supportsWriteOnIOS: Bool {
        self != .leave
    }
}

/// The two decisions the approve/reject buttons can post. Serialized
/// as the `p_decision` TEXT arg of the `approvals_apply_action` RPC.
public enum ApprovalActionDecision: String, Codable, Hashable {
    case approve
    case reject

    public var displayLabel: String {
        switch self {
        case .approve: return "批准"
        case .reject:  return "拒绝"
        }
    }
}
