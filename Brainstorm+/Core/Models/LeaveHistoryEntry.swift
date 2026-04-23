import Foundation

// ══════════════════════════════════════════════════════════════════
// Phase 2.2 — Leave history entry
//
// Mirrors the `LeaveHistory` interface declared inline in Web
// `src/app/dashboard/leaves/page.tsx:18-26`. Web builds this array by
// merging two sources:
//
//   1. `approval_requests` ⨝ `approval_request_leave` — the current
//      approvals pipeline, one row per leave submission.
//   2. `rest_records` — legacy comp_time rows with no backing approval.
//      Each is synthesized as `leave_type='comp_time'`,
//      `status='approved'` because the legacy flow auto-approved.
//
// iOS reuses the same two-query approach in `LeavesViewModel` and
// returns a flat `[LeaveHistoryEntry]` sorted by `createdAt` descending
// (matching Web line 115). The view groups by calendar year for a
// cleaner mobile layout (the brief asks for "grouped by year").
// ══════════════════════════════════════════════════════════════════

/// One past leave — whether from the approvals pipeline or the legacy
/// rest_records table. `leaveType` is kept as a raw string so the
/// unknown-escape-hatch pattern from `ApprovalModel.LeaveType` can
/// re-hydrate it at the view layer for the Chinese label.
public struct LeaveHistoryEntry: Identifiable, Hashable {
    public let id: UUID
    public let leaveType: String     // "annual" | "sick" | "personal" | "comp_time" | …
    public let startDate: String     // "YYYY-MM-DD" — kept as String (Attendance/Approval convention)
    public let endDate: String
    public let days: Double
    public let status: String        // "approved" | "pending" | "rejected" | …
    public let createdAt: Date

    public init(
        id: UUID,
        leaveType: String,
        startDate: String,
        endDate: String,
        days: Double,
        status: String,
        createdAt: Date
    ) {
        self.id = id
        self.leaveType = leaveType
        self.startDate = startDate
        self.endDate = endDate
        self.days = days
        self.status = status
        self.createdAt = createdAt
    }

    /// Chinese label — shares the `WorkStateLabels.leaveType` mapping
    /// with `LeaveBalance` so a rename in Schedule.swift carries here.
    public var leaveTypeLabel: String {
        WorkStateLabels.leaveType[leaveType] ?? leaveType
    }

    /// Chinese status label. Web maps only 3 concrete states
    /// (my-submissions parity). Unknown statuses fall through raw.
    public var statusLabel: String {
        switch status {
        case "approved":  return "已通过"
        case "pending":   return "审核中"
        case "rejected":  return "已驳回"
        case "withdrawn", "cancelled", "revoked": return "已撤回"
        default:          return status
        }
    }

    /// Calendar year of `createdAt` — used by the view to group
    /// entries into yearly sections (brief §2).
    public var year: Int {
        Calendar.current.component(.year, from: createdAt)
    }
}
