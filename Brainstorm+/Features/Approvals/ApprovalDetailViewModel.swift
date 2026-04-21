import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Sprint 4.2 — Approval detail screen ViewModel.
//
// Parity target: Web `GET /api/approval/detail?id=X`
// (`src/app/api/approval/detail/route.ts`) + the ApprovalDetailDialog
// rendering. iOS can't reuse the HTTP route because it runs on the
// Next.js server with `createAdminClient()`, so we replicate the
// fetch shape directly against Supabase with user-JWT.
//
// What's safe under RLS:
//   - SELECT approval_requests    → requester_id = auth.uid() (020:209)
//   - SELECT approval_request_*   → inherited via request_id join (020:233-275)
//   - SELECT approval_request_revoke_comp_time → 051:61
//   - SELECT approval_actions     → actor or requester (020:279)
//   - SELECT profiles(id, full_name, avatar_url, department) → public read
//
// Revoke flow goes through a SECURITY DEFINER RPC
// (`approvals_request_comp_time_revocation`) because user-JWT cannot
// DELETE from approval_requests to roll back a failed dual-insert.
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class ApprovalDetailViewModel: ObservableObject {
    @Published public private(set) var request: ApprovalRequestDetail?
    @Published public private(set) var typedDetail: ApprovalTypedDetail = .none
    @Published public private(set) var actions: [ApprovalAuditLogEntry] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?

    /// Revoke flow — separate loading flag so the sheet button animates
    /// independently of the detail spinner.
    @Published public private(set) var isSubmittingRevoke: Bool = false

    private let client: SupabaseClient
    private let requestId: UUID

    public init(requestId: UUID, client: SupabaseClient) {
        self.requestId = requestId
        self.client = client
    }

    // MARK: - Load

    /// Fetches the request, its type-specific detail, the audit log, and
    /// all the profile joins needed to render names + avatars. Mirrors
    /// the 3-round-trip shape of the Web detail route (minus capability
    /// gate — RLS already scopes to `requester_id = auth.uid()` for
    /// self-served rows from "我提交的").
    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Step 1 — parent row. Must be serialized before per-type
            // detail because the fetch target depends on `request_type`.
            let parent: ApprovalRequestDetail = try await client
                .from("approval_requests")
                .select()
                .eq("id", value: requestId.uuidString)
                .single()
                .execute()
                .value

            var parentMut = parent

            // Step 2 — three parallel fetches: requester profile,
            // typed detail (dispatched on request_type), audit log.
            async let requesterProfileTask = fetchProfile(id: parent.requesterId)
            async let typedDetailTask = fetchTypedDetail(for: parent.requestType)
            async let rawActionsTask = fetchRawActions()

            let requesterProfile = try await requesterProfileTask
            let fetchedTypedDetail = try await typedDetailTask
            var rawActions = try await rawActionsTask

            // Step 3 — batch profile fetch for action actors.
            let actorIds = Array(Set(rawActions.compactMap(\.actorId)))
            let actorProfiles: [UUID: ApprovalActorProfile]
            if actorIds.isEmpty {
                actorProfiles = [:]
            } else {
                actorProfiles = try await fetchProfiles(ids: actorIds)
            }

            for i in rawActions.indices {
                if let actorId = rawActions[i].actorId {
                    rawActions[i].actor = actorProfiles[actorId]
                }
            }

            parentMut.requesterProfile = requesterProfile
            self.request = parentMut
            self.typedDetail = fetchedTypedDetail
            self.actions = rawActions
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Revoke comp-time (self-service)

    /// Calls the SECURITY DEFINER RPC that atomically creates the
    /// revoke request + detail rows. On success re-loads the detail so
    /// the audit trail reflects the new state.
    /// Returns `true` on success, `false` on failure (error message
    /// surfaced via `errorMessage`).
    @discardableResult
    public func submitRevokeCompTime(reason: String) async -> Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "请填写撤回事由"
            return false
        }

        isSubmittingRevoke = true
        errorMessage = nil
        defer { isSubmittingRevoke = false }

        struct Params: Encodable {
            let p_original_id: String
            let p_reason: String
        }

        do {
            let _: UUID = try await client
                .rpc(
                    "approvals_request_comp_time_revocation",
                    params: Params(
                        p_original_id: requestId.uuidString,
                        p_reason: trimmed
                    )
                )
                .execute()
                .value

            // Refresh the detail so reviewer sees updated state (though
            // the parent approval itself doesn't change — the child
            // revoke request is a sibling row). Mainly refreshes
            // `actions` in case the RPC writes an `approval_actions`
            // entry in future iterations. Cheap and matches Web's
            // `onSuccess` which closes + refetches.
            await load()
            return true
        } catch {
            self.errorMessage = prettyRPCError(error)
            return false
        }
    }

    // MARK: - Private fetchers

    private func fetchProfile(id: UUID) async throws -> ApprovalActorProfile? {
        let rows: [ApprovalActorProfile] = try await client
            .from("profiles")
            .select("id, full_name, avatar_url, department")
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    private func fetchProfiles(ids: [UUID]) async throws -> [UUID: ApprovalActorProfile] {
        let idStrings = ids.map { $0.uuidString }
        let rows: [ApprovalActorProfile] = try await client
            .from("profiles")
            .select("id, full_name, avatar_url, department")
            .in("id", values: idStrings)
            .execute()
            .value
        var map: [UUID: ApprovalActorProfile] = [:]
        for row in rows {
            if let id = row.id { map[id] = row }
        }
        return map
    }

    private func fetchRawActions() async throws -> [ApprovalAuditLogEntry] {
        try await client
            .from("approval_actions")
            .select("id, action_type, comment, created_at, actor_id")
            .eq("request_id", value: requestId.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    private func fetchTypedDetail(
        for type: ApprovalRequestType
    ) async throws -> ApprovalTypedDetail {
        switch type {
        case .leave:
            let rows: [ApprovalLeaveFullDetail] = try await client
                .from("approval_request_leave")
                .select()
                .eq("request_id", value: requestId.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first.map(ApprovalTypedDetail.leave) ?? .none

        case .reimbursement:
            let rows: [ApprovalReimbursementDetail] = try await client
                .from("approval_request_reimbursement")
                .select()
                .eq("request_id", value: requestId.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first.map(ApprovalTypedDetail.reimbursement) ?? .none

        case .procurement:
            let rows: [ApprovalProcurementDetail] = try await client
                .from("approval_request_procurement")
                .select()
                .eq("request_id", value: requestId.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first.map(ApprovalTypedDetail.procurement) ?? .none

        case .fieldWork:
            let rows: [ApprovalFieldWorkDetail] = try await client
                .from("approval_request_field_work")
                .select()
                .eq("request_id", value: requestId.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first.map(ApprovalTypedDetail.fieldWork) ?? .none

        case .businessTrip:
            let rows: [ApprovalBusinessTripDetail] = try await client
                .from("business_trip_requests")
                .select()
                .eq("approval_request_id", value: requestId.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first.map(ApprovalTypedDetail.businessTrip) ?? .none

        case .dailyLog, .weeklyReport:
            return try await fetchReportDetail(kind: type)

        case .revokeCompTime:
            return try await fetchRevokeCompTimeDetail()

        case .attendanceException, .generic, .unknown:
            // No dedicated detail table — Web falls back to a raw
            // key-value dump. iOS shows the shared "详情" empty state
            // (handled at the view layer).
            return .none
        }
    }

    private func fetchReportDetail(kind: ApprovalRequestType) async throws -> ApprovalTypedDetail {
        struct ReportRow: Decodable {
            let report_id: UUID?
            let report_date: String?
            let week_start: String?
        }
        struct DailyBody: Decodable {
            let date: String?
            let mood: String?
            let progress: String?
            let blockers: String?
            let content: String?
        }
        struct WeeklyBody: Decodable {
            let week_start: String?
            let week_end: String?
            let accomplishments: String?
            let highlights: String?
            let plans: String?
            let blockers: String?
            let challenges: String?
            let summary: String?
        }

        let reportRows: [ReportRow] = try await client
            .from("approval_request_report")
            .select("report_id, report_date, week_start")
            .eq("request_id", value: requestId.uuidString)
            .limit(1)
            .execute()
            .value

        guard let row = reportRows.first, let reportId = row.report_id else {
            return .none
        }

        if kind == .dailyLog {
            let bodies: [DailyBody] = try await client
                .from("daily_logs")
                .select("date, mood, progress, blockers, content")
                .eq("id", value: reportId.uuidString)
                .limit(1)
                .execute()
                .value
            let body = bodies.first
            return .report(ApprovalReportDetail(
                reportDate: row.report_date,
                weekStart: row.week_start,
                bodyDate: body?.date,
                bodyWeekStart: nil,
                bodyWeekEnd: nil,
                mood: body?.mood,
                progress: body?.progress,
                blockers: body?.blockers,
                content: body?.content,
                accomplishments: nil,
                plans: nil,
                summary: nil
            ))
        } else {
            let bodies: [WeeklyBody] = try await client
                .from("weekly_reports")
                .select("week_start, week_end, accomplishments, highlights, plans, blockers, challenges, summary")
                .eq("id", value: reportId.uuidString)
                .limit(1)
                .execute()
                .value
            let body = bodies.first
            return .report(ApprovalReportDetail(
                reportDate: row.report_date,
                weekStart: row.week_start,
                bodyDate: nil,
                bodyWeekStart: body?.week_start,
                bodyWeekEnd: body?.week_end,
                mood: nil,
                progress: nil,
                blockers: body?.blockers ?? body?.challenges,
                content: nil,
                accomplishments: body?.accomplishments ?? body?.highlights,
                plans: body?.plans,
                summary: body?.summary
            ))
        }
    }

    private func fetchRevokeCompTimeDetail() async throws -> ApprovalTypedDetail {
        struct RawRow: Decodable {
            let original_approval_id: UUID
            let reason: String?
        }

        let rows: [RawRow] = try await client
            .from("approval_request_revoke_comp_time")
            .select("original_approval_id, reason")
            .eq("approval_request_id", value: requestId.uuidString)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else { return .none }

        // Second hop: pull the original leave window so the detail
        // view can render "原调休区间". Read-only, same RLS as main
        // request — user already owns this revoke request so the
        // original was theirs too.
        struct LeaveSpan: Decodable {
            let start_date: String?
            let end_date: String?
        }
        let leaveRows: [LeaveSpan] = (try? await client
            .from("approval_request_leave")
            .select("start_date, end_date")
            .eq("request_id", value: row.original_approval_id.uuidString)
            .limit(1)
            .execute()
            .value) ?? []

        return .revokeCompTime(ApprovalRevokeCompTimeDetail(
            originalApprovalId: row.original_approval_id,
            reason: row.reason,
            originalStartDate: leaveRows.first?.start_date,
            originalEndDate: leaveRows.first?.end_date
        ))
    }

    // MARK: - Error shaping

    /// PostgREST surfaces `RAISE EXCEPTION '<message>'` verbatim in the
    /// error description but wraps it in additional framing. The Web
    /// action just hands the raw message to the toast; we do the same
    /// here, stripping the Postgres-prefix noise so the banner shows
    /// "仅调休可申请撤回" instead of "ERROR: 仅调休可申请撤回 (SQLSTATE ...)".
    private func prettyRPCError(_ error: Error) -> String {
        let raw = error.localizedDescription
        // Strip `ERROR: ` prefix if present. Supabase-Swift typically
        // carries `message` inside `PostgrestError`; `localizedDescription`
        // falls back to JSON. Either way a plain contains-check finds the
        // authored Chinese string for users.
        if let range = raw.range(of: "ERROR:") {
            return String(raw[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return raw
    }
}

// MARK: - Revoke affordance gating

public extension ApprovalDetailViewModel {
    /// Matches the Web revoke-button gate
    /// (`approval-item-card.tsx` / `approval-detail-dialog.tsx` surface
    /// the affordance only for the user's own approved comp-time leave
    /// whose start_date is strictly in the future).
    var canRevokeCompTime: Bool {
        guard let req = request else { return false }
        guard req.requestType == .leave else { return false }
        guard req.status == .approved else { return false }
        guard case .leave(let leave) = typedDetail else { return false }
        guard leave.leaveType == .compTime else { return false }

        let todayUTC = Self.todayUTCString
        return leave.startDate > todayUTC
    }

    /// Original comp-time window, surfaced to the revoke sheet header.
    var compTimeWindow: (start: String, end: String)? {
        guard case .leave(let leave) = typedDetail else { return nil }
        return (leave.startDate, leave.endDate)
    }

    private static var todayUTCString: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
