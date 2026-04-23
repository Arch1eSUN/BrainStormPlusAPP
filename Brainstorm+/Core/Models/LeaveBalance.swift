import Foundation

// ══════════════════════════════════════════════════════════════════
// Phase 2.2 — Leaves balance center
//
// 1:1 port of the data shape returned by Web
// `src/lib/actions/leaves.ts::fetchLeaveBalance` (the action used by
// `src/app/dashboard/leaves/page.tsx`). Web has no `get_leave_balance`
// RPC — the balance is computed client-side by combining:
//
//   1. `leave_balances` (row-per-user; migration 023) — the annual /
//      sick / personal column-per-type totals. Defaults to
//      { annual: 14, sick: 14, personal: 5 } when the row is absent.
//
//   2. `approval_requests` JOIN `approval_request_leave` (migration 020)
//      — filtered to `request_type='leave'`, `status='approved'`, and
//      the current month. Days per leave_type get summed into
//      `used_*`.
//
//   3. `rest_records` (migration 034) — legacy row source; any rows for
//      the current month are collapsed into `used_comp_time`.
//
//   4. `comp_time` total — hard-coded to 4 in Web (see leaves.ts:93
//      "Phase 3 Policy: 4-day flexible monthly quota"). Not stored in
//      `leave_balances`.
//
// The iOS VM replicates the same aggregation client-side because (a)
// there's no RPC yet, (b) the Web source is Phase 2 and slated for
// removal later so introducing an RPC just for iOS parity would
// create churn, and (c) the read volumes are tiny (1 user × current
// month).
//
// Presentation shape keeps one card per leave type rather than the
// Web monolithic object — makes SwiftUI's ForEach layout natural
// and matches the task brief's "Balance cards (one per leave type)".
// ══════════════════════════════════════════════════════════════════

/// One balance card's worth of data. `leaveType` is a raw string
/// (DB `leave_type` enum value) so `WorkStateLabels.leaveType`
/// renders the Chinese label without an intermediate enum hop.
public struct LeaveBalance: Identifiable, Hashable {
    public let leaveType: String        // "annual" | "sick" | "personal" | "comp_time"
    public let totalDays: Double
    public let usedDays: Double

    public var id: String { leaveType }

    public var remainingDays: Double {
        max(0, totalDays - usedDays)
    }

    /// 0…1 progress for the consumed bar. Web uses `(used/total) * 100`,
    /// capped at 100. We return the raw ratio and let the view clamp.
    public var consumedFraction: Double {
        guard totalDays > 0 else { return 0 }
        return min(1, usedDays / totalDays)
    }

    public init(leaveType: String, totalDays: Double, usedDays: Double) {
        self.leaveType = leaveType
        self.totalDays = totalDays
        self.usedDays = usedDays
    }

    /// Chinese label — reuses `WorkStateLabels.leaveType` so changes
    /// to the Schedule-module mapping automatically propagate.
    public var displayLabel: String {
        WorkStateLabels.leaveType[leaveType] ?? leaveType
    }
}

/// Raw row from `leave_balances` (column-per-type schema post-023).
/// Only consumed by `LeavesViewModel`; not part of the view layer.
struct LeaveBalanceRow: Decodable {
    let annual: Int?
    let sick: Int?
    let personal: Int?

    enum CodingKeys: String, CodingKey {
        case annual
        case sick
        case personal
    }
}

/// Intermediate row used for the monthly aggregation join
/// `approval_requests` ⨝ `approval_request_leave`. Matches the
/// projection Web selects in `calculateUserCompTime` (leaves.ts:100-116).
struct LeaveApprovalJoinRow: Decodable {
    let status: String
    let approvalRequestLeave: [ApprovalRequestLeaveRow]

    enum CodingKeys: String, CodingKey {
        case status
        case approvalRequestLeave = "approval_request_leave"
    }

    /// PostgREST sometimes emits the nested select as a single object
    /// and sometimes as a 1-element array (depending on FK uniqueness
    /// inference). Normalize to `[]` on decode — same posture as
    /// `ApprovalMySubmissionRow`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try c.decode(String.self, forKey: .status)
        if let arr = try? c.decodeIfPresent([ApprovalRequestLeaveRow].self, forKey: .approvalRequestLeave) {
            self.approvalRequestLeave = arr
        } else if let single = try? c.decodeIfPresent(ApprovalRequestLeaveRow.self, forKey: .approvalRequestLeave) {
            self.approvalRequestLeave = [single]
        } else {
            self.approvalRequestLeave = []
        }
    }
}

struct ApprovalRequestLeaveRow: Decodable {
    let leaveType: String
    let days: Double?
    let startDate: String
    let endDate: String

    enum CodingKeys: String, CodingKey {
        case leaveType = "leave_type"
        case days
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

/// Raw `rest_records` projection for comp_time legacy aggregation.
struct RestRecordRow: Decodable {
    let startDate: String
    let endDate: String

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
    }
}
