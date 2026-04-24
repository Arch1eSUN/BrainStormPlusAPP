import Foundation
import Combine
import Supabase

/// View model backing `OKRListView`. Mirrors Web's `OkrPage` in
/// `BrainStorm+-Web/src/app/dashboard/okr/page.tsx` +
/// `fetchObjectives` / `fetchOkrStats` in
/// `BrainStorm+-Web/src/lib/actions/okr.ts:86-148`.
///
/// ── Visibility model ───────────────────────────────────────────────────
/// Web RLS on `public.objectives` is `FOR SELECT USING (true)` (see
/// `BrainStorm+-Web/supabase/migrations/004_schema_alignment.sql:149-158`)
/// and the matching row on `key_results` (`:160-163`). That means **every
/// authenticated user sees every OKR in the workspace** — there is no
/// self/manager/department gating. Only writes are restricted:
/// owner OR admin/manager via the `Owners manage objectives` policy.
///
/// iOS mirrors this faithfully: the list is fetched with no client-side
/// filter on `owner_id` / `assignee_id`. Web's server action *does* compute
/// `org_id` on insert, so the server already limits what the session can
/// read — we don't add any extra scope.
///
/// Read-only surface for this pass: no create/edit/delete/check-in. Those
/// land in a later iOS batch.
@MainActor
public class OKRListViewModel: ObservableObject {
    @Published public private(set) var objectives: [Objective] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    /// Selected period, in Web's `yyyy-Q{1-4}` format (e.g. `2026-Q1`).
    /// Defaults to the current calendar quarter at construction time —
    /// mirrors Web defaulting to `2026-Q1` in `page.tsx:32`.
    @Published public var period: String

    /// Active employees available as assignee picks for OKR create/edit.
    /// Loaded on demand from the sheet via `loadAvailableAssignees()`.
    /// Mirrors the `profiles` select pattern used in
    /// `DeliverableListViewModel.runFilterOptionsQuery()`.
    @Published public private(set) var availableAssignees: [AssigneeOption] = []

    /// Minimal profile row used by the assignee picker. Kept local to
    /// the VM so we don't add a public type to Core/Models for a
    /// picker-only projection.
    public struct AssigneeOption: Identifiable, Hashable, Decodable {
        public let id: UUID
        public let fullName: String?
        public let avatarUrl: String?

        enum CodingKeys: String, CodingKey {
            case id
            case fullName = "full_name"
            case avatarUrl = "avatar_url"
        }
    }

    private let client: SupabaseClient

    public init(client: SupabaseClient, initialPeriod: String? = nil) {
        self.client = client
        self.period = initialPeriod ?? Self.currentQuarter()
    }

    // MARK: - Period helpers

    /// Returns the current calendar-year quarter as `yyyy-Q{1-4}`.
    public static func currentQuarter(reference: Date = Date()) -> String {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month], from: reference)
        let year = comps.year ?? 2026
        let month = comps.month ?? 1
        let q = ((month - 1) / 3) + 1
        return "\(year)-Q\(q)"
    }

    /// Parses a period string back into `(year, quarter)` for the picker.
    public static func parsePeriod(_ period: String) -> (year: Int, quarter: Int)? {
        // Format: "yyyy-Q{1-4}"
        let parts = period.split(separator: "-")
        guard parts.count == 2 else { return nil }
        guard let year = Int(parts[0]) else { return nil }
        let qStr = parts[1]
        guard qStr.hasPrefix("Q"), let q = Int(qStr.dropFirst()) else { return nil }
        return (year, q)
    }

    public static func formatPeriod(year: Int, quarter: Int) -> String {
        "\(year)-Q\(quarter)"
    }

    /// Year range offered by the picker — Web hardcodes 2026 only, iOS
    /// allows one year back / forward for flexibility.
    public var availableYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return [current - 1, current, current + 1]
    }

    public var availableQuarters: [Int] { [1, 2, 3, 4] }

    // MARK: - Derived stats (mirror Web `fetchOkrStats`)

    public struct Stats: Equatable {
        public let totalObjectives: Int
        public let avgProgress: Int
        public let completedCount: Int
        /// Objectives with `status == .active` AND `computedProgress < 30`.
        /// Matches Web `okr.ts:139`.
        public let atRiskCount: Int
    }

    public var stats: Stats {
        let total = objectives.count
        if total == 0 {
            return Stats(totalObjectives: 0, avgProgress: 0, completedCount: 0, atRiskCount: 0)
        }
        let avg = objectives.reduce(0) { $0 + $1.computedProgress } / total
        let completed = objectives.filter { $0.status == .completed }.count
        let atRisk = objectives.filter {
            $0.status == .active && $0.computedProgress < 30
        }.count
        return Stats(
            totalObjectives: total,
            avgProgress: avg,
            completedCount: completed,
            atRiskCount: atRisk
        )
    }

    /// Mirrors the header badge in `page.tsx:276` — mean of mean-of-KRs
    /// across all visible objectives (unweighted).
    public var overallProgress: Int {
        guard !objectives.isEmpty else { return 0 }
        let sum = objectives.reduce(0) { $0 + $1.computedProgress }
        return sum / objectives.count
    }

    // MARK: - Fetch

    /// Mirrors Web `fetchObjectives(period)` in `okr.ts:86-110` — embeds KRs
    /// via PostgREST's nested select syntax (`objectives(*, key_results(*))`).
    public func fetchObjectives() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rows: [Objective] = try await client
                .from("objectives")
                .select("*, key_results(*)")
                .eq("period", value: period)
                .order("created_at", ascending: false)
                .execute()
                .value
            self.objectives = rows
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    // MARK: - Mutations
    //
    // Parity with Web `okr.ts` server actions (createObjective,
    // updateObjective, createKeyResult, updateKeyResult). Web routes through a
    // service-role admin client after `serverGuard()`; iOS relies on the
    // authenticated user's Supabase client + RLS (`Owners manage objectives`
    // policy — owner OR admin/manager via `profiles.role`).
    //
    // RLS assumptions this code leans on (backend should verify):
    //   • `objectives` insert allowed when `owner_id = auth.uid()`
    //   • `objectives` update allowed when `auth.uid() = owner_id` OR role
    //     is super_admin/admin/manager
    //   • `key_results` insert allowed when parent objective is writable
    //     (Web `004_schema_alignment.sql:160-163` + migrations chain)
    //   • `org_id` is nullable on `objectives` (confirmed in
    //     `001_rbac_multi_tenant.sql:37`) — we best-effort populate it from
    //     the caller's `profiles.org_id` just like Web does.

    /// Create a new objective row. Mirrors Web `createObjective` in
    /// `okr.ts:152-184`. Returns the inserted row so the caller can route
    /// to it if needed. List is re-fetched afterwards to refresh the
    /// published state.
    public func createObjective(
        title: String,
        description: String?,
        ownerId: UUID? = nil,
        assigneeId: UUID? = nil,
        period: String? = nil
    ) async throws -> Objective {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw NSError(
                domain: "OKRListViewModel",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "目标名称不能为空"]
            )
        }

        // Resolve owner: explicit arg > current authenticated user.
        let resolvedOwnerId: UUID
        if let ownerId = ownerId {
            resolvedOwnerId = ownerId
        } else {
            resolvedOwnerId = try await client.auth.session.user.id
        }

        // Mirror Web: read `profiles.org_id` and pass it through so inserts
        // scope correctly. Nullable — leave nil if the user has none, RLS
        // still gates the insert by owner.
        let orgId = try? await fetchCurrentOrgId(userId: resolvedOwnerId)

        let targetPeriod = period ?? self.period

        let payload = ObjectiveInsert(
            title: trimmedTitle,
            description: description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            period: targetPeriod,
            owner_id: resolvedOwnerId,
            assignee_id: assigneeId,
            org_id: orgId,
            status: Objective.ObjectiveStatus.active.rawValue,
            progress: 0
        )

        let inserted: Objective = try await client
            .from("objectives")
            .insert(payload)
            .select("*, key_results(*)")
            .single()
            .execute()
            .value

        await fetchObjectives()
        return inserted
    }

    /// Update an existing objective's editable metadata. Mirrors Web
    /// `updateObjective` in `okr.ts:188-218` (title / description /
    /// assignee_id only — status goes through a separate transition API).
    public func updateObjective(_ objective: Objective) async throws {
        let trimmedTitle = objective.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw NSError(
                domain: "OKRListViewModel",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "目标名称不能为空"]
            )
        }

        let payload = ObjectiveUpdate(
            title: trimmedTitle,
            description: objective.description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            assignee_id: objective.assigneeId
        )

        try await client
            .from("objectives")
            .update(payload)
            .eq("id", value: objective.id.uuidString)
            .execute()

        await fetchObjectives()
    }

    /// Add a new KR under an existing objective. Mirrors Web
    /// `createKeyResult` in `okr.ts:259-280`. `current_value` starts at 0.
    public func addKeyResult(
        objectiveId: UUID,
        title: String,
        target: Double,
        unit: String?
    ) async throws -> KeyResult {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw NSError(
                domain: "OKRListViewModel",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "KR 名称不能为空"]
            )
        }
        guard target > 0 else {
            throw NSError(
                domain: "OKRListViewModel",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "目标值必须大于 0"]
            )
        }

        let payload = KeyResultInsert(
            objective_id: objectiveId,
            title: trimmedTitle,
            target_value: target,
            current_value: 0,
            unit: unit?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )

        let inserted: KeyResult = try await client
            .from("key_results")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value

        await fetchObjectives()
        return inserted
    }

    /// Update a KR's current value (check-in). Mirrors Web
    /// `updateKeyResult` in `okr.ts:284-317`. The `note` parameter is
    /// accepted for forward-compat but not yet persisted — Web doesn't
    /// store check-in notes either, and there's no target table on
    /// `key_results` for it. TODO: add a `kr_check_ins` log table if the
    /// product team wants history.
    public func updateKeyResultProgress(
        keyResultId: UUID,
        progress: Double,
        note: String? = nil
    ) async throws {
        guard progress >= 0 else {
            throw NSError(
                domain: "OKRListViewModel",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "进度值不能为负数"]
            )
        }

        let payload = KeyResultProgressUpdate(current_value: progress)

        try await client
            .from("key_results")
            .update(payload)
            .eq("id", value: keyResultId.uuidString)
            .execute()

        _ = note  // reserved for a future `kr_check_ins` table
        await fetchObjectives()
    }

    /// Mirrors Web `updateKeyResultMeta` in `okr.ts:321-373`. Updates KR
    /// `title` / `target_value` / `unit`. Guards parity with Web:
    ///   • title 非空
    ///   • target_value > 0
    ///   • target_value ≥ current_value（不能把门槛降到已有进度以下）
    ///   • parent objective.status != completed（已完成目标锁定 KR 编辑）
    /// Writes an activity_log entry on success (non-blocking).
    public func updateKeyResultMeta(
        keyResultId: UUID,
        title: String?,
        targetValue: Double?,
        unit: String?
    ) async throws {
        // Fetch current KR (need current_value + objective_id).
        struct KrFetchRow: Decodable {
            let id: UUID
            let title: String
            let current_value: Double
            let objective_id: UUID
        }
        let krRow: KrFetchRow = try await client
            .from("key_results")
            .select("id, title, current_value, objective_id")
            .eq("id", value: keyResultId.uuidString)
            .single()
            .execute()
            .value

        // Fetch parent objective status — Web blocks edits on completed OKRs.
        struct ObjStatusRow: Decodable {
            let status: String?
        }
        let objRow: ObjStatusRow = try await client
            .from("objectives")
            .select("status")
            .eq("id", value: krRow.objective_id.uuidString)
            .single()
            .execute()
            .value
        if objRow.status == Objective.ObjectiveStatus.completed.rawValue {
            throw NSError(
                domain: "OKRListViewModel",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "已完成的目标无法编辑 KR"]
            )
        }

        // Build partial payload with per-field validation mirroring Web.
        var trimmedTitle: String? = nil
        if let t = title {
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw NSError(
                    domain: "OKRListViewModel",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "KR 名称不能为空"]
                )
            }
            trimmedTitle = trimmed
        }

        if let target = targetValue {
            guard target > 0 else {
                throw NSError(
                    domain: "OKRListViewModel",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "目标值必须大于 0"]
                )
            }
            if target < krRow.current_value {
                throw NSError(
                    domain: "OKRListViewModel",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "目标值不能小于当前进度 \(formatTrailing(krRow.current_value))"]
                )
            }
        }

        let unitValue: String?? = unit.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }

        let payload = KeyResultMetaUpdate(
            title: trimmedTitle,
            target_value: targetValue,
            unit: unitValue
        )

        try await client
            .from("key_results")
            .update(payload)
            .eq("id", value: keyResultId.uuidString)
            .execute()

        await fetchObjectives()

        let logTitle = trimmedTitle ?? krRow.title
        await ActivityLogWriter.write(
            client: client,
            type: .okr,
            action: "update_kr_meta",
            description: "编辑了 KR「\(logTitle)」",
            entityType: "key_result",
            entityId: keyResultId
        )
    }

    /// Mirrors Web `updateObjectiveStatus` in `okr.ts:229-255`. Fetches
    /// current status and enforces the `VALID_STATUS_TRANSITIONS` state
    /// machine:
    ///   draft      → active | cancelled
    ///   active     → completed | cancelled
    ///   completed  → ∅ (terminal)
    ///   cancelled  → draft (re-open)
    /// Writes an activity_log entry on success (non-blocking).
    public func updateObjectiveStatus(
        objectiveId: UUID,
        newStatus: Objective.ObjectiveStatus
    ) async throws {
        struct ObjRow: Decodable {
            let status: String?
            let title: String
        }
        let obj: ObjRow = try await client
            .from("objectives")
            .select("status, title")
            .eq("id", value: objectiveId.uuidString)
            .single()
            .execute()
            .value

        let currentRaw = obj.status ?? Objective.ObjectiveStatus.active.rawValue
        guard let current = Objective.ObjectiveStatus(rawValue: currentRaw) else {
            throw NSError(
                domain: "OKRListViewModel",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "目标状态异常"]
            )
        }

        let allowed = Self.validStatusTransitions[current] ?? []
        guard allowed.contains(newStatus) else {
            throw NSError(
                domain: "OKRListViewModel",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "不允许从「\(current.displayLabel)」转到「\(newStatus.displayLabel)」"]
            )
        }

        let payload = ObjectiveStatusUpdate(status: newStatus.rawValue)
        try await client
            .from("objectives")
            .update(payload)
            .eq("id", value: objectiveId.uuidString)
            .execute()

        await fetchObjectives()

        let verb: String
        switch newStatus {
        case .active: verb = "启用"
        case .completed: verb = "标记为已完成"
        case .cancelled: verb = "取消"
        case .draft: verb = "重开为草稿"
        }
        await ActivityLogWriter.write(
            client: client,
            type: .okr,
            action: "update_objective_status",
            description: "将目标「\(obj.title)」\(verb)",
            entityType: "objective",
            entityId: objectiveId
        )
    }

    /// Mirrors Web `deleteObjective` in `okr.ts:377-383`. DB cascades to
    /// KRs via FK (see migrations). Writes an activity_log entry.
    public func deleteObjective(objectiveId: UUID) async throws {
        // Read title first so the log entry stays readable post-delete.
        let title = (try? await fetchEntityTitle(
            table: "objectives",
            id: objectiveId
        )) ?? "未命名"

        try await client
            .from("objectives")
            .delete()
            .eq("id", value: objectiveId.uuidString)
            .execute()

        await fetchObjectives()

        await ActivityLogWriter.write(
            client: client,
            type: .okr,
            action: "delete_objective",
            description: "删除了目标「\(title)」",
            entityType: "objective",
            entityId: objectiveId
        )
    }

    /// Mirrors Web `deleteKeyResult` in `okr.ts:387-393`.
    public func deleteKeyResult(keyResultId: UUID) async throws {
        let title = (try? await fetchEntityTitle(
            table: "key_results",
            id: keyResultId
        )) ?? "未命名"

        try await client
            .from("key_results")
            .delete()
            .eq("id", value: keyResultId.uuidString)
            .execute()

        await fetchObjectives()

        await ActivityLogWriter.write(
            client: client,
            type: .okr,
            action: "delete_key_result",
            description: "删除了 KR「\(title)」",
            entityType: "key_result",
            entityId: keyResultId
        )
    }

    /// Small helper — reads `title` off any row in a single-column select,
    /// returning nil-friendly String so we still log on fetch failure.
    private func fetchEntityTitle(table: String, id: UUID) async throws -> String {
        struct TitleRow: Decodable { let title: String }
        let row: TitleRow = try await client
            .from(table)
            .select("title")
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
        return row.title
    }

    /// Mirror Web `VALID_STATUS_TRANSITIONS` in `okr.ts:222-227`.
    public static let validStatusTransitions: [Objective.ObjectiveStatus: [Objective.ObjectiveStatus]] = [
        .draft: [.active, .cancelled],
        .active: [.completed, .cancelled],
        .completed: [],
        .cancelled: [.draft]
    ]

    private func formatTrailing(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(v)) }
        return String(format: "%.1f", v)
    }

    // MARK: - Insert/update payloads

    // Kept nested so these stay local to OKR mutations and don't leak
    // into the wider Core/Models namespace (those types model DB rows,
    // not wire payloads).

    private struct ObjectiveInsert: Encodable {
        let title: String
        let description: String?
        let period: String
        let owner_id: UUID
        let assignee_id: UUID?
        let org_id: UUID?
        let status: String
        let progress: Int
    }

    private struct ObjectiveUpdate: Encodable {
        let title: String
        let description: String?
        let assignee_id: UUID?
    }

    private struct KeyResultInsert: Encodable {
        let objective_id: UUID
        let title: String
        let target_value: Double
        let current_value: Double
        let unit: String?
    }

    private struct KeyResultProgressUpdate: Encodable {
        let current_value: Double
    }

    /// Partial KR meta update. Fields set to `nil` on the wrapper are
    /// omitted from the request; fields with `Optional<String>.some(nil)`
    /// explicitly clear the column (used by `unit` to allow removal).
    private struct KeyResultMetaUpdate: Encodable {
        let title: String?
        let target_value: Double?
        /// Outer nil = omit key; inner nil = explicit null (clear unit).
        let unit: String??

        enum CodingKeys: String, CodingKey {
            case title
            case target_value
            case unit
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if let title = title { try c.encode(title, forKey: .title) }
            if let target = target_value { try c.encode(target, forKey: .target_value) }
            if let unitOuter = unit {
                if let unitInner = unitOuter {
                    try c.encode(unitInner, forKey: .unit)
                } else {
                    try c.encodeNil(forKey: .unit)
                }
            }
        }
    }

    private struct ObjectiveStatusUpdate: Encodable {
        let status: String
    }

    // MARK: - Assignee directory

    /// Loads the active-employee directory for OKREditSheet's assignee
    /// picker. Mirrors the `profiles` projection used by
    /// `DeliverableListViewModel.runFilterOptionsQuery()` — read-only,
    /// cheap, and gated by the same RLS as every other profile read.
    /// Silently no-ops on error (picker just shows the empty list — the
    /// user can still save without assigning).
    public func loadAvailableAssignees() async {
        do {
            let rows: [AssigneeOption] = try await client
                .from("profiles")
                .select("id, full_name, avatar_url")
                .eq("status", value: "active")
                .order("full_name", ascending: true)
                .execute()
                .value
            self.availableAssignees = rows
        } catch {
            // Non-fatal: the picker just stays empty.
            self.availableAssignees = []
        }
    }

    // MARK: - Helpers

    /// Mirrors Web `getCurrentOrgId` in `okr.ts:43-67` (minus the admin
    /// fallback — iOS doesn't have a service-role client). Reading a
    /// single `profiles.org_id` row is well within the user's RLS scope.
    private func fetchCurrentOrgId(userId: UUID) async throws -> UUID? {
        struct Row: Decodable {
            let orgId: UUID?
            enum CodingKeys: String, CodingKey { case orgId = "org_id" }
        }
        let rows: [Row] = try await client
            .from("profiles")
            .select("org_id")
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first?.orgId
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
