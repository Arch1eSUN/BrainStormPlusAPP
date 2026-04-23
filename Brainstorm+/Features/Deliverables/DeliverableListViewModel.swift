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
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    /// Re-runs just the list query — used after filter changes and
    /// after a status mutation so the row reflects Web-style
    /// `submitted_at` stamping.
    public func reloadItems() async {
        do {
            self.items = try await runItemsQuery()
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
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

    // MARK: - Mutations (status only — list + detail scope)

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
            errorMessage = ErrorLocalizer.localize(error)
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
            errorMessage = ErrorLocalizer.localize(error)
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
