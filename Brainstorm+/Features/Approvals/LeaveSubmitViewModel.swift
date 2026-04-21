import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Sprint 4.4 — Leave submit ViewModel.
//
// Parity target: Web `submitLeaveRequest` in `src/lib/leave/unified.ts`
// + the leave-request form in `src/components/approval/leave-form.tsx`.
//
// Why call the RPC instead of inserting directly:
//   1. The `shouldAutoApprove` deadlock bypass requires writing
//      `status='approved' + reviewer_id=null` on insert, which user-
//      JWT RLS forbids (WITH CHECK auth.uid() = requester_id allows
//      the insert but a malicious client could also forge 'approved'
//      for any leave — we need server-side trust).
//   2. The per-month comp_time quota pre-check reads
//      `comp_time_quotas` and must race-safely succeed-or-reject as
//      one atomic operation. Doing it in two round-trips lets a second
//      concurrent submission slip past the check.
//
// Chinese errors from the RPC (quota exhausted, date range invalid,
// reason missing) surface here via `errorMessage` and bubble to
// `.zyErrorBanner`. See migration 20260421180000_approvals_submit_rpcs.sql
// for the RAISE-EXCEPTION call sites.
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class LeaveSubmitViewModel: ObservableObject {
    // MARK: - Form state (bound by the view)

    @Published public var leaveType: LeaveType = .annual
    @Published public var startDate: Date = Date()
    @Published public var endDate: Date = Date()
    @Published public var reason: String = ""
    @Published public var priority: RequestPriority = .medium

    // MARK: - Submit state (read-only from the view)

    @Published public private(set) var isSubmitting: Bool = false
    @Published public var errorMessage: String?
    @Published public private(set) var createdRequestId: UUID?

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Derived

    /// Inclusive day count, matching Web `splitDaysByMonth` / the form
    /// preview (`leave-form.tsx` renders `{days}天`). Default to 1 when
    /// the range is a single day. Whole-day steps only — half-days via
    /// `NUMERIC(4,1)` are reserved for admin adjustments, not this form.
    public var days: Double {
        let cal = Calendar(identifier: .iso8601)
        let s = cal.startOfDay(for: startDate)
        let e = cal.startOfDay(for: endDate)
        let components = cal.dateComponents([.day], from: s, to: e)
        let diff = components.day ?? 0
        return Double(max(0, diff) + 1)
    }

    /// Mirrors Web's client-side gate: end ≥ start, reason present,
    /// leave type != `.unknown`. Also rejects the UI's `unknown`
    /// sentinel enum which shouldn't be user-selectable but we defend
    /// against it anyway.
    public var canSubmit: Bool {
        guard leaveType != .unknown else { return false }
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard days >= 1 else { return false }
        return !isSubmitting
    }

    // MARK: - Submit

    /// Calls `approvals_submit_leave` and stores the returned UUID in
    /// `createdRequestId` on success. Returns `true` for the view to
    /// decide dismiss/navigation. Returning `false` with
    /// `errorMessage` set is the non-throwing failure path.
    @discardableResult
    public func submit() async -> Bool {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard leaveType != .unknown else {
            errorMessage = "请选择请假类型"
            return false
        }
        guard !trimmedReason.isEmpty else {
            errorMessage = "请填写请假事由"
            return false
        }
        guard startDate <= endDate else {
            errorMessage = "开始日期不能晚于结束日期"
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let input = LeaveSubmitInput(
            leaveType: leaveType,
            startDate: Self.yyyyMMdd.string(from: startDate),
            endDate: Self.yyyyMMdd.string(from: endDate),
            days: days,
            reason: trimmedReason,
            priority: priority
        )

        do {
            let id: UUID = try await client
                .rpc("approvals_submit_leave", params: input)
                .execute()
                .value
            self.createdRequestId = id
            return true
        } catch {
            self.errorMessage = prettyApprovalRPCError(error)
            return false
        }
    }

    // MARK: - Formatter
    //
    // UTC date formatter — the DB `DATE` column is tz-naive, matching
    // Web's use of `YYYY-MM-DD` strings. Picking UTC keeps the "today"
    // anchor stable across DST boundaries and user timezone changes.

    private static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
