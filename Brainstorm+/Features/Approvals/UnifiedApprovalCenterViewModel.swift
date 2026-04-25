import Foundation
import Combine
import Supabase

/// Sprint 4.5 (redesign) — Unified ViewModel backing the redesigned
/// `ApprovalCenterView`.
///
/// Replaces the per-tab split (`MySubmissionsViewModel` +
/// `ApprovalQueueViewModel`) with a single VM that owns both modes.
/// Reasons:
///   1. The redesigned center renders BOTH modes from one View, with
///      a unified header (segmented `我审 / 我提` + kind chip scroller)
///      + a single sectioned list. Splitting state across two VMs
///      produced the "tab-blank from MainTabView" race that motivated
///      this redesign — depending on which subview's `.task` fired
///      first, the user could land on a queue tab whose VM never
///      received its `load()` trigger.
///   2. `refreshIfStale` semantics are simpler with one cache TTL per
///      (mode, kind) cell rather than per-VM-instance state that gets
///      dropped on tab swap.
///
/// Caching strategy:
///   - `mineRows: [ApprovalMySubmissionRow]` — single bucket, reused
///     across kind filter (filter is local). Refreshed on user action
///     or stale TTL.
///   - `queueRowsByKind: [ApprovalQueueKind: [ApprovalListRow]]` —
///     per-kind cache. Switching chip is instant (cache hit), pull-to-
///     refresh always reloads.
///   - `lastFetchAt: [CacheKey: Date]` — TTL gate consumed by
///     `refreshIfStale(...)`.
///
/// Write path: `applyAction` does optimistic local removal of the row
/// from `queueRowsByKind`, then calls the SECURITY DEFINER RPC, then
/// re-fetches the queue in the background to reconcile state. On RPC
/// failure the row is restored.
@MainActor
public final class UnifiedApprovalCenterViewModel: ObservableObject {

    // MARK: - Mode

    public enum Mode: String, Hashable {
        case queue   // 我审
        case mine    // 我提

        public var label: String {
            switch self {
            case .queue: return "我审"
            case .mine:  return "我提"
            }
        }
    }

    // MARK: - Cache key

    private struct CacheKey: Hashable {
        let mode: Mode
        // Mine mode ignores kind (filter is local); we encode `nil` as
        // a sentinel so the dictionary key still hashes uniquely.
        let kind: ApprovalQueueKind?
    }

    // MARK: - State

    @Published public private(set) var mineRows: [ApprovalMySubmissionRow] = []
    @Published public private(set) var queueRowsByKind: [ApprovalQueueKind: [ApprovalListRow]] = [:]
    @Published public private(set) var pendingCounts: [ApprovalQueueKind: Int] = [:]
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var busyIds: Set<UUID> = []
    @Published public var errorMessage: String?
    /// Iter 6 review §B.4 — set per-cell when the slice is sourced from
    /// EntityCache and the network refresh hasn't finished. The view
    /// uses it together with `NetworkMonitor.isOnline` to decide whether
    /// to flag the section as offline-stale.
    @Published public private(set) var cachedCells: Set<String> = []

    private var lastFetchAt: [CacheKey: Date] = [:]
    private let staleAfter: TimeInterval = 60   // refreshIfStale debounce

    private let client: SupabaseClient

    /// Iter 8 P1 §B.9 — Realtime cross-device sync. Watches the parent
    /// `approval_requests` table; on any INSERT/UPDATE/DELETE we
    /// derive the affected ApprovalQueueKind from the row's
    /// `request_type` and re-fetch that kind's slice (the live row
    /// needs the requester profile join we'd lose otherwise).
    private let realtimeSync: RealtimeListSync

    public init(client: SupabaseClient) {
        self.client = client
        self.realtimeSync = RealtimeListSync(client: client, tableName: "approval_requests")
    }

    // MARK: - Realtime (Iter 8 P1 §B.9)

    public func subscribeRealtime() async {
        guard !realtimeSync.isActive else { return }
        await realtimeSync.start { [weak self] change in
            guard let self else { return }
            self.handleRealtime(change)
        }
    }

    public func unsubscribeRealtime() async {
        await realtimeSync.stop()
    }

    private func handleRealtime(_ change: RealtimeListChange) {
        // Approval rows carry per-leaf joins (leave details, requester
        // profile) that the WAL payload doesn't include — so on every
        // event we reload the affected kind's slice in the background
        // rather than trying to splice the partial payload in-place.
        let payload: JSONObject
        switch change {
        case .insert(let row): payload = row
        case .update(let newRow, _): payload = newRow
        case .delete(let oldRow): payload = oldRow
        }

        let kind: ApprovalQueueKind? = kindForPayload(payload)

        // Mine view: refresh if it's the current user's submission.
        Task { [weak self] in
            guard let self else { return }
            if let uid = try? await self.client.auth.session.user.id,
               let requesterId = payload.uuidColumn("requester_id"),
               requesterId == uid {
                await self.refresh(mode: .mine, kind: nil)
            }
            if let kind {
                await self.refresh(mode: .queue, kind: kind)
                await self.refreshPendingCounts(for: [kind])
            } else {
                // Couldn't decode kind — refresh all loaded queues.
                let active = Array(self.queueRowsByKind.keys)
                for k in active {
                    await self.refresh(mode: .queue, kind: k)
                }
                if !active.isEmpty {
                    await self.refreshPendingCounts(for: active)
                }
            }
        }
    }

    private func kindForPayload(_ payload: JSONObject) -> ApprovalQueueKind? {
        guard let raw = payload["request_type"] else { return nil }
        let rawString: String
        switch raw {
        case .string(let s): rawString = s
        default: return nil
        }
        return ApprovalQueueKind.allCases.first { $0.requestTypes.contains(rawString) }
    }

    // MARK: - Public API

    /// Force-load (or first-load). Bypasses TTL.
    public func refresh(mode: Mode, kind: ApprovalQueueKind?) async {
        await load(mode: mode, kind: kind, force: true)
    }

    /// Honor TTL; only reload if cache is older than `staleAfter`. Called
    /// from `.onAppear` so re-entering the tab doesn't spinner-flash.
    public func refreshIfStale(mode: Mode, kind: ApprovalQueueKind?) async {
        let key = CacheKey(mode: mode, kind: kind)
        if let last = lastFetchAt[key], Date().timeIntervalSince(last) < staleAfter {
            return
        }
        await load(mode: mode, kind: kind, force: true)
    }

    /// Refresh the pending head-counts for all visible queue kinds.
    /// Cheap (HEAD-only); used to drive the count badges next to chips.
    public func refreshPendingCounts(for kinds: [ApprovalQueueKind]) async {
        guard !kinds.isEmpty else { return }
        await withTaskGroup(of: (ApprovalQueueKind, Int).self) { group in
            for kind in kinds {
                group.addTask { [client] in
                    let n = await ApprovalQueueViewModel
                        .fetchPendingCount(kind: kind, client: client)
                    return (kind, n)
                }
            }
            for await (kind, n) in group {
                pendingCounts[kind] = n
            }
        }
    }

    /// Apply approve / reject. Optimistic remove; reconcile on RPC return.
    @discardableResult
    public func applyAction(
        on row: ApprovalListRow,
        kind: ApprovalQueueKind,
        decision: ApprovalActionDecision,
        comment: String?
    ) async -> Bool {
        let trimmedComment = comment?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        if decision == .reject && trimmedComment == nil {
            errorMessage = "拒绝需填写原因"
            return false
        }

        busyIds.insert(row.id)
        defer { busyIds.remove(row.id) }

        // Optimistic remove (only for pending rows — we intentionally
        // keep approved/rejected visible so users see history).
        let snapshot = queueRowsByKind[kind] ?? []
        if row.status == .pending {
            queueRowsByKind[kind] = snapshot.filter { $0.id != row.id }
            if let current = pendingCounts[kind], current > 0 {
                pendingCounts[kind] = current - 1
            }
        }

        // Iter 6 review §B.4 — when offline, persist the decision to
        // the queue and trust the optimistic remove. The handler
        // replays the same RPC server-side once reachability returns.
        if !NetworkMonitor.shared.isOnline {
            let queued = WriteActionHandlers.ApprovalActionPayload(
                request_id: row.id,
                decision: decision.rawValue,
                comment: trimmedComment
            )
            await WriteActionQueue.shared.enqueue(
                kind: WriteActionKind.approvalAction,
                payload: queued
            )
            return true
        }

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
                        p_request_id: row.id.uuidString,
                        p_decision: decision.rawValue,
                        p_comment: trimmedComment
                    )
                )
                .execute()
                .value
            // Background reconcile — keeps server-side state truth-y
            // for status / reviewerNote / reviewedAt.
            Task { await self.refresh(mode: .queue, kind: kind) }
            return true
        } catch {
            // Restore optimistic snapshot.
            queueRowsByKind[kind] = snapshot
            await refreshPendingCounts(for: [kind])
            errorMessage = prettyRPCError(error)
            return false
        }
    }

    // MARK: - Loaders

    private func load(mode: Mode, kind: ApprovalQueueKind?, force: Bool) async {
        let key = CacheKey(mode: mode, kind: kind)
        if !force, let last = lastFetchAt[key], Date().timeIntervalSince(last) < staleAfter {
            return
        }

        isLoading = true
        defer { isLoading = false }

        switch mode {
        case .mine:
            await loadMine()
        case .queue:
            guard let kind else { return }
            await loadQueue(kind: kind)
        }

        lastFetchAt[key] = Date()
    }

    private func loadMine() async {
        let currentUserId: UUID
        do {
            currentUserId = try await client.auth.session.user.id
        } catch {
            errorMessage = "请先登录"
            return
        }

        // Iter 6 review §B.4 — paint cached snapshot first so swapping
        // segmented control to "我提" never shows blank during slow
        // networks / offline.
        if mineRows.isEmpty {
            let key = EntityCacheKey.approvalsMine(userId: currentUserId)
            if let cached: [ApprovalMySubmissionRow] = await EntityCache.shared
                .fetch([ApprovalMySubmissionRow].self, key: key) {
                self.mineRows = cached
                self.cachedCells.insert("mine")
            }
        }

        do {
            let fetched: [ApprovalMySubmissionRow] = try await client
                .from("approval_requests")
                .select("""
                    id,
                    request_type,
                    status,
                    priority_by_requester,
                    business_reason,
                    reviewer_note,
                    reviewed_at,
                    created_at,
                    approval_request_leave ( leave_type, start_date, end_date, days )
                """)
                .eq("requester_id", value: currentUserId.uuidString)
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            self.mineRows = fetched
            self.cachedCells.remove("mine")
            let key = EntityCacheKey.approvalsMine(userId: currentUserId)
            Task { await EntityCache.shared.store(fetched, key: key) }
        } catch {
            handleSilentlyOrSurface(error)
        }
    }

    private func loadQueue(kind: ApprovalQueueKind) async {
        let currentUserId: UUID
        do {
            currentUserId = try await client.auth.session.user.id
        } catch {
            errorMessage = "请先登录"
            return
        }

        // Iter 6 review §B.4 — cache-first paint per-kind. Profile
        // joins live alongside the row in cache so swapping kinds
        // doesn't lose the requester avatar/name.
        let cellKey = "queue::\(kind.rawValue)"
        if (queueRowsByKind[kind]?.isEmpty ?? true) {
            let cacheKey = EntityCacheKey.approvalsQueue(userId: currentUserId, kindRaw: kind.rawValue)
            if let cached: [ApprovalListRow] = await EntityCache.shared
                .fetch([ApprovalListRow].self, key: cacheKey) {
                self.queueRowsByKind[kind] = cached
                self.cachedCells.insert(cellKey)
            }
        }

        do {
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
                .limit(200)
                .execute()
                .value

            // Batch profile join — same posture as ApprovalQueueViewModel.
            let requesterIds = Array(Set(fetched.map(\.requesterId)))
            let profileMap: [UUID: ApprovalActorProfile]
            if requesterIds.isEmpty {
                profileMap = [:]
            } else {
                profileMap = try await fetchProfiles(ids: requesterIds)
            }

            var merged = fetched
            for i in merged.indices {
                merged[i].requesterProfile = profileMap[merged[i].requesterId]
            }

            queueRowsByKind[kind] = merged
            pendingCounts[kind] = merged.filter { $0.status == .pending }.count
            self.cachedCells.remove(cellKey)
            let cacheKey = EntityCacheKey.approvalsQueue(userId: currentUserId, kindRaw: kind.rawValue)
            Task { await EntityCache.shared.store(merged, key: cacheKey) }
        } catch {
            handleSilentlyOrSurface(error)
        }
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

    // MARK: - Error handling

    /// Mirrors the established posture in `ApprovalQueueViewModel.load()`:
    /// surface auth / network / RLS errors via the banner, swallow decode
    /// noise so empty state shows instead of a red bar.
    private func handleSilentlyOrSurface(_ error: Error) {
        // iter6 §B.2 — Cancellation 永远 silent (避免 .task 重入红条)。
        if ErrorLocalizer.isCancellation(error) { return }
        let raw = error.localizedDescription
        let userFacingKeywords = [
            "Auth session", "session_not_found", "JWT",
            "not authenticated", "row-level security",
            "permission denied", "network", "offline",
            "timed out", "timeout"
        ]
        let shouldShowBanner = userFacingKeywords.contains { raw.localizedCaseInsensitiveContains($0) }
        if shouldShowBanner {
            // Iter 7 §C.2 — silent CancellationError;nil 时 banner 不闪屏。
            errorMessage = ErrorPresenter.userFacingMessage(error) ?? errorMessage
        } else {
            #if DEBUG
            print("[UnifiedApprovalCenterViewModel] silent error: \(raw)")
            #endif
        }
    }

    private func prettyRPCError(_ error: Error) -> String {
        let raw = error.localizedDescription
        if let range = raw.range(of: "ERROR:") {
            return String(raw[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return raw
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
