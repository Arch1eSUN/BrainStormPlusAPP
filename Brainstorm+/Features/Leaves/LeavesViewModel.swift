import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 2.2 — Leaves center VM
//
// 1:1 port of the data-loading logic in Web
// `src/app/dashboard/leaves/page.tsx` + the backing action
// `src/lib/actions/leaves.ts::fetchLeaveBalance` /
// `calculateUserCompTime`.
//
// Balance computation approach — CLIENT-SIDE (no RPC):
//   Web intentionally does not provide a `get_leave_balance` RPC.
//   The formula lives in `lib/actions/leaves.ts:75-170` and runs as a
//   Next.js server action. iOS replicates the same formula inline
//   because:
//     - Read cost is trivial (1 user × current month).
//     - Introducing an RPC just for iOS parity would fork the
//       truth-table on a module already slated for Phase-3 rewrite
//       (see the file header deprecation comment).
//     - The Web logic is exact arithmetic — no pg-side functions
//       needed (no date math the client can't do).
//
// Sources joined on the client:
//   1. `leave_balances` — annual / sick / personal totals (defaults
//      { 14, 14, 5 } when absent, matching leaves.ts:85-90).
//   2. `approval_requests` ⨝ `approval_request_leave` — monthly
//      approved leave days, bucketed by leave_type. Filter:
//      `request_type='leave'`, `status='approved'`,
//      `start_date BETWEEN <month-start> AND <month-end>`.
//   3. `rest_records` — legacy comp_time usage for the same month.
//   4. `comp_time` total — hard-coded to 4 days (Web leaves.ts:93
//      "Phase 3 Policy: 4-day flexible monthly quota").
//
// History fetch:
//   Mirrors Web page.tsx:55-113 — two parallel queries merged into
//   `[LeaveHistoryEntry]`, sorted by `createdAt` desc. iOS runs them
//   concurrently via `async let`. The limit (30 approvals + 10 legacy
//   rests) matches Web exactly.
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class LeavesViewModel: ObservableObject {
    @Published public private(set) var balances: [LeaveBalance] = []
    @Published public private(set) var history: [LeaveHistoryEntry] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    private let client: SupabaseClient

    /// Hard-coded default comp_time quota — matches Web leaves.ts:93.
    /// Not a DB column; Phase-3 flexible monthly quota.
    private static let compTimeQuotaPerMonth: Double = 4

    /// Web leaves.ts:85-90 default totals when the row is absent.
    private static let defaultAnnualDays: Double = 14
    private static let defaultSickDays: Double = 14
    private static let defaultPersonalDays: Double = 5

    public init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Public entry point

    /// Loads balances + history in parallel. Safe to call repeatedly
    /// (e.g. from `.refreshable`); resets both arrays on entry.
    public func loadAll() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let currentUserId: UUID
        do {
            currentUserId = try await client.auth.session.user.id
        } catch {
            self.errorMessage = "请先登录"
            return
        }

        do {
            // Parallelize: balance and history are independent reads.
            async let balancesTask = fetchBalance(userId: currentUserId)
            async let historyTask = fetchHistory(userId: currentUserId)

            let (b, h) = try await (balancesTask, historyTask)
            self.balances = b
            self.history = h
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    // MARK: - Balance

    /// Computes the 4 balance cards (annual / sick / personal / comp_time)
    /// by replicating Web `calculateUserCompTime` exactly.
    ///
    /// Returns in a fixed display order — annual, sick, personal,
    /// comp_time — so the ForEach layout is stable across reloads.
    /// Cards with `totalDays == 0` are still returned; the view can
    /// filter them if needed (for now we always show all 4 to match
    /// the Web quota page's shape).
    private func fetchBalance(userId: UUID) async throws -> [LeaveBalance] {
        // ─── 1. leave_balances (column-per-type) ─────────────────
        let balanceRow: LeaveBalanceRow? = try? await client
            .from("leave_balances")
            .select("annual, sick, personal")
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
            .value
        // `.single()` throws when 0 rows → we swallow via `try?` so the
        // default-limits branch (leaves.ts:85-87) kicks in.

        let annualTotal  = Double(balanceRow?.annual  ?? Int(Self.defaultAnnualDays))
        let sickTotal    = Double(balanceRow?.sick    ?? Int(Self.defaultSickDays))
        let personalTotal = Double(balanceRow?.personal ?? Int(Self.defaultPersonalDays))
        let compTimeTotal = Self.compTimeQuotaPerMonth

        // ─── 2. Monthly approved leaves ──────────────────────────
        let (monthStart, monthEnd) = Self.currentMonthBounds()

        // `!inner` join + a filter on the nested column is the same as
        // Web leaves.ts:101-115 — PostgREST supports column-qualified
        // filters on embedded rows via the `approval_request_leave.start_date`
        // key path. Swift SDK passes it through verbatim in `.gte` /
        // `.lte` arg names.
        let approvalRows: [LeaveApprovalJoinRow] = (try? await client
            .from("approval_requests")
            .select("""
                status,
                approval_request_leave!inner ( leave_type, days, start_date, end_date )
            """)
            .eq("requester_id", value: userId.uuidString)
            .eq("request_type", value: "leave")
            .eq("status", value: "approved")
            .gte("approval_request_leave.start_date", value: monthStart)
            .lte("approval_request_leave.start_date", value: monthEnd)
            .execute()
            .value) ?? []

        var usedAnnual: Double = 0
        var usedSick: Double = 0
        var usedPersonal: Double = 0
        var usedCompTime: Double = 0

        for row in approvalRows {
            guard let detail = row.approvalRequestLeave.first else { continue }
            let days = detail.days ?? Self.inclusiveDayCount(
                startISO: detail.startDate,
                endISO: detail.endDate
            )
            switch detail.leaveType {
            case "annual":    usedAnnual += days
            case "sick":      usedSick += days
            case "personal":  usedPersonal += days
            case "comp_time": usedCompTime += days
            default: break  // maternity / paternity / bereavement not
                            // surfaced as cards in the Web /leaves UI
            }
        }

        // ─── 3. Legacy rest_records (comp_time only) ─────────────
        let restRows: [RestRecordRow] = (try? await client
            .from("rest_records")
            .select("start_date, end_date")
            .eq("user_id", value: userId.uuidString)
            .gte("start_date", value: monthStart)
            .lte("start_date", value: monthEnd)
            .execute()
            .value) ?? []

        for r in restRows {
            let days = Self.inclusiveDayCount(startISO: r.startDate, endISO: r.endDate)
            if days > 0 { usedCompTime += days }
        }

        // ─── 4. Assemble the 4 cards ─────────────────────────────
        return [
            LeaveBalance(leaveType: "annual",    totalDays: annualTotal,   usedDays: usedAnnual),
            LeaveBalance(leaveType: "sick",      totalDays: sickTotal,     usedDays: usedSick),
            LeaveBalance(leaveType: "personal",  totalDays: personalTotal, usedDays: usedPersonal),
            LeaveBalance(leaveType: "comp_time", totalDays: compTimeTotal, usedDays: usedCompTime),
        ]
    }

    // MARK: - History

    /// Merges the approvals pipeline and the legacy rest_records
    /// table into a single history feed. Sorted newest-first.
    private func fetchHistory(userId: UUID) async throws -> [LeaveHistoryEntry] {
        // Run both queries in parallel (Web serializes them, but the
        // reads are independent so we don't need to).
        async let approvalTask = fetchApprovalHistory(userId: userId)
        async let restTask = fetchRestHistory(userId: userId)
        let (approvals, rests) = try await (approvalTask, restTask)

        let merged = approvals + rests
        return merged.sorted { $0.createdAt > $1.createdAt }
    }

    private func fetchApprovalHistory(userId: UUID) async throws -> [LeaveHistoryEntry] {
        // Web page.tsx:55-72 — last 30 rows, newest first.
        struct ApprovalHistoryRow: Decodable {
            let id: UUID
            let status: String
            let createdAt: Date
            let approvalRequestLeave: [ApprovalRequestLeaveRow]

            enum CodingKeys: String, CodingKey {
                case id
                case status
                case createdAt = "created_at"
                case approvalRequestLeave = "approval_request_leave"
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.id = try c.decode(UUID.self, forKey: .id)
                self.status = try c.decode(String.self, forKey: .status)
                self.createdAt = try c.decode(Date.self, forKey: .createdAt)
                if let arr = try? c.decodeIfPresent([ApprovalRequestLeaveRow].self, forKey: .approvalRequestLeave) {
                    self.approvalRequestLeave = arr
                } else if let single = try? c.decodeIfPresent(ApprovalRequestLeaveRow.self, forKey: .approvalRequestLeave) {
                    self.approvalRequestLeave = [single]
                } else {
                    self.approvalRequestLeave = []
                }
            }
        }

        let rows: [ApprovalHistoryRow] = (try? await client
            .from("approval_requests")
            .select("""
                id,
                status,
                created_at,
                approval_request_leave!inner ( leave_type, start_date, end_date, days )
            """)
            .eq("requester_id", value: userId.uuidString)
            .eq("request_type", value: "leave")
            .order("created_at", ascending: false)
            .limit(30)
            .execute()
            .value) ?? []

        return rows.compactMap { row in
            guard let detail = row.approvalRequestLeave.first else { return nil }
            let days = detail.days ?? Self.inclusiveDayCount(
                startISO: detail.startDate,
                endISO: detail.endDate
            )
            return LeaveHistoryEntry(
                id: row.id,
                leaveType: detail.leaveType,
                startDate: detail.startDate,
                endDate: detail.endDate,
                days: days,
                status: row.status,
                createdAt: row.createdAt
            )
        }
    }

    private func fetchRestHistory(userId: UUID) async throws -> [LeaveHistoryEntry] {
        // Web page.tsx:74-80 — last 10 legacy rows, always synthesized
        // as approved comp_time. `rest_records.id` is UUID per
        // migration 034.
        struct RestHistoryRow: Decodable {
            let id: UUID
            let startDate: String
            let endDate: String
            let createdAt: Date

            enum CodingKeys: String, CodingKey {
                case id
                case startDate = "start_date"
                case endDate = "end_date"
                case createdAt = "created_at"
            }
        }

        let rows: [RestHistoryRow] = (try? await client
            .from("rest_records")
            .select("id, start_date, end_date, created_at")
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(10)
            .execute()
            .value) ?? []

        return rows.map { r in
            LeaveHistoryEntry(
                id: r.id,
                leaveType: "comp_time",
                startDate: r.startDate,
                endDate: r.endDate,
                days: Self.inclusiveDayCount(startISO: r.startDate, endISO: r.endDate),
                status: "approved",
                createdAt: r.createdAt
            )
        }
    }

    // MARK: - Helpers

    /// `(YYYY-MM-01, YYYY-MM-31)` for the current system month.
    /// The end of the range is always `31` — Web does the same
    /// (leaves.ts:114) because `.lte` on a `DATE` column accepts
    /// days that don't exist in the calendar (e.g. Feb-31 just
    /// matches through Feb-28/29).
    private static func currentMonthBounds() -> (String, String) {
        let now = Date()
        let cal = Calendar.current
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        let mm = String(format: "%02d", month)
        return ("\(year)-\(mm)-01", "\(year)-\(mm)-31")
    }

    /// Inclusive day count between two ISO "YYYY-MM-DD" dates —
    /// Web convention `ceil((end - start) / 86400000) + 1`.
    private static func inclusiveDayCount(startISO: String, endISO: String) -> Double {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let s = f.date(from: startISO), let e = f.date(from: endISO) else { return 0 }
        let ms = e.timeIntervalSince(s) * 1000
        let days = ceil(ms / 86_400_000) + 1
        return max(0, days)
    }
}
