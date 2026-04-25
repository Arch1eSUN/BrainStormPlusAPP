import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Sprint 4.3 — Approver queue ViewModel.
//
// Per-tab loader. One ViewModel instance per `ApprovalQueueKind`
// (leave / field_work / business_trip / expense / report / generic),
// mirroring the Web 1-component-per-tab layout
// (src/app/dashboard/approval/_tabs/*-list.tsx).
//
// Fetch shape parity with Web `fetchApprovalsByType`
// (src/lib/actions/approval-requests.ts:389-533):
//   1. SELECT approval_requests with nested `approval_request_leave`
//      (flat columns up at the row level via the flat `ApprovalListRow`
//      decoder)
//   2. Excludes self at query level via `.neq('requester_id', <uid>)`
//      — on iOS we rely on RLS (027:115-120, SELECT policy) + the neq
//      filter together: non-approvers who somehow reach this VM will
//      hit an empty list because RLS filters out non-self rows AND we
//      excluded self
//   3. Batch-fetches `profiles(id, full_name, avatar_url)` for all
//      unique requester_ids, post-injects into each row
//
// Write path: `applyAction` calls the SECURITY DEFINER RPC
// `approvals_apply_action(p_request_id, p_decision, p_comment)` (see
// migration 20260421170000_approvals_apply_action_rpc.sql). Leave rows
// surface a Chinese error via the RPC's RAISE; the view still shows
// the action buttons but tapping them will post that error to the
// banner. Alternative: gate buttons client-side off
// `ApprovalQueueKind.supportsWriteOnIOS` — done in the view layer.
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class ApprovalQueueViewModel: ObservableObject {
    // `rows` / `pendingCount` / `isLoading` are read-only from outside;
    // `errorMessage` mutable for `.zyErrorBanner($vm.errorMessage)` dismiss.
    @Published public private(set) var rows: [ApprovalListRow] = []
    @Published public private(set) var pendingCount: Int = 0
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?

    /// Per-row busy state — keyed by request id so multiple rows can
    /// animate independently without a shared "global" spinner
    /// blocking the whole list. Matches Web's `busyId` + disabled state
    /// pattern (leave-list.tsx:60-66).
    @Published public private(set) var busyIds: Set<UUID> = []

    public let kind: ApprovalQueueKind
    private let client: SupabaseClient

    public init(kind: ApprovalQueueKind, client: SupabaseClient) {
        self.kind = kind
        self.client = client
    }

    // MARK: - Load

    /// Loads rows for the configured queue kind + post-injects requester
    /// profiles. Mirrors the 2-step fetch shape from Web `fetchApprovalsByType`
    /// — self-exclusion via `.neq`, batch profile join via `.in('id', …)`.
    public func load(limit: Int = 200) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let currentUserId: UUID
        do {
            currentUserId = try await client.auth.session.user.id
        } catch {
            errorMessage = "请先登录"
            return
        }

        do {
            // Step 1 — rows. Embed the nested leave detail; the row
            // decoder flattens it.
            let fetched: [ApprovalListRow] = try await client
                .from("approval_requests")
                .select("""
                    id,
                    request_type,
                    status,
                    priority_by_requester,
                    business_reason,
                    requester_id,
                    reviewer_id,
                    reviewer_note,
                    reviewed_at,
                    created_at,
                    approval_request_leave ( leave_type, start_date, end_date, days )
                """)
                .in("request_type", values: kind.requestTypes)
                .neq("requester_id", value: currentUserId.uuidString)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value

            // Step 2 — batch profile fetch.
            let requesterIds = Array(Set(fetched.map(\.requesterId)))
            let profileMap: [UUID: ApprovalActorProfile]
            if requesterIds.isEmpty {
                profileMap = [:]
            } else {
                profileMap = try await fetchProfiles(ids: requesterIds)
            }

            // Step 3 — post-inject profiles.
            var merged = fetched
            for i in merged.indices {
                merged[i].requesterProfile = profileMap[merged[i].requesterId]
            }

            self.rows = merged
            self.pendingCount = merged.filter { $0.status == .pending }.count
        } catch {
            // Bug-fix(审批中心顶部分类点击红色报错):
            // 切 pillBar tab 触发 .task -> load(),decode 失败 / 网络瞬断
            // 都会让 banner 闪一下;首屏切换 tab 用户预期看到的是"暂无审批"
            // empty state,而不是顶部红条。区分错误类型:
            //   • auth / 权限 / 网络 -> 仍设 banner(用户应该看到)
            //   • decode / 其他 -> silent + console,留 row 空让 empty state 显示
            // 配合 ErrorLocalizer 的 keyword map,banner 文案命中明确分类才弹。
            let raw = error.localizedDescription
            let userFacingKeywords = [
                "Auth session", "session_not_found", "JWT",
                "not authenticated", "row-level security",
                "permission denied", "network", "offline",
                "timed out", "timeout"
            ]
            let shouldShowBanner = userFacingKeywords.contains { keyword in
                raw.localizedCaseInsensitiveContains(keyword)
            }
            if shouldShowBanner {
                self.errorMessage = ErrorLocalizer.localize(error)
            } else {
                #if DEBUG
                print("[ApprovalQueueViewModel] silent load error (kind=\(kind.rawValue)): \(raw)")
                #endif
                self.rows = []
                self.pendingCount = 0
            }
        }
    }

    // MARK: - Pending count (head-only)

    /// Lightweight HEAD count for tab-badge display without fetching
    /// rows. Matches the iOS count convention:
    ///   `.select("*", head: true, count: .exact).execute().count`.
    ///
    /// Mirrors Web's per-tab `result.pendingCount` plumbed through the
    /// `onPendingChange` callback (approval-requests.ts:528). Filter
    /// shape parity: same `request_type IN (...)`, same self-exclusion
    /// via `.neq(requester_id)`, plus `status = 'pending'`.
    ///
    /// Returns 0 on any failure (silent) — a failed count isn't worth
    /// surfacing a banner for, and the main `load()` path carries the
    /// actual error when the tab gets opened.
    public static func fetchPendingCount(
        kind: ApprovalQueueKind,
        client: SupabaseClient
    ) async -> Int {
        do {
            let currentUserId = try await client.auth.session.user.id
            let response = try await client
                .from("approval_requests")
                .select("*", head: true, count: .exact)
                .in("request_type", values: kind.requestTypes)
                .eq("status", value: "pending")
                .neq("requester_id", value: currentUserId.uuidString)
                .execute()
            return response.count ?? 0
        } catch {
            return 0
        }
    }

    // MARK: - Apply action (approve / reject)

    /// Calls the `approvals_apply_action` SECURITY DEFINER RPC. On
    /// success refreshes the queue so the row moves out of the
    /// pending count and into the approved/rejected bucket. On failure
    /// surfaces the RPC's RAISE message (Chinese) via `errorMessage`.
    ///
    /// Returns `true` on success — callers that want to close a
    /// confirmation sheet can read the return value.
    @discardableResult
    public func applyAction(
        to requestId: UUID,
        decision: ApprovalActionDecision,
        comment: String?
    ) async -> Bool {
        // Defense-in-depth: the RPC already RAISEs on this condition, but
        // we short-circuit to avoid a round-trip + give a cleaner banner
        // if a future caller forgets the comment sheet.
        let normalizedComment = comment?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if decision == .reject && normalizedComment == nil {
            errorMessage = "拒绝需填写原因"
            return false
        }

        busyIds.insert(requestId)
        errorMessage = nil
        defer { busyIds.remove(requestId) }

        struct Params: Encodable {
            let p_request_id: String
            let p_decision: String
            let p_comment: String?
        }

        do {
            let _: UUID = try await client
                .rpc(
                    "approvals_apply_action",
                    params: Params(
                        p_request_id: requestId.uuidString,
                        p_decision: decision.rawValue,
                        p_comment: normalizedComment
                    )
                )
                .execute()
                .value

            // Refresh the queue so the pendingCount badge updates and
            // the row reflects its new status. Cheap because the list
            // is capped at 200.
            await load()
            return true
        } catch {
            self.errorMessage = prettyRPCError(error)
            return false
        }
    }

    // MARK: - Private

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

    /// PostgREST wraps `RAISE EXCEPTION '<msg>'` in extra framing.
    /// Matches `ApprovalDetailViewModel.prettyRPCError` — strip the
    /// `ERROR:` prefix so the toast shows the Chinese guard message
    /// verbatim.
    private func prettyRPCError(_ error: Error) -> String {
        let raw = error.localizedDescription
        if let range = raw.range(of: "ERROR:") {
            return String(raw[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return raw
    }
}

private extension String {
    /// Helper so `applyAction`'s optional-empty-string normalization
    /// matches what the RPC treats as "no comment" (NULL after btrim).
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
