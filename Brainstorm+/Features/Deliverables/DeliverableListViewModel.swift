import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 2.1 — Deliverables list VM.
//
// Parity targets (Web):
//   fetchDeliverables / fetchDeliverableFilterOptions
//     → BrainStorm+-Web/src/lib/actions/deliverables.ts
//   list surface
//     → BrainStorm+-Web/src/app/dashboard/deliverables/page.tsx
//
// Semantics preserved from Web:
//   • fetch orders by `created_at DESC`, joins projects(id, name) +
//     profiles(id, full_name, avatar_url). iOS picks up the extra `id`
//     on each join so we can feed the detail VM without re-fetching.
//   • filters: status / project_id / assignee_id / search (ilike on
//     title) / date_from / date_to. Search + date filters are applied
//     server-side to match Web.
//   • "mine" is a client-side convenience (not a Web filter) — it
//     narrows the already-fetched set to rows whose `assigneeId ==
//     currentUserId`. Web doesn't have this toggle but the brief asks
//     for `fetch + filter (status / project / mine)`, so we add it
//     without touching the server round-trip.
//
// Intentionally NOT ported:
//   • Create / edit / delete flows. Per the batch brief this pass is
//     "list + detail only"; the VM exposes status updates (used by the
//     detail view) but no create/update/delete of the row itself.
//   • Platform-icon mapping (`LINK_PLATFORMS` in page.tsx:23-36) —
//     done in the view layer on iOS too.
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class DeliverableListViewModel: ObservableObject {
    @Published public private(set) var items: [Deliverable] = []
    @Published public private(set) var projects: [Deliverable.RelatedProject] = []
    @Published public private(set) var members: [Deliverable.RelatedProfile] = []
    @Published public private(set) var currentUserId: UUID? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isMutating: Bool = false
    @Published public var errorMessage: String?
    @Published public var successMessage: String?

    // Filters
    @Published public var searchText: String = ""
    @Published public var statusFilter: Deliverable.DeliverableStatus? = nil
    @Published public var projectFilter: UUID? = nil
    @Published public var assigneeFilter: UUID? = nil
    @Published public var onlyMine: Bool = false
    @Published public var dateFrom: Date? = nil
    @Published public var dateTo: Date? = nil

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Derived

    /// `onlyMine` is evaluated client-side — same reason
    /// `TaskListViewModel` evaluates its search locally: keeps the
    /// server query shape aligned with Web.
    public var filteredItems: [Deliverable] {
        guard onlyMine, let uid = currentUserId else { return items }
        return items.filter { $0.assigneeId == uid }
    }

    /// Mirrors `statusCounts` in page.tsx:171-174.
    public var statusCounts: [Deliverable.DeliverableStatus: Int] {
        var acc: [Deliverable.DeliverableStatus: Int] = [:]
        for d in items {
            acc[d.status, default: 0] += 1
        }
        return acc
    }

    // MARK: - Fetch

    /// 1:1 port of `fetchDeliverables(filters)` in deliverables.ts:69-93
    /// — same SELECT shape, same filter semantics.
    public func loadAll() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let itemsTask: [Deliverable] = runItemsQuery()
            async let optionsTask: (projects: [Deliverable.RelatedProject], profiles: [Deliverable.RelatedProfile]) = runFilterOptionsQuery()
            async let sessionTask: UUID = client.auth.session.user.id

            self.items = try await itemsTask
            let opts = try await optionsTask
            self.projects = opts.projects
            self.members = opts.profiles
            self.currentUserId = try await sessionTask
        } catch {
            // Iter 7 §C.2 — silent CancellationError;nil 时 banner 不闪屏。
            self.errorMessage = ErrorPresenter.userFacingMessage(error) ?? self.errorMessage
        }
    }

    /// Re-runs just the list query — used after filter changes and
    /// after a status mutation so the row reflects Web-style
    /// `submitted_at` stamping.
    public func reloadItems() async {
        do {
            self.items = try await runItemsQuery()
        } catch {
            // Iter 7 §C.2 — silent CancellationError;nil 时 banner 不闪屏。
            self.errorMessage = ErrorPresenter.userFacingMessage(error) ?? self.errorMessage
        }
    }

    private func runItemsQuery() async throws -> [Deliverable] {
        var query = client
            .from("deliverables")
            .select(
                """
                id, title, description, url, status,
                project_id, assignee_id, org_id,
                due_date, submitted_at, file_url,
                created_at, updated_at,
                projects:project_id(id, name),
                profiles:assignee_id(id, full_name, avatar_url)
                """
            )

        if let status = statusFilter {
            query = query.eq("status", value: status.rawValue)
        }
        if let pid = projectFilter {
            query = query.eq("project_id", value: pid.uuidString)
        }
        if let aid = assigneeFilter {
            query = query.eq("assignee_id", value: aid.uuidString)
        }
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            query = query.ilike("title", pattern: "%\(needle)%")
        }
        if let from = dateFrom {
            query = query.gte("created_at", value: Self.dayStart(from))
        }
        if let to = dateTo {
            query = query.lte("created_at", value: Self.dayEnd(to))
        }

        return try await query
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    private func runFilterOptionsQuery() async throws -> (
        projects: [Deliverable.RelatedProject],
        profiles: [Deliverable.RelatedProfile]
    ) {
        async let projectsRes: [Deliverable.RelatedProject] = client
            .from("projects")
            .select("id, name")
            .order("name", ascending: true)
            .execute()
            .value

        async let profilesRes: [Deliverable.RelatedProfile] = client
            .from("profiles")
            .select("id, full_name, avatar_url")
            .eq("status", value: "active")
            .order("full_name", ascending: true)
            .execute()
            .value

        return try await (projectsRes, profilesRes)
    }

    // MARK: - Mutations (status / full update / delete — list + detail scope)

    private struct StatusPayload: Encodable {
        let status: String
        let submittedAt: String?
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case status
            case submittedAt = "submitted_at"
            case updatedAt = "updated_at"
        }
    }

    /// Partial-update payload for `updateDeliverable`. Each field is
    /// Optional — `nil` means "leave as-is" so the payload only encodes
    /// the fields that actually changed (mirrors Web's
    /// `updates.field !== undefined` gate in deliverables.ts:136-143).
    ///
    /// Web treats an empty string as "clear the field" (`|| null`). We
    /// replicate that by letting the caller pass `""` — the VM trims
    /// and converts to an explicit `NSNull` before encoding.
    private struct UpdatePayload: Encodable {
        let title: String?
        let description: FieldValue?
        let url: FieldValue?
        let projectId: FieldValue?
        let status: String?
        let submittedAt: String?
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case title
            case description
            case url
            case projectId = "project_id"
            case status
            case submittedAt = "submitted_at"
            case updatedAt = "updated_at"
        }

        /// Tri-state field value:
        ///   • `.skip` — field absent from payload (no change)
        ///   • `.null` — field emitted as JSON `null` (clear column)
        ///   • `.value(x)` — field emitted with encoded value
        enum FieldValue {
            case skip
            case null
            case stringValue(String)
            case uuidValue(UUID)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if let title { try c.encode(title, forKey: .title) }
            try Self.encodeField(description, forKey: .description, into: &c)
            try Self.encodeField(url, forKey: .url, into: &c)
            try Self.encodeField(projectId, forKey: .projectId, into: &c)
            if let status { try c.encode(status, forKey: .status) }
            if let submittedAt { try c.encode(submittedAt, forKey: .submittedAt) }
            try c.encode(updatedAt, forKey: .updatedAt)
        }

        private static func encodeField(
            _ value: FieldValue?,
            forKey key: CodingKeys,
            into container: inout KeyedEncodingContainer<CodingKeys>
        ) throws {
            guard let value else { return }
            switch value {
            case .skip:
                return
            case .null:
                try container.encodeNil(forKey: key)
            case .stringValue(let s):
                try container.encode(s, forKey: key)
            case .uuidValue(let u):
                try container.encode(u, forKey: key)
            }
        }
    }

    // MARK: - Create

    /// Row shape used to resolve the creator's `org_id` — same narrow DTO as
    /// `ProjectCreateViewModel.ProfileOrgRow`. Kept private to avoid leaking
    /// into the `Profile` core model.
    private struct ProfileOrgRow: Decodable {
        let orgId: UUID
        enum CodingKeys: String, CodingKey { case orgId = "org_id" }
    }

    /// Encodable payload for `deliverables.insert(...)`. Mirrors Web
    /// `createDeliverable(form)` in deliverables.ts:97-127 — server auto-fills
    /// `status='submitted'`, `assignee_id`, `org_id`, and stamps `submitted_at`.
    private struct CreatePayload: Encodable {
        let title: String
        let description: String?
        let url: String?
        let projectId: UUID?
        let status: String
        let assigneeId: UUID
        let orgId: UUID
        let submittedAt: String

        enum CodingKeys: String, CodingKey {
            case title
            case description
            case url
            case projectId = "project_id"
            case status
            case assigneeId = "assignee_id"
            case orgId = "org_id"
            case submittedAt = "submitted_at"
        }
    }

    /// 1:1 port of `createDeliverable(form)` in deliverables.ts:97-127.
    ///
    /// Two-step write:
    ///   1. Resolve `org_id` from `profiles.eq('id', currentUserId)` (matches
    ///      Web `getCurrentOrgId(guard.userId)`).
    ///   2. Insert the row with `status='submitted'`, `assignee_id=currentUser`,
    ///      `submitted_at=now()`, then `.select()` the joined shape so the list
    ///      picks up the project + profile cards without a second round-trip.
    ///
    /// Returns `true` on success. Caller should dismiss the sheet and the VM
    /// will self-refresh the list.
    @discardableResult
    public func createDeliverable(
        title: String,
        description: String?,
        url: String?,
        projectId: UUID?
    ) async -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "请填写交付物名称。"
            return false
        }

        isMutating = true
        errorMessage = nil
        defer { isMutating = false }

        do {
            // Creator = currently authenticated user. Same guard Web applies.
            let userId = try await client.auth.session.user.id

            // Resolve org_id — same pattern as ProjectCreateViewModel.
            let orgRows: [ProfileOrgRow] = try await client
                .from("profiles")
                .select("org_id")
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value
            guard let org = orgRows.first else {
                errorMessage = "无法获取组织信息。"
                return false
            }

            let trimmedDesc = description?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedUrl = url?.trimmingCharacters(in: .whitespacesAndNewlines)

            let payload = CreatePayload(
                title: trimmedTitle,
                description: (trimmedDesc?.isEmpty ?? true) ? nil : trimmedDesc,
                url: (trimmedUrl?.isEmpty ?? true) ? nil : trimmedUrl,
                projectId: projectId,
                status: Deliverable.DeliverableStatus.submitted.rawValue,
                assigneeId: userId,
                orgId: org.orgId,
                submittedAt: ISO8601DateFormatter().string(from: Date())
            )

            // `.select()` with the same joined shape the list uses — so the
            // newly-created row slots in with its project/profile cards.
            let created: Deliverable = try await client
                .from("deliverables")
                .insert(payload)
                .select(
                    """
                    id, title, description, url, status,
                    project_id, assignee_id, org_id,
                    due_date, submitted_at, file_url,
                    created_at, updated_at,
                    projects:project_id(id, name),
                    profiles:assignee_id(id, full_name, avatar_url)
                    """
                )
                .single()
                .execute()
                .value

            // Optimistic insert at the top — matches the `ORDER BY created_at
            // DESC` the list uses, so `reloadItems()` would put it there anyway.
            items.insert(created, at: 0)
            successMessage = "交付物已创建"
            return true
        } catch {
            // Iter 7 §C.2 — silent CancellationError;nil 时 banner 不闪屏。
            errorMessage = ErrorPresenter.userFacingMessage(error) ?? errorMessage
            return false
        }
    }

    /// Mirrors the status branch of `updateDeliverable` in
    /// deliverables.ts:131-153 — stamps `submitted_at` only when
    /// transitioning to `submitted`, and always bumps `updated_at`.
    @discardableResult
    public func updateStatus(
        id: UUID,
        to status: Deliverable.DeliverableStatus
    ) async -> Bool {
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }

        let nowISO = ISO8601DateFormatter().string(from: Date())
        let payload = StatusPayload(
            status: status.rawValue,
            submittedAt: status == .submitted ? nowISO : nil,
            updatedAt: nowISO
        )

        do {
            // Round-trip through `.select()` so we pick the same joined
            // shape used by the list — keeps the row's project/profile
            // cards in sync with the new status without a full reload.
            let updated: Deliverable = try await client
                .from("deliverables")
                .update(payload)
                .eq("id", value: id.uuidString)
                .select(
                    """
                    id, title, description, url, status,
                    project_id, assignee_id, org_id,
                    due_date, submitted_at, file_url,
                    created_at, updated_at,
                    projects:project_id(id, name),
                    profiles:assignee_id(id, full_name, avatar_url)
                    """
                )
                .single()
                .execute()
                .value

            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx] = updated
            }
            successMessage = "状态已更新"
            return true
        } catch {
            // Iter 7 §C.2 — silent CancellationError;nil 时 banner 不闪屏。
            errorMessage = ErrorPresenter.userFacingMessage(error) ?? errorMessage
            return false
        }
    }

    /// Mirrors Web `updateDeliverable(id, updates)` in deliverables.ts:131-153.
    ///
    /// Partial-update semantics:
    ///   • Any argument passed as `nil` is treated as "do not modify"
    ///     (matches Web's `updates.field !== undefined` gate).
    ///   • For string fields (`description`, `url`), a trimmed empty
    ///     string (`""`) is treated as "clear the column to NULL"
    ///     (matches Web's `updates.description || null`).
    ///   • `projectId = nil` argument → no change;  to clear the column
    ///     callers should use the `updateDeliverable(..., clearProject:)`
    ///     convenience — but since Web encodes `undefined` vs `null`
    ///     via the same gate, we expose the behaviour via the sheet that
    ///     tracks diffs explicitly.
    ///   • When `status` transitions to `.submitted`, `submitted_at` is
    ///     stamped to `now()`.
    ///   • `updated_at` is always bumped.
    ///
    /// Activity log: fires `update_deliverable` on success (type `.system`
    /// because Web's `ActivityType` has no `deliverable` case).
    @discardableResult
    public func updateDeliverable(
        id: UUID,
        title: String? = nil,
        description: String? = nil,
        url: String? = nil,
        projectId: UUID? = nil,
        clearProject: Bool = false,
        status: Deliverable.DeliverableStatus? = nil
    ) async -> Bool {
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }

        let nowISO = ISO8601DateFormatter().string(from: Date())

        // Title: trim + non-empty guard (Web doesn't allow title clearing).
        var encodedTitle: String? = nil
        if let t = title {
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                errorMessage = "标题不能为空。"
                return false
            }
            encodedTitle = trimmed
        }

        // Description: "" → null, non-empty → value, nil → skip.
        let descField: UpdatePayload.FieldValue? = {
            guard let d = description else { return nil }
            let trimmed = d.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .null : .stringValue(trimmed)
        }()

        // URL: "" → null, non-empty → value, nil → skip.
        let urlField: UpdatePayload.FieldValue? = {
            guard let u = url else { return nil }
            let trimmed = u.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .null : .stringValue(trimmed)
        }()

        // Project: explicit clearProject flag takes precedence; else
        // UUID = set; else nil = skip (Web maps `undefined` → skip).
        let projectField: UpdatePayload.FieldValue? = {
            if clearProject { return .null }
            if let pid = projectId { return .uuidValue(pid) }
            return nil
        }()

        let submittedStamp: String? = (status == .submitted) ? nowISO : nil

        let payload = UpdatePayload(
            title: encodedTitle,
            description: descField,
            url: urlField,
            projectId: projectField,
            status: status?.rawValue,
            submittedAt: submittedStamp,
            updatedAt: nowISO
        )

        // Capture title before mutation for the activity-log copy.
        let priorTitle = items.first(where: { $0.id == id })?.title ?? "交付物"

        do {
            // `.select()` with the same joined shape the list uses — so
            // the newly-updated row slots back in without a full reload.
            let updated: Deliverable = try await client
                .from("deliverables")
                .update(payload)
                .eq("id", value: id.uuidString)
                .select(
                    """
                    id, title, description, url, status,
                    project_id, assignee_id, org_id,
                    due_date, submitted_at, file_url,
                    created_at, updated_at,
                    projects:project_id(id, name),
                    profiles:assignee_id(id, full_name, avatar_url)
                    """
                )
                .single()
                .execute()
                .value

            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx] = updated
            }

            await ActivityLogWriter.write(
                client: client,
                type: .system,
                action: "update_deliverable",
                description: "更新了交付物「\(updated.title.isEmpty ? priorTitle : updated.title)」",
                entityType: "deliverable",
                entityId: id
            )

            // Haptic removed: update 非关键 terminal mutation
            successMessage = "交付物已更新"
            return true
        } catch {
            Haptic.warning()
            // Iter 7 §C.2 — silent CancellationError;nil 时 banner 不闪屏。
            errorMessage = ErrorPresenter.userFacingMessage(error) ?? errorMessage
            return false
        }
    }

    /// Mirrors Web `deleteDeliverable(id)` in deliverables.ts:157-163.
    /// Activity log: fires `delete_deliverable` on success.
    @discardableResult
    public func deleteDeliverable(id: UUID) async -> Bool {
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }

        // Capture title before row drops out of items — activity log
        // needs a human-readable label.
        let priorTitle = items.first(where: { $0.id == id })?.title ?? "交付物"

        do {
            try await client
                .from("deliverables")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()

            items.removeAll { $0.id == id }

            await ActivityLogWriter.write(
                client: client,
                type: .system,
                action: "delete_deliverable",
                description: "删除了交付物「\(priorTitle)」",
                entityType: "deliverable",
                entityId: id
            )

            Haptic.warning() // destructive 真删确认完成
            successMessage = "交付物已删除"
            return true
        } catch {
            Haptic.warning()
            // Iter 7 §C.2 — silent CancellationError;nil 时 banner 不闪屏。
            errorMessage = ErrorPresenter.userFacingMessage(error) ?? errorMessage
            return false
        }
    }

    // MARK: - Helpers

    private static func dayStart(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: date)
        return ISO8601DateFormatter().string(from: start)
    }

    private static func dayEnd(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .second, value: 86_399, to: start) ?? date
        return ISO8601DateFormatter().string(from: end)
    }
}
